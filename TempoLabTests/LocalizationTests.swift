import Foundation
import XCTest

final class LocalizationTests: XCTestCase {
    func testJapaneseAndEnglishResourcesAreBundled() throws {
        let japanese = try languageBundle("ja")
        let english = try languageBundle("en")

        XCTAssertEqual(japanese.localizedString(forKey: "設定", value: nil, table: "Localizable"), "設定")
        XCTAssertEqual(english.localizedString(forKey: "設定", value: nil, table: "Localizable"), "Settings")
        XCTAssertEqual(english.localizedString(forKey: "音符単位", value: nil, table: "Localizable"), "Subdivision")
        XCTAssertEqual(english.localizedString(forKey: "NSMicrophoneUsageDescription", value: nil, table: "InfoPlist"),
                       "Microphone access is needed to analyze the tempo of your performance.")
    }

    private func languageBundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }
}
