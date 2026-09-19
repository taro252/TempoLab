import Combine
import Foundation

@MainActor
final class TempoDetectorViewModel: ObservableObject {
    @Published private(set) var permissionState: MicrophonePermissionState
    @Published private(set) var lifecycleState: AudioInputLifecycleState = .stopped
    @Published private(set) var inputDecibels = AudioLevelMath.minimumDecibels
    @Published private(set) var normalizedInputLevel = 0.0
    @Published private(set) var detectedBPM: Int?
    @Published private(set) var message: String?

    private let audioInputEngine: any AudioInputEngineProtocol
    private var requestID = 0

    var isListening: Bool {
        lifecycleState == .listening
    }

    init(audioInputEngine: any AudioInputEngineProtocol = AudioInputEngine()) {
        self.audioInputEngine = audioInputEngine
        permissionState = audioInputEngine.permissionState()
    }

    func toggleListening() {
        if isListening || lifecycleState == .starting || lifecycleState == .requestingPermission {
            stopListening()
        } else {
            startListening()
        }
    }

    func startListening() {
        guard lifecycleState != .listening,
              lifecycleState != .starting,
              lifecycleState != .requestingPermission else { return }

        requestID += 1
        let activeRequestID = requestID
        message = nil
        detectedBPM = nil
        permissionState = audioInputEngine.permissionState()

        switch permissionState {
        case .granted:
            beginInput(requestID: activeRequestID)
        case .denied:
            lifecycleState = .failed(AudioInputEngineError.permissionDenied.localizedDescription)
            message = AudioInputEngineError.permissionDenied.localizedDescription
        case .undetermined:
            lifecycleState = .requestingPermission
            audioInputEngine.requestPermission { [weak self] state in
                guard let self, requestID == activeRequestID else { return }
                permissionState = state
                if state == .granted {
                    beginInput(requestID: activeRequestID)
                } else {
                    let errorMessage = AudioInputEngineError.permissionDenied.localizedDescription
                    lifecycleState = .failed(errorMessage)
                    message = errorMessage
                }
            }
        }
    }

    func stopListening() {
        requestID += 1
        audioInputEngine.stop()
        lifecycleState = .stopped
        resetLevel()
    }

    func applicationBecameInactive() {
        guard isListening || lifecycleState == .starting else { return }
        stopListening()
        message = "バックグラウンド移行によりマイク入力を停止しました。"
    }

    private func beginInput(requestID activeRequestID: Int) {
        lifecycleState = .starting
        audioInputEngine.start(
            bufferHandler: nil,
            levelHandler: { [weak self] decibels, normalized in
                guard let self,
                      requestID == activeRequestID,
                      lifecycleState == .listening else { return }
                inputDecibels = decibels
                normalizedInputLevel = normalized
            },
            stopHandler: { [weak self] reason in
                guard let self, requestID == activeRequestID else { return }
                requestID += 1
                lifecycleState = .stopped
                resetLevel()
                message = Self.message(for: reason)
            },
            completion: { [weak self] result in
                guard let self, requestID == activeRequestID else { return }
                switch result {
                case .success:
                    lifecycleState = .listening
                case let .failure(error):
                    lifecycleState = .failed(error.localizedDescription)
                    message = error.localizedDescription
                    resetLevel()
                }
            }
        )
    }

    private func resetLevel() {
        inputDecibels = AudioLevelMath.minimumDecibels
        normalizedInputLevel = 0
    }

    private static func message(for reason: AudioInputStopReason) -> String {
        switch reason {
        case .interruption:
            return "オーディオ割り込みによりマイク入力を停止しました。"
        case .routeChanged:
            return "入力機器の変更によりマイク入力を停止しました。"
        case .engineConfigurationChanged:
            return "オーディオ構成の変更によりマイク入力を停止しました。"
        }
    }
}
