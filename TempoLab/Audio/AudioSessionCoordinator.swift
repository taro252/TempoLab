import AVFoundation
import Foundation

/// iOSの共有Audio Sessionを、再生側と入力側が互いに停止させず利用するための調整役。
nonisolated final class AudioSessionCoordinator: @unchecked Sendable {
    static let shared = AudioSessionCoordinator()

    private let lock = NSLock()
    private var playbackIsActive = false
    private var inputIsActive = false

    private init() {}

    func beginPlayback() throws {
        try updateActivity(playback: true)
    }

    func endPlayback() {
        try? updateActivity(playback: false)
    }

    func beginInput() throws {
        try updateActivity(input: true)
    }

    func endInput() {
        try? updateActivity(input: false)
    }

    private func updateActivity(
        playback: Bool? = nil,
        input: Bool? = nil
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        let previousPlayback = playbackIsActive
        let previousInput = inputIsActive
        playbackIsActive = playback ?? playbackIsActive
        inputIsActive = input ?? inputIsActive

        do {
            try applyAudioSession(
                previousPlayback: previousPlayback,
                previousInput: previousInput
            )
        } catch {
            playbackIsActive = previousPlayback
            inputIsActive = previousInput
            throw error
        }
    }

    private func applyAudioSession(
        previousPlayback: Bool,
        previousInput: Bool
    ) throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()

        if inputIsActive || playbackIsActive {
            if !previousInput && !previousPlayback {
                // 再生開始後にcategoryを切り替えると出力Engineが再構成され得るため、
                // 最初から入出力を共存できる構成でSessionを開始する。
                try session.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [.mixWithOthers, .defaultToSpeaker]
                )
                try session.setActive(true)
            }
            return
        }

        if previousPlayback || previousInput {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        }
        #endif
    }
}
