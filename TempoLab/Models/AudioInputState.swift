import Foundation

nonisolated enum MicrophonePermissionState: Sendable, Equatable {
    case undetermined
    case granted
    case denied

    var displayName: String {
        switch self {
        case .undetermined:
            return "未確認"
        case .granted:
            return "許可済み"
        case .denied:
            return "許可されていません"
        }
    }
}

nonisolated enum AudioInputLifecycleState: Sendable, Equatable {
    case stopped
    case requestingPermission
    case starting
    case listening
    case failed(String)
}

nonisolated enum AudioInputStopReason: Sendable, Equatable {
    case interruption
    case routeChanged
    case engineConfigurationChanged
}

nonisolated enum AudioInputEngineError: Error, LocalizedError, Sendable {
    case permissionDenied
    case inputFormatUnavailable
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "マイクへのアクセスが許可されていません。システム設定でTempoLabのマイクアクセスを許可してください。"
        case .inputFormatUnavailable:
            return "利用可能なマイク入力形式を取得できませんでした。"
        case let .startFailed(message):
            return "マイク入力を開始できませんでした: \(message)"
        }
    }
}
