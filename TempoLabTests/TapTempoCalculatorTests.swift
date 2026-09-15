import XCTest
@testable import TempoLab

final class TapTempoCalculatorTests: XCTestCase {
    func testFiveHundredMillisecondIntervalsProduce120BPM() {
        var calculator = TapTempoCalculator()

        XCTAssertNil(calculator.registerTap(at: 0.0))
        XCTAssertEqual(calculator.registerTap(at: 0.5), 120)
        XCTAssertEqual(calculator.registerTap(at: 1.0), 120)
        XCTAssertEqual(calculator.registerTap(at: 1.5), 120)
    }

    func testOneSecondIntervalsProduce60BPM() {
        var calculator = TapTempoCalculator()

        XCTAssertNil(calculator.registerTap(at: 10.0))
        XCTAssertEqual(calculator.registerTap(at: 11.0), 60)
        XCTAssertEqual(calculator.registerTap(at: 12.0), 60)
        XCTAssertEqual(calculator.registerTap(at: 13.0), 60)
    }

    func testSingleIrregularTapDoesNotDistortMedianTempo() {
        var calculator = TapTempoCalculator()
        let tapTimes = [0.0, 0.5, 1.0, 1.8, 2.3, 2.8]

        let results = tapTimes.compactMap { calculator.registerTap(at: $0) }

        XCTAssertEqual(results.last, 120)
    }

    func testTwoSecondGapStartsNewSession() {
        var calculator = TapTempoCalculator()

        XCTAssertNil(calculator.registerTap(at: 0.0))
        XCTAssertEqual(calculator.registerTap(at: 0.5), 120)
        XCTAssertNil(calculator.registerTap(at: 2.5))
        XCTAssertEqual(calculator.registerTap(at: 3.5), 60)
    }
}
