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
}
