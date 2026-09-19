import AVFoundation
import XCTest
@testable import TempoLab

@MainActor
final class TempoDetectorViewModelTests: XCTestCase {
    func testGrantedStartTransitionsFromStoppedToStartingToListening() {
        let engine = AudioInputEngineSpy(permission: .granted)
        let viewModel = TempoDetectorViewModel(audioInputEngine: engine)

        XCTAssertEqual(viewModel.lifecycleState, .stopped)
        viewModel.startListening()
        XCTAssertEqual(viewModel.lifecycleState, .starting)

        engine.completeStartSuccessfully()
        XCTAssertEqual(viewModel.lifecycleState, .listening)
    }

    func testStopTransitionsFromListeningToStopped() {
        let engine = AudioInputEngineSpy(permission: .granted)
        let viewModel = TempoDetectorViewModel(audioInputEngine: engine)
        viewModel.startListening()
        engine.completeStartSuccessfully()

        viewModel.stopListening()

        XCTAssertEqual(viewModel.lifecycleState, .stopped)
        XCTAssertEqual(engine.stopCallCount, 1)
        XCTAssertEqual(viewModel.normalizedInputLevel, 0)
    }

    func testDeniedPermissionDoesNotStartEngine() {
        let engine = AudioInputEngineSpy(permission: .denied)
        let viewModel = TempoDetectorViewModel(audioInputEngine: engine)

        viewModel.startListening()

        XCTAssertEqual(viewModel.permissionState, .denied)
        XCTAssertFalse(viewModel.isListening)
        XCTAssertEqual(engine.startCallCount, 0)
    }

    func testUndeterminedPermissionStartsAfterGrant() {
        let engine = AudioInputEngineSpy(permission: .undetermined)
        let viewModel = TempoDetectorViewModel(audioInputEngine: engine)

        viewModel.startListening()
        XCTAssertEqual(viewModel.lifecycleState, .requestingPermission)

        engine.resolvePermission(.granted)
        XCTAssertEqual(viewModel.permissionState, .granted)
        XCTAssertEqual(viewModel.lifecycleState, .starting)

        engine.completeStartSuccessfully()
        XCTAssertEqual(viewModel.lifecycleState, .listening)
    }

    func testSystemInterruptionStopsListening() {
        let engine = AudioInputEngineSpy(permission: .granted)
        let viewModel = TempoDetectorViewModel(audioInputEngine: engine)
        viewModel.startListening()
        engine.completeStartSuccessfully()

        engine.reportStop(.interruption)

        XCTAssertEqual(viewModel.lifecycleState, .stopped)
        XCTAssertEqual(viewModel.normalizedInputLevel, 0)
        XCTAssertNotNil(viewModel.message)
    }

    func testDetectionResultCommitsRoundedTempoThroughHandler() {
        let engine = AudioInputEngineSpy(permission: .granted)
        let detector = TempoDetectorSpy()
        var committedBPM: Int?
        let viewModel = TempoDetectorViewModel(
            audioInputEngine: engine,
            tempoDetector: detector,
            tempoCommitHandler: { committedBPM = $0 }
        )
        viewModel.startListening()
        engine.completeStartSuccessfully()

        detector.emit(.init(
            bpm: 119.7,
            confidence: 0.82,
            candidates: [.init(bpm: 119.7, score: 0.82)]
        ))
        viewModel.useDetectedTempo()

        XCTAssertEqual(viewModel.detectedBPM, 120)
        XCTAssertEqual(committedBPM, 120)
    }

    func testResultPublishedAfterStopIsIgnored() {
        let engine = AudioInputEngineSpy(permission: .granted)
        let detector = TempoDetectorSpy()
        let viewModel = TempoDetectorViewModel(
            audioInputEngine: engine,
            tempoDetector: detector
        )
        viewModel.startListening()
        engine.completeStartSuccessfully()
        viewModel.stopListening()

        detector.emit(.init(bpm: 100, confidence: 0.8, candidates: []))

        XCTAssertNil(viewModel.detectionResult)
    }
}

nonisolated private final class TempoDetectorSpy: TempoDetecting, @unchecked Sendable {
    private var resultHandler: ResultHandler?
    private(set) var resetCallCount = 0

    func setResultHandler(_ handler: @escaping ResultHandler) {
        resultHandler = handler
    }

    func process(buffer: AVAudioPCMBuffer, at time: AVAudioTime) {}

    func reset() {
        resetCallCount += 1
    }

    @MainActor
    func emit(_ result: TempoDetectionResult?) {
        resultHandler?(result)
    }
}

nonisolated private final class AudioInputEngineSpy: AudioInputEngineProtocol, @unchecked Sendable {
    var permission: MicrophonePermissionState
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private var permissionHandler: PermissionHandler?
    private var startHandler: StartHandler?
    private var stopHandler: StopHandler?

    init(permission: MicrophonePermissionState) {
        self.permission = permission
    }

    func permissionState() -> MicrophonePermissionState {
        permission
    }

    func requestPermission(completion: @escaping PermissionHandler) {
        permissionHandler = completion
    }

    func start(
        bufferHandler: BufferHandler?,
        levelHandler: @escaping LevelHandler,
        stopHandler: @escaping StopHandler,
        completion: @escaping StartHandler
    ) {
        startCallCount += 1
        self.stopHandler = stopHandler
        startHandler = completion
    }

    func stop() {
        stopCallCount += 1
    }

    @MainActor
    func resolvePermission(_ permission: MicrophonePermissionState) {
        self.permission = permission
        permissionHandler?(permission)
    }

    @MainActor
    func completeStartSuccessfully() {
        startHandler?(.success(()))
    }

    @MainActor
    func reportStop(_ reason: AudioInputStopReason) {
        stopHandler?(reason)
    }
}
