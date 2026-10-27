import XCTest
@testable import TempoLab

@MainActor
final class MetronomeViewModelTests: XCTestCase {
    func testAudioIsPreparedOnceBeforePlaybackAndNotForEachStart() {
        let engine = MetronomeEngineSpy()
        let viewModel = makeViewModel(engine: engine)

        XCTAssertEqual(engine.preparedSettings, [viewModel.clickSoundSettings])
        viewModel.toggleRunning()
        viewModel.toggleRunning()
        viewModel.toggleRunning()
        XCTAssertEqual(engine.preparedSettings.count, 1)
        XCTAssertEqual(engine.starts.count, 2)
    }

    func testSetBPMCommitsSliderResultOnce() {
        let engine = MetronomeEngineSpy()
        let viewModel = makeViewModel(engine: engine)

        viewModel.toggleRunning()

        XCTAssertEqual(engine.updates.count, 0)
        XCTAssertEqual(viewModel.bpm, 120)

        viewModel.setBPM(140)

        XCTAssertEqual(viewModel.bpm, 140)
        XCTAssertEqual(engine.updates.map(\.bpm), [140])
    }

    func testSetBPMDoesNotUpdateEngineWhenFinalValueIsUnchanged() {
        let engine = MetronomeEngineSpy()
        let viewModel = makeViewModel(engine: engine)

        viewModel.toggleRunning()
        viewModel.setBPM(120)

        XCTAssertTrue(engine.updates.isEmpty)
    }

    func testDirectInputCommitUpdatesRunningEngineOnceAndPersistsWithoutResettingPosition() throws {
        let engine = MetronomeEngineSpy()
        let store = InMemorySettingsStore()
        let viewModel = MetronomeViewModel(
            metronomeEngine: engine,
            settingsStore: store,
            presetStore: InMemoryPresetStore(),
            screenAwakeController: ScreenAwakeControllerSpy()
        )
        viewModel.toggleRunning()
        let position = try XCTUnwrap(
            PlaybackPosition(
                stepIndex: 2,
                timeSignature: .fourFour,
                subdivision: .quarter
            )
        )
        engine.report(position)

        XCTAssertTrue(engine.updates.isEmpty)
        viewModel.setBPM(try XCTUnwrap(BPMInputParser.parse("150")))

        XCTAssertEqual(viewModel.bpm, 150)
        XCTAssertEqual(engine.updates.map(\.bpm), [150])
        XCTAssertEqual(viewModel.currentPlaybackPosition, position)
        XCTAssertEqual(store.load().bpm, 150)
    }

    func testBPMButtonUpdatesEngineImmediately() {
        let engine = MetronomeEngineSpy()
        let viewModel = makeViewModel(engine: engine)

        viewModel.toggleRunning()
        viewModel.adjustBPM(by: 1)

        XCTAssertEqual(viewModel.bpm, 121)
        XCTAssertEqual(engine.updates.map(\.bpm), [121])
    }

    func testBPMPlusFiveButtonUpdatesEngineImmediately() {
        let engine = MetronomeEngineSpy()
        let viewModel = makeViewModel(engine: engine)

        viewModel.toggleRunning()
        viewModel.adjustBPM(by: 5)

        XCTAssertEqual(viewModel.bpm, 125)
        XCTAssertEqual(engine.updates.map(\.bpm), [125])
    }

    func testBPMButtonsUpdateTheSingleBPMState() {
        let engine = MetronomeEngineSpy()
        let viewModel = makeViewModel(engine: engine)

        viewModel.adjustBPM(by: 1)
        XCTAssertEqual(viewModel.bpm, 121)

        viewModel.adjustBPM(by: 5)
        XCTAssertEqual(viewModel.bpm, 126)
    }

    func testBPMAdjustmentsAreClampedToBounds() {
        let engine = MetronomeEngineSpy()
        let viewModel = makeViewModel(engine: engine)

        viewModel.setBPM(299)
        viewModel.adjustBPM(by: 5)
        XCTAssertEqual(viewModel.bpm, 300)

        viewModel.setBPM(31)
        viewModel.adjustBPM(by: -5)
        XCTAssertEqual(viewModel.bpm, 30)
    }

    func testButtonUsesBPMCommittedBySlider() {
        let engine = MetronomeEngineSpy()
        let viewModel = makeViewModel(engine: engine)

        viewModel.setBPM(150)
        viewModel.adjustBPM(by: 1)

        XCTAssertEqual(viewModel.bpm, 151)
    }

