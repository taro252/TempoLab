import CloudKit
import Foundation
#if os(macOS)
import Security
#endif

/// 通信とCloudKitのイベントはこのactorで直列化する。音声スレッドには触れない。
actor CloudPresetSyncService: PresetSyncing, CKSyncEngineDelegate {
    static let shared = CloudPresetSyncService(repository: .shared)
    private let repository: PresetRepository
    private var container: CKContainer?
    private var engine: CKSyncEngine?
    private var scope: String?
    private var observers: [NSObjectProtocol] = []
    private var refreshInProgress = false
    private var refreshRequested = false
    private var fetchError: (any Error)?
    private var cycleFailed = false
    private var fetchedSuccessfully = false
    private var accountGeneration = 0

    init(repository: PresetRepository) {
        self.repository = repository
    }

    func refresh() async {
        if refreshInProgress { refreshRequested = true; return }
        refreshInProgress = true
        defer {
            refreshInProgress = false
            if refreshRequested {
                refreshRequested = false
                Task { await self.refresh() }
            }
        }
        installObservers()
        guard Self.hasCloudKitEntitlement else {
            await report(.unavailable, message: String(localized: "iCloud同期にはCloudKit対応の署名と実機が必要です。ローカル保存は利用できます。"))
            return
        }
        do {
            let container = self.container ?? CKContainer(identifier: PresetCloudRecord.containerIdentifier)
            self.container = container
            let verificationGeneration = accountGeneration
            let status = try await container.accountStatus()
            guard verificationGeneration == accountGeneration else { refreshRequested = true; return }
            guard status == .available else {
                invalidateEngine()
                if status == .noAccount { try repository.useSignedOutPartition() }
                await report(.unavailable, message: String(localized: "iCloudに接続できません。ローカル保存は利用できます。"))
                return
            }
            let user = try await container.userRecordID()
            guard verificationGeneration == accountGeneration else { refreshRequested = true; return }
            let newScope = "account:" + user.recordName
            if scope != newScope || engine == nil {
                invalidateEngine()
                scope = try repository.activateAccount(user.recordName)
                let partition = try repository.partition(scope: newScope)
                let serialization = try partition.engineState.map {
                    try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
                }
                let configuration = CKSyncEngine.Configuration(
                    database: container.privateCloudDatabase, stateSerialization: serialization, delegate: self
                )
                engine = CKSyncEngine(configuration)
            }
            guard let engine, let scope else { return }
            cycleFailed = false
            fetchError = nil
            await report(.syncing)
            try await engine.fetchChanges()
            guard self.engine === engine else { return }
            if let fetchError { throw fetchError }
            try repository.finishInitialFetch(scope: scope)
            fetchedSuccessfully = true
            enqueuePending(engine: engine, scope: scope)
            try await engine.sendChanges()
            guard self.engine === engine else { return }
            try await confirmIfComplete(scope: scope)
        } catch {
            await report(.failed, message: error.localizedDescription)
        }
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { await self?.accountMayHaveChanged() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .presetRepositoryLocalChange, object: repository, queue: nil
        ) { [weak self] _ in
            Task { await self?.localDataChanged() }
        })
    }

    private func accountMayHaveChanged() async {
        invalidateEngine()
        await refresh()
    }

    private func invalidateEngine() {
        accountGeneration += 1
        let previous = engine
        engine = nil
        scope = nil
        fetchedSuccessfully = false
        if let previous { Task { await previous.cancelOperations() } }
    }

    private func localDataChanged() async {
        guard let engine, let scope else { return }
        enqueuePending(engine: engine, scope: scope)
        if let partition = try? repository.partition(scope: scope), !partition.pending.isEmpty {
            await report(.syncing)
        }
    }

    private func enqueuePending(engine: CKSyncEngine, scope: String, excluding: Set<String> = []) {
        guard self.engine === engine,
              let partition = try? repository.partition(scope: scope), partition.initialFetchComplete else { return }
        let obsolete = engine.state.pendingRecordZoneChanges.filter { change in
            switch change {
            case .saveRecord(let id): return id.zoneID == PresetCloudRecord.zoneID && !partition.pending.contains(id.recordName)
            case .deleteRecord: return true
            @unknown default: return false
            }
        }
        if !obsolete.isEmpty { engine.state.remove(pendingRecordZoneChanges: obsolete) }
        let existing = Set(engine.state.pendingRecordZoneChanges.map { change in
            switch change {
            case .saveRecord(let id), .deleteRecord(let id): id.recordName
            @unknown default: ""
            }
        })
        let changes = partition.pending.sorted().filter { !existing.contains($0) && !excluding.contains($0) }.map {
            CKSyncEngine.PendingRecordZoneChange.saveRecord(CKRecord.ID(recordName: $0, zoneID: PresetCloudRecord.zoneID))
        }
        if !changes.isEmpty {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: PresetCloudRecord.zoneID))])
            engine.state.add(pendingRecordZoneChanges: changes)
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard engine === syncEngine, let scope,
              let partition = try? repository.partition(scope: scope), partition.initialFetchComplete else { return nil }
        do {
            var records: [CKRecord.ID: CKRecord] = [:]
            let pendingNames = Set(partition.pending)
            for value in partition.pendingCloudRecords {
                let record = try value.makeRecord(systemFields: partition.systemFields[value.recordName])
                records[record.recordID] = record
            }
            let changes = syncEngine.state.pendingRecordZoneChanges.filter { change in
                guard context.options.scope.contains(change) else { return false }
                switch change {
                case .saveRecord(let id): return pendingNames.contains(id.recordName)
                default: return false // アプリ操作では物理削除を送らない。
                }
            }
            let snapshot = records
            let batch = await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { id in snapshot[id] }
            guard engine === syncEngine, self.scope == scope else { return nil }
            return batch
        } catch {
            cycleFailed = true
            await report(.failed, message: error.localizedDescription)
            return nil
        }
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard engine === syncEngine, let scope else { return }
        do {
            switch event {
            case .stateUpdate(let event):
                try repository.saveEngineState(JSONEncoder().encode(event.stateSerialization), scope: scope)
            case .accountChange(let event):
                let currentUser: CKRecord.ID?
                switch event.changeType {
                case .signIn(let user), .switchAccounts(_, let user): currentUser = user
                case .signOut: currentUser = nil
                @unknown default: currentUser = nil
                }
                if currentUser.map({ "account:" + $0.recordName }) != scope {
                    invalidateEngine()
                    if currentUser == nil { try repository.useSignedOutPartition() }
                    await report(.unavailable, message: String(localized: "iCloudアカウントの確認が必要です。ローカルの変更は保持されています。"))
                    Task { await self.refresh() }
                }
            case .fetchedRecordZoneChanges(let event):
                var presets: [PresetSyncRecord] = []
                var order: PresetOrderRecord?
                var fields: [String: Data] = [:]
                for change in event.modifications where change.record.recordID.zoneID == PresetCloudRecord.zoneID {
                    let value = try PresetCloudRecord(record: change.record)
                    switch value {
                    case .preset(let preset): presets.append(preset)
                    case .order(let remoteOrder): order = order?.merged(with: remoteOrder) ?? remoteOrder
                    }
                    fields[value.recordName] = PresetCloudRecord.systemFields(of: change.record)
                }
                try repository.merge(records: presets, order: order, systemFields: fields, scope: scope)
                let deletedIDs = event.deletions.filter { $0.recordID.zoneID == PresetCloudRecord.zoneID }
                    .compactMap { UUID(uuidString: $0.recordID.recordName) }
                if !deletedIDs.isEmpty { try repository.receiveDeletion(ids: deletedIDs, scope: scope) }
                enqueuePending(engine: syncEngine, scope: scope)
            case .fetchedDatabaseChanges(let event):
                if event.deletions.contains(where: { $0.zoneID == PresetCloudRecord.zoneID }) {
                    // ゾーン削除は全件削除の指示とは解釈しない。ローカルを保護して再取得する。
                    try repository.resetServerState(scope: scope)
                    invalidateEngine()
                    Task { await self.refresh() }
                }
            case .sentRecordZoneChanges(let event):
                try handleSent(event, engine: syncEngine, scope: scope)
            case .sentDatabaseChanges(let event):
                if let failure = event.failedZoneSaves.first {
                    cycleFailed = true
                    await report(.failed, message: failure.error.localizedDescription)
                }
            case .willFetchChanges:
                fetchedSuccessfully = false
                fetchError = nil
                await report(.syncing)
            case .didFetchRecordZoneChanges(let event):
                if let error = event.error { fetchError = error; cycleFailed = true }
            case .didFetchChanges:
                if let fetchError { await report(.failed, message: fetchError.localizedDescription) }
                else if try repository.partition(scope: scope).initialFetchComplete {
                    fetchedSuccessfully = true
                    try await confirmIfComplete(scope: scope)
                }
            case .willSendChanges:
                cycleFailed = false
                await report(.syncing)
            case .didSendChanges:
                try await confirmIfComplete(scope: scope)
            default: break
            }
        } catch {
            // 保存できなかった受信変更より先へカーソルを進めない。次回は最後の保存済み状態から再開する。
            cycleFailed = true
            invalidateEngine()
            await report(.failed, message: error.localizedDescription)
        }
    }

    private func handleSent(_ event: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine, scope: String) throws {
        var saved: [PresetSyncRecord] = []
        var order: PresetOrderRecord?
        var fields: [String: Data] = [:]
        for record in event.savedRecords {
            let value = try PresetCloudRecord(record: record)
            switch value {
            case .preset(let preset): saved.append(preset)
            case .order(let value): order = value
            }
            fields[value.recordName] = PresetCloudRecord.systemFields(of: record)
        }
        try repository.acknowledge(records: saved, order: order, systemFields: fields, scope: scope)
        var deferredNames = Set<String>()
        for failure in event.failedRecordSaves {
            switch failure.error.code {
            case .serverRecordChanged:
                guard let server = failure.error.serverRecord else { throw PresetSyncError.invalidRecord }
                let value = try PresetCloudRecord(record: server)
                let fields = [value.recordName: PresetCloudRecord.systemFields(of: server)]
                switch value {
                case .preset(let preset): try repository.merge(records: [preset], systemFields: fields, scope: scope)
                case .order(let order): try repository.merge(records: [], order: order, systemFields: fields, scope: scope)
                }
            case .zoneNotFound, .unknownItem:
                // サーバの物理削除が分かったプリセットは削除優先。ゾーン消失では全ローカルを保持する。
                if failure.error.code == .unknownItem, let id = UUID(uuidString: failure.record.recordID.recordName) {
                    try repository.receiveDeletion(ids: [id], scope: scope)
                } else {
                    try repository.resetServerState(scope: scope)
                    invalidateEngine()
                    Task { await self.refresh() }
                    return
                }
            default:
                cycleFailed = true
                deferredNames.insert(failure.record.recordID.recordName)
                Task { await self.report(.failed, message: failure.error.localizedDescription) }
            }
        }
        // Engine側が送信完了として消した後も、最新のローカル変更は再登録する。
        enqueuePending(engine: engine, scope: scope, excluding: deferredNames)
    }

    private func confirmIfComplete(scope: String) async throws {
        let partition = try repository.partition(scope: scope)
        guard fetchedSuccessfully, !cycleFailed, partition.initialFetchComplete, partition.pending.isEmpty else { return }
        try repository.confirmSync(scope: scope)
        await report(.upToDate)
    }

    private func report(_ phase: PresetSyncStatus.Phase, message: String? = nil) async {
        let expectedScope = scope
        let repository = repository
        await MainActor.run {
            let partition = expectedScope.flatMap { try? repository.partition(scope: $0) }
            let currentPhase: PresetSyncStatus.Phase = phase == .upToDate && partition?.pending.isEmpty != true ? .waiting : phase
            PresetSyncMonitor.shared.update(PresetSyncStatus(
                phase: currentPhase, lastSyncDate: partition?.lastSyncDate, message: message
            ))
        }
    }

    private static var hasCloudKitEntitlement: Bool {
        // SimulatorでPushを含む同期を成功扱いにしない。署名なしのMacビルドも安全にローカル動作する。
        #if targetEnvironment(simulator)
        return false
        #elseif os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let services = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) as? [String],
              let containers = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String] else { return false }
        return services.contains("CloudKit") && containers.contains(PresetCloudRecord.containerIdentifier)
        #else
        return true // 実機向けの署名には同じCloudKit entitlementが必須。
        #endif
    }
}
