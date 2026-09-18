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
    private var subdivision = Subdivision.quarter
    private var accentPattern = AccentPattern.defaultPattern(
        timeSignature: .fourFour,
        subdivision: .quarter
    )
    private var bpm = 120
    private var clickSettings = ClickSoundSettings.default
    private var isPreviewing = false
    private var nextBeatIndex = 0
    private var nextSubdivisionIndexInBeat = 0
    private var nextGlobalSubdivisionIndex: Int64 = 0
    private var timelineOriginSampleTime: AVAudioFramePosition = 0
    private var scheduledSteps: [ScheduledStep] = []
    private var lastCompletedStep: ScheduledStep?
    private var normalClickBuffer: AVAudioPCMBuffer?
    private var accentClickBuffer: AVAudioPCMBuffer?
    private var muteBuffer: AVAudioPCMBuffer?
    private var transitionSilenceBuffer: AVAudioPCMBuffer?
    private var clickFrameCount: AVAudioFramePosition = 0

    private struct ScheduledStep: Sendable, Equatable {
        let beatIndex: Int
        let subdivisionIndexInBeat: Int
        let emphasis: StepEmphasis
        let sampleTime: AVAudioFramePosition
        let beatStartSampleTime: AVAudioFramePosition
    }

    init() {
        audioEngine.attach(playerNode)
    }

    func start(
        bpm: Int,
        timeSignature: TimeSignature,
        subdivision: Subdivision,
        accentPattern: AccentPattern,
        clickSettings: ClickSoundSettings,
        completion: @escaping StartHandler
    ) {
        schedulingQueue.async { [self] in
            let result: Result<Void, MetronomeEngineError>

            do {
                try startImmediately(
                    bpm: bpm,
                    timeSignature: timeSignature,
                    subdivision: subdivision,
                    accentPattern: accentPattern,
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
        subdivision: Subdivision,
        accentPattern: AccentPattern,
        onFailure: @escaping FailureHandler
    ) {
        schedulingQueue.async { [self] in
            guard isRunning else { return }

            do {
                try scheduleUpdatedConfiguration(
                    bpm: bpm,
                    timeSignature: timeSignature,
                    subdivision: subdivision,
                    accentPattern: accentPattern
                )
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
        subdivision: Subdivision,
        accentPattern: AccentPattern,
        clickSettings: ClickSoundSettings
    ) throws {
        stopImmediately()
        try configureAudioSessionIfNeeded()
        try prepareAudioGraph(clickSettings: clickSettings)

        self.bpm = bpm
        self.timeSignature = timeSignature
        self.subdivision = subdivision
        self.accentPattern = accentPattern
        nextBeatIndex = 0
        nextSubdivisionIndexInBeat = 0
        nextGlobalSubdivisionIndex = 0
        timelineOriginSampleTime = 0
        generation += 1

        try scheduleSteps(
            count: lookAheadBeatCount * subdivision.divisionsPerBeat,
            firstBufferOptions: []
        )

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

    private func scheduleUpdatedConfiguration(
        bpm: Int,
        timeSignature: TimeSignature,
        subdivision: Subdivision,
        accentPattern: AccentPattern
    ) throws {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            throw MetronomeEngineError.audioFormatUnavailable
        }

        let currentSampleTime = playerTime.sampleTime
        let currentStep = currentStep(at: currentSampleTime)
        let nextIndex = currentStep.map {
            MetronomeTiming.nextBeatIndex(after: $0.beatIndex, timeSignature: timeSignature)
        } ?? 0
        let newFramesPerBeat = AVAudioFramePosition(
            MetronomeTiming.samplesPerBeat(bpm: bpm, sampleRate: sampleRate).rounded()
        )
        let intendedNextBeatTime = currentStep.map { $0.beatStartSampleTime + newFramesPerBeat }
            ?? currentSampleTime + newFramesPerBeat
        let currentClickEndTime = currentStep.map {
            $0.emphasis.isAudible ? $0.sampleTime + clickFrameCount : currentSampleTime
        } ?? currentSampleTime
        let clearTime = max(
            currentSampleTime + schedulingLeadFrameCount,
            currentClickEndTime
        )
        let firstNewBeatTime = max(intendedNextBeatTime, clearTime)

        generation += 1
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.subdivision = subdivision
        self.accentPattern = accentPattern
        nextBeatIndex = nextIndex
        nextSubdivisionIndexInBeat = 0
        nextGlobalSubdivisionIndex = 0
        timelineOriginSampleTime = firstNewBeatTime
        scheduledSteps.removeAll(keepingCapacity: true)
        lastCompletedStep = currentStep

        let silenceFrameCount = firstNewBeatTime - clearTime
        if silenceFrameCount > 0 {
            let silenceBuffer = try makeSilenceBuffer(frameCount: silenceFrameCount)
            transitionSilenceBuffer = silenceBuffer
            playerNode.scheduleBuffer(
                silenceBuffer,
                at: AVAudioTime(sampleTime: clearTime, atRate: sampleRate),
                options: .interrupts
            )
            try scheduleSteps(
                count: lookAheadBeatCount * subdivision.divisionsPerBeat,
                firstBufferOptions: []
            )
        } else {
            transitionSilenceBuffer = nil
            try scheduleSteps(
                count: lookAheadBeatCount * subdivision.divisionsPerBeat,
                firstBufferOptions: .interrupts
            )
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
            muteBuffer = try makeMuteBuffer(format: format)
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
            try scheduleUpdatedConfiguration(
                bpm: bpm,
                timeSignature: timeSignature,
                subdivision: subdivision,
                accentPattern: accentPattern
            )
        }
    }

    private func scheduleSteps(
        count: Int,
        firstBufferOptions: AVAudioPlayerNodeBufferOptions
    ) throws {
        guard let normalClickBuffer, let accentClickBuffer, let muteBuffer else {
            throw MetronomeEngineError.audioFormatUnavailable
        }

        let currentGeneration = generation
        for offset in 0..<count {
            let sampleTime = timelineOriginSampleTime + MetronomeTiming.samplePosition(
                forSubdivision: nextGlobalSubdivisionIndex,
                bpm: bpm,
                sampleRate: sampleRate,
                subdivision: subdivision
            )
            let beatStartSampleTime = timelineOriginSampleTime + MetronomeTiming.samplePosition(
                forSubdivision: nextGlobalSubdivisionIndex - Int64(nextSubdivisionIndexInBeat),
                bpm: bpm,
                sampleRate: sampleRate,
                subdivision: subdivision
            )
            let patternIndex = nextBeatIndex * subdivision.divisionsPerBeat
                + nextSubdivisionIndexInBeat
            let emphasis = accentPattern.emphasis(at: patternIndex)
            let step = ScheduledStep(
                beatIndex: nextBeatIndex,
                subdivisionIndexInBeat: nextSubdivisionIndexInBeat,
                emphasis: emphasis,
                sampleTime: sampleTime,
                beatStartSampleTime: beatStartSampleTime
            )
            let buffer: AVAudioPCMBuffer = switch emphasis {
            case .accent: accentClickBuffer
            case .normal: normalClickBuffer
            case .mute: muteBuffer
            }
            let options = offset == 0 ? firstBufferOptions : []

            scheduledSteps.append(step)
            playerNode.scheduleBuffer(
                buffer,
                at: AVAudioTime(sampleTime: step.sampleTime, atRate: sampleRate),
                options: options,
                completionCallbackType: .dataPlayedBack
            ) { [weak self] _ in
                guard let self else { return }
                schedulingQueue.async { [weak self] in
                    self?.stepDidComplete(step, generation: currentGeneration)
                }
            }

            nextGlobalSubdivisionIndex += 1
            nextSubdivisionIndexInBeat += 1
            if nextSubdivisionIndexInBeat == subdivision.divisionsPerBeat {
                nextSubdivisionIndexInBeat = 0
                nextBeatIndex = MetronomeTiming.nextBeatIndex(
                    after: nextBeatIndex,
                    timeSignature: timeSignature
                )
            }
        }
    }

    private func stepDidComplete(_ step: ScheduledStep, generation: Int) {
        guard isRunning, self.generation == generation else { return }

        scheduledSteps.removeAll { $0 == step }
        lastCompletedStep = step

        do {
            try scheduleSteps(count: 1, firstBufferOptions: [])
        } catch {
            stopImmediately()
        }
    }

    private func currentStep(at sampleTime: AVAudioFramePosition) -> ScheduledStep? {
        let startedStep = scheduledSteps.last { $0.sampleTime <= sampleTime }

        switch (lastCompletedStep, startedStep) {
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

    private func makeMuteBuffer(format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1),
              let sample = buffer.floatChannelData?[0] else {
            throw MetronomeEngineError.audioFormatUnavailable
        }
        buffer.frameLength = 1
        sample[0] = 0
        return buffer
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
        scheduledSteps.removeAll(keepingCapacity: false)
        lastCompletedStep = nil
        normalClickBuffer = nil
        accentClickBuffer = nil
        muteBuffer = nil
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
        subdivision: Subdivision,
        accentPattern: AccentPattern,
        clickSettings: ClickSoundSettings,
        completion: @escaping MetronomeEngine.StartHandler
    )

    func stop()

    func update(
        bpm: Int,
        timeSignature: TimeSignature,
        subdivision: Subdivision,
        accentPattern: AccentPattern,
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