    func testTapTempoUpdatesEngineWhenTempoIsCalculated() {
        let engine = MetronomeEngineSpy()
        let viewModel = makeViewModel(engine: engine)

        viewModel.toggleRunning()
        viewModel.registerTap(at: 0)
        viewModel.registerTap(at: 0.4)

        XCTAssertEqual(viewModel.bpm, 150)
        XCTAssertEqual(engine.updates.map(\.bpm), [150])
    }

    func testSliderTempoIsUsedWhenStartingAfterEditing() {
        let engine = MetronomeEngineSpy()
        let viewModel = makeViewModel(engine: engine)

        viewModel.setBPM(180)
        viewModel.toggleRunning()

        XCTAssertTrue(engine.updates.isEmpty)
        XCTAssertEqual(engine.starts.map(\.bpm), [180])
    }

    func testClickSettingsAreClampedAndUpdateRunningEngine() {
        let engine = MetronomeEngineSpy()
        let viewModel = makeViewModel(engine: engine)

        viewModel.toggleRunning()
        viewModel.setNormalFrequency(100)
        viewModel.setAccentFrequency(4_000)
        viewModel.setClickVolume(2)
        viewModel.setClickSoundType(.wood)

        XCTAssertEqual(viewModel.clickSoundSettings.normalFrequency, 300)
        XCTAssertEqual(viewModel.clickSoundSettings.accentFrequency, 3_000)
        XCTAssertEqual(viewModel.clickSoundSettings.volume, 1)
        XCTAssertEqual(viewModel.clickSoundSettings.soundType, .wood)
        XCTAssertEqual(engine.clickSettingsUpdates.count, 4)
        XCTAssertEqual(engine.clickSettingsUpdates.last, viewModel.clickSoundSettings)
    }

    func testClickSettingsArePassedWhenStarting() {
        let engine = MetronomeEngineSpy()
        let viewModel = makeViewModel(engine: engine)

        viewModel.setNormalFrequency(500)
        viewModel.setAccentFrequency(2_000)
        viewModel.setClickVolume(0.5)
        viewModel.setClickSoundType(.digital)
        viewModel.toggleRunning()

        XCTAssertEqual(engine.starts.last?.clickSettings, viewModel.clickSoundSettings)
        XCTAssertEqual(engine.preparedSettings.last, viewModel.clickSoundSettings)
        XCTAssertEqual(engine.preparedSettings.count, 5)
    }

    func testSubdivisionAndPatternArePassedToRunningEngine() {
        let engine = MetronomeEngineSpy()
        let viewModel = makeViewModel(engine: engine)

        viewModel.setSubdivision(.sixteenth)
        viewModel.toggleRunning()
        viewModel.cyclePatternStep(at: 1)

        XCTAssertEqual(engine.starts.last?.subdivision, .sixteenth)
        XCTAssertEqual(engine.starts.last?.accentPattern.steps.count, 16)
        XCTAssertEqual(engine.updates.last?.accentPattern.steps[1], .mute)
    }

    func testRunningStateIsNotRestored() {
        let store = InMemorySettingsStore(
            settings: AppSettings(bpm: 150, keepScreenAwake: true)
        )
        let firstViewModel = MetronomeViewModel(
            metronomeEngine: MetronomeEngineSpy(),
            settingsStore: store,
            presetStore: InMemoryPresetStore(),
            screenAwakeController: ScreenAwakeControllerSpy()
        )
        firstViewModel.toggleRunning()
        XCTAssertTrue(firstViewModel.isRunning)

        let restoredViewModel = MetronomeViewModel(
            metronomeEngine: MetronomeEngineSpy(),
            settingsStore: store,
            presetStore: InMemoryPresetStore(),
            screenAwakeController: ScreenAwakeControllerSpy()
        )

        XCTAssertEqual(restoredViewModel.bpm, 150)
        XCTAssertFalse(restoredViewModel.isRunning)
    }

    func testScreenAwakeControllerFollowsSettingAndPlayback() {
        let controller = ScreenAwakeControllerSpy()
        let viewModel = MetronomeViewModel(
            metronomeEngine: MetronomeEngineSpy(),
            settingsStore: InMemorySettingsStore(),
            presetStore: InMemoryPresetStore(),
            screenAwakeController: controller
        )

        viewModel.setKeepScreenAwake(true)
        XCTAssertEqual(controller.values.last, false)

        viewModel.toggleRunning()
        XCTAssertEqual(controller.values.last, true)

        viewModel.toggleRunning()
        XCTAssertEqual(controller.values.last, false)
    }

