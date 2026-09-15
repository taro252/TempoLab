import AVFoundation

nonisolated enum ClickSoundGeneratorError: Error, Sendable {
    case bufferAllocationFailed
    case measureTooLong
}

nonisolated struct ClickSoundGenerator {
    private let normalFrequency = 950.0
    private let accentFrequency = 1_450.0
    private let clickDuration = 0.03

    func makeMeasureBuffer(
        bpm: Int,
        timeSignature: TimeSignature,
        format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let normalClick = try makeClickBuffer(frequency: normalFrequency, amplitude: 0.65, format: format)
        let accentClick = try makeClickBuffer(frequency: accentFrequency, amplitude: 0.9, format: format)
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

    private func makeClickBuffer(
        frequency: Double,
        amplitude: Float,
        format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount((format.sampleRate * clickDuration).rounded())
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0] else {
            throw ClickSoundGeneratorError.bufferAllocationFailed
        }

        buffer.frameLength = frameCount
        let attackFrames = max(1, Int(format.sampleRate * 0.001))
        let lastFrame = max(1, Int(frameCount) - 1)

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / format.sampleRate
            let attack = min(1.0, Double(frame) / Double(attackFrames))
            let decay = max(0.0, Double(lastFrame - frame) / Double(lastFrame))
            let envelope = attack * decay * decay
            samples[frame] = amplitude * Float(sin(2.0 * .pi * frequency * time) * envelope)
        }

        return buffer
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
