import CloudKit
import Foundation
import XCTest
@testable import TempoLab

final class PresetCloudSyncTests: XCTestCase {
    func testAccountNamespaceUsesTheBuiltCloudKitEnvironment() throws {
        let environment = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "PresetCloudKitEnvironment") as? String)
        XCTAssertTrue(["Development", "Production"].contains(environment))
        let key = try PresetCloudRecord.accountKey(for: CKRecord.ID(recordName: "test-user"))
        XCTAssertEqual(key, "iCloud.app.merodoa.PiTempo|\(environment)|test-user")
    }

    func testCloudRecordRoundTripIncludesBodyRevisionTombstoneAndOrder() throws {
        let preset = try syncPreset("日本語の練習", bpm: 180)
        var deleted = syncRecord(preset, counter: 37)
        deleted.isDeleted = true
        deleted.deletedAt = Date(timeIntervalSince1970: 123)
        let values: [PresetCloudRecord] = [
            .preset(syncRecord(preset, counter: 36)), .preset(deleted),
            .order(PresetOrderRecord(orderedIDs: [preset.id], revision: deleted.revision))
        ]
        for value in values {
            let record = try value.makeRecord()
            XCTAssertEqual(try PresetCloudRecord(record: record), value)
            let restored = try value.makeRecord(systemFields: PresetCloudRecord.systemFields(of: record))
            XCTAssertEqual(try PresetCloudRecord(record: restored), value)
        }
    }

    func testInvalidOrFutureCloudRecordsAreRejectedWithoutLocalMutation() throws {
        let value = PresetCloudRecord.preset(syncRecord(try syncPreset("正常")))
        let record = try value.makeRecord()
        record["schemaVersion"] = 999 as NSNumber
        XCTAssertThrowsError(try PresetCloudRecord(record: record))
        record["schemaVersion"] = 1 as NSNumber
        record["uuid"] = UUID().uuidString as NSString
        XCTAssertThrowsError(try PresetCloudRecord(record: record))
        record["uuid"] = value.recordName as NSString
        record["presetJSON"] = Data("broken".utf8) as NSData
        XCTAssertThrowsError(try PresetCloudRecord(record: record))
    }

    func testTwoDevicesKeepInitialDataAndReceiveNewPresetsRenameAndOverwrite() async throws {
        let server = FakePresetCloud()
        let local = try syncPreset("既存ローカル"), cloud = try syncPreset("既存クラウド")
        await server.seed([.preset(syncRecord(cloud))])
        let a = makeRepository([local]), b = makeRepository()
        let sa = FakePresetSyncService(repository: a, server: server)
        let sb = FakePresetSyncService(repository: b, server: server)
        await sa.refresh(); await sb.refresh()
        XCTAssertEqual(Set(try b.load().presets.map(\.id)), Set([local.id, cloud.id]))
        _ = try a.apply(.rename(local.id, "改名"))
        _ = try a.apply(.overwrite(local.id, syncPreset("設定", bpm: 240).configuration))
        await sa.refresh(); await sb.refresh()
        XCTAssertEqual(try b.load().presets.first { $0.id == local.id }?.name, "改名")
        XCTAssertEqual(try b.load().presets.first { $0.id == local.id }?.configuration.bpm, 240)
        XCTAssertEqual(try b.load().presets.count, 2)
    }

    func testOfflineEditThenRestartAndReconnectSendsPendingChanges() async throws {
        let metadata = SyncTestMetadataStore(), server = FakePresetCloud()
        let repository = PresetRepository(legacyStore: SyncTestLegacyStore(), metadataStore: metadata)
        let offline = FakePresetSyncService(repository: repository, server: server)
        await offline.setOffline(true)
        _ = try repository.apply(.insert(syncPreset("通信なし")))
        await offline.refresh()
        XCTAssertFalse(try XCTUnwrap(metadata.document?.partitions["local"]).pending.isEmpty)
        XCTAssertFalse(try XCTUnwrap(metadata.document?.partitions["local"]).initialFetchComplete)
        let restarted = PresetRepository(legacyStore: SyncTestLegacyStore(), metadataStore: metadata)
        let service = FakePresetSyncService(repository: restarted, server: server)
        await service.refresh()
        let other = makeRepository()
        await FakePresetSyncService(repository: other, server: server).refresh()
        XCTAssertEqual(try other.load().presets.map(\.name), ["通信なし"])
        XCTAssertTrue(try restarted.partition(scope: "account:A").pending.isEmpty)
    }

    func testDeleteDoesNotResurrectFromOfflineDeviceEvenAfterLaterEdit() async throws {
        let preset = try syncPreset("削除")
        let server = FakePresetCloud()
        let a = makeRepository([preset]), b = makeRepository()
        let sa = FakePresetSyncService(repository: a, server: server), sb = FakePresetSyncService(repository: b, server: server)
        await sa.refresh(); await sb.refresh()
        _ = try a.apply(.delete(preset.id))
        _ = try b.apply(.rename(preset.id, "オフラインの古い端末"))
        await sa.refresh(); await sb.refresh(); await sa.refresh()
        XCTAssertTrue(try a.load().presets.isEmpty)
        XCTAssertTrue(try b.load().presets.isEmpty)
        let records = await server.snapshot()
        XCTAssertTrue(records.contains { if case .preset(let record) = $0 { return record.isDeleted }; return false })
    }

    func testOrderIsSyncedAndConcurrentNewIDIsNotLost() async throws {
        let presets = try [syncPreset("A"), syncPreset("B"), syncPreset("C")]
        let server = FakePresetCloud()
        let a = makeRepository(presets), b = makeRepository()
        let sa = FakePresetSyncService(repository: a, server: server), sb = FakePresetSyncService(repository: b, server: server)
        await sa.refresh(); await sb.refresh()
        _ = try a.apply(.reorder(presets.reversed().map(\.id)))
        let added = try syncPreset("他端末で追加")
        _ = try b.apply(.insert(added))
        await sa.refresh(); await sb.refresh(); await sa.refresh()
        XCTAssertEqual(try a.load().presets, try b.load().presets)
        XCTAssertEqual(Set(try a.load().presets.map(\.id)), Set((presets + [added]).map(\.id)))
    }

    func testAccountSwitchAndDelayedResponseCannotLeakData() async throws {
        let privatePreset = try syncPreset("Aだけ")
        let aCloud = FakePresetCloud(), bCloud = FakePresetCloud()
        let repository = makeRepository([privatePreset])
        let serviceA = FakePresetSyncService(repository: repository, server: aCloud)
        await serviceA.refresh()
        let oldScope = "account:A"
        let oldResponse = await aCloud.snapshot()
        let serviceB = FakePresetSyncService(repository: repository, server: bCloud, account: "B")
        await serviceB.refresh()
        XCTAssertTrue(try repository.load().presets.isEmpty)
        XCTAssertThrowsError(try repository.merge(records: oldResponse.compactMap {
            if case .preset(let record) = $0 { return record }; return nil
        }, scope: oldScope))
        let bRecords = await bCloud.snapshot()
        XCTAssertTrue(bRecords.isEmpty)
        try repository.activateAccount("A")
        XCTAssertEqual(try repository.load().presets, [privatePreset])
    }

    func testMergeAndUnconfirmedSyncNeverInventLastSyncDate() async throws {
        let repository = makeRepository(try [syncPreset("未送信")])
        let scope = try repository.activateAccount("A")
        try repository.confirmSync(scope: scope)
        XCTAssertNil(try repository.partition(scope: scope).lastSyncDate)
        try repository.finishInitialFetch(scope: scope)
        try repository.confirmSync(scope: scope)
        XCTAssertNil(try repository.partition(scope: scope).lastSyncDate)
        let server = FakePresetCloud()
        await FakePresetSyncService(repository: repository, server: server).refresh()
        XCTAssertNotNil(try repository.partition(scope: scope).lastSyncDate)
    }

    private func makeRepository(_ presets: [MetronomePreset] = []) -> PresetRepository {
        PresetRepository(legacyStore: SyncTestLegacyStore(presets), metadataStore: SyncTestMetadataStore())
    }
}

