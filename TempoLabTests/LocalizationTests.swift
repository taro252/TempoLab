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

    func testEnglishIsTheDevelopmentLanguageAndInputDialogIsTranslated() throws {
        XCTAssertEqual(Bundle.main.infoDictionary?["CFBundleDevelopmentRegion"] as? String, "en")

        let english = try languageBundle("en")
        let japanese = try languageBundle("ja")
        XCTAssertEqual(english.localizedString(forKey: "BPMを入力", value: nil, table: "Localizable"), "Enter BPM")
        XCTAssertEqual(english.localizedString(forKey: "キャンセル", value: nil, table: "Localizable"), "Cancel")
        XCTAssertEqual(japanese.localizedString(forKey: "BPMを入力", value: nil, table: "Localizable"), "BPMを入力")
    }

    func testPresetActionsAndErrorsAreLocalized() throws {
        let english = try languageBundle("en")
        let japanese = try languageBundle("ja")
        let translations = [
            "プリセット": "Presets", "現在の設定を保存": "Save Current Settings",
            "プリセット名": "Preset Name", "名前変更": "Rename", "上書き保存": "Overwrite",
            "変更あり": "Modified", "保存": "Save", "プリセットがありません": "No Presets",
            "プリセットを保存できませんでした。": "Presets could not be saved."
        ]
        for (key, value) in translations {
            XCTAssertEqual(english.localizedString(forKey: key, value: nil, table: "Localizable"), value)
            XCTAssertEqual(japanese.localizedString(forKey: key, value: nil, table: "Localizable"), key)
        }
    }

    func testPresetSyncStatesAreLocalized() throws {
        let english = try languageBundle("en")
        let japanese = try languageBundle("ja")
        for (key, value) in ["iCloud同期中": "Syncing with iCloud", "iCloud利用不可": "iCloud Unavailable", "同期エラー": "Sync Error", "今すぐ同期": "Sync Now", "最終同期": "Last Sync"] {
            XCTAssertEqual(english.localizedString(forKey: key, value: nil, table: "Localizable"), value)
            XCTAssertEqual(japanese.localizedString(forKey: key, value: nil, table: "Localizable"), key)
        }
    }

    private func languageBundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }
}
