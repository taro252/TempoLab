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

struct BPMControlView: View {
    let bpm: Int
    let range: ClosedRange<Int>
    let onCommit: (Int) -> Void

    @State private var dragStartBPM: Int?
    @State private var dragBPM: Int?
    @State private var dragTranslation: CGFloat = 0

    private let pointsPerBPM: CGFloat = 12

    private var displayedBPM: Int {
        dragBPM ?? bpm
    }

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 0) {
                Text(displayedBPM, format: .number)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("BPM")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            ruler
        }
        .transaction { transaction in
            transaction.animation = nil
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
            let visibleRadius = Int(ceil(geometry.size.width / (2 * pointsPerBPM))) + 2
            let lowerBPM = max(displayedBPM - visibleRadius, range.lowerBound)
            let upperBPM = min(displayedBPM + visibleRadius, range.upperBound)
            let anchorBPM = dragStartBPM ?? bpm

            ZStack {
                Rectangle()
                    .fill(.secondary.opacity(0.25))
                    .frame(height: 1)
                    .position(x: centerX, y: 50)

                ForEach(lowerBPM...upperBPM, id: \.self) { tickBPM in
                    tick(for: tickBPM)
                        .position(
                            x: centerX
                                + CGFloat(tickBPM - anchorBPM) * pointsPerBPM
                                + dragTranslation,
                            y: 31
                        )
                }

                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 34)
                    .position(x: centerX, y: 43)

                Image(systemName: "triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)
                    .position(x: centerX, y: 67)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
        }
        .frame(height: 76)
        .clipped()
    }

    private func tick(for tickBPM: Int) -> some View {
        let isTenBPM = tickBPM.isMultiple(of: 10)
        let isFiveBPM = tickBPM.isMultiple(of: 5)
        let height: CGFloat = isTenBPM ? 24 : (isFiveBPM ? 18 : 10)

        return VStack(spacing: 3) {
            Text(isFiveBPM ? "\(tickBPM)" : "")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(isTenBPM ? .primary : .secondary)
                .frame(width: 36)

            Rectangle()
                .fill(isTenBPM ? .primary : .secondary)
                .frame(width: isFiveBPM ? 1.5 : 1, height: height)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let startBPM = dragStartBPM ?? bpm
                if dragStartBPM == nil {
                    dragStartBPM = startBPM
                }

                dragTranslation = gesture.translation.width
                dragBPM = calculatedBPM(
                    startBPM: startBPM,
                    translation: gesture.translation.width
                )
            }
            .onEnded { gesture in
                let startBPM = dragStartBPM ?? bpm
                let finalBPM = calculatedBPM(
                    startBPM: startBPM,
                    translation: gesture.translation.width
                )

                onCommit(finalBPM)
                dragStartBPM = nil
                dragBPM = nil
                dragTranslation = 0
            }
    }

    private func calculatedBPM(startBPM: Int, translation: CGFloat) -> Int {
        BPMDialMath.bpm(
            startBPM: startBPM,
            translation: Double(translation),
            pointsPerBPM: Double(pointsPerBPM),
            range: range
        )
    }
}
