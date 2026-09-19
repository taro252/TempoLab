import XCTest
@testable import TempoLab

final class AudioLevelMathTests: XCTestCase {
    func testRootMeanSquareForKnownSamples() {
        let rms = AudioLevelMath.rootMeanSquare(samples: [1, -1, 1, -1])
        XCTAssertEqual(rms, 1, accuracy: 0.000_001)
    }

    func testSilenceUsesMinimumDecibels() {
        XCTAssertEqual(
            AudioLevelMath.decibels(fromRootMeanSquare: 0),
            AudioLevelMath.minimumDecibels
        )
    }

    func testDecibelsAreClampedToMeterRange() {
        XCTAssertEqual(AudioLevelMath.decibels(fromRootMeanSquare: 10), 0)
        XCTAssertEqual(
            AudioLevelMath.decibels(fromRootMeanSquare: 0.000_000_1),
            AudioLevelMath.minimumDecibels
        )
    }

    func testNormalizedLevelIsClampedFromZeroToOne() {
        XCTAssertEqual(AudioLevelMath.normalizedLevel(decibels: -100), 0)
        XCTAssertEqual(AudioLevelMath.normalizedLevel(decibels: -30), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(AudioLevelMath.normalizedLevel(decibels: 10), 1)
    }

    func testInvalidValuesRemainFinite() {
        let decibels = AudioLevelMath.decibels(fromRootMeanSquare: .nan)
        let normalized = AudioLevelMath.normalizedLevel(decibels: .infinity)

        XCTAssertTrue(decibels.isFinite)
        XCTAssertTrue(normalized.isFinite)
    }
}