    func testPlaybackPositionClearsWhenStopped() throws {
        let engine = MetronomeEngineSpy()
        let viewModel = makeViewModel(engine: engine)
        viewModel.toggleRunning()

        let position = try XCTUnwrap(
            PlaybackPosition(
                stepIndex: 2,
                timeSignature: .fourFour,
                subdivision: .quarter
            )
        )
        engine.report(position)
        XCTAssertEqual(viewModel.currentPlaybackPosition, position)

        viewModel.toggleRunning()
        XCTAssertNil(viewModel.currentPlaybackPosition)
    }

    func testSavingCreatesIndependentSnapshotWithoutUpdatingAudio() throws {
        let engine = MetronomeEngineSpy()
        let store = InMemoryPresetStore()
        let model = makeViewModel(engine: engine, presets: store)
        model.setBPM(180)
        model.selectedTimeSignature = .sixEight
        model.setSubdivision(.eighth)
        model.cyclePatternStep(at: 1)
        model.setNormalFrequency(500)
        model.setAccentFrequency(1500)
        model.setClickVolume(0.4)
        model.setClickSoundType(.wood)
        model.toggleRunning()
        let original = model.currentConfiguration
        let updateCount = engine.updates.count
        let preparedCount = engine.preparedSettings.count
        XCTAssertTrue(model.createPreset(name: "  練習 🎹  "))
        let saved = try XCTUnwrap(model.presets.first)
        XCTAssertEqual(saved.configuration, original)
        XCTAssertEqual(saved.name, "練習 🎹")
        XCTAssertEqual(store.presets, model.presets)
        XCTAssertEqual(engine.updates.count, updateCount)
        XCTAssertEqual(engine.preparedSettings.count, preparedCount)
        XCTAssertTrue(engine.configurationUpdates.isEmpty)
        XCTAssertTrue(engine.clickSettingsUpdates.isEmpty)
        model.setBPM(60)
        model.cyclePatternStep(at: 1)
        model.setClickVolume(0.9)
        XCTAssertEqual(model.presets.first?.configuration, original)
        XCTAssertTrue(model.isAppliedPresetModified)
    }

    func testRunningPresetAppliesAllSettingsWithOneUnifiedUpdateAndPersists() throws {
        let engine = MetronomeEngineSpy()
        let settings = InMemorySettingsStore(settings: AppSettings(keepScreenAwake: true))
        let preset = try makePreset(bpm: 180)
        let model = makeViewModel(engine: engine, store: settings, presets: InMemoryPresetStore([preset]))
        model.toggleRunning()
        XCTAssertTrue(model.applyPreset(id: preset.id))
        XCTAssertTrue(model.isRunning)
        XCTAssertTrue(model.keepScreenAwake)
        XCTAssertEqual(model.currentConfiguration, preset.configuration)
        XCTAssertEqual(engine.starts.count, 1)
        XCTAssertEqual(engine.stopCount, 0)
        XCTAssertTrue(engine.updates.isEmpty)
        XCTAssertTrue(engine.clickSettingsUpdates.isEmpty)
        XCTAssertEqual(engine.configurationUpdates.count, 1)
        let request = try XCTUnwrap(engine.configurationUpdates.first)
        XCTAssertEqual(request.bpm, 180)
        XCTAssertEqual(request.timeSignature, .sixEight)
        XCTAssertEqual(request.subdivision, .eighth)
        XCTAssertEqual(request.accentPattern, preset.configuration.accentPattern)
        XCTAssertEqual(request.clickSettings, preset.configuration.clickSoundSettings)
        XCTAssertEqual(settings.saveCount, 1)
        let restored = makeViewModel(engine: MetronomeEngineSpy(), store: settings)
        XCTAssertEqual(restored.currentConfiguration, preset.configuration)
        XCTAssertTrue(restored.keepScreenAwake)
        XCTAssertFalse(restored.isRunning)
    }

    func testPresetPreservesOtherMeterAndSubdivisionPatterns() throws {
        let engine = MetronomeEngineSpy()
        let preset = try makePreset()
        let model = makeViewModel(engine: engine, presets: InMemoryPresetStore([preset]))
        model.selectedTimeSignature = .threeFour
        model.setSubdivision(.triplet)
        model.cyclePatternStep(at: 1)
        let other = model.currentAccentPattern
        model.selectedTimeSignature = .sixEight
        model.setSubdivision(.sixteenth)
        model.cyclePatternStep(at: 2)
        let otherSubdivision = model.currentAccentPattern
        XCTAssertTrue(model.applyPreset(id: preset.id))
        XCTAssertEqual(model.accentPatterns.pattern(for: .threeFour, subdivision: .triplet), other)
        XCTAssertEqual(model.accentPatterns.pattern(for: .sixEight, subdivision: .sixteenth), otherSubdivision)
        XCTAssertEqual(model.currentAccentPattern, preset.configuration.accentPattern)
    }

