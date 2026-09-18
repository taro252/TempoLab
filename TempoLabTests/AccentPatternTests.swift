import XCTest
@testable import TempoLab

final class AccentPatternTests: XCTestCase {
    func testSubdivisionDivisionsPerBeat() {
        XCTAssertEqual(Subdivision.quarter.divisionsPerBeat, 1)
        XCTAssertEqual(Subdivision.eighth.divisionsPerBeat, 2)
        XCTAssertEqual(Subdivision.triplet.divisionsPerBeat, 3)
        XCTAssertEqual(Subdivision.sixteenth.divisionsPerBeat, 4)
    }

    func testStepsPerMeasure() {
        XCTAssertEqual(stepCount(.fourFour, .quarter), 4)
        XCTAssertEqual(stepCount(.fourFour, .eighth), 8)
        XCTAssertEqual(stepCount(.fourFour, .triplet), 12)
        XCTAssertEqual(stepCount(.fourFour, .sixteenth), 16)
        XCTAssertEqual(stepCount(.threeFour, .triplet), 9)
        XCTAssertEqual(stepCount(.fiveFour, .sixteenth), 20)
    }

    func testDefaultFourFourQuarterPatternMatchesClassicMetronome() {
        let pattern = AccentPattern.defaultPattern(
            timeSignature: .fourFour,
            subdivision: .quarter
        )

        XCTAssertEqual(pattern.steps, [.accent, .normal, .normal, .normal])
    }

    func testStepCyclesFromAccentToNormalToMute() {
        var pattern = AccentPattern.defaultPattern(
            timeSignature: .fourFour,
            subdivision: .quarter
        )

        pattern.cycleStep(at: 0)
        XCTAssertEqual(pattern.steps[0], .normal)
        pattern.cycleStep(at: 0)
        XCTAssertEqual(pattern.steps[0], .mute)
        pattern.cycleStep(at: 0)
        XCTAssertEqual(pattern.steps[0], .accent)
    }

    func testMuteIsSilentWithoutRemovingItsTimelinePosition() {
        let pattern = AccentPattern(
            timeSignature: .twoFour,
            subdivision: .eighth,
            steps: [.accent, .mute, .normal, .normal]
        )

        XCTAssertFalse(pattern.emphasis(at: 1).isAudible)
        XCTAssertEqual(
            MetronomeTiming.samplePosition(
                forSubdivision: 2,
                bpm: 120,
                sampleRate: 48_000,
                subdivision: .eighth
            ),
            24_000
        )
    }

    private func stepCount(
        _ timeSignature: TimeSignature,
        _ subdivision: Subdivision
    ) -> Int {
        AccentPattern.stepCount(
            timeSignature: timeSignature,
            subdivision: subdivision
        )
    }
}
