import XCTest
@testable import TempoLab

final class BPMDialMathTests: XCTestCase {
    private let range = 30...300
    private let pointsPerBPM = 12.0

    func testZeroTranslationKeepsStartingBPM() {
        XCTAssertEqual(calculatedBPM(startBPM: 150, translation: 0), 150)
    }

    func testLeftDragRaisesBPMByOnePerTwelvePoints() {
        XCTAssertEqual(calculatedBPM(startBPM: 150, translation: -12), 151)
        XCTAssertEqual(calculatedBPM(startBPM: 150, translation: -24), 152)
    }

    func testRightDragLowersBPMByOnePerTwelvePoints() {
        XCTAssertEqual(calculatedBPM(startBPM: 150, translation: 12), 149)
    }

    func testResultIsClampedToBPMRange() {
        XCTAssertEqual(calculatedBPM(startBPM: 30, translation: 120), 30)
        XCTAssertEqual(calculatedBPM(startBPM: 300, translation: -120), 300)
    }

    private func calculatedBPM(startBPM: Int, translation: Double) -> Int {
        BPMDialMath.bpm(
            startBPM: startBPM,
            translation: translation,
            pointsPerBPM: pointsPerBPM,
            range: range
        )
    }
}
