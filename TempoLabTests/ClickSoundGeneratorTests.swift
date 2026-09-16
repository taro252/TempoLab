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

        let clickFrameCount = Int(format.sampleRate * 0.035)
        let beatPositions = [0, 24_000, 48_000, 72_000]
        let peaks = beatPositions.map { beatPosition in
            (beatPosition..<(beatPosition + clickFrameCount))
                .map { abs(samples[$0]) }
                .max() ?? 0
        }

        XCTAssertTrue(peaks.allSatisfy { $0 > 0 })
        XCTAssertGreaterThan(peaks[0], peaks[1])
    }

    func testClickSoundSettingsClampFrequenciesAndVolume() {
        let settings = ClickSoundSettings(
            normalFrequency: 100,
            accentFrequency: 4_000,
            volume: 1.5
        )

        XCTAssertEqual(settings.normalFrequency, 300)
        XCTAssertEqual(settings.accentFrequency, 3_000)
        XCTAssertEqual(settings.volume, 1)

        let oppositeBounds = ClickSoundSettings(
            normalFrequency: 2_500,
            accentFrequency: 100,
            volume: -0.2
        )

        XCTAssertEqual(oppositeBounds.normalFrequency, 2_000)
        XCTAssertEqual(oppositeBounds.accentFrequency, 300)
        XCTAssertEqual(oppositeBounds.volume, 0)
    }

    func testAllSoundTypesGenerateFiniteSafeSamples() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let generator = ClickSoundGenerator()

        for soundType in ClickSoundType.allCases {
            let settings = ClickSoundSettings(soundType: soundType)
            let buffer = try generator.makeClickBuffer(
                isAccent: false,
                settings: settings,
                format: format
            )
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            let values = (0..<Int(buffer.frameLength)).map { samples[$0] }

            XCTAssertGreaterThan(buffer.frameLength, 0, "\(soundType)")
            XCTAssertTrue(values.allSatisfy(\.isFinite), "\(soundType)")
            XCTAssertLessThanOrEqual(values.map { abs($0) }.max() ?? 0, 1, "\(soundType)")
            XCTAssertGreaterThan(values.map { abs($0) }.max() ?? 0, 0, "\(soundType)")
        }
    }
}
