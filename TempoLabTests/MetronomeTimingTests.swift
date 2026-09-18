import XCTest
@testable import TempoLab

final class MetronomeTimingTests: XCTestCase {
    func testSamplesPerBeatAtCommonTempos() {
        XCTAssertEqual(MetronomeTiming.samplesPerBeat(bpm: 60, sampleRate: 48_000), 48_000)
        XCTAssertEqual(MetronomeTiming.samplesPerBeat(bpm: 120, sampleRate: 48_000), 24_000)
        XCTAssertEqual(MetronomeTiming.samplesPerBeat(bpm: 300, sampleRate: 48_000), 9_600)
    }

    func testBeatPositionsAreCalculatedFromUnroundedInterval() {
        let sampleRate = 44_100.0
        let bpm = 137

        XCTAssertEqual(
            MetronomeTiming.samplePosition(forBeat: 3, bpm: bpm, sampleRate: sampleRate),
            Int64((3.0 * sampleRate * 60.0 / Double(bpm)).rounded())
        )
    }

    func testSamplesPerSubdivisionAt120BPM() {
        XCTAssertEqual(
            MetronomeTiming.samplesPerSubdivision(
                bpm: 120, sampleRate: 48_000, subdivision: .quarter
            ),
            24_000
        )
        XCTAssertEqual(
            MetronomeTiming.samplesPerSubdivision(
                bpm: 120, sampleRate: 48_000, subdivision: .eighth
            ),
            12_000
        )
        XCTAssertEqual(
            MetronomeTiming.samplesPerSubdivision(
                bpm: 120, sampleRate: 48_000, subdivision: .triplet
            ),
            8_000
        )
        XCTAssertEqual(
            MetronomeTiming.samplesPerSubdivision(
                bpm: 120, sampleRate: 48_000, subdivision: .sixteenth
            ),
            6_000
        )
    }

    func testSixteenthSubdivisionAtMaximumTempoUsesTwentyStepsPerSecond() {
        XCTAssertEqual(
            MetronomeTiming.samplesPerSubdivision(
                bpm: 300, sampleRate: 48_000, subdivision: .sixteenth
            ),
            2_400
        )
    }

    func testLongTermSubdivisionPositionDoesNotAccumulateRoundedIntervalError() {
        let index: Int64 = 100_000
        let sampleRate = 44_100.0
        let bpm = 137
        let expected = Int64(
            (Double(index) * sampleRate * 60 / Double(bpm) / 3).rounded()
        )

        XCTAssertEqual(
            MetronomeTiming.samplePosition(
                forSubdivision: index,
                bpm: bpm,
                sampleRate: sampleRate,
                subdivision: .triplet
            ),
            expected
        )
    }

    func testMeasureFrameCountUsesTimeSignatureNumerator() {
        XCTAssertEqual(
            MetronomeTiming.framesPerMeasure(bpm: 120, sampleRate: 48_000, timeSignature: .fourFour),
            96_000
        )
        XCTAssertEqual(
            MetronomeTiming.framesPerMeasure(bpm: 120, sampleRate: 48_000, timeSignature: .sixEight),
            144_000
        )
    }

    func testFirstBeatOfEachMeasureIsAccent() {
        XCTAssertTrue(MetronomeTiming.isAccent(beatIndex: 0, timeSignature: .fourFour))
        XCTAssertFalse(MetronomeTiming.isAccent(beatIndex: 1, timeSignature: .fourFour))
        XCTAssertFalse(MetronomeTiming.isAccent(beatIndex: 3, timeSignature: .fourFour))
        XCTAssertTrue(MetronomeTiming.isAccent(beatIndex: 4, timeSignature: .fourFour))
        XCTAssertTrue(MetronomeTiming.isAccent(beatIndex: 6, timeSignature: .sixEight))
    }

    func testTempoChangeAfterBeatThreeInFourFourContinuesWithBeatFour() {
        let nextBeat = MetronomeTiming.nextBeatIndex(after: 2, timeSignature: .fourFour)

        XCTAssertEqual(nextBeat, 3)
        XCTAssertFalse(MetronomeTiming.isAccent(beatIndex: nextBeat, timeSignature: .fourFour))
    }

    func testTempoChangeAfterBeatFourInFourFourContinuesWithAccentBeatOne() {
        let nextBeat = MetronomeTiming.nextBeatIndex(after: 3, timeSignature: .fourFour)

        XCTAssertEqual(nextBeat, 0)
        XCTAssertTrue(MetronomeTiming.isAccent(beatIndex: nextBeat, timeSignature: .fourFour))
    }

    func testTempoChangeAfterBeatOneInThreeFourContinuesWithBeatTwo() {
        let nextBeat = MetronomeTiming.nextBeatIndex(after: 0, timeSignature: .threeFour)

        XCTAssertEqual(nextBeat, 1)
        XCTAssertFalse(MetronomeTiming.isAccent(beatIndex: nextBeat, timeSignature: .threeFour))
    }
}
