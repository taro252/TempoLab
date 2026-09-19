import AVFoundation
import Foundation

nonisolated enum AudioLevelMath {
    static let minimumDecibels = -60.0
    static let maximumDecibels = 0.0

    static func rootMeanSquare(samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }

        var sum = 0.0
        for sample in samples {
            let value = Double(sample)
            guard value.isFinite else { continue }
            sum += value * value
        }
        return sqrt(sum / Double(samples.count))
    }

    static func decibels(
        fromRootMeanSquare rms: Double,
        minimum: Double = minimumDecibels
    ) -> Double {
        guard rms.isFinite, rms > 0 else { return minimum }
        return min(max(20 * log10(rms), minimum), maximumDecibels)
    }

    static func normalizedLevel(
        decibels: Double,
        minimum: Double = minimumDecibels
    ) -> Double {
        guard decibels.isFinite, minimum < maximumDecibels else { return 0 }
        let clamped = min(max(decibels, minimum), maximumDecibels)
        return (clamped - minimum) / (maximumDecibels - minimum)
    }

    static func rootMeanSquare(buffer: AVAudioPCMBuffer) -> Double {
        guard buffer.frameLength > 0,
              let channelData = buffer.floatChannelData else { return 0 }

        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard channelCount > 0, frameCount > 0 else { return 0 }

        var sum = 0.0
        var sampleCount = 0
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameCount {
                let value = Double(samples[frame])
                guard value.isFinite else { continue }
                sum += value * value
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else { return 0 }
        return sqrt(sum / Double(sampleCount))
    }
}
