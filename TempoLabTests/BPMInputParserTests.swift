import XCTest
@testable import TempoLab

final class BPMInputParserTests: XCTestCase {
    func testValidValues() {
        XCTAssertEqual(BPMInputParser.parse("30"), 30)
        XCTAssertEqual(BPMInputParser.parse("120"), 120)
        XCTAssertEqual(BPMInputParser.parse("300"), 300)
    }

    func testValuesOutsideRangeAreClamped() {
        XCTAssertEqual(BPMInputParser.parse("20"), 30)
        XCTAssertEqual(BPMInputParser.parse("350"), 300)
        XCTAssertEqual(BPMInputParser.parse("0"), 30)
    }

    func testEmptyAndInvalidValuesAreIgnored() {
        XCTAssertNil(BPMInputParser.parse(""))
        XCTAssertNil(BPMInputParser.parse("  "))
        XCTAssertNil(BPMInputParser.parse("abc"))
    }
}