    func testStoppedPresetOnlyPreparesChangedClickSettings() throws {
        let engine = MetronomeEngineSpy()
        let preset = try makePreset()
        let model = makeViewModel(engine: engine, presets: InMemoryPresetStore([preset]))
        XCTAssertTrue(model.applyPreset(id: preset.id))
        XCTAssertFalse(model.isRunning)
        XCTAssertFalse(model.keepScreenAwake)
        XCTAssertTrue(engine.starts.isEmpty)
        XCTAssertEqual(engine.stopCount, 0)
        XCTAssertTrue(engine.configurationUpdates.isEmpty)
        XCTAssertTrue(engine.updates.isEmpty)
        XCTAssertTrue(engine.clickSettingsUpdates.isEmpty)
        XCTAssertEqual(engine.preparedSettings, [.default, preset.configuration.clickSoundSettings])
        XCTAssertTrue(model.applyPreset(id: preset.id))
        XCTAssertEqual(engine.preparedSettings.count, 2)
    }

    func testIdenticalPresetSkipsAllAudioAndSettingsWrites() throws {
        let engine = MetronomeEngineSpy()
        let settings = InMemorySettingsStore()
        let model = makeViewModel(engine: engine, store: settings)
        model.createPreset(name: "同じ設定")
        let id = try XCTUnwrap(model.presets.first?.id)
        model.toggleRunning()
        XCTAssertTrue(model.applyPreset(id: id))
        XCTAssertTrue(model.applyPreset(id: id))
        XCTAssertTrue(engine.configurationUpdates.isEmpty)
        XCTAssertTrue(engine.updates.isEmpty)
        XCTAssertTrue(engine.clickSettingsUpdates.isEmpty)
        XCTAssertEqual(engine.preparedSettings.count, 1)
        XCTAssertEqual(engine.starts.count, 1)
        XCTAssertEqual(engine.stopCount, 0)
        XCTAssertEqual(settings.saveCount, 0)
    }

    func testRenameOverwriteAndDeleteKeepIdentityAndCurrentSettings() throws {
        let engine = MetronomeEngineSpy()
        let store = InMemoryPresetStore()
        let model = makeViewModel(engine: engine, presets: store)
        model.createPreset(name: "元")
        let original = try XCTUnwrap(model.presets.first)
        XCTAssertTrue(model.renamePreset(id: original.id, name: " 改名 "))
        XCTAssertEqual(model.presets.first?.id, original.id)
        model.setBPM(155)
        XCTAssertTrue(model.isAppliedPresetModified)
        XCTAssertTrue(model.overwritePreset(id: original.id))
        XCTAssertFalse(model.isAppliedPresetModified)
        XCTAssertEqual(model.presets.first?.id, original.id)
        XCTAssertEqual(model.presets.first?.createdAt, original.createdAt)
        XCTAssertEqual(model.presets.first?.configuration.bpm, 155)
        XCTAssertEqual(store.presets, model.presets)
        let current = model.currentConfiguration
        XCTAssertTrue(model.deletePreset(id: original.id))
        XCTAssertEqual(model.currentConfiguration, current)
        XCTAssertNil(model.lastAppliedPresetID)
        XCTAssertTrue(store.presets.isEmpty)
    }

    func testReorderingMultipleRowsPersistsOrder() throws {
        let store = try InMemoryPresetStore([makePreset(bpm: 30), makePreset(bpm: 120), makePreset(bpm: 300)])
        let model = makeViewModel(engine: MetronomeEngineSpy(), presets: store)
        let ids = model.presets.map(\.id)
        XCTAssertTrue(model.movePresets(from: IndexSet([0, 2]), to: 3))
        XCTAssertEqual(model.presets.map(\.id), [ids[1], ids[0], ids[2]])
        XCTAssertEqual(store.presets, model.presets)
        XCTAssertTrue(model.movePresets(from: IndexSet(integer: 2), to: 0))
        XCTAssertEqual(model.presets.map(\.id), [ids[2], ids[1], ids[0]])
        XCTAssertFalse(model.movePresets(from: IndexSet(integer: 5), to: 0))
    }

