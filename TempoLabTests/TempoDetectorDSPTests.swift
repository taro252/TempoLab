import XCTest
@testable import TempoLab

final class TempoDetectorDSPTests: XCTestCase {
    func testSyntheticClickTracksAt44100Hz() throws {
        try assertDetectedTempos(sampleRate: 44_100)
    }

    func testSyntheticClickTracksAt48000Hz() throws {
        try assertDetectedTempos(sampleRate: 48_000)
    }

    func testClickTrackWithWhiteNoiseRemainsAccurate() throws {
        let samples = SyntheticClickTrackGenerator.make(
            bpm: 120,
            sampleRate: 48_000,
            noiseAmplitude: 0.012
        )
        let result = try XCTUnwrap(TempoDetectorDSP.analyze(samples: samples, sampleRate: 48_000))
        XCTAssertEqual(result.bpm, 120, accuracy: 2)
    }

    func testSilenceDoesNotProduceResult() {
        let silence = [Float](repeating: 0, count: 10 * 44_100)
        XCTAssertNil(TempoDetectorDSP.analyze(samples: silence, sampleRate: 44_100))
    }

    func testWhiteNoiseDoesNotProduceConfidentTempo() {
        let noise = SyntheticClickTrackGenerator.noise(sampleRate: 48_000)
        let result = TempoDetectorDSP.analyze(samples: noise, sampleRate: 48_000)
        XCTAssertTrue(
            result == nil || result!.confidence < 0.3,
            "ホワイトノイズの検出結果: \(String(describing: result))"
        )
    }

    func test120BPMIsNotReportedAsHalfTime() throws {
        let samples = SyntheticClickTrackGenerator.make(bpm: 120, sampleRate: 48_000)
        let result = try XCTUnwrap(TempoDetectorDSP.analyze(samples: samples, sampleRate: 48_000))
        XCTAssertEqual(result.bpm, 120, accuracy: 2)
        XCTAssertNotEqual(result.bpm, 60, accuracy: 2)
    }

    func test80BPMDoesNotBecomeFixedAtDoubleTime() throws {
        let samples = SyntheticClickTrackGenerator.make(bpm: 80, sampleRate: 44_100)
        let result = try XCTUnwrap(TempoDetectorDSP.analyze(samples: samples, sampleRate: 44_100))
        XCTAssertEqual(result.bpm, 80, accuracy: 2)
    }

    func testMissingClicksRemainAccurate() throws {
        let samples = SyntheticClickTrackGenerator.make(
            bpm: 140,
            duration: 12,
            sampleRate: 48_000,
            omittedBeatIndices: [3, 8, 14, 19]
        )
        let result = try XCTUnwrap(TempoDetectorDSP.analyze(samples: samples, sampleRate: 48_000))
        XCTAssertEqual(result.bpm, 140, accuracy: 2)
    }

    func testLongTrackRemainsStable() throws {
        let samples = SyntheticClickTrackGenerator.make(
            bpm: 120,
            duration: 20,
            sampleRate: 48_000,
            noiseAmplitude: 0.006,
            omittedBeatIndices: [7, 19, 31]
        )
        let analyzer = TempoDetectorDSP()
        let chunkSize = 4_096
        var results: [Double] = []

        for start in stride(from: 0, to: samples.count, by: chunkSize) {
            let end = min(start + chunkSize, samples.count)
            let chunk = Array(samples[start..<end])
            let result = chunk.withUnsafeBufferPointer {
                analyzer.process(samples: $0, sampleRate: 48_000)
            }
            if let result {
                results.append(result.bpm)
            }
        }

        XCTAssertGreaterThanOrEqual(results.count, 8)
        XCTAssertTrue(results.suffix(5).allSatisfy { abs($0 - 120) <= 2 })
    }

    func testCandidateAndConfidenceRanges() throws {
        let samples = SyntheticClickTrackGenerator.make(bpm: 100, sampleRate: 44_100)
        let result = try XCTUnwrap(TempoDetectorDSP.analyze(samples: samples, sampleRate: 44_100))

        XCTAssertTrue((0...1).contains(result.confidence))
        XCTAssertFalse(result.candidates.isEmpty)
        XCTAssertLessThanOrEqual(result.candidates.count, 3)
        XCTAssertTrue(result.candidates.allSatisfy { (0...1).contains($0.score) })
        XCTAssertTrue(result.candidates.allSatisfy { (50...220).contains($0.bpm) })
    }

    private func assertDetectedTempos(
        sampleRate: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for expectedBPM in [60.0, 80, 100, 120, 140, 160, 180, 200] {
            let samples = SyntheticClickTrackGenerator.make(
                bpm: expectedBPM,
                sampleRate: sampleRate
            )
            let result = try XCTUnwrap(
                TempoDetectorDSP.analyze(samples: samples, sampleRate: sampleRate),
                "\(expectedBPM) BPM / \(sampleRate) Hzで結果がありません",
                file: file,
                line: line
            )
            XCTAssertEqual(
                result.bpm,
                expectedBPM,
                accuracy: 2,
                "\(sampleRate) Hz: expected \(expectedBPM), actual \(result.bpm)",
                file: file,
                line: line
            )
        }
    }
}
