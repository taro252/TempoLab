import AVFoundation
import Foundation

nonisolated protocol AudioInputEngineProtocol: AnyObject, Sendable {
    typealias PermissionHandler = @MainActor @Sendable (MicrophonePermissionState) -> Void
    typealias StartHandler = @MainActor @Sendable (Result<Void, AudioInputEngineError>) -> Void
    typealias LevelHandler = @MainActor @Sendable (_ decibels: Double, _ normalized: Double) -> Void
    typealias StopHandler = @MainActor @Sendable (AudioInputStopReason) -> Void
    typealias BufferHandler = @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void

    func permissionState() -> MicrophonePermissionState
    func requestPermission(completion: @escaping PermissionHandler)
    func start(
        bufferHandler: BufferHandler?,
        levelHandler: @escaping LevelHandler,
        stopHandler: @escaping StopHandler,
        completion: @escaping StartHandler
    )
    func stop()
}

nonisolated final class AudioInputEngine: AudioInputEngineProtocol, @unchecked Sendable {
    static let bufferSize: AVAudioFrameCount = 1_024
    static let meterUpdatesPerSecond = 15.0

    private let audioEngine = AVAudioEngine()
    private let sessionCoordinator: AudioSessionCoordinator
    private let controlQueue = DispatchQueue(label: "jp.taro252.TempoLab.audio-input-control")
    private var tapIsInstalled = false
    private var isListening = false
    private var notificationTokens: [NSObjectProtocol] = []
    private var stopHandler: StopHandler?

    init(sessionCoordinator: AudioSessionCoordinator = .shared) {
        self.sessionCoordinator = sessionCoordinator
    }

    deinit {
        stopImmediately()
    }

    func permissionState() -> MicrophonePermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .undetermined
        @unknown default:
            return .denied
        }
    }

    func requestPermission(completion: @escaping PermissionHandler) {
        let current = permissionState()
        guard current == .undetermined else {
            DispatchQueue.main.async {
                completion(current)
            }
            return
        }

        AVAudioApplication.requestRecordPermission { [weak self] _ in
            let state = self?.permissionState() ?? .denied
            DispatchQueue.main.async {
                completion(state)
            }
        }
    }

    func start(
        bufferHandler: BufferHandler?,
        levelHandler: @escaping LevelHandler,
        stopHandler: @escaping StopHandler,
        completion: @escaping StartHandler
    ) {
        controlQueue.async { [self] in
            guard !isListening else {
                DispatchQueue.main.async { completion(.success(())) }
                return
            }

            guard permissionState() == .granted else {
                DispatchQueue.main.async { completion(.failure(.permissionDenied)) }
                return
            }

            do {
                try startImmediately(
                    bufferHandler: bufferHandler,
                    levelHandler: levelHandler,
                    stopHandler: stopHandler
                )
                DispatchQueue.main.async { completion(.success(())) }
            } catch let error as AudioInputEngineError {
                stopImmediately()
                DispatchQueue.main.async { completion(.failure(error)) }
            } catch {
                stopImmediately()
                let wrapped = AudioInputEngineError.startFailed(error.localizedDescription)
                DispatchQueue.main.async { completion(.failure(wrapped)) }
            }
        }
    }

    func stop() {
        controlQueue.async { [self] in
            stopImmediately()
        }
    }

    private func startImmediately(
        bufferHandler: BufferHandler?,
        levelHandler: @escaping LevelHandler,
        stopHandler: @escaping StopHandler
    ) throws {
        stopImmediately()
        try sessionCoordinator.beginInput()

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              inputFormat.channelCount > 0,
              let tapFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputFormat.sampleRate,
                channels: inputFormat.channelCount,
                interleaved: false
              ) else {
            sessionCoordinator.endInput()
            throw AudioInputEngineError.inputFormatUnavailable
        }

        let meterFrameInterval = inputFormat.sampleRate / Self.meterUpdatesPerSecond
        var framesSinceMeterUpdate = 0.0

        inputNode.installTap(
            onBus: 0,
            bufferSize: Self.bufferSize,
            format: tapFormat
        ) { buffer, time in
            // Bufferはtap callbackの間だけ有効。保持せず、Phase 8ではここから
            // 事前確保したリングバッファへコピーして解析キューへ渡す。
            bufferHandler?(buffer, time)

            framesSinceMeterUpdate += Double(buffer.frameLength)
            guard framesSinceMeterUpdate >= meterFrameInterval else { return }
            framesSinceMeterUpdate.formTruncatingRemainder(dividingBy: meterFrameInterval)

            let rms = AudioLevelMath.rootMeanSquare(buffer: buffer)
            let decibels = AudioLevelMath.decibels(fromRootMeanSquare: rms)
            let normalized = AudioLevelMath.normalizedLevel(decibels: decibels)
            DispatchQueue.main.async {
                levelHandler(decibels, normalized)
            }
        }
        tapIsInstalled = true
        self.stopHandler = stopHandler
        installNotifications()

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw AudioInputEngineError.startFailed(error.localizedDescription)
        }
        isListening = true
    }

    private func stopImmediately() {
        removeNotifications()
        if tapIsInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapIsInstalled = false
        }
        audioEngine.stop()
        audioEngine.reset()
        isListening = false
        stopHandler = nil
        sessionCoordinator.endInput()
    }

    private func installNotifications() {
        removeNotifications()
        let center = NotificationCenter.default

        notificationTokens.append(
            center.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: audioEngine,
                queue: nil
            ) { [weak self] _ in
                self?.handleSystemStop(reason: .engineConfigurationChanged)
            }
        )

        #if os(iOS)
        notificationTokens.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: nil
            ) { [weak self] notification in
                guard let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: rawValue) == .began else { return }
                self?.handleSystemStop(reason: .interruption)
            }
        )

        notificationTokens.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: nil
            ) { [weak self] _ in
                self?.handleSystemStop(reason: .routeChanged)
            }
        )
        #endif
    }

    private func removeNotifications() {
        let center = NotificationCenter.default
        notificationTokens.forEach(center.removeObserver)
        notificationTokens.removeAll(keepingCapacity: false)
    }

    private func handleSystemStop(reason: AudioInputStopReason) {
        controlQueue.async { [weak self] in
            guard let self, isListening else { return }
            let handler = stopHandler
            stopImmediately()
            guard let handler else { return }
            DispatchQueue.main.async {
                handler(reason)
            }
        }
    }
}
