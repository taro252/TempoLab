import Combine
import Foundation

@MainActor
final class PlaybackPositionState: ObservableObject {
    @Published private(set) var current: PlaybackPosition?

    func update(_ position: PlaybackPosition?) {
        guard current != position else { return }
        current = position
    }
}

@MainActor
final class MetronomeViewModel: ObservableObject {
    static let bpmRange = AppSettings.bpmRange

    @Published private(set) var presets: [MetronomePreset] = []
    @Published private(set) var lastAppliedPresetID: UUID?
    @Published private(set) var presetErrorMessage: String?
    @Published private(set) var bpm: Int
    @Published private(set) var isRunning = false
    @Published private(set) var audioErrorMessage: String?
    @Published private(set) var clickSoundSettings: ClickSoundSettings
    @Published private(set) var keepScreenAwake: Bool
    @Published private(set) var selectedSubdivision: Subdivision
    @Published private(set) var accentPatterns: AccentPatternLibrary
    @Published var selectedTimeSignature: TimeSignature {
        didSet {
            guard selectedTimeSignature != oldValue, !isApplyingPreset else { return }
            persistSettings()
            updateEngineIfRunning()
        }
    }

    private var tapTempoCalculator = TapTempoCalculator(bpmRange: bpmRange)
    private let metronomeEngine: any MetronomeEngineProtocol
    private let settingsStore: any SettingsStoring
    private let presetStore: any PresetStoring
    private var isApplyingPreset = false
    private let screenAwakeController: any ScreenAwakeControlling
    private var playbackRequestID = 0
    let playbackPositionState = PlaybackPositionState()

    var currentPlaybackPosition: PlaybackPosition? {
        playbackPositionState.current
    }

    var currentAccentPattern: AccentPattern {
        accentPatterns.pattern(
            for: selectedTimeSignature,
            subdivision: selectedSubdivision
        )
    }

    init(
        metronomeEngine: any MetronomeEngineProtocol = MetronomeEngine(),
        settingsStore: any SettingsStoring = SettingsStore(),
        presetStore: any PresetStoring = PresetStore(),
        screenAwakeController: (any ScreenAwakeControlling)? = nil
    ) {
        let settings = settingsStore.load()
        self.metronomeEngine = metronomeEngine
        self.settingsStore = settingsStore
        self.presetStore = presetStore
        self.screenAwakeController = screenAwakeController ?? ScreenAwakeController()
        bpm = settings.bpm
        selectedTimeSignature = settings.timeSignature
        clickSoundSettings = settings.clickSoundSettings
        keepScreenAwake = settings.keepScreenAwake
        selectedSubdivision = settings.subdivision
        accentPatterns = settings.accentPatterns
        self.screenAwakeController.setPreventSleep(false)
        metronomeEngine.prepare(clickSettings: settings.clickSoundSettings)
        loadPresets()
    }

    var currentConfiguration: PresetConfiguration {
        PresetConfiguration(
            bpm: bpm,
            timeSignature: selectedTimeSignature,
            subdivision: selectedSubdivision,
            accentPattern: currentAccentPattern,
            clickSoundSettings: clickSoundSettings
        )
    }

    var isAppliedPresetModified: Bool {
        guard let preset = presets.first(where: { $0.id == lastAppliedPresetID }) else { return false }
        return preset.configuration != currentConfiguration
    }

    func loadPresets() {
        do {
            let result = try presetStore.load()
            presets = result.presets
            presetErrorMessage = result.skippedRecordCount > 0
                ? String(localized: "一部のプリセットを読み込めませんでした。読み込めたプリセットを表示しています。")
                : nil
        } catch {
            presetErrorMessage = error.localizedDescription
        }
    }

    func dismissPresetError() {
        presetErrorMessage = nil
    }

