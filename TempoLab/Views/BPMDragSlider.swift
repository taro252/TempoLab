import SwiftUI

nonisolated enum BPMSliderMapping {
    static func bpm(
        at location: Double,
        trackWidth: Double,
        range: ClosedRange<Int>
    ) -> Int {
        guard trackWidth > 0 else { return range.lowerBound }

        let clampedLocation = min(max(location, 0), trackWidth)
        let ratio = clampedLocation / trackWidth
        let value = Double(range.lowerBound) + ratio * Double(range.upperBound - range.lowerBound)
        return min(max(Int(value.rounded()), range.lowerBound), range.upperBound)
    }
}

struct BPMDragSlider: View {
    let value: Int
    let range: ClosedRange<Int>
    let onChanged: (Int) -> Void
    let onEnded: (Int) -> Void

    private let thumbDiameter = 28.0

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = max(geometry.size.width - thumbDiameter, 1)
            let ratio = CGFloat(value - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.25))
                    .frame(width: trackWidth, height: 4)
                    .offset(x: thumbDiameter / 2)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: trackWidth * ratio, height: 4)
                    .offset(x: thumbDiameter / 2)

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .offset(x: trackWidth * ratio)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        onChanged(bpm(at: gesture.location.x, trackWidth: trackWidth))
                    }
                    .onEnded { gesture in
                        onEnded(bpm(at: gesture.location.x, trackWidth: trackWidth))
                    }
            )
        }
        .frame(height: 44)
        .transaction { transaction in
            transaction.animation = nil
        }
        .accessibilityElement()
        .accessibilityLabel("BPM")
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                onEnded(min(value + 1, range.upperBound))
            case .decrement:
                onEnded(max(value - 1, range.lowerBound))
            @unknown default:
                break
            }
        }
    }

    private func bpm(at x: CGFloat, trackWidth: CGFloat) -> Int {
        BPMSliderMapping.bpm(
            at: Double(x - thumbDiameter / 2),
            trackWidth: Double(trackWidth),
            range: range
        )
    }
}
