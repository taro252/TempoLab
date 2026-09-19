import Foundation

enum SyntheticClickTrackGenerator {
    static func make(
        bpm: Double,
        duration: Double = 10,
        sampleRate: Double,
        noiseAmplitude: Float = 0,
        omittedBeatIndices: Set<Int> = []
    ) -> [Float] {
        let sampleCount = Int(duration * sampleRate)
        var samples = [Float](repeating: 0, count: sampleCount)
        let samplesPerBeat = sampleRate * 60 / bpm
        let clickLength = max(1, Int(sampleRate * 0.018))
        var beatIndex = 0
        var beatPosition = 0.0

        while Int(beatPosition) < sampleCount {
            if !omittedBeatIndices.contains(beatIndex) {
                let start = Int(beatPosition.rounded())
                for offset in 0..<clickLength where start + offset < sampleCount {
                    let time = Double(offset) / sampleRate
                    let envelope = exp(-time * 180)
                    let tone = sin(2 * .pi * 1_200 * time)
                    let transient = offset == 0 ? 0.8 : 0
                    samples[start + offset] += Float((0.55 * tone + transient) * envelope)
                }
            }
            beatIndex += 1
            beatPosition = Double(beatIndex) * samplesPerBeat
        }

        if noiseAmplitude > 0 {
            var generator = DeterministicNoiseGenerator(state: 0x1234_5678)
            for index in samples.indices {
                samples[index] += generator.next() * noiseAmplitude
            }
        }
        return samples
    }

    static func noise(
        duration: Double = 10,
        sampleRate: Double,
        amplitude: Float = 0.02
    ) -> [Float] {
        var generator = DeterministicNoiseGenerator(state: 0x8765_4321)
        return (0..<Int(duration * sampleRate)).map { _ in
            generator.next() * amplitude
        }
    }
}

private struct DeterministicNoiseGenerator {
    var state: UInt64

    mutating func next() -> Float {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        let value = Float((state >> 40) & 0x00FF_FFFF) / Float(0x00FF_FFFF)
        return value * 2 - 1
    }
}