    @discardableResult
    func createPreset(name: String) -> Bool {
        do {
            let preset = try MetronomePreset(name: name, configuration: currentConfiguration)
            guard savePresets(presets + [preset]) else { return false }
            lastAppliedPresetID = preset.id
            return true
        } catch {
            presetErrorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func applyPreset(id: UUID) -> Bool {
        guard let preset = presets.first(where: { $0.id == id }) else {
            presetErrorMessage = PresetError.notFound.localizedDescription
            return false
        }
        let configuration = preset.configuration
        let previous = currentConfiguration
        lastAppliedPresetID = id
        guard previous != configuration else { return true }

        // 拍子のdidSetから個別更新を送らず、全設定を反映した後に一度だけ保存・通知する。
        isApplyingPreset = true
        bpm = configuration.bpm
        selectedTimeSignature = configuration.timeSignature
        selectedSubdivision = configuration.subdivision
        accentPatterns.setPattern(configuration.accentPattern)
        clickSoundSettings = configuration.clickSoundSettings
        isApplyingPreset = false
        if previous.timeSignature != configuration.timeSignature
            || previous.subdivision != configuration.subdivision {
            playbackPositionState.update(nil)
        }
        persistSettings()

        if isRunning {
            let requestID = playbackRequestID
            metronomeEngine.updateConfiguration(
                bpm: bpm,
                timeSignature: selectedTimeSignature,
                subdivision: selectedSubdivision,
                accentPattern: currentAccentPattern,
                clickSettings: clickSoundSettings
            ) { [weak self] error in
                guard let self, playbackRequestID == requestID else { return }
                setRunning(false)
                audioErrorMessage = error.localizedDescription
            }
        } else if previous.clickSoundSettings != clickSoundSettings {
            metronomeEngine.prepare(clickSettings: clickSoundSettings)
        }
        return true
    }

    @discardableResult
    func renamePreset(id: UUID, name: String) -> Bool {
        guard let index = presets.firstIndex(where: { $0.id == id }) else {
            presetErrorMessage = PresetError.notFound.localizedDescription
            return false
        }
        var updated = presets
        do {
            try updated[index].rename(name)
            return savePresets(updated)
        } catch {
            presetErrorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func overwritePreset(id: UUID) -> Bool {
        guard let index = presets.firstIndex(where: { $0.id == id }) else {
            presetErrorMessage = PresetError.notFound.localizedDescription
            return false
        }
        var updated = presets
        updated[index].configuration = currentConfiguration
        updated[index].updatedAt = Date()
        return savePresets(updated)
    }

    @discardableResult
    func deletePreset(id: UUID) -> Bool {
        guard presets.contains(where: { $0.id == id }) else {
            presetErrorMessage = PresetError.notFound.localizedDescription
            return false
        }
        guard savePresets(presets.filter { $0.id != id }) else { return false }
        if lastAppliedPresetID == id { lastAppliedPresetID = nil }
        return true
    }

    @discardableResult
    func movePresets(from offsets: IndexSet, to destination: Int) -> Bool {
        guard !offsets.isEmpty, offsets.allSatisfy({ presets.indices.contains($0) }),
              (0...presets.count).contains(destination) else { return false }
        let moving = offsets.map { presets[$0] }
        var updated = presets.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertion = destination - offsets.filter { $0 < destination }.count
        updated.insert(contentsOf: moving, at: insertion)
        guard updated != presets else { return true }
        return savePresets(updated)
    }

    private func savePresets(_ updated: [MetronomePreset]) -> Bool {
        do {
            try presetStore.save(updated)
            presets = updated
            presetErrorMessage = nil
            return true
        } catch {
            presetErrorMessage = error.localizedDescription
            return false
        }
    }

    func adjustBPM(by amount: Int) {
        setBPM(bpm + amount)
    }

    func toggleRunning() {
        let actionUptime = ProcessInfo.processInfo.systemUptime
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
            actionUptime: actionUptime,
            bpm: bpm,
            timeSignature: selectedTimeSignature,
            subdivision: selectedSubdivision,
            accentPattern: currentAccentPattern,
            clickSettings: clickSoundSettings,
            positionHandler: { [weak self] position in
                guard let self,
                      playbackRequestID == requestID,
                      isRunning else { return }
                if let position,
                   position.timeSignature != selectedTimeSignature
                    || position.subdivision != selectedSubdivision { return }
                playbackPositionState.update(position)
            }
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

    func setSubdivision(_ subdivision: Subdivision) {
        guard selectedSubdivision != subdivision else { return }
        selectedSubdivision = subdivision
        persistSettings()
        updateEngineIfRunning()
    }

    func cyclePatternStep(at index: Int) {
        var pattern = currentAccentPattern
        guard pattern.steps.indices.contains(index) else { return }
        pattern.cycleStep(at: index)
        accentPatterns.setPattern(pattern)
        persistSettings()
        updateEngineIfRunning()
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

        metronomeEngine.update(
            bpm: bpm,
            timeSignature: selectedTimeSignature,
            subdivision: selectedSubdivision,
            accentPattern: currentAccentPattern
        ) { [weak self] error in
            guard let self, playbackRequestID == requestID else { return }
            setRunning(false)
            audioErrorMessage = error.localizedDescription
        }
    }

    private func setClickSoundSettings(_ settings: ClickSoundSettings) {
        guard clickSoundSettings != settings else { return }
        clickSoundSettings = settings
        persistSettings()

        guard isRunning else {
            metronomeEngine.prepare(clickSettings: settings)
            return
        }
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
        if !running {
            playbackPositionState.update(nil)
        }
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
                subdivision: selectedSubdivision,
                accentPatterns: accentPatterns,
                clickSoundSettings: clickSoundSettings,
                keepScreenAwake: keepScreenAwake
            )
        )
    }

}
