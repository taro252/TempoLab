import XCTest
@testable import TempoLab

@MainActor
final class MetronomeViewModelTests: XCTestCase {
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
            screenAwakeController: ScreenAwakeControllerSpy()
        )
        firstViewModel.toggleRunning()
        XCTAssertTrue(firstViewModel.isRunning)

        let restoredViewModel = MetronomeViewModel(
            metronomeEngine: MetronomeEngineSpy(),
            settingsStore: store,
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
            screenAwakeController: controller
        )

        viewModel.setKeepScreenAwake(true)
        XCTAssertEqual(controller.values.last, false)

        viewModel.toggleRunning()
        XCTAssertEqual(controller.values.last, true)

        viewModel.toggleRunning()
        XCTAssertEqual(controller.values.last, false)
    }

    private func makeViewModel(engine: MetronomeEngineSpy) -> MetronomeViewModel {
        MetronomeViewModel(
            metronomeEngine: engine,
            settingsStore: InMemorySettingsStore(),
            screenAwakeController: ScreenAwakeControllerSpy()
        )
    }
}

nonisolated private final class InMemorySettingsStore: SettingsStoring, @unchecked Sendable {
    private var settings: AppSettings

    init(settings: AppSettings = .default) {
        self.settings = settings
    }

    func load() -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) {
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
    private(set) var updates: [Request] = []
    private(set) var clickSettingsUpdates: [ClickSoundSettings] = []

    func start(
        bpm: Int,
        timeSignature: TimeSignature,
        subdivision: Subdivision,
        accentPattern: AccentPattern,
        clickSettings: ClickSoundSettings,
        completion: @escaping MetronomeEngine.StartHandler
    ) {
        starts.append((bpm, timeSignature, subdivision, accentPattern, clickSettings))
    }

    func stop() {}

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
}
