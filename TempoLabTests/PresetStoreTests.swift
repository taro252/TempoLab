import Foundation
import XCTest
@testable import TempoLab

final class PresetStoreTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "app.merodoa.PiTempoPresetTests.\(UUID().uuidString)"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
    }

    func testFreshInstallHasNoPresetsAndDoesNotChangeAppSettings() throws {
        let settings = AppSettings(bpm: 145, keepScreenAwake: true)
        SettingsStore(userDefaults: userDefaults).save(settings)
        let originalData = userDefaults.data(forKey: SettingsStore.storageKey)
        let store = PresetStore(userDefaults: userDefaults)
        XCTAssertTrue(try store.load().presets.isEmpty)
        try store.save([preset("保存")])
        XCTAssertEqual(userDefaults.data(forKey: SettingsStore.storageKey), originalData)
        XCTAssertEqual(SettingsStore(userDefaults: userDefaults).load(), settings)
    }

    func testNewStoreRestoresUUIDNamesConfigurationDatesAndArrayOrder() throws {
        let presets = try [preset("同じ名前", bpm: 180), preset("同じ名前", bpm: 30), preset("練習", bpm: 300)]
        try PresetStore(userDefaults: userDefaults).save(presets)
        let result = try PresetStore(userDefaults: userDefaults).load()
        XCTAssertEqual(result.presets, presets)
        XCTAssertEqual(result.skippedRecordCount, 0)
        XCTAssertNotEqual(presets[0].id, presets[1].id)
    }

    func testRenameOverwriteReorderAndDeletionArePersisted() throws {
        let store = PresetStore(userDefaults: userDefaults)
        var presets = try [preset("A"), preset("B"), preset("C")]
        let id = presets[1].id
        try store.save(presets)
        try presets[1].rename("改名")
        presets[1].configuration = configuration(bpm: 200)
        presets.swapAt(0, 1)
        presets.removeLast()
        try store.save(presets)
        let restored = try PresetStore(userDefaults: userDefaults).load().presets
        XCTAssertEqual(restored, presets)
        XCTAssertEqual(restored.first?.id, id)
        XCTAssertEqual(restored.first?.name, "改名")
        XCTAssertEqual(restored.first?.configuration.bpm, 200)
        try store.save([])
        XCTAssertTrue(try PresetStore(userDefaults: userDefaults).load().presets.isEmpty)
    }

    func testBadRecordsDoNotDiscardValidNeighbors() throws {
        let valid = try [preset("前"), preset("後")]
        let first = try jsonObject(valid[0])
        let last = try jsonObject(valid[1])
        var blankName = first
        blankName["name"] = " \n"
        var badID = first
        badID["id"] = "invalid-uuid"
        try setContainer([first, NSNull(), "broken", ["name": "incomplete"], blankName, badID, last, first])
        let loaded = try PresetStore(userDefaults: userDefaults).load()
        XCTAssertEqual(loaded.presets, valid)
        XCTAssertEqual(loaded.skippedRecordCount, 6)
    }

    func testInvalidConfigurationIsNormalizedDuringStoreLoad() throws {
        var object = try jsonObject(preset("不正値"))
        object["configuration"] = [
            "bpm": -20,
            "timeSignature": ["numerator": 6, "denominator": 8],
            "subdivision": "eighth",
            "accentPattern": [
                "timeSignature": ["numerator": 4, "denominator": 4],
                "subdivision": "quarter", "steps": ["accent"]
            ],
            "clickSoundSettings": [
                "normalFrequency": 5, "accentFrequency": 9000,
                "volume": -1, "soundType": "wood"
            ]
        ] as [String: Any]
        try setContainer([object])
        let config = try XCTUnwrap(PresetStore(userDefaults: userDefaults).load().presets.first?.configuration)
        XCTAssertEqual(config.bpm, 30)
        XCTAssertEqual(config.clickSoundSettings.volume, 0)
        XCTAssertEqual(config.clickSoundSettings.normalFrequency, 300)
        XCTAssertEqual(config.clickSoundSettings.accentFrequency, 3000)
        XCTAssertEqual(config.accentPattern, .defaultPattern(timeSignature: .sixEight, subdivision: .eighth))
    }

    func testCorruptContainerIsPreservedAndSaveIsRejected() throws {
        for data in [Data("not-json".utf8), Data(#"{"schemaVersion":1,"presets":{}}"#.utf8)] {
            userDefaults.set(data, forKey: PresetStore.storageKey)
            let store = PresetStore(userDefaults: userDefaults)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.save([]))
            XCTAssertEqual(userDefaults.data(forKey: PresetStore.storageKey), data)
        }
    }

    func testUnsupportedSchemaIsPreservedEvenByANewStore() throws {
        let data = Data(#"{"schemaVersion":2,"presets":[{"future":"data"}]}"#.utf8)
        userDefaults.set(data, forKey: PresetStore.storageKey)
        XCTAssertThrowsError(try PresetStore(userDefaults: userDefaults).load()) { error in
            guard case PresetError.unsupportedSchema = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try PresetStore(userDefaults: userDefaults).save([preset("新規")]))
        XCTAssertEqual(userDefaults.data(forKey: PresetStore.storageKey), data)
    }

    func testEncodingFailureKeepsPreviousData() throws {
        let store = PresetStore(userDefaults: userDefaults)
        try store.save([preset("正常")])
        let data = userDefaults.data(forKey: PresetStore.storageKey)
        var invalid = try preset("無効な日付")
        invalid.updatedAt = Date(timeIntervalSinceReferenceDate: .infinity)
        XCTAssertThrowsError(try store.save([invalid]))
        XCTAssertEqual(userDefaults.data(forKey: PresetStore.storageKey), data)
    }

    private func configuration(bpm: Int = 120) -> PresetConfiguration {
        PresetConfiguration(
            bpm: bpm, timeSignature: .threeFour, subdivision: .triplet,
            accentPattern: AccentPattern(
                timeSignature: .threeFour, subdivision: .triplet,
                steps: [.mute, .accent] + Array(repeating: .normal, count: 7)
            ),
            clickSoundSettings: ClickSoundSettings(
                normalFrequency: 700, accentFrequency: 1900, volume: 0.4, soundType: .digital
            )
        )
    }

    private func preset(_ name: String, bpm: Int = 120) throws -> MetronomePreset {
        try MetronomePreset(name: name, configuration: configuration(bpm: bpm))
    }

    private func jsonObject(_ preset: MetronomePreset) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(preset)) as? [String: Any])
    }

    private func setContainer(_ records: [Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "presets": records])
        userDefaults.set(data, forKey: PresetStore.storageKey)
    }
}
