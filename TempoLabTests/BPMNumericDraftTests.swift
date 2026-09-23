import XCTest
@testable import TempoLab

final class BPMNumericDraftTests: XCTestCase {
    func testFirstDigitReplacesCurrentBPM() {
        var draft = BPMNumericDraft(bpm: 120)
        draft.append(1)
        draft.append(5)
        draft.append(0)
        XCTAssertEqual(draft.text, "150")
    }

    func testInputStopsAtThreeDigits() {
        var draft = BPMNumericDraft(bpm: 120)
        for digit in [3, 0, 0, 9] { draft.append(digit) }
        XCTAssertEqual(draft.text, "300")
    }

    func testDeleteCanClearInitialValue() {
        var draft = BPMNumericDraft(bpm: 120)
        draft.delete()
        XCTAssertEqual(draft.text, "")
        XCTAssertNil(BPMInputParser.parse(draft.text))
    }
}
