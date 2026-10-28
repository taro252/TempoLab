import Foundation

nonisolated extension Notification.Name {
    static let presetRepositoryLocalChange = Notification.Name("PiTempo.presetRepositoryLocalChange")
    static let presetRepositoryDidChange = Notification.Name("PiTempo.presetRepositoryDidChange")
}

nonisolated enum PresetSyncError: Error, LocalizedError, Sendable {
    case accountChanged
    case invalidRecord
    case invalidConfiguration
    case revisionOverflow

    var errorDescription: String? {
        switch self {
        case .accountChanged: String(localized: "iCloudアカウントの確認が必要です。ローカルの変更は保持されています。")
        case .invalidConfiguration: String(localized: "iCloud同期の構成を確認してください。ローカル保存は利用できます。")
        case .invalidRecord: String(localized: "iCloudのプリセットを読み込めませんでした。ローカルの変更は保持されています。")
        case .revisionOverflow: String(localized: "同期リビジョンを更新できませんでした。")
        }
    }
}

/// UI操作とクラウド受信の唯一の書き込み経路。ロック内では最新の状態を読み、保存後に公開する。
nonisolated final class PresetRepository: PresetStoring, @unchecked Sendable {
    static let shared = PresetRepository()
    private let lock = NSLock()
    private let metadataStore: any PresetSyncMetadataStoring
    private var document = PresetSyncDocument()
    private var loadError: (any Error)?
    private var recoveryPresets: [MetronomePreset] = []
    private var skippedRecordCount = 0

    init(
        legacyStore: any PresetStoring = PresetStore(),
        metadataStore: any PresetSyncMetadataStoring = PresetSyncMetadataStore()
    ) {
        self.metadataStore = metadataStore
        do {
            if let saved = try metadataStore.load() {
                document = saved
            } else {
                let legacy = try legacyStore.load()
                skippedRecordCount = legacy.skippedRecordCount
                recoveryPresets = legacy.presets
                var partition = PresetSyncPartition()
                try Self.update(&partition, to: legacy.presets, writerID: document.writerID)
                document.partitions["local"] = partition
                try metadataStore.save(document)
            }
        } catch {
            loadError = error
            recoveryPresets = (try? legacyStore.load().presets) ?? recoveryPresets
        }
    }

    func load() throws -> PresetLoadResult {
        try lock.withLock {
            if let loadError { throw loadError }
            return PresetLoadResult(presets: current.presets, skippedRecordCount: skippedRecordCount)
        }
    }

    /// 保存に失敗した移行元を画面で確認できる。書き込みは成功したように扱わない。
    var migrationBackup: [MetronomePreset] { lock.withLock { recoveryPresets } }
    var lastSyncDate: Date? { lock.withLock { current.lastSyncDate } }

    func save(_ presets: [MetronomePreset]) throws {
        try transaction(localChange: true) { document in
            var partition = document.partitions[document.activeScope] ?? PresetSyncPartition()
            try Self.update(&partition, to: presets, writerID: document.writerID)
            document.partitions[document.activeScope] = partition
        }
    }

    func apply(_ mutation: PresetMutation) throws -> [MetronomePreset] {
        try transaction(localChange: true) { document in
            var partition = document.partitions[document.activeScope] ?? PresetSyncPartition()
            var presets = partition.presets
            try mutation.apply(to: &presets)
            try Self.update(&partition, to: presets, writerID: document.writerID)
            document.partitions[document.activeScope] = partition
            return partition.presets
        }
    }

    /// 最初のログイン時だけ未所属のローカルデータを引き継ぐ。以後はアカウント別に保管する。
    @discardableResult
    func activateAccount(_ accountID: String) throws -> String {
        let scope = "account:" + accountID
        return try transaction { document in
            if document.partitions[scope] == nil {
                if !document.localWasBound {
                    document.partitions[scope] = document.partitions["local"] ?? PresetSyncPartition()
                } else {
                    document.partitions[scope] = PresetSyncPartition()
                }
            }
            document.localWasBound = true
            document.activeScope = scope
            return scope
        }
    }

    /// サインアウト後は前アカウントのデータをバックアップし、独立したローカル領域を表示する。
    func useSignedOutPartition() throws {
        try transaction { document in
            guard document.localWasBound else { return }
            document.activeScope = "signed-out"
            if document.partitions["signed-out"] == nil { document.partitions["signed-out"] = PresetSyncPartition() }
        }
    }

    func partition(scope: String) throws -> PresetSyncPartition {
        try lock.withLock {
            if let loadError { throw loadError }
            guard document.activeScope == scope, let partition = document.partitions[scope] else {
                throw PresetSyncError.accountChanged
            }
            return partition
        }
    }

    func merge(
        records: [PresetSyncRecord], order: PresetOrderRecord? = nil,
        systemFields: [String: Data] = [:], scope: String
    ) throws {
        try changePartition(scope: scope) { partition in
            for remote in records {
                guard remote.isValid else { throw PresetSyncError.invalidRecord }
                let key = remote.id.uuidString
                let winner = partition.records[key]?.merged(with: remote) ?? remote
                partition.records[key] = winner
                partition.logicalClock = max(partition.logicalClock, remote.revision.counter)
                if winner == remote { partition.pending.remove(key) }
                else { partition.pending.insert(key) }
            }
            if let order {
                guard order.revision.counter >= 0, !order.revision.writerID.isEmpty else {
                    throw PresetSyncError.invalidRecord
                }
                let winner = partition.order?.merged(with: order) ?? order
                partition.order = winner
                partition.logicalClock = max(partition.logicalClock, order.revision.counter)
                if winner == order { partition.pending.remove(PresetOrderRecord.recordName) }
                else { partition.pending.insert(PresetOrderRecord.recordName) }
            }
            partition.systemFields.merge(systemFields) { _, new in new }
        }
    }

    /// 送信中の追加編集を消さないよう、送信された内容と現在の内容が同じ場合だけ確認済みにする。
    func acknowledge(records: [PresetSyncRecord], order: PresetOrderRecord?, systemFields: [String: Data], scope: String) throws {
        try changePartition(scope: scope) { partition in
            for record in records where partition.records[record.id.uuidString] == record {
                partition.pending.remove(record.id.uuidString)
            }
            if let order, partition.order == order { partition.pending.remove(PresetOrderRecord.recordName) }
            partition.systemFields.merge(systemFields) { _, new in new }
        }
    }

    func saveEngineState(_ data: Data, scope: String) throws {
        try changePartition(scope: scope) { $0.engineState = data }
    }

    func finishInitialFetch(scope: String) throws {
        try changePartition(scope: scope) { $0.initialFetchComplete = true }
    }

    func confirmSync(scope: String, date: Date = Date()) throws {
        try changePartition(scope: scope) {
            guard $0.initialFetchComplete, $0.pending.isEmpty else { return }
            $0.lastSyncDate = date
        }
    }

    /// 管理者などによる物理削除も削除記録へ変換し、古い端末からの復活を防ぐ。
    func receiveDeletion(ids: [UUID], scope: String) throws {
        try transaction { document in
            guard document.activeScope == scope, var partition = document.partitions[scope] else {
                throw PresetSyncError.accountChanged
            }
            for id in ids {
                let revision = try Self.nextRevision(&partition, writerID: document.writerID)
                partition.records[id.uuidString] = PresetSyncRecord(
                    id: id, preset: nil, revision: revision, isDeleted: true, deletedAt: Date()
                )
                partition.systemFields[id.uuidString] = nil
                partition.pending.insert(id.uuidString)
            }
            document.partitions[scope] = partition
        }
    }

    func resetServerState(scope: String) throws {
        try changePartition(scope: scope) {
            $0.systemFields = [:]
            $0.engineState = nil
            $0.initialFetchComplete = false
            $0.pending.formUnion($0.records.keys)
            if $0.order != nil { $0.pending.insert(PresetOrderRecord.recordName) }
        }
    }

    private var current: PresetSyncPartition { document.partitions[document.activeScope] ?? PresetSyncPartition() }

    private func changePartition(scope: String, _ change: (inout PresetSyncPartition) throws -> Void) throws {
        try transaction { document in
            guard document.activeScope == scope, var partition = document.partitions[scope] else {
                throw PresetSyncError.accountChanged
            }
            try change(&partition)
            document.partitions[scope] = partition
        }
    }

    private func transaction<T>(localChange: Bool = false, _ change: (inout PresetSyncDocument) throws -> T) throws -> T {
        let result = try lock.withLock {
            if let loadError { throw loadError }
            var candidate = document
            let result = try change(&candidate)
            if candidate != document {
                try metadataStore.save(candidate)
                document = candidate
            }
            return result
        }
        NotificationCenter.default.post(name: .presetRepositoryDidChange, object: self)
        if localChange { NotificationCenter.default.post(name: .presetRepositoryLocalChange, object: self) }
        return result
    }

    private static func nextRevision(_ partition: inout PresetSyncPartition, writerID: String) throws -> PresetRevision {
        guard partition.logicalClock < Int64.max else { throw PresetSyncError.revisionOverflow }
        partition.logicalClock += 1
        return PresetRevision(counter: partition.logicalClock, writerID: writerID)
    }

    private static func update(_ partition: inout PresetSyncPartition, to presets: [MetronomePreset], writerID: String) throws {
        guard Set(presets.map(\.id)).count == presets.count else { throw PresetSyncError.invalidRecord }
        let ids = Set(presets.map { $0.id.uuidString })
        for key in Array(partition.records.keys) where !ids.contains(key) && partition.records[key]?.isDeleted == false {
            let revision = try nextRevision(&partition, writerID: writerID)
            partition.records[key]?.isDeleted = true
            partition.records[key]?.deletedAt = Date()
            partition.records[key]?.revision = revision
            partition.pending.insert(key)
        }
        for preset in presets {
            let key = preset.id.uuidString
            // 削除したUUIDの再利用を禁止する。
            guard partition.records[key]?.isDeleted != true else { throw PresetSyncError.invalidRecord }
            if partition.records[key]?.preset != preset {
                partition.records[key] = PresetSyncRecord(
                    id: preset.id, preset: preset, revision: try nextRevision(&partition, writerID: writerID)
                )
                partition.pending.insert(key)
            }
        }
        if partition.presets.map(\.id) != presets.map(\.id) || partition.order == nil && !presets.isEmpty {
            partition.order = PresetOrderRecord(
                orderedIDs: presets.map(\.id), revision: try nextRevision(&partition, writerID: writerID)
            )
            partition.pending.insert(PresetOrderRecord.recordName)
        }
    }
}
