import AVFoundation
import XCTest
@testable import TempoLab

final class ClickSoundGeneratorTests: XCTestCase {
    func testMeasureBufferContainsSamplePositionedClicksAndStrongerAccent() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try ClickSoundGenerator().makeMeasureBuffer(
            bpm: 120,
            timeSignature: .fourFour,
            format: format
        )
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])

        XCTAssertEqual(buffer.frameLength, 96_000)

        let clickFrameCount = Int(format.sampleRate * 0.03)
        let beatPositions = [0, 24_000, 48_000, 72_000]
        let peaks = beatPositions.map { beatPosition in
            (beatPosition..<(beatPosition + clickFrameCount))
                .map { abs(samples[$0]) }
                .max() ?? 0
        }

        XCTAssertTrue(peaks.allSatisfy { $0 > 0 })
        XCTAssertGreaterThan(peaks[0], peaks[1])
    }
}
