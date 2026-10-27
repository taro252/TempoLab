import Foundation
import XCTest
@testable import TempoLab

final class MetronomePresetTests: XCTestCase {
    func testConfigurationAndMetadataRoundTrip() throws {
        let preset = try MetronomePreset(name: "  練習 🎵  ", configuration: configuration())
        let restored = try JSONDecoder().decode(
            MetronomePreset.self, from: JSONEncoder().encode(preset)
        )
        XCTAssertEqual(restored, preset)
        XCTAssertEqual(restored.name, "練習 🎵")
        XCTAssertEqual(restored.configuration.accentPattern.steps[1], .mute)
    }

    func testNameMustContainNonWhitespaceAndDuplicatesHaveDifferentIDs() throws {
        XCTAssertThrowsError(try MetronomePreset(name: " \n\t ", configuration: configuration()))
        let first = try MetronomePreset(name: "練習", configuration: configuration())
        let second = try MetronomePreset(name: "練習", configuration: configuration())
        XCTAssertNotEqual(first.id, second.id)
    }

    func testRenamePreservesIdentityAndCreationDate() throws {
        var preset = try MetronomePreset(name: "元", configuration: configuration(), createdAt: .distantPast)
        let id = preset.id
        try preset.rename("  日本語の名前 🎹 \n")
        XCTAssertEqual(preset.id, id)
        XCTAssertEqual(preset.createdAt, .distantPast)
        XCTAssertEqual(preset.name, "日本語の名前 🎹")
        XCTAssertGreaterThan(preset.updatedAt, preset.createdAt)
        XCTAssertThrowsError(try preset.rename(" \n"))
        XCTAssertEqual(preset.name, "日本語の名前 🎹")
    }

    func testDecodedValuesAreNormalizedAndMismatchedPatternFallsBack() throws {
        var object = try configurationObject()
        object["bpm"] = 999
        object["timeSignature"] = ["numerator": 9, "denominator": 16]
        object["subdivision"] = "sixteenth"
        object["clickSoundSettings"] = [
            "normalFrequency": 100, "accentFrequency": 9000,
            "volume": 2.0, "soundType": "digital"
        ]
        let restored = try decode(object)
        XCTAssertEqual(restored.bpm, 300)
        XCTAssertEqual(restored.timeSignature, .fourFour)
        XCTAssertEqual(restored.subdivision, .sixteenth)
        XCTAssertEqual(restored.accentPattern, .defaultPattern(timeSignature: .fourFour, subdivision: .sixteenth))
        XCTAssertEqual(restored.clickSoundSettings, ClickSoundSettings(
            normalFrequency: 300, accentFrequency: 3000, volume: 1, soundType: .digital
        ))
    }

    func testInvalidStepCountAndSubdivisionAreSafelyRestored() throws {
        var object = try configurationObject()
        object["bpm"] = -1
        object["subdivision"] = "unknown"
        object["accentPattern"] = [
            "timeSignature": ["numerator": 6, "denominator": 8],
            "subdivision": "quarter", "steps": ["accent"]
        ] as [String: Any]
        let restored = try decode(object)
        XCTAssertEqual(restored.bpm, 30)
        XCTAssertEqual(restored.subdivision, .quarter)
        XCTAssertEqual(restored.accentPattern, .defaultPattern(timeSignature: .sixEight, subdivision: .quarter))
    }

    func testMalformedAccentStepsFallBackWithoutLosingConfiguration() throws {
        var object = try configurationObject()
        object["accentPattern"] = ["steps": ["unknown"]]
        let restored = try decode(object)
        XCTAssertEqual(restored.accentPattern, .defaultPattern(timeSignature: .sixEight, subdivision: .eighth))
        XCTAssertEqual(restored.clickSoundSettings, configuration().clickSoundSettings)
    }

    func testClickSettingsValidateWhenDecodedDirectly() throws {
        let data = Data(#"{"normalFrequency":-10,"accentFrequency":9999,"volume":-2,"soundType":"wood"}"#.utf8)
        let settings = try JSONDecoder().decode(ClickSoundSettings.self, from: data)
        XCTAssertEqual(settings.normalFrequency, 300)
        XCTAssertEqual(settings.accentFrequency, 3000)
        XCTAssertEqual(settings.volume, 0)
        XCTAssertEqual(settings.soundType, .wood)
        XCTAssertEqual(ClickSoundSettings(volume: .nan).volume, ClickSoundSettings.default.volume)
    }

    func testEncodedPresetContainsOnlySelectedPatternAndNoPlaybackOrScreenState() throws {
        let object = try configurationObject()
        XCTAssertEqual(Set(object.keys), Set([
            "bpm", "timeSignature", "subdivision", "accentPattern", "clickSoundSettings"
        ]))
    }

    private func configuration() -> PresetConfiguration {
        PresetConfiguration(
            bpm: 180, timeSignature: .sixEight, subdivision: .eighth,
            accentPattern: AccentPattern(
                timeSignature: .sixEight, subdivision: .eighth,
                steps: [.accent, .mute] + Array(repeating: .normal, count: 10)
            ),
            clickSoundSettings: ClickSoundSettings(
                normalFrequency: 600, accentFrequency: 1800, volume: 0.35, soundType: .wood
            )
        )
    }

    private func configurationObject() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration())) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> PresetConfiguration {
        try JSONDecoder().decode(PresetConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