    func testSaveFailuresNeverChangeListOrReportSuccess() throws {
        let store = InMemoryPresetStore()
        let model = makeViewModel(engine: MetronomeEngineSpy(), presets: store)
        XCTAssertFalse(model.createPreset(name: " \n "))
        XCTAssertTrue(model.presets.isEmpty)
        XCTAssertNotNil(model.presetErrorMessage)
        XCTAssertTrue(model.createPreset(name: "正常"))
        let original = try XCTUnwrap(model.presets.first)
        store.failSave = true
        model.setBPM(180)
        XCTAssertFalse(model.createPreset(name: "失敗"))
        XCTAssertFalse(model.renamePreset(id: original.id, name: "失敗"))
        XCTAssertFalse(model.overwritePreset(id: original.id))
        XCTAssertFalse(model.deletePreset(id: original.id))
        XCTAssertEqual(model.presets, [original])
        XCTAssertEqual(model.lastAppliedPresetID, original.id)
        XCTAssertTrue(model.isAppliedPresetModified)
        XCTAssertNotNil(model.presetErrorMessage)
    }

    func testLoadingFailureAndRecoveryWarningAreVisible() throws {
        let store = InMemoryPresetStore()
        store.failLoad = true
        let model = makeViewModel(engine: MetronomeEngineSpy(), presets: store)
        XCTAssertTrue(model.presets.isEmpty)
        XCTAssertNotNil(model.presetErrorMessage)
        store.failLoad = false
        store.skippedRecordCount = 1
        store.presets = [try makePreset()]
        model.loadPresets()
        XCTAssertEqual(model.presets, store.presets)
        XCTAssertNotNil(model.presetErrorMessage)
        store.skippedRecordCount = 0
        model.loadPresets()
        XCTAssertNil(model.presetErrorMessage)
    }

    func testRapidPresetCallsKeepOrderAndFinalSettingsWithoutStopping() throws {
        let engine = MetronomeEngineSpy()
        let presets = try [makePreset(bpm: 30), makePreset(bpm: 300), makePreset(bpm: 180)]
        let model = makeViewModel(engine: engine, presets: InMemoryPresetStore(presets))
        model.toggleRunning()
        for preset in presets { XCTAssertTrue(model.applyPreset(id: preset.id)) }
        XCTAssertEqual(engine.configurationUpdates.map(\.bpm), [30, 300, 180])
        XCTAssertEqual(model.currentConfiguration, presets.last?.configuration)
        XCTAssertEqual(model.lastAppliedPresetID, presets.last?.id)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(engine.starts.count, 1)
        XCTAssertEqual(engine.stopCount, 0)
    }

    func testNewMeterClearsOldPositionAndRejectsStaleCallbacks() throws {
        let engine = MetronomeEngineSpy()
        let preset = try makePreset()
        let model = makeViewModel(engine: engine, presets: InMemoryPresetStore([preset]))
        model.toggleRunning()
        let old = try XCTUnwrap(PlaybackPosition(stepIndex: 3, timeSignature: .fourFour, subdivision: .quarter))
        engine.report(old)
        XCTAssertEqual(model.currentPlaybackPosition, old)
        model.applyPreset(id: preset.id)
        XCTAssertNil(model.currentPlaybackPosition)
        engine.report(old)
        XCTAssertNil(model.currentPlaybackPosition)
        let new = try XCTUnwrap(PlaybackPosition(stepIndex: 11, timeSignature: .sixEight, subdivision: .eighth))
        engine.report(new)
        XCTAssertEqual(model.currentPlaybackPosition, new)
    }

    func testConfigurationFailureUsesExistingAudioErrorPolicy() throws {
        let engine = MetronomeEngineSpy()
        let preset = try makePreset()
        let model = makeViewModel(engine: engine, presets: InMemoryPresetStore([preset]))
        model.toggleRunning()
        model.applyPreset(id: preset.id)
        engine.failConfiguration()
        XCTAssertFalse(model.isRunning)
        XCTAssertNotNil(model.audioErrorMessage)
    }

    private func makePreset(bpm: Int = 180) throws -> MetronomePreset {
        try MetronomePreset(name: "練習", configuration: PresetConfiguration(
            bpm: bpm, timeSignature: .sixEight, subdivision: .eighth,
            accentPattern: AccentPattern(
                timeSignature: .sixEight, subdivision: .eighth,
                steps: [.mute, .accent] + Array(repeating: .normal, count: 10)
            ),
            clickSoundSettings: ClickSoundSettings(
                normalFrequency: 500, accentFrequency: 1700, volume: 0.35, soundType: .wood
            )
        ))
    }

