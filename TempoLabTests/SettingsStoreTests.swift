import Foundation
import XCTest
@testable import TempoLab

final class SettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "jp.taro252.TempoLabTests.\(UUID().uuidString)"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testSavedSettingsAreRestoredByNewStore() {
        let settings = AppSettings(
            bpm: 150,
            timeSignature: .threeFour,
            clickSoundSettings: ClickSoundSettings(
                normalFrequency: 600,
                accentFrequency: 1_600,
                volume: 0.7,
                soundType: .wood
            ),
            keepScreenAwake: true
        )

        SettingsStore(userDefaults: userDefaults).save(settings)
        let restored = SettingsStore(userDefaults: userDefaults).load()

        XCTAssertEqual(restored, settings)
    }

    func testInvalidStoredValuesAreValidatedWhenLoaded() throws {
        let invalidJSON = """
        {
          "bpm": 500,
          "timeSignature": { "numerator": 9, "denominator": 16 },
          "clickSoundSettings": {
            "normalFrequency": 100,
            "accentFrequency": 4000,
            "volume": 2,
            "soundType": "digital"
          },
          "keepScreenAwake": true
        }
        """
        userDefaults.set(
            try XCTUnwrap(invalidJSON.data(using: .utf8)),
            forKey: SettingsStore.storageKey
        )

        let restored = SettingsStore(userDefaults: userDefaults).load()

        XCTAssertEqual(restored.bpm, 300)
        XCTAssertEqual(restored.timeSignature, .fourFour)
        XCTAssertEqual(restored.clickSoundSettings.normalFrequency, 300)
        XCTAssertEqual(restored.clickSoundSettings.accentFrequency, 3_000)
        XCTAssertEqual(restored.clickSoundSettings.volume, 1)
        XCTAssertEqual(restored.clickSoundSettings.soundType, .digital)
        XCTAssertTrue(restored.keepScreenAwake)
    }

    func testCorruptDataFallsBackToDefaults() {
        userDefaults.set(Data("not-json".utf8), forKey: SettingsStore.storageKey)

        XCTAssertEqual(SettingsStore(userDefaults: userDefaults).load(), .default)
    }

    func testScreenAwakePolicyRequiresSettingAndPlayback() {
        XCTAssertTrue(
            ScreenAwakePolicy.shouldPreventSleep(keepScreenAwake: true, isRunning: true)
        )
        XCTAssertFalse(
            ScreenAwakePolicy.shouldPreventSleep(keepScreenAwake: true, isRunning: false)
        )
        XCTAssertFalse(
            ScreenAwakePolicy.shouldPreventSleep(keepScreenAwake: false, isRunning: true)
        )
    }
}
