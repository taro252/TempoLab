import SwiftUI

nonisolated enum BPMDialMath {
    static func bpm(
        startBPM: Int,
        translation: Double,
        pointsPerBPM: Double,
        range: ClosedRange<Int>
    ) -> Int {
        precondition(pointsPerBPM > 0)

        let bpmOffset = Int((-translation / pointsPerBPM).rounded())
        return min(max(startBPM + bpmOffset, range.lowerBound), range.upperBound)
    }
}

nonisolated struct BPMDragState: Equatable {
    let startBPM: Int
    private(set) var visualTranslation = 0.0
    private var lastGestureTranslation = 0.0

    init(startBPM: Int) {
        self.startBPM = startBPM
    }

    mutating func update(
        gestureTranslation: Double,
        pointsPerBPM: Double,
        range: ClosedRange<Int>
    ) -> Int {
        precondition(pointsPerBPM > 0)

        let translationDelta = gestureTranslation - lastGestureTranslation
        lastGestureTranslation = gestureTranslation

        let minimumTranslation = Double(startBPM - range.upperBound) * pointsPerBPM
        let maximumTranslation = Double(startBPM - range.lowerBound) * pointsPerBPM
        visualTranslation = min(
            max(visualTranslation + translationDelta, minimumTranslation),
            maximumTranslation
        )

        return BPMDialMath.bpm(
            startBPM: startBPM,
            translation: visualTranslation,
            pointsPerBPM: pointsPerBPM,
            range: range
        )
    }
}

nonisolated struct BPMAnimationRequest: Equatable {
    let id: Int
    let fromBPM: Int
    let toBPM: Int
}

nonisolated enum BPMHapticStrength: Equatable {
    case light
    case strong
}

nonisolated enum BPMHapticPolicy {
    static func strength(for bpm: Int) -> BPMHapticStrength? {
        guard bpm.isMultiple(of: 5) else { return nil }
        return bpm.isMultiple(of: 10) ? .strong : .light
    }
}

nonisolated struct BPMHapticGate: Equatable {
    private(set) var lastHapticBPM: Int?

    mutating func begin(at bpm: Int) {
        lastHapticBPM = BPMHapticPolicy.strength(for: bpm) == nil ? nil : bpm
    }

    mutating func feedback(for bpm: Int) -> BPMHapticStrength? {
        guard lastHapticBPM != bpm else { return nil }

        guard let strength = BPMHapticPolicy.strength(for: bpm) else {
            lastHapticBPM = nil
            return nil
        }

        lastHapticBPM = bpm
        return strength
    }

    mutating func reset() {
        lastHapticBPM = nil
    }
}

struct BPMControlView: View {
    let bpm: Int
    let range: ClosedRange<Int>
    let animationRequest: BPMAnimationRequest?
    let compact: Bool
    let onCommit: (Int) -> Void

    @State private var dragState: BPMDragState?
    @State private var dragBPM: Int?
    @State private var hapticGate = BPMHapticGate()
    @State private var visualBPM: Double

    private let pointsPerBPM: CGFloat = 12
    private let buttonAnimationDuration = 0.16

    init(
        bpm: Int,
        range: ClosedRange<Int>,
        animationRequest: BPMAnimationRequest?,
        compact: Bool = false,
        onCommit: @escaping (Int) -> Void
    ) {
        self.bpm = bpm
        self.range = range
        self.animationRequest = animationRequest
        self.compact = compact
        self.onCommit = onCommit
        _visualBPM = State(initialValue: Double(bpm))
    }

    private var displayedBPM: Int {
        dragBPM ?? bpm
    }

    var body: some View {
        ruler
        .onChange(of: bpm) { _, newBPM in
            guard dragState == nil else { return }
            guard animationRequest?.toBPM != newBPM else { return }
            visualBPM = Double(newBPM)
        }
        .onChange(of: animationRequest) { _, request in
            guard dragState == nil,
                  let request,
                  request.toBPM == bpm else { return }

            var immediateTransaction = Transaction(animation: nil)
            immediateTransaction.disablesAnimations = true
            withTransaction(immediateTransaction) {
                visualBPM = Double(request.fromBPM)
            }
            withAnimation(.easeOut(duration: buttonAnimationDuration)) {
                visualBPM = Double(request.toBPM)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tempo")
        .accessibilityValue("\(displayedBPM) BPM")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                onCommit(min(bpm + 1, range.upperBound))
            case .decrement:
                onCommit(max(bpm - 1, range.lowerBound))
            @unknown default:
                break
            }
        }
    }

