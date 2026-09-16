import AVFoundation

nonisolated enum ClickSoundGeneratorError: Error, Sendable {
    case bufferAllocationFailed
    case measureTooLong
}

nonisolated struct ClickSoundGenerator {
    private let clickDuration = 0.035

    func makeMeasureBuffer(
        bpm: Int,
        timeSignature: TimeSignature,
        settings: ClickSoundSettings = .default,
        format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let normalClick = try makeClickBuffer(isAccent: false, settings: settings, format: format)
        let accentClick = try makeClickBuffer(isAccent: true, settings: settings, format: format)
        let measureFrameCount = MetronomeTiming.framesPerMeasure(
            bpm: bpm,
            sampleRate: format.sampleRate,
            timeSignature: timeSignature
        )

        guard measureFrameCount > 0, measureFrameCount <= Int64(UInt32.max) else {
            throw ClickSoundGeneratorError.measureTooLong
        }

        let frameCount = AVAudioFrameCount(measureFrameCount)
        guard let measureBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let measureSamples = measureBuffer.floatChannelData?[0] else {
            throw ClickSoundGeneratorError.bufferAllocationFailed
        }

        measureBuffer.frameLength = frameCount
        measureSamples.initialize(repeating: 0, count: Int(frameCount))

        for beatIndex in 0..<timeSignature.numerator {
            let clickBuffer = MetronomeTiming.isAccent(beatIndex: beatIndex, timeSignature: timeSignature)
                ? accentClick
                : normalClick
            mix(
                clickBuffer,
                into: measureBuffer,
                startingAt: MetronomeTiming.samplePosition(
                    forBeat: beatIndex,
                    bpm: bpm,
                    sampleRate: format.sampleRate
                )
            )
        }

        return measureBuffer
    }

    func makeClickBuffer(
        isAccent: Bool,
        settings: ClickSoundSettings = .default,
        format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let frequency = Double(isAccent ? settings.accentFrequency : settings.normalFrequency)
        let frameCount = AVAudioFrameCount((format.sampleRate * clickDuration).rounded())
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData else {
            throw ClickSoundGeneratorError.bufferAllocationFailed
        }

        buffer.frameLength = frameCount
        let baseAmplitude = isAccent ? 0.9 : 0.68
        let sampleCount = Int(frameCount)

        for frame in 0..<sampleCount {
            let time = Double(frame) / format.sampleRate
            let envelope = envelope(
                frame: frame,
                frameCount: sampleCount,
                sampleRate: format.sampleRate,
                soundType: settings.soundType
            )
            let waveform = waveform(
                type: settings.soundType,
                frequency: frequency,
                time: time,
                frame: frame,
                sampleRate: format.sampleRate
            )
            let sample = Float(min(max(waveform * envelope * baseAmplitude, -1.0), 1.0))

            for channel in 0..<Int(format.channelCount) {
                channelData[channel][frame] = sample
            }
        }

        return buffer
    }

    private func waveform(
        type: ClickSoundType,
        frequency: Double,
        time: Double,
        frame: Int,
        sampleRate: Double
    ) -> Double {
        let phase = 2.0 * Double.pi * frequency * time

        switch type {
        case .sine:
            return sin(phase)
        case .square:
            return bandLimitedSquare(
                phase: phase,
                frequency: frequency,
                sampleRate: sampleRate,
                maximumHarmonic: 9
            ) * 0.72
        case .wood:
            let fundamental = sin(phase) * exp(-time * 85.0)
            let upper = sin(phase * 2.41) * exp(-time * 145.0) * 0.62
            let knock = sin(phase * 3.73) * exp(-time * 210.0) * 0.32
            return (fundamental + upper + knock) * 0.82
        case .digital:
            let square = bandLimitedSquare(
                phase: phase,
                frequency: frequency,
                sampleRate: sampleRate,
                maximumHarmonic: 5
            ) * 0.55
            let highTone = frequency * 3.0 < sampleRate / 2.0 ? sin(phase * 3.0) * 0.28 : 0
            let noise = deterministicNoise(frame: frame) * 0.22
            return square + highTone + noise
        }
    }

    private func bandLimitedSquare(
        phase: Double,
        frequency: Double,
        sampleRate: Double,
        maximumHarmonic: Int
    ) -> Double {
        let nyquist = sampleRate / 2.0
        var value = 0.0
        var harmonic = 1

        while harmonic <= maximumHarmonic, frequency * Double(harmonic) < nyquist {
            value += sin(phase * Double(harmonic)) / Double(harmonic)
            harmonic += 2
        }

        return value
    }

    private func envelope(
        frame: Int,
        frameCount: Int,
        sampleRate: Double,
        soundType: ClickSoundType
    ) -> Double {
        let attackFrames = max(1, Int(sampleRate * 0.0008))
        let releaseFrames = max(1, Int(sampleRate * 0.004))
        let attack = min(1.0, Double(frame) / Double(attackFrames))
        let remainingFrames = max(0, frameCount - 1 - frame)
        let release = min(1.0, Double(remainingFrames) / Double(releaseFrames))
        let time = Double(frame) / sampleRate
        let decayRate: Double

        switch soundType {
        case .sine: decayRate = 70
        case .square: decayRate = 82
        case .wood: decayRate = 48
        case .digital: decayRate = 105
        }

        return attack * exp(-time * decayRate) * release
    }

    private func deterministicNoise(frame: Int) -> Double {
        var value = UInt32(truncatingIfNeeded: frame &* 1_664_525 &+ 1_013_904_223)
        value ^= value >> 13
        value &*= 1_274_126_177
        return Double(value) / Double(UInt32.max) * 2.0 - 1.0
    }

    private func mix(
        _ source: AVAudioPCMBuffer,
        into destination: AVAudioPCMBuffer,
        startingAt startFrame: Int64
    ) {
        guard startFrame >= 0,
              let sourceSamples = source.floatChannelData?[0],
              let destinationSamples = destination.floatChannelData?[0] else {
            return
        }

        let availableFrames = Int64(destination.frameLength) - startFrame
        let framesToCopy = min(Int64(source.frameLength), max(0, availableFrames))
        guard framesToCopy > 0 else { return }

        for frameOffset in 0..<Int(framesToCopy) {
            destinationSamples[Int(startFrame) + frameOffset] += sourceSamples[frameOffset]
        }
    }
}