    private func makeViewModel(
        engine: MetronomeEngineSpy,
        store: InMemorySettingsStore = InMemorySettingsStore(),
        presets: InMemoryPresetStore = InMemoryPresetStore()
    ) -> MetronomeViewModel {
        MetronomeViewModel(
            metronomeEngine: engine,
            settingsStore: store,
            presetStore: presets,
            screenAwakeController: ScreenAwakeControllerSpy()
        )
    }
}

nonisolated private final class InMemorySettingsStore: SettingsStoring, @unchecked Sendable {
    private var settings: AppSettings
    private(set) var saveCount = 0

    init(settings: AppSettings = .default) {
        self.settings = settings
    }

    func load() -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) {
        saveCount += 1
        self.settings = settings
    }
}

@MainActor
private final class ScreenAwakeControllerSpy: ScreenAwakeControlling {
    private(set) var values: [Bool] = []

    func setPreventSleep(_ shouldPreventSleep: Bool) {
        values.append(shouldPreventSleep)
    }
}

nonisolated private final class MetronomeEngineSpy: MetronomeEngineProtocol, @unchecked Sendable {
    typealias Request = (
        bpm: Int,
        timeSignature: TimeSignature,
        subdivision: Subdivision,
        accentPattern: AccentPattern,
        clickSettings: ClickSoundSettings
    )

    private(set) var starts: [Request] = []
    private(set) var configurationUpdates: [Request] = []
    private(set) var stopCount = 0
    private var configurationFailure: MetronomeEngine.FailureHandler?
    private(set) var updates: [Request] = []
    private(set) var clickSettingsUpdates: [ClickSoundSettings] = []
    private(set) var preparedSettings: [ClickSoundSettings] = []
    private var positionHandler: MetronomeEngine.PositionHandler?

    func prepare(clickSettings: ClickSoundSettings) {
        preparedSettings.append(clickSettings)
    }

    func start(
        actionUptime: TimeInterval,
        bpm: Int,
        timeSignature: TimeSignature,
        subdivision: Subdivision,
        accentPattern: AccentPattern,
        clickSettings: ClickSoundSettings,
        positionHandler: @escaping MetronomeEngine.PositionHandler,
        completion: @escaping MetronomeEngine.StartHandler
    ) {
        starts.append((bpm, timeSignature, subdivision, accentPattern, clickSettings))
        self.positionHandler = positionHandler
    }

    func stop() { stopCount += 1 }

    func updateConfiguration(
        bpm: Int,
        timeSignature: TimeSignature,
        subdivision: Subdivision,
        accentPattern: AccentPattern,
        clickSettings: ClickSoundSettings,
        onFailure: @escaping MetronomeEngine.FailureHandler
    ) {
        configurationUpdates.append((bpm, timeSignature, subdivision, accentPattern, clickSettings))
        configurationFailure = onFailure
    }

    @MainActor
    func failConfiguration() {
        configurationFailure?(.audioFormatUnavailable)
    }

    func update(
        bpm: Int,
        timeSignature: TimeSignature,
        subdivision: Subdivision,
        accentPattern: AccentPattern,
        onFailure: @escaping MetronomeEngine.FailureHandler
    ) {
        updates.append((bpm, timeSignature, subdivision, accentPattern, .default))
    }

    func updateClickSettings(
        _ settings: ClickSoundSettings,
        onFailure: @escaping MetronomeEngine.FailureHandler
    ) {
        clickSettingsUpdates.append(settings)
    }

    func previewClick(
        isAccent: Bool,
        settings: ClickSoundSettings,
        completion: @escaping MetronomeEngine.StartHandler
    ) {}

    @MainActor
    func report(_ position: PlaybackPosition?) {
        positionHandler?(position)
    }
}

nonisolated private final class InMemoryPresetStore: PresetStoring, @unchecked Sendable {
    var presets: [MetronomePreset]
    var failSave = false
    var failLoad = false
    var skippedRecordCount = 0

    init(_ presets: [MetronomePreset] = []) { self.presets = presets }

    func load() throws -> PresetLoadResult {
        if failLoad { throw PresetError.unreadableData }
        return PresetLoadResult(presets: presets, skippedRecordCount: skippedRecordCount)
    }

    func save(_ presets: [MetronomePreset]) throws {
        if failSave { throw PresetError.saveFailed }
        self.presets = presets
    }
}