/// CloudKit非接続の代替実装。製品と同じレコード変換、Repositoryのマージ・確認処理を通す。
private actor FakePresetSyncService: PresetSyncing {
    let repository: PresetRepository
    let server: FakePresetCloud
    let account: String
    var offline = false

    init(repository: PresetRepository, server: FakePresetCloud, account: String = "A") {
        self.repository = repository; self.server = server; self.account = account
    }
    func setOffline(_ value: Bool) { offline = value }
    func refresh() async {
        guard !offline else { return }
        do {
            let scope = try repository.activateAccount(account)
            for value in await server.snapshot() { try receive(value, scope: scope) }
            try repository.finishInitialFetch(scope: scope)
            for sent in try repository.partition(scope: scope).pendingCloudRecords {
                let serverValue = await server.save(sent)
                if serverValue == sent {
                    switch sent {
                    case .preset(let record): try repository.acknowledge(records: [record], order: nil, systemFields: [:], scope: scope)
                    case .order(let order): try repository.acknowledge(records: [], order: order, systemFields: [:], scope: scope)
                    }
                } else { try receive(serverValue, scope: scope) }
            }
            try repository.confirmSync(scope: scope)
        } catch { XCTFail("Fake sync: \(error)") }
    }
    private func receive(_ value: PresetCloudRecord, scope: String) throws {
        let decoded = try PresetCloudRecord(record: value.makeRecord())
        switch decoded {
        case .preset(let record): try repository.merge(records: [record], scope: scope)
        case .order(let order): try repository.merge(records: [], order: order, scope: scope)
        }
    }
}

private actor FakePresetCloud {
    var records: [String: PresetCloudRecord] = [:]
    func seed(_ values: [PresetCloudRecord]) { for value in values { records[value.recordName] = value } }
    func snapshot() -> [PresetCloudRecord] { records.keys.sorted().compactMap { records[$0] } }
    func save(_ incoming: PresetCloudRecord) -> PresetCloudRecord {
        let winner: PresetCloudRecord
        switch (records[incoming.recordName], incoming) {
        case (.preset(let old), .preset(let new)): winner = .preset(old.merged(with: new))
        case (.order(let old), .order(let new)): winner = .order(old.merged(with: new))
        default: winner = incoming
        }
        records[incoming.recordName] = winner
        return winner
    }
}
