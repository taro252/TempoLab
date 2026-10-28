import Foundation
import XCTest
@testable import TempoLab

final class PresetRepositoryTests: XCTestCase {
    func testMigrationIsDurableIdempotentAndKeepsLegacyData() throws {
        let legacy = SyncTestLegacyStore(try [syncPreset("旧A"), syncPreset("旧B")])
        let metadata = SyncTestMetadataStore()
        let first = PresetRepository(legacyStore: legacy, metadataStore: metadata)
        XCTAssertEqual(try first.load().presets, legacy.presets)
        XCTAssertEqual(legacy.saveCount, 0)
        let scope = try first.activateAccount("A")
        XCTAssertFalse(try first.partition(scope: scope).initialFetchComplete)
        XCTAssertFalse(try first.partition(scope: scope).pending.isEmpty)
        let restarted = PresetRepository(legacyStore: legacy, metadataStore: metadata)
        XCTAssertEqual(try restarted.load().presets, legacy.presets)
        XCTAssertEqual(try restarted.partition(scope: scope), try first.partition(scope: scope))
        XCTAssertEqual(metadata.document?.partitions["local"]?.presets, legacy.presets)
    }

    func testInitialMergeKeepsDifferentIDsAndDeduplicatesSameID() throws {
        let local = try syncPreset("ローカル")
        let cloud = try syncPreset("クラウド")
        let repository = makeRepository([local])
        let scope = try repository.activateAccount("A")
        let remote = syncRecord(cloud, counter: 5, writer: "B")
        try repository.merge(records: [remote, remote], scope: scope)
        XCTAssertEqual(Set(try repository.load().presets.map(\.id)), Set([local.id, cloud.id]))
        try repository.finishInitialFetch(scope: scope)
        XCTAssertTrue(try repository.partition(scope: scope).initialFetchComplete)
    }

    func testConcurrentEditsAreDeterministicRegardlessOfArrivalOrder() throws {
        let original = try syncPreset("元")
        var a = original
        var b = original
        try a.rename("Aの名前")
        try b.rename("Bの名前")
        let ra = syncRecord(a, counter: 10, writer: "A")
        let rb = syncRecord(b, counter: 10, writer: "B")
        XCTAssertEqual(ra.merged(with: rb), rb.merged(with: ra))
        XCTAssertEqual(ra.merged(with: rb).preset?.name, "Bの名前")
        let left = makeRepository(), right = makeRepository()
        let ls = try left.activateAccount("A"), rs = try right.activateAccount("A")
        try left.merge(records: [ra, rb], scope: ls)
        try right.merge(records: [rb, ra], scope: rs)
        XCTAssertEqual(try left.load().presets, try right.load().presets)
    }

    func testDeletionWinsEvenAgainstAnUnseenHigherRevisionEdit() throws {
        let preset = try syncPreset("削除対象")
        var deleted = syncRecord(preset, counter: 2)
        deleted.isDeleted = true
        deleted.deletedAt = Date()
        let oldDevice = syncRecord(preset, counter: 1000, writer: "古い端末")
        XCTAssertTrue(deleted.merged(with: oldDevice).isDeleted)
        XCTAssertTrue(oldDevice.merged(with: deleted).isDeleted)
        let repository = makeRepository([preset])
        let scope = try repository.activateAccount("A")
        try repository.merge(records: [deleted, oldDevice], scope: scope)
        XCTAssertTrue(try repository.load().presets.isEmpty)
        XCTAssertTrue(try repository.partition(scope: scope).pending.contains(preset.id.uuidString))
    }

    func testConcurrentOrderKeepsNewPresetsMissingFromWinningOrder() throws {
        let presets = try [syncPreset("A"), syncPreset("B"), syncPreset("C")]
        let repository = makeRepository(presets)
        let scope = try repository.activateAccount("A")
        let order = PresetOrderRecord(orderedIDs: [presets[1].id, presets[0].id], revision: PresetRevision(counter: 100, writerID: "B"))
        try repository.merge(records: [], order: order, scope: scope)
        XCTAssertEqual(try repository.load().presets.map(\.id), [presets[1].id, presets[0].id, presets[2].id])
        let reverse = PresetOrderRecord(orderedIDs: presets.map(\.id).reversed(), revision: order.revision)
        XCTAssertEqual(order.merged(with: reverse), reverse.merged(with: order))
    }

    func testMutationReadsLatestStateAndDoesNotRemoveConcurrentRemoteInsert() throws {
        let a = try syncPreset("A"), b = try syncPreset("B")
        let repository = makeRepository([a])
        let scope = try repository.activateAccount("A")
        try repository.merge(records: [syncRecord(b)], scope: scope)
        let result = try repository.apply(.rename(a.id, "変更"))
        XCTAssertEqual(Set(result.map(\.id)), Set([a.id, b.id]))
        XCTAssertEqual(result.first { $0.id == a.id }?.name, "変更")
    }

    func testOldAcknowledgementDoesNotClearNewerLocalEdit() throws {
        let preset = try syncPreset("A")
        let repository = makeRepository([preset])
        let scope = try repository.activateAccount("A")
        let sent = try XCTUnwrap(repository.partition(scope: scope).records[preset.id.uuidString])
        _ = try repository.apply(.rename(preset.id, "送信中の変更"))
        try repository.acknowledge(records: [sent], order: nil, systemFields: [:], scope: scope)
        XCTAssertTrue(try repository.partition(scope: scope).pending.contains(preset.id.uuidString))
    }

