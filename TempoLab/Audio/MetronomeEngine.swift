import AVFoundation

nonisolated enum MetronomeEngineError: Error, LocalizedError, Sendable {
    case audioFormatUnavailable
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .audioFormatUnavailable:
            return "利用可能なオーディオ形式を取得できませんでした。"
        case let .startFailed(message):
            return "メトロノームを開始できませんでした: \(message)"
        }
    }
}

nonisolated final class MetronomeEngine: @unchecked Sendable {
    typealias FailureHandler = @MainActor @Sendable (MetronomeEngineError) -> Void
    typealias StartHandler = @MainActor @Sendable (Result<Void, MetronomeEngineError>) -> Void

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let soundGenerator = ClickSoundGenerator()
    private let schedulingQueue = DispatchQueue(label: "jp.taro252.TempoLab.metronome-scheduling")

    private var isRunning = false
    private var isGraphConnected = false
    private var scheduledMeasureBuffer: AVAudioPCMBuffer?

    init() {
        audioEngine.attach(playerNode)
    }

    func start(
        bpm: Int,
        timeSignature: TimeSignature,
        completion: @escaping StartHandler
    ) {
        schedulingQueue.async { [self] in
            let result: Result<Void, MetronomeEngineError>

            do {
                try startImmediately(bpm: bpm, timeSignature: timeSignature)
                result = .success(())
            } catch let error as MetronomeEngineError {
                stopImmediately()
                result = .failure(error)
            } catch {
                stopImmediately()
                result = .failure(.startFailed(error.localizedDescription))
            }

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func stop() {
        schedulingQueue.async { [self] in
            stopImmediately()
        }
    }

    func update(
        bpm: Int,
        timeSignature: TimeSignature,
        onFailure: @escaping FailureHandler
    ) {
        schedulingQueue.async { [self] in
            guard isRunning else { return }

            do {
                try scheduleMeasure(bpm: bpm, timeSignature: timeSignature)
            } catch let error as MetronomeEngineError {
                stopImmediately()
                DispatchQueue.main.async {
                    onFailure(error)
                }
            } catch {
                stopImmediately()
                DispatchQueue.main.async {
                    onFailure(.startFailed(error.localizedDescription))
                }
            }
        }
    }

    private func startImmediately(bpm: Int, timeSignature: TimeSignature) throws {
        stopImmediately()
        try configureAudioSessionIfNeeded()
        try scheduleMeasure(bpm: bpm, timeSignature: timeSignature)
        isRunning = true
    }

    private func scheduleMeasure(bpm: Int, timeSignature: TimeSignature) throws {
        playerNode.stop()
        playerNode.reset()

        let sampleRate = audioEngine.outputNode.outputFormat(forBus: 0).sampleRate
        guard sampleRate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw MetronomeEngineError.audioFormatUnavailable
        }

        if !isGraphConnected {
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
            isGraphConnected = true
        }

        let measureBuffer: AVAudioPCMBuffer
        do {
            measureBuffer = try soundGenerator.makeMeasureBuffer(
                bpm: bpm,
                timeSignature: timeSignature,
                format: format
            )
        } catch {
            throw MetronomeEngineError.startFailed(error.localizedDescription)
        }

        scheduledMeasureBuffer = measureBuffer
        let startTime = AVAudioTime(sampleTime: 0, atRate: sampleRate)
        playerNode.scheduleBuffer(measureBuffer, at: startTime, options: .loops)

        if !audioEngine.isRunning {
            audioEngine.prepare()
            do {
                try audioEngine.start()
            } catch {
                throw MetronomeEngineError.startFailed(error.localizedDescription)
            }
        }

        playerNode.play()
    }

    private func stopImmediately() {
        isRunning = false
        playerNode.stop()
        playerNode.reset()
        scheduledMeasureBuffer = nil
        audioEngine.stop()
        deactivateAudioSessionIfNeeded()
    }

    private func configureAudioSessionIfNeeded() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        #endif
    }

    private func deactivateAudioSessionIfNeeded() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }
}
