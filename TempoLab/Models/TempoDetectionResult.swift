import Foundation

nonisolated struct TempoCandidate: Sendable, Equatable, Identifiable {
    let bpm: Double
    let score: Double

    var id: Int {
        Int((bpm * 10).rounded())
    }
}

nonisolated struct TempoDetectionResult: Sendable, Equatable {
    let bpm: Double
    let confidence: Double
    let candidates: [TempoCandidate]
}

nonisolated struct TempoDetectionConfiguration: Sendable, Equatable {
    var bpmRange: ClosedRange<Double> = 50...220
    var fftSize = 2_048
    var hopSize = 512
    var minimumAnalysisDuration = 4.0
    var maximumHistoryDuration = 12.0
    var analysisInterval = 0.5
    var minimumFrequency = 40.0
    var maximumFrequency = 8_000.0
}
