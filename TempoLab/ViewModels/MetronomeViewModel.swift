import Combine
import Foundation

@MainActor
final class MetronomeViewModel: ObservableObject {
    static let bpmRange = 30...300

    @Published private(set) var bpm = 120
    @Published private(set) var isRunning = false
    @Published private(set) var audioErrorMessage: String?
    @Published var selectedTimeSignature = TimeSignature.fourFour {
        didSet {
            updateEngineIfRunning()
        }
    }

    private var tapTempoCalculator = TapTempoCalculator(bpmRange: bpmRange)
    private let metronomeEngine: MetronomeEngine
    private var playbackRequestID = 0

    init(metronomeEngine: MetronomeEngine = MetronomeEngine()) {
        self.metronomeEngine = metronomeEngine
    }

    func setBPM(_ value: Double) {
        bpm = clampedBPM(Int(value.rounded()))
        updateEngineIfRunning()
    }

    func adjustBPM(by amount: Int) {
        bpm = clampedBPM(bpm + amount)
        updateEngineIfRunning()
    }

    func toggleRunning() {
        playbackRequestID += 1

        if isRunning {
            isRunning = false
            metronomeEngine.stop()
            return
        }

        let requestID = playbackRequestID
        audioErrorMessage = nil
        isRunning = true
        metronomeEngine.start(bpm: bpm, timeSignature: selectedTimeSignature) { [weak self] result in
            guard let self, playbackRequestID == requestID else { return }
            if case let .failure(error) = result {
                isRunning = false
                audioErrorMessage = error.localizedDescription
            }
        }
    }

    func registerTap(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if let calculatedBPM = tapTempoCalculator.registerTap(at: time) {
            bpm = calculatedBPM
            updateEngineIfRunning()
        }
    }

    func dismissAudioError() {
        audioErrorMessage = nil
    }

    private func clampedBPM(_ value: Int) -> Int {
        min(max(value, Self.bpmRange.lowerBound), Self.bpmRange.upperBound)
    }

    private func updateEngineIfRunning() {
        guard isRunning else { return }
        let requestID = playbackRequestID

        metronomeEngine.update(bpm: bpm, timeSignature: selectedTimeSignature) { [weak self] error in
            guard let self, playbackRequestID == requestID else { return }
            isRunning = false
            audioErrorMessage = error.localizedDescription
        }
    }
}
