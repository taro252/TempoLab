import Foundation

nonisolated enum MicrophonePermissionState: Sendable, Equatable {
    case undetermined
    case granted
    case denied

    var displayName: String {
        switch self {
        case .undetermined:
            return String(localized: "未確認")
        case .granted:
            return String(localized: "許可済み")
        case .denied:
            return String(localized: "許可されていません")
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
            return String(localized: "マイクへのアクセスが許可されていません。システム設定でTempoLabのマイクアクセスを許可してください。")
        case .inputFormatUnavailable:
            return String(localized: "利用可能なマイク入力形式を取得できませんでした。")
        case let .startFailed(message):
            return String(format: String(localized: "マイク入力を開始できませんでした: %@"), message)
        }
    }
}