    func testOfflineChangesAndEngineStateSurviveRestart() throws {
        let metadata = SyncTestMetadataStore()
        let repository = PresetRepository(legacyStore: SyncTestLegacyStore(), metadataStore: metadata)
        let scope = try repository.activateAccount("A")
        let preset = try syncPreset("オフライン")
        _ = try repository.apply(.insert(preset))
        try repository.saveEngineState(Data([1, 2, 3]), scope: scope)
        let restored = PresetRepository(legacyStore: SyncTestLegacyStore(), metadataStore: metadata)
        XCTAssertEqual(try restored.partition(scope: scope), try repository.partition(scope: scope))
        XCTAssertEqual(try restored.load().presets, [preset])
    }

    func testAccountSwitchNeverCopiesPreviousOrSignedOutPresets() throws {
        let preset = try syncPreset("A専用")
        let repository = makeRepository([preset])
        let a = try repository.activateAccount("A")
        try repository.useSignedOutPartition()
        XCTAssertTrue(try repository.load().presets.isEmpty)
        _ = try repository.apply(.insert(syncPreset("未ログインの作業")))
        let b = try repository.activateAccount("B")
        XCTAssertTrue(try repository.load().presets.isEmpty)
        XCTAssertTrue(try repository.partition(scope: b).pending.isEmpty)
        XCTAssertThrowsError(try repository.partition(scope: a))
        try repository.activateAccount("A")
        XCTAssertEqual(try repository.load().presets, [preset])
    }

    func testFailedSaveDoesNotPublishOrLosePreviousData() throws {
        let preset = try syncPreset("元")
        let metadata = SyncTestMetadataStore()
        let repository = PresetRepository(legacyStore: SyncTestLegacyStore([preset]), metadataStore: metadata)
        let before = metadata.document
        metadata.failSave = true
        XCTAssertThrowsError(try repository.apply(.delete(preset.id)))
        XCTAssertEqual(try repository.load().presets, [preset])
        XCTAssertEqual(metadata.document, before)
    }

    func testAtomicFileRestoresAndProtectsUnsupportedOrCorruptData() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "state.json")
        let store = PresetSyncMetadataStore(fileURL: url)
        let repository = PresetRepository(legacyStore: SyncTestLegacyStore(try [syncPreset("移行")]), metadataStore: store)
        _ = try repository.apply(.insert(syncPreset("追加")))
        XCTAssertEqual(try store.load(), try PresetSyncMetadataStore(fileURL: url).load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("previous").path))
        for data in [Data("broken".utf8), try JSONEncoder().encode(futureDocument())] {
            try data.write(to: url, options: .atomic)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.save(PresetSyncDocument()))
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }

    func testLastConfirmedSyncDateSurvivesRestart() throws {
        let metadata = SyncTestMetadataStore()
        let repository = PresetRepository(legacyStore: SyncTestLegacyStore(), metadataStore: metadata)
        let scope = try repository.activateAccount("A")
        try repository.finishInitialFetch(scope: scope)
        let date = Date(timeIntervalSince1970: 500)
        try repository.confirmSync(scope: scope, date: date)
        let restored = PresetRepository(legacyStore: SyncTestLegacyStore(), metadataStore: metadata)
        XCTAssertEqual(restored.lastSyncDate, date)
        try restored.useSignedOutPartition()
        XCTAssertNil(restored.lastSyncDate)
    }

    private func futureDocument() -> PresetSyncDocument {
        var document = PresetSyncDocument()
        document.schemaVersion = 999
        return document
    }

    private func makeRepository(_ presets: [MetronomePreset] = []) -> PresetRepository {
        PresetRepository(legacyStore: SyncTestLegacyStore(presets), metadataStore: SyncTestMetadataStore())
    }
}

nonisolated func syncPreset(_ name: String, bpm: Int = 120) throws -> MetronomePreset {
    try MetronomePreset(name: name, configuration: PresetConfiguration(
        bpm: bpm, timeSignature: .fourFour, subdivision: .quarter,
        accentPattern: .defaultPattern(timeSignature: .fourFour, subdivision: .quarter), clickSoundSettings: .default
    ))
}

nonisolated func syncRecord(_ preset: MetronomePreset, counter: Int64 = 1, writer: String = "remote") -> PresetSyncRecord {
    PresetSyncRecord(id: preset.id, preset: preset, revision: PresetRevision(counter: counter, writerID: writer))
}

nonisolated final class SyncTestMetadataStore: PresetSyncMetadataStoring, @unchecked Sendable {
    var document: PresetSyncDocument?
    var failSave = false
    func load() throws -> PresetSyncDocument? { document }
    func save(_ document: PresetSyncDocument) throws {
        if failSave { throw PresetError.saveFailed }
        self.document = document
    }
}

nonisolated final class SyncTestLegacyStore: PresetStoring, @unchecked Sendable {
    var presets: [MetronomePreset]
    var saveCount = 0
    init(_ presets: [MetronomePreset] = []) { self.presets = presets }
    func load() throws -> PresetLoadResult { PresetLoadResult(presets: presets) }
    func save(_ presets: [MetronomePreset]) throws { self.presets = presets; saveCount += 1 }
}
