import XCTest
@testable import TempoLab

@MainActor
final class MetronomeViewModelTests: XCTestCase {
    func testSetBPMCommitsSliderResultOnce() {
        let engine = MetronomeEngineSpy()
        let viewModel = MetronomeViewModel(metronomeEngine: engine)

        viewModel.toggleRunning()

        XCTAssertEqual(engine.updates.count, 0)
        XCTAssertEqual(viewModel.bpm, 120)

        viewModel.setBPM(140)

        XCTAssertEqual(viewModel.bpm, 140)
        XCTAssertEqual(engine.updates.map(\.bpm), [140])
    }

    func testSetBPMDoesNotUpdateEngineWhenFinalValueIsUnchanged() {
        let engine = MetronomeEngineSpy()
        let viewModel = MetronomeViewModel(metronomeEngine: engine)

        viewModel.toggleRunning()
        viewModel.setBPM(120)

        XCTAssertTrue(engine.updates.isEmpty)
    }

    func testBPMButtonUpdatesEngineImmediately() {
        let engine = MetronomeEngineSpy()
        let viewModel = MetronomeViewModel(metronomeEngine: engine)

        viewModel.toggleRunning()
        viewModel.adjustBPM(by: 1)

        XCTAssertEqual(viewModel.bpm, 121)
        XCTAssertEqual(engine.updates.map(\.bpm), [121])
    }

    func testBPMPlusFiveButtonUpdatesEngineImmediately() {
        let engine = MetronomeEngineSpy()
        let viewModel = MetronomeViewModel(metronomeEngine: engine)

        viewModel.toggleRunning()
        viewModel.adjustBPM(by: 5)

        XCTAssertEqual(viewModel.bpm, 125)
        XCTAssertEqual(engine.updates.map(\.bpm), [125])
    }

    func testBPMButtonsUpdateTheSingleBPMState() {
        let engine = MetronomeEngineSpy()
        let viewModel = MetronomeViewModel(metronomeEngine: engine)

        viewModel.adjustBPM(by: 1)
        XCTAssertEqual(viewModel.bpm, 121)

        viewModel.adjustBPM(by: 5)
        XCTAssertEqual(viewModel.bpm, 126)
    }

    func testBPMAdjustmentsAreClampedToBounds() {
        let engine = MetronomeEngineSpy()
        let viewModel = MetronomeViewModel(metronomeEngine: engine)

        viewModel.setBPM(299)
        viewModel.adjustBPM(by: 5)
        XCTAssertEqual(viewModel.bpm, 300)

        viewModel.setBPM(31)
        viewModel.adjustBPM(by: -5)
        XCTAssertEqual(viewModel.bpm, 30)
    }

    func testButtonUsesBPMCommittedBySlider() {
        let engine = MetronomeEngineSpy()
        let viewModel = MetronomeViewModel(metronomeEngine: engine)

        viewModel.setBPM(150)
        viewModel.adjustBPM(by: 1)

        XCTAssertEqual(viewModel.bpm, 151)
    }

    func testTapTempoUpdatesEngineWhenTempoIsCalculated() {
        let engine = MetronomeEngineSpy()
        let viewModel = MetronomeViewModel(metronomeEngine: engine)

        viewModel.toggleRunning()
        viewModel.registerTap(at: 0)
        viewModel.registerTap(at: 0.4)

        XCTAssertEqual(viewModel.bpm, 150)
        XCTAssertEqual(engine.updates.map(\.bpm), [150])
    }

    func testSliderTempoIsUsedWhenStartingAfterEditing() {
        let engine = MetronomeEngineSpy()
        let viewModel = MetronomeViewModel(metronomeEngine: engine)

        viewModel.setBPM(180)
        viewModel.toggleRunning()

        XCTAssertTrue(engine.updates.isEmpty)
        XCTAssertEqual(engine.starts.map(\.bpm), [180])
    }
}

nonisolated private final class MetronomeEngineSpy: MetronomeEngineProtocol, @unchecked Sendable {
    typealias Request = (bpm: Int, timeSignature: TimeSignature)

    private(set) var starts: [Request] = []
    private(set) var updates: [Request] = []

    func start(
        bpm: Int,
        timeSignature: TimeSignature,
        completion: @escaping MetronomeEngine.StartHandler
    ) {
        starts.append((bpm, timeSignature))
    }

    func stop() {}

    func update(
        bpm: Int,
        timeSignature: TimeSignature,
        onFailure: @escaping MetronomeEngine.FailureHandler
    ) {
        updates.append((bpm, timeSignature))
    }
}
