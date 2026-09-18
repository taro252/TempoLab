import XCTest
@testable import TempoLab

final class PlaybackPositionTests: XCTestCase {
    func testQuarterFourFourPositions() throws {
        for step in 0..<4 {
            let position = try XCTUnwrap(
                PlaybackPosition(
                    stepIndex: step,
                    timeSignature: .fourFour,
                    subdivision: .quarter
                )
            )
            XCTAssertEqual(position.beatIndex, step)
            XCTAssertEqual(position.subdivisionIndex, 0)
        }
    }

    func testEighthFourFourPositions() throws {
        for step in 0..<8 {
            let position = try XCTUnwrap(
                PlaybackPosition(
                    stepIndex: step,
                    timeSignature: .fourFour,
                    subdivision: .eighth
                )
            )
            XCTAssertEqual(position.beatIndex, step / 2)
            XCTAssertEqual(position.subdivisionIndex, step % 2)
        }
    }

    func testTripletFourFourPositions() throws {
        for step in 0..<12 {
            let position = try XCTUnwrap(
                PlaybackPosition(
                    stepIndex: step,
                    timeSignature: .fourFour,
                    subdivision: .triplet
                )
            )
            XCTAssertEqual(position.beatIndex, step / 3)
            XCTAssertEqual(position.subdivisionIndex, step % 3)
        }
    }

    func testSixteenthLastStepIsBeatFourSubdivisionFour() throws {
        let position = try XCTUnwrap(
            PlaybackPosition(
                stepIndex: 15,
                timeSignature: .fourFour,
                subdivision: .sixteenth
            )
        )

        XCTAssertEqual(position.beatIndex, 3)
        XCTAssertEqual(position.subdivisionIndex, 3)
    }

    func testMuteDoesNotRemovePositionFromTimeline() throws {
        let pattern = AccentPattern(
            timeSignature: .fourFour,
            subdivision: .quarter,
            steps: [.accent, .mute, .normal, .normal]
        )
        let position = try XCTUnwrap(
            PlaybackPosition(
                stepIndex: 1,
                timeSignature: pattern.timeSignature,
                subdivision: pattern.subdivision
            )
        )

        XCTAssertEqual(pattern.emphasis(at: position.stepIndex), .mute)
        XCTAssertEqual(position.beatIndex, 1)
    }

    func testOutOfRangeStepIsRejected() {
        XCTAssertNil(
            PlaybackPosition(
                stepIndex: 4,
                timeSignature: .fourFour,
                subdivision: .quarter
            )
        )
    }
}