    private var ruler: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let trackY: CGFloat = compact ? 40 : 50
            let tickY: CGFloat = compact ? 25 : 31
            let indicatorY: CGFloat = compact ? 34 : 44
            let markerY: CGFloat = compact ? 55 : 67
            let visibleRadius = Int(ceil(geometry.size.width / (2 * pointsPerBPM))) + 2
            let lowerBPM = max(displayedBPM - visibleRadius, range.lowerBound)
            let upperBPM = min(displayedBPM + visibleRadius, range.upperBound)

            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 1)
                    .position(x: centerX, y: trackY)

                ForEach(lowerBPM...upperBPM, id: \.self) { tickBPM in
                    tick(for: tickBPM)
                        .position(
                            x: tickPosition(
                                for: tickBPM,
                                centerX: centerX
                            ),
                            y: tickY
                        )
                }

                Capsule()
                    .fill(Color("AppAccent"))
                    .frame(width: 2, height: compact ? 34 : 42)
                    .position(x: centerX, y: indicatorY)

                Image(systemName: "triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color("AppAccent"))
                    .position(x: centerX, y: markerY)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
        }
        .frame(height: compact ? 60 : 76)
        .clipped()
    }

    private func tick(for tickBPM: Int) -> some View {
        let isTenBPM = tickBPM.isMultiple(of: 10)
        let isFiveBPM = tickBPM.isMultiple(of: 5)
        let height: CGFloat = isTenBPM ? 22 : (isFiveBPM ? 16 : 9)
        let width: CGFloat = isTenBPM ? 2 : (isFiveBPM ? 1.5 : 1)

        return VStack(spacing: 3) {
            Text(isFiveBPM ? "\(tickBPM)" : "")
                .font(
                    isTenBPM
                        ? .caption2.monospacedDigit().weight(.semibold)
                        : .caption2.monospacedDigit()
                )
                .foregroundStyle(
                    isTenBPM ? Color.white : Color("AppSecondaryText")
                )
                .frame(width: 36)

            Rectangle()
                .fill(
                    isTenBPM ? Color.white : Color("AppSecondaryText")
                )
                .frame(width: width, height: height)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if dragState == nil {
                    dragState = BPMDragState(startBPM: bpm)
                    visualBPM = Double(bpm)
                    hapticGate.begin(at: bpm)
                    prepareHaptics()
                }

                guard var updatedDragState = dragState else { return }
                let newBPM = updatedDragState.update(
                    gestureTranslation: Double(gesture.translation.width),
                    pointsPerBPM: Double(pointsPerBPM),
                    range: range
                )
                dragState = updatedDragState
                dragBPM = newBPM
                playHapticIfNeeded(for: newBPM)
            }
            .onEnded { gesture in
                var finalDragState = dragState ?? BPMDragState(startBPM: bpm)
                let finalBPM = finalDragState.update(
                    gestureTranslation: Double(gesture.translation.width),
                    pointsPerBPM: Double(pointsPerBPM),
                    range: range
                )

                onCommit(finalBPM)
                visualBPM = Double(finalBPM)
                dragState = nil
                dragBPM = nil
                hapticGate.reset()
            }
    }

    private func tickPosition(for tickBPM: Int, centerX: CGFloat) -> CGFloat {
        if let dragState {
            return centerX
                + CGFloat(tickBPM - dragState.startBPM) * pointsPerBPM
                + CGFloat(dragState.visualTranslation)
        }

        return centerX + CGFloat(Double(tickBPM) - visualBPM) * pointsPerBPM
    }

    private func prepareHaptics() {
        #if os(iOS)
        HapticFeedbackHelper.prepare()
        #endif
    }

    private func playHapticIfNeeded(for bpm: Int) {
        guard let strength = hapticGate.feedback(for: bpm) else { return }

        #if os(iOS)
        HapticFeedbackHelper.play(strength)
        #endif
    }
}
