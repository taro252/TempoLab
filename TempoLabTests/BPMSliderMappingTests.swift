import XCTest
@testable import TempoLab

final class BPMSliderMappingTests: XCTestCase {
    func testLocationMapsLinearlyToIntegerBPM() {
        XCTAssertEqual(BPMSliderMapping.bpm(at: 0, trackWidth: 270, range: 30...300), 30)
        XCTAssertEqual(BPMSliderMapping.bpm(at: 90, trackWidth: 270, range: 30...300), 120)
        XCTAssertEqual(BPMSliderMapping.bpm(at: 120, trackWidth: 270, range: 30...300), 150)
        XCTAssertEqual(BPMSliderMapping.bpm(at: 270, trackWidth: 270, range: 30...300), 300)
    }

    func testFinalLocationIsRoundedOnceToNearestBPM() {
        XCTAssertEqual(BPMSliderMapping.bpm(at: 119.6, trackWidth: 270, range: 30...300), 150)
        XCTAssertEqual(BPMSliderMapping.bpm(at: 120.4, trackWidth: 270, range: 30...300), 150)
    }

    func testLocationIsClampedToRange() {
        XCTAssertEqual(BPMSliderMapping.bpm(at: -20, trackWidth: 270, range: 30...300), 30)
        XCTAssertEqual(BPMSliderMapping.bpm(at: 400, trackWidth: 270, range: 30...300), 300)
    }
}
