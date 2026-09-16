import XCTest
@testable import TempoLab

final class ImmediateButtonTests: XCTestCase {
    func testPressBeginsOnlyOnceUntilItEnds() {
        var state = ImmediatePressState()

        XCTAssertTrue(state.begin())
        XCTAssertFalse(state.begin())
        XCTAssertFalse(state.begin())
        XCTAssertTrue(state.isActive)
    }

    func testPressCanBeginAgainAfterItEnds() {
        var state = ImmediatePressState()

        XCTAssertTrue(state.begin())
        state.end()
        XCTAssertFalse(state.isActive)
        XCTAssertTrue(state.begin())
    }
}
