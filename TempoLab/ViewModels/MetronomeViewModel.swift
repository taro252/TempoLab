import Combine
import Foundation

@MainActor
final class MetronomeViewModel: ObservableObject {
    static let bpmRange = AppSettings.bpmRange

    @Published private(set) var bpm: Int
    @Published private(set) var isRunning = false
    @Published private(set) var audioErrorMessage: String?
    @Published private(set) var clickSoundSettings: ClickSoundSettings
    @Published private(set) var keepScreenAwake: Bool
    @Published var selectedTimeSignature: TimeSignature {
        didSet {
            guard selectedTimeSignature != oldValue else { return }
            persistSettings()
            updateEngineIfRunning()
        }
    }

    private var tapTempoCalculator = TapTempoCalculator(bpmRange: bpmRange)
    private let metronomeEngine: any MetronomeEngineProtocol
    private let settingsStore: any SettingsStoring
    private let screenAwakeController: any ScreenAwakeControlling
    private var playbackRequestID = 0

    init(
        metronomeEngine: any MetronomeEngineProtocol = MetronomeEngine(),
        settingsStore: any SettingsStoring = SettingsStore(),
        screenAwakeController: (any ScreenAwakeControlling)? = nil
    ) {
        let settings = settingsStore.load()
        self.metronomeEngine = metronomeEngine
        self.settingsStore = settingsStore
        self.screenAwakeController = screenAwakeController ?? ScreenAwakeController()
        bpm = settings.bpm
        selectedTimeSignature = settings.timeSignature
        clickSoundSettings = settings.clickSoundSettings
        keepScreenAwake = settings.keepScreenAwake
        self.screenAwakeController.setPreventSleep(false)
    }

    func adjustBPM(by amount: Int) {
        setBPM(bpm + amount)
    }

    func toggleRunning() {
        playbackRequestID += 1

        if isRunning {
            setRunning(false)
            metronomeEngine.stop()
            return
        }

        let requestID = playbackRequestID
        audioErrorMessage = nil
        setRunning(true)
        metronomeEngine.start(
            bpm: bpm,
            timeSignature: selectedTimeSignature,
            clickSettings: clickSoundSettings
        ) { [weak self] result in
            guard let self, playbackRequestID == requestID else { return }
            if case let .failure(error) = result {
                setRunning(false)
                audioErrorMessage = error.localizedDescription
            }
        }
    }

    func registerTap(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if let calculatedBPM = tapTempoCalculator.registerTap(at: time) {
            setBPM(calculatedBPM)
        }
    }

    func dismissAudioError() {
        audioErrorMessage = nil
    }

    func setNormalFrequency(_ frequency: Int) {
        setClickSoundSettings(clickSoundSettings.updatingNormalFrequency(frequency))
    }

    func setAccentFrequency(_ frequency: Int) {
        setClickSoundSettings(clickSoundSettings.updatingAccentFrequency(frequency))
    }

    func setClickVolume(_ volume: Double) {
        setClickSoundSettings(clickSoundSettings.updatingVolume(volume))
    }

    func setClickSoundType(_ soundType: ClickSoundType) {
        setClickSoundSettings(clickSoundSettings.updatingSoundType(soundType))
    }

    func setKeepScreenAwake(_ enabled: Bool) {
        guard keepScreenAwake != enabled else { return }
        keepScreenAwake = enabled
        persistSettings()
        updateScreenAwakeState()
    }

    func previewNormalClick() {
        previewClick(isAccent: false)
    }

    func previewAccentClick() {
        previewClick(isAccent: true)
    }

    private func clampedBPM(_ value: Int) -> Int {
        min(max(value, Self.bpmRange.lowerBound), Self.bpmRange.upperBound)
    }

    func setBPM(_ value: Int) {
        let clampedValue = clampedBPM(value)
        guard bpm != clampedValue else { return }
        bpm = clampedValue
        persistSettings()
        updateEngineIfRunning()
    }

    private func updateEngineIfRunning() {
        guard isRunning else { return }
        let requestID = playbackRequestID

        metronomeEngine.update(bpm: bpm, timeSignature: selectedTimeSignature) { [weak self] error in
            guard let self, playbackRequestID == requestID else { return }
            setRunning(false)
            audioErrorMessage = error.localizedDescription
        }
    }

    private func setClickSoundSettings(_ settings: ClickSoundSettings) {
        guard clickSoundSettings != settings else { return }
        clickSoundSettings = settings
        persistSettings()

        guard isRunning else { return }
        let requestID = playbackRequestID
        metronomeEngine.updateClickSettings(settings) { [weak self] error in
            guard let self, playbackRequestID == requestID else { return }
            setRunning(false)
            audioErrorMessage = error.localizedDescription
        }
    }

    private func previewClick(isAccent: Bool) {
        guard !isRunning else { return }
        audioErrorMessage = nil

        metronomeEngine.previewClick(
            isAccent: isAccent,
            settings: clickSoundSettings
        ) { [weak self] result in
            guard let self else { return }
            if case let .failure(error) = result {
                audioErrorMessage = error.localizedDescription
            }
        }
    }

    private func setRunning(_ running: Bool) {
        isRunning = running
        updateScreenAwakeState()
    }

    private func updateScreenAwakeState() {
        screenAwakeController.setPreventSleep(
            ScreenAwakePolicy.shouldPreventSleep(
                keepScreenAwake: keepScreenAwake,
                isRunning: isRunning
            )
        )
    }

    private func persistSettings() {
        settingsStore.save(
            AppSettings(
                bpm: bpm,
                timeSignature: selectedTimeSignature,
                clickSoundSettings: clickSoundSettings,
                keepScreenAwake: keepScreenAwake
            )
        )
    }

}
