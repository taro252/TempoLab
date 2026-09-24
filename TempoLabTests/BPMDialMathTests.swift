import XCTest
@testable import TempoLab

final class BPMDialMathTests: XCTestCase {
    private let range = 30...300
    private let pointsPerBPM = 12.0

    func testZeroTranslationKeepsStartingBPM() {
        XCTAssertEqual(calculatedBPM(startBPM: 150, translation: 0), 150)
    }

    func testLeftDragRaisesBPMByOnePerTwelvePoints() {
        XCTAssertEqual(calculatedBPM(startBPM: 150, translation: -12), 151)
        XCTAssertEqual(calculatedBPM(startBPM: 150, translation: -24), 152)
    }

    func testRightDragLowersBPMByOnePerTwelvePoints() {
        XCTAssertEqual(calculatedBPM(startBPM: 150, translation: 12), 149)
    }

    func testResultIsClampedToBPMRange() {
        XCTAssertEqual(calculatedBPM(startBPM: 30, translation: 120), 30)
        XCTAssertEqual(calculatedBPM(startBPM: 300, translation: -120), 300)
    }

    func testVisibleTicksFollowRenderedPositionDuringDirectBPMChange() {
        let width = 360.0

        // The model may already be 90 while the ruler still renders at 122.
        let beforeVisualUpdate = BPMDialMath.visibleRange(
            centeredAt: 122,
            width: width,
            pointsPerBPM: pointsPerBPM,
            range: range
        )
        XCTAssertTrue(beforeVisualUpdate.contains(122))

        let afterVisualUpdate = BPMDialMath.visibleRange(
            centeredAt: 90,
            width: width,
            pointsPerBPM: pointsPerBPM,
            range: range
        )
        XCTAssertTrue(afterVisualUpdate.contains(90))
        XCTAssertEqual(afterVisualUpdate, 73...107)
    }

    func testStaleButtonAnimationDoesNotSuppressDirectBPMChange() {
        let previousButtonAnimation = BPMAnimationRequest(id: 1, fromBPM: 85, toBPM: 90)

        XCTAssertFalse(previousButtonAnimation.matchesTransition(from: 122, to: 90))
        XCTAssertTrue(previousButtonAnimation.matchesTransition(from: 85, to: 90))
    }

    func testLowerBoundaryStopsBPMAndVisualTranslation() {
        var state = BPMDragState(startBPM: 35)

        XCTAssertEqual(updatedBPM(&state, translation: 60), 30)
        XCTAssertEqual(state.visualTranslation, 60)
        XCTAssertEqual(updatedBPM(&state, translation: 180), 30)
        XCTAssertEqual(state.visualTranslation, 60)
    }

    func testUpperBoundaryStopsBPMAndVisualTranslation() {
        var state = BPMDragState(startBPM: 295)

        XCTAssertEqual(updatedBPM(&state, translation: -60), 300)
        XCTAssertEqual(state.visualTranslation, -60)
        XCTAssertEqual(updatedBPM(&state, translation: -180), 300)
        XCTAssertEqual(state.visualTranslation, -60)
    }

    func testVisualTranslationMovesImmediatelyWhenReversingFromBoundary() {
        var state = BPMDragState(startBPM: 35)

        XCTAssertEqual(updatedBPM(&state, translation: 180), 30)
        XCTAssertEqual(state.visualTranslation, 60)

        XCTAssertEqual(updatedBPM(&state, translation: 179), 30)
        XCTAssertEqual(state.visualTranslation, 59)
        XCTAssertEqual(updatedBPM(&state, translation: 168), 31)
        XCTAssertEqual(state.visualTranslation, 48)
    }

    func testFiveBPMMilestoneUsesLightHaptic() {
        XCTAssertEqual(BPMHapticPolicy.strength(for: 155), .light)
    }

    func testTenBPMMilestoneUsesStrongHaptic() {
        XCTAssertEqual(BPMHapticPolicy.strength(for: 150), .strong)
    }

    func testNonMilestoneDoesNotUseHaptic() {
        XCTAssertNil(BPMHapticPolicy.strength(for: 151))
    }

    func testHapticFiresOnceUntilBPMLeavesMilestone() {
        var gate = BPMHapticGate()
        gate.begin(at: 149)

        XCTAssertEqual(gate.feedback(for: 150), .strong)
        XCTAssertNil(gate.feedback(for: 150))
        XCTAssertNil(gate.feedback(for: 150))
        XCTAssertNil(gate.feedback(for: 149))
        XCTAssertEqual(gate.feedback(for: 150), .strong)
    }

    func testStartingOnMilestoneDoesNotImmediatelyFireHaptic() {
        var gate = BPMHapticGate()
        gate.begin(at: 150)

        XCTAssertNil(gate.feedback(for: 150))
        XCTAssertNil(gate.feedback(for: 151))
        XCTAssertEqual(gate.feedback(for: 150), .strong)
    }

    private func calculatedBPM(startBPM: Int, translation: Double) -> Int {
        BPMDialMath.bpm(
            startBPM: startBPM,
            translation: translation,
            pointsPerBPM: pointsPerBPM,
            range: range
        )
    }

    private func updatedBPM(_ state: inout BPMDragState, translation: Double) -> Int {
        state.update(
            gestureTranslation: translation,
            pointsPerBPM: pointsPerBPM,
            range: range
        )
    }
}
