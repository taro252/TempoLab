import AVFoundation
import XCTest
@testable import TempoLab

@MainActor
final class MetronomeEngineConfigurationTests: XCTestCase {
    func testWaveformChangeKeepsRemainingEighthNoteAndUsesNewWaveformAtBoundary() throws {
        let fixture = try OfflineMetronome(bpm: 120, subdivision: .eighth)
        defer { fixture.stop() }
        try fixture.render(chunks: 10)
        fixture.update(bpm: 120, subdivision: .eighth, settings: ClickSoundSettings(soundType: .wood))
        try fixture.render(chunks: 50)
        assertOnsets(fixture, [0, 250, 500])
        // 次の拍（第2拍）は通常クリック。PCMそのものが新しいWood波形と一致する。
        let click = try ClickSoundGenerator().makeClickBuffer(
            isAccent: false, settings: ClickSoundSettings(soundType: .wood), format: fixture.format
        )
        let channel = try XCTUnwrap(click.floatChannelData?[0])
        for index in 0..<Int(click.frameLength) {
            XCTAssertEqual(fixture.samples[24_000 + index], channel[index] * 0.8, accuracy: 0.00001)
        }
    }

    func testSlowerTempoFinishesCurrentBeatBeforeSwitching() throws {
        let fixture = try OfflineMetronome(bpm: 120, subdivision: .eighth)
        defer { fixture.stop() }
        try fixture.render(chunks: 10)
        fixture.update(bpm: 30, subdivision: .quarter)
        try fixture.render(chunks: 260)
        assertOnsets(fixture, [0, 250, 500, 2500])
    }

    func testFasterTempoPreservesCurrentClickAndThenUsesNewIntervals() throws {
        let fixture = try OfflineMetronome(bpm: 30, subdivision: .quarter)
        defer { fixture.stop() }
        try fixture.render(chunks: 10)
        fixture.update(bpm: 300, subdivision: .quarter)
        try fixture.render(chunks: 240)
        assertOnsets(fixture, [0, 2000, 2200, 2400])
    }

    func testRapidUpdatesKeepBoundaryAndUseFinalTempoMeterAndSubdivision() throws {
        let fixture = try OfflineMetronome(bpm: 120, subdivision: .eighth)
        defer { fixture.stop() }
        try fixture.render(chunks: 10)
        fixture.update(bpm: 180, signature: .sixEight, subdivision: .eighth, settings: ClickSoundSettings(soundType: .wood))
        try fixture.render(chunks: 10)
        fixture.update(bpm: 300, subdivision: .sixteenth)
        try fixture.render(chunks: 60)
        assertOnsets(fixture, [0, 250, 500, 550, 600, 650, 700, 750])
    }

    func testMutedStepIsSilentAfterSwitch() throws {
        let fixture = try OfflineMetronome(bpm: 120, subdivision: .quarter)
        defer { fixture.stop() }
        try fixture.render(chunks: 10)
        fixture.update(
            bpm: 120, subdivision: .quarter,
            pattern: AccentPattern(timeSignature: .fourFour, subdivision: .quarter,
                                   steps: [.accent, .mute, .normal, .normal])
        )
        try fixture.render(chunks: 100)
        assertOnsets(fixture, [0, 1000])
    }

    func testUpdateImmediatelyAfterStartDoesNotStopPlayback() throws {
        let fixture = try OfflineMetronome(bpm: 120, subdivision: .quarter)
        defer { fixture.stop() }
        fixture.update(bpm: 180, signature: .sixEight, subdivision: .eighth)
        try fixture.render(chunks: 60)
        XCTAssertFalse(fixture.onsetMilliseconds.isEmpty)
    }

    func testVolumeOnlyUpdateKeepsSamplePositionsAndScalesExistingBuffers() throws {
        let fixture = try OfflineMetronome(bpm: 120, subdivision: .eighth)
        defer { fixture.stop() }
        try fixture.render(chunks: 10)
        fixture.update(bpm: 120, subdivision: .eighth, settings: ClickSoundSettings(volume: 0.4))
        try fixture.render(chunks: 50)
        assertOnsets(fixture, [0, 250, 500])
        let click = try ClickSoundGenerator().makeClickBuffer(isAccent: false, format: fixture.format)
        let channel = try XCTUnwrap(click.floatChannelData?[0])
        // ネイティブミキサーの短い音量ランプが収束した、クリック末尾を比較する。
        let tail = (Int(click.frameLength) - 240)..<Int(click.frameLength)
        let actualEnergy = tail.reduce(0.0) { $0 + Double(abs(fixture.samples[12_000 + $1])) }
        let referenceEnergy = tail.reduce(0.0) { $0 + Double(abs(channel[$1])) }
        XCTAssertEqual(actualEnergy / referenceEnergy, 0.4, accuracy: 0.0001)
    }

    private func assertOnsets(
        _ fixture: OfflineMetronome, _ expected: [Double],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let actual = fixture.onsetMilliseconds
        XCTAssertEqual(actual.count, expected.count, "発音位置: \(actual)", file: file, line: line)
        for (actual, expected) in zip(actual, expected) {
            XCTAssertEqual(actual, expected, accuracy: 2, file: file, line: line)
        }
    }
}

/// 実際のAVAudioEngineをオフラインでレンダーし、スピーカーを使わず発音を検証する。
@MainActor
private final class OfflineMetronome {
    let format: AVAudioFormat
    private let audio = AVAudioEngine()
    private let queue = DispatchQueue(label: "app.merodoa.PiTempoTests.offline-scheduling")
    private let engine: MetronomeEngine
    private let output: AVAudioPCMBuffer
    private(set) var samples: [Float] = []

    init(bpm: Int, subdivision: Subdivision) throws {
        format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
        try audio.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 480)
        engine = MetronomeEngine(audioEngine: audio, schedulingQueue: queue)
        engine.start(
            actionUptime: 0, bpm: bpm, timeSignature: .fourFour, subdivision: subdivision,
            accentPattern: .defaultPattern(timeSignature: .fourFour, subdivision: subdivision),
            clickSettings: .default,
            positionHandler: { _ in },
            completion: { result in
                if case let .failure(error) = result { XCTFail(error.localizedDescription) }
            }
        )
        queue.sync {}
    }

    func update(
        bpm: Int, signature: TimeSignature = .fourFour, subdivision: Subdivision,
        settings: ClickSoundSettings = .default, pattern: AccentPattern? = nil
    ) {
        engine.updateConfiguration(
            bpm: bpm, timeSignature: signature, subdivision: subdivision,
            accentPattern: pattern ?? .defaultPattern(timeSignature: signature, subdivision: subdivision),
            clickSettings: settings,
            onFailure: { XCTFail($0.localizedDescription) }
        )
        queue.sync {}
    }

    func render(chunks: Int) throws {
        for _ in 0..<chunks {
            let status = try audio.renderOffline(480, to: output)
            XCTAssertEqual(status, .success)
            let channel = try XCTUnwrap(output.floatChannelData?[0])
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            queue.sync {}
        }
    }

    func stop() {
        engine.stop()
        queue.sync {}
        audio.stop()
    }

    var onsetMilliseconds: [Double] {
        var onsets: [Int] = []
        var wasAudible = false
        for start in stride(from: 0, to: max(0, samples.count - 48), by: 48) {
            let audible = samples[start..<start + 48].contains { abs($0) > 0.02 }
            if audible && !wasAudible && (onsets.last.map { start - $0 > 2000 } ?? true) {
                onsets.append(start)
            }
            wasAudible = audible
        }
        return onsets.map { Double($0) / 48 }
    }
}
