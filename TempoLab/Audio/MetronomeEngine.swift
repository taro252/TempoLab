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
    private let lookAheadBeatCount = 2
    private let schedulingLeadFrameCount: AVAudioFramePosition = 512

    private var isRunning = false
    private var isGraphConnected = false
    private var generation = 0
    private var sampleRate = 0.0
    private var timeSignature = TimeSignature.fourFour
    private var bpm = 120
    private var clickSettings = ClickSoundSettings.default
    private var isPreviewing = false
    private var nextBeatIndex = 0
    private var nextBeatSampleTime: AVAudioFramePosition = 0
    private var scheduledBeats: [ScheduledBeat] = []
    private var lastCompletedBeat: ScheduledBeat?
    private var normalClickBuffer: AVAudioPCMBuffer?
    private var accentClickBuffer: AVAudioPCMBuffer?
    private var transitionSilenceBuffer: AVAudioPCMBuffer?
    private var clickFrameCount: AVAudioFramePosition = 0

    private struct ScheduledBeat: Sendable, Equatable {
        let beatIndex: Int
        let sampleTime: AVAudioFramePosition
    }

    init() {
        audioEngine.attach(playerNode)
    }

    func start(
        bpm: Int,
        timeSignature: TimeSignature,
        clickSettings: ClickSoundSettings,
        completion: @escaping StartHandler
    ) {
        schedulingQueue.async { [self] in
            let result: Result<Void, MetronomeEngineError>

            do {
                try startImmediately(
                    bpm: bpm,
                    timeSignature: timeSignature,
                    clickSettings: clickSettings
                )
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
                try scheduleUpdatedTempo(bpm: bpm, timeSignature: timeSignature)
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

    func updateClickSettings(
        _ settings: ClickSoundSettings,
        onFailure: @escaping FailureHandler
    ) {
        schedulingQueue.async { [self] in
            guard isRunning else {
                clickSettings = settings
                return
            }

            do {
                try applyClickSettings(settings)
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

    func previewClick(
        isAccent: Bool,
        settings: ClickSoundSettings,
        completion: @escaping StartHandler
    ) {
        schedulingQueue.async { [self] in
            let result: Result<Void, MetronomeEngineError>

            do {
                guard !isRunning else {
                    throw MetronomeEngineError.startFailed("再生中はプレビューできません。")
                }
                try previewClickImmediately(isAccent: isAccent, settings: settings)
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

    private func startImmediately(
        bpm: Int,
        timeSignature: TimeSignature,
        clickSettings: ClickSoundSettings
    ) throws {
        stopImmediately()
        try configureAudioSessionIfNeeded()
        try prepareAudioGraph(clickSettings: clickSettings)

        self.bpm = bpm
        self.timeSignature = timeSignature
        nextBeatIndex = 0
        nextBeatSampleTime = 0
        generation += 1

        try scheduleBeats(count: lookAheadBeatCount, firstBufferOptions: [])

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw MetronomeEngineError.startFailed(error.localizedDescription)
        }

        playerNode.play()
        isRunning = true
    }

    private func previewClickImmediately(
        isAccent: Bool,
        settings: ClickSoundSettings
    ) throws {
        stopImmediately()
        try configureAudioSessionIfNeeded()
        try prepareAudioGraph(clickSettings: settings)

        guard let buffer = isAccent ? accentClickBuffer : normalClickBuffer else {
            throw MetronomeEngineError.audioFormatUnavailable
        }

        generation += 1
        let previewGeneration = generation
        isPreviewing = true
        playerNode.scheduleBuffer(
            buffer,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            guard let self else { return }
            schedulingQueue.async { [weak self] in
                guard let self,
                      isPreviewing,
                      generation == previewGeneration else { return }
                stopImmediately()
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw MetronomeEngineError.startFailed(error.localizedDescription)
        }
        playerNode.play()
    }

    private func scheduleUpdatedTempo(bpm: Int, timeSignature: TimeSignature) throws {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            throw MetronomeEngineError.audioFormatUnavailable
        }

        let currentSampleTime = playerTime.sampleTime
        let currentBeat = currentBeat(at: currentSampleTime)
        let nextIndex = currentBeat.map {
            MetronomeTiming.nextBeatIndex(after: $0.beatIndex, timeSignature: timeSignature)
        } ?? 0
        let newFramesPerBeat = AVAudioFramePosition(
            MetronomeTiming.samplesPerBeat(bpm: bpm, sampleRate: sampleRate).rounded()
        )
        let intendedNextBeatTime = currentBeat.map { $0.sampleTime + newFramesPerBeat }
            ?? currentSampleTime + newFramesPerBeat
        let currentClickEndTime = currentBeat.map {
            $0.sampleTime + clickFrameCount
        } ?? currentSampleTime
        let clearTime = max(
            currentSampleTime + schedulingLeadFrameCount,
            currentClickEndTime
        )
        let firstNewBeatTime = max(intendedNextBeatTime, clearTime)

        generation += 1
        self.bpm = bpm
        self.timeSignature = timeSignature
        nextBeatIndex = nextIndex
        nextBeatSampleTime = firstNewBeatTime
        scheduledBeats.removeAll(keepingCapacity: true)
        lastCompletedBeat = currentBeat

        let silenceFrameCount = firstNewBeatTime - clearTime
        if silenceFrameCount > 0 {
            let silenceBuffer = try makeSilenceBuffer(frameCount: silenceFrameCount)
            transitionSilenceBuffer = silenceBuffer
            playerNode.scheduleBuffer(
                silenceBuffer,
                at: AVAudioTime(sampleTime: clearTime, atRate: sampleRate),
                options: .interrupts
            )
            try scheduleBeats(count: lookAheadBeatCount, firstBufferOptions: [])
        } else {
            transitionSilenceBuffer = nil
            try scheduleBeats(count: lookAheadBeatCount, firstBufferOptions: .interrupts)
        }
    }

    private func prepareAudioGraph(clickSettings: ClickSoundSettings) throws {
        sampleRate = audioEngine.outputNode.outputFormat(forBus: 0).sampleRate
        guard sampleRate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw MetronomeEngineError.audioFormatUnavailable
        }

        if !isGraphConnected {
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
            isGraphConnected = true
        }

        do {
            normalClickBuffer = try soundGenerator.makeClickBuffer(
                isAccent: false,
                settings: clickSettings,
                format: format
            )
            accentClickBuffer = try soundGenerator.makeClickBuffer(
                isAccent: true,
                settings: clickSettings,
                format: format
            )
            clickFrameCount = AVAudioFramePosition(normalClickBuffer?.frameLength ?? 0)
            self.clickSettings = clickSettings
            playerNode.volume = Float(clickSettings.volume)
        } catch {
            throw MetronomeEngineError.startFailed(error.localizedDescription)
        }
    }

    private func applyClickSettings(_ settings: ClickSoundSettings) throws {
        let waveformChanged = settings.normalFrequency != clickSettings.normalFrequency
            || settings.accentFrequency != clickSettings.accentFrequency
            || settings.soundType != clickSettings.soundType

        if waveformChanged {
            guard let format = normalClickBuffer?.format else {
                throw MetronomeEngineError.audioFormatUnavailable
            }

            let newNormalBuffer = try soundGenerator.makeClickBuffer(
                isAccent: false,
                settings: settings,
                format: format
            )
            let newAccentBuffer = try soundGenerator.makeClickBuffer(
                isAccent: true,
                settings: settings,
                format: format
            )

            normalClickBuffer = newNormalBuffer
            accentClickBuffer = newAccentBuffer
            clickFrameCount = AVAudioFramePosition(newNormalBuffer.frameLength)
        }

        clickSettings = settings
        playerNode.volume = Float(settings.volume)

        if waveformChanged {
            try scheduleUpdatedTempo(bpm: bpm, timeSignature: timeSignature)
        }
    }

    private func scheduleBeats(
        count: Int,
        firstBufferOptions: AVAudioPlayerNodeBufferOptions
    ) throws {
        guard let normalClickBuffer, let accentClickBuffer else {
            throw MetronomeEngineError.audioFormatUnavailable
        }

        let currentGeneration = generation
        for offset in 0..<count {
            let beat = ScheduledBeat(beatIndex: nextBeatIndex, sampleTime: nextBeatSampleTime)
            let buffer = MetronomeTiming.isAccent(
                beatIndex: beat.beatIndex,
                timeSignature: timeSignature
            ) ? accentClickBuffer : normalClickBuffer
            let options = offset == 0 ? firstBufferOptions : []

            scheduledBeats.append(beat)
            playerNode.scheduleBuffer(
                buffer,
                at: AVAudioTime(sampleTime: beat.sampleTime, atRate: sampleRate),
                options: options,
                completionCallbackType: .dataPlayedBack
            ) { [weak self] _ in
                guard let self else { return }
                schedulingQueue.async { [weak self] in
                    self?.beatDidComplete(beat, generation: currentGeneration)
                }
            }

            nextBeatIndex = MetronomeTiming.nextBeatIndex(
                after: nextBeatIndex,
                timeSignature: timeSignature
            )
            nextBeatSampleTime += AVAudioFramePosition(
                MetronomeTiming.samplesPerBeat(bpm: bpm, sampleRate: sampleRate).rounded()
            )
        }
    }

    private func beatDidComplete(_ beat: ScheduledBeat, generation: Int) {
        guard isRunning, self.generation == generation else { return }

        scheduledBeats.removeAll { $0 == beat }
        lastCompletedBeat = beat

        do {
            try scheduleBeats(count: 1, firstBufferOptions: [])
        } catch {
            stopImmediately()
        }
    }

    private func currentBeat(at sampleTime: AVAudioFramePosition) -> ScheduledBeat? {
        let startedBeat = scheduledBeats.last { $0.sampleTime <= sampleTime }

        switch (lastCompletedBeat, startedBeat) {
        case let (completed?, started?):
            return completed.sampleTime > started.sampleTime ? completed : started
        case let (completed?, nil):
            return completed
        case let (nil, started?):
            return started
        case (nil, nil):
            return nil
        }
    }

    private func makeSilenceBuffer(
        frameCount: AVAudioFramePosition
    ) throws -> AVAudioPCMBuffer {
        guard frameCount > 0,
              frameCount <= AVAudioFramePosition(UInt32.max),
              let format = normalClickBuffer?.format,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
              ),
              let samples = buffer.floatChannelData?[0] else {
            throw MetronomeEngineError.audioFormatUnavailable
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        samples.initialize(repeating: 0, count: Int(frameCount))
        return buffer
    }

    private func stopImmediately() {
        isRunning = false
        isPreviewing = false
        generation += 1
        playerNode.stop()
        playerNode.reset()
        scheduledBeats.removeAll(keepingCapacity: false)
        lastCompletedBeat = nil
        normalClickBuffer = nil
        accentClickBuffer = nil
        transitionSilenceBuffer = nil
        clickFrameCount = 0
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

nonisolated protocol MetronomeEngineProtocol: Sendable {
    func start(
        bpm: Int,
        timeSignature: TimeSignature,
        clickSettings: ClickSoundSettings,
        completion: @escaping MetronomeEngine.StartHandler
    )

    func stop()

    func update(
        bpm: Int,
        timeSignature: TimeSignature,
        onFailure: @escaping MetronomeEngine.FailureHandler
    )

    func updateClickSettings(
        _ settings: ClickSoundSettings,
        onFailure: @escaping MetronomeEngine.FailureHandler
    )

    func previewClick(
        isAccent: Bool,
        settings: ClickSoundSettings,
        completion: @escaping MetronomeEngine.StartHandler
    )
}

extension MetronomeEngine: MetronomeEngineProtocol {}
