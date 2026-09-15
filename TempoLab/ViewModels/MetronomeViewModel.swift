import Combine
import Foundation

@MainActor
final class MetronomeViewModel: ObservableObject {
    static let bpmRange = 30...300

    @Published private(set) var bpm = 120
    @Published private(set) var isRunning = false
    @Published var selectedTimeSignature = TimeSignature.fourFour

    private var tapTempoCalculator = TapTempoCalculator(bpmRange: bpmRange)

    func setBPM(_ value: Double) {
        bpm = clampedBPM(Int(value.rounded()))
    }

    func adjustBPM(by amount: Int) {
        bpm = clampedBPM(bpm + amount)
    }

    func toggleRunning() {
        isRunning.toggle()
    }

    func registerTap(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if let calculatedBPM = tapTempoCalculator.registerTap(at: time) {
            bpm = calculatedBPM
        }
    }

    private func clampedBPM(_ value: Int) -> Int {
        min(max(value, Self.bpmRange.lowerBound), Self.bpmRange.upperBound)
    }
}
