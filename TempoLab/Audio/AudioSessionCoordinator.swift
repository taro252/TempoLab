import AVFoundation
import Foundation

/// 入出力に共通のAudio Sessionを一度だけ構成し、通常のStart/Stopでは変更しない。
nonisolated final class AudioSessionCoordinator: @unchecked Sendable {
    static let shared = AudioSessionCoordinator()

    private let lock = NSLock()
    private var isActive = false
    #if os(iOS)
    private var interruptionToken: NSObjectProtocol?
    #endif

    private init() {
        #if os(iOS)
        interruptionToken = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] notification in
            guard let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: rawValue) == .began,
                  let self else { return }
            self.lock.withLock { self.isActive = false }
        }
        #endif
    }

    func beginPlayback() throws {
        try activateIfNeeded()
    }

    func beginInput() throws {
        try activateIfNeeded()
    }

    // 入力停止後も再生側のEngineと共有Sessionをwarmに保つ。
    func endInput() {}

    var isReady: Bool {
        #if os(iOS)
        return lock.withLock { isActive }
        #else
        return true
        #endif
    }

    private func activateIfNeeded() throws {
        lock.lock()
        defer { lock.unlock() }
        #if os(iOS)
        guard !isActive else { return }
        let session = AVAudioSession.sharedInstance()
        // マイクとバックグラウンド再生を同時に使える構成を最初から選ぶ。
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.mixWithOthers, .defaultToSpeaker]
        )
        try session.setActive(true)
        isActive = true
        #endif
    }
}
