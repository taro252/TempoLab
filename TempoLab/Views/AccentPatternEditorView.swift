import SwiftUI

struct AccentPatternEditorView: View {
    @ObservedObject var viewModel: MetronomeViewModel
    @Environment(\.dismiss) private var dismiss

    private var pattern: AccentPattern { viewModel.currentAccentPattern }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("\(viewModel.selectedTimeSignature.displayName)・\(viewModel.selectedSubdivision.displayName)")
                    .font(.headline)

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(0..<viewModel.selectedTimeSignature.numerator, id: \.self) { beat in
                            beatGroup(beat: beat)
                        }
                    }
                    .padding(.vertical, 4)
                }

                HStack(spacing: 18) {
                    legend(.accent)
                    legend(.normal)
                    legend(.mute)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Text("各ステップをタップすると、アクセント → 通常 → ミュートの順に切り替わります。再生中の変更は次の拍から反映されます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("アクセントパターン")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }

    private func beatGroup(beat: Int) -> some View {
        VStack(spacing: 8) {
            Text("Beat \(beat + 1)")
                .font(.caption.bold())

            HStack(spacing: 6) {
                ForEach(0..<viewModel.selectedSubdivision.divisionsPerBeat, id: \.self) { part in
                    let index = beat * viewModel.selectedSubdivision.divisionsPerBeat + part
                    stepButton(index: index, beat: beat, part: part)
                }
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func stepButton(index: Int, beat: Int, part: Int) -> some View {
        let emphasis = pattern.emphasis(at: index)
        let subdivisionLabel = viewModel.selectedSubdivision.stepLabel(at: part)

        return Button {
            viewModel.cyclePatternStep(at: index)
        } label: {
            VStack(spacing: 4) {
                Text(subdivisionLabel.isEmpty ? "\(beat + 1)" : subdivisionLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(emphasis.symbol)
                    .font(.title2.bold())
                    .foregroundStyle(color(for: emphasis))
                    .frame(width: 34, height: 34)
                    .overlay {
                        CurrentPatternStepRing(
                            state: viewModel.playbackPositionState,
                            timeSignature: viewModel.selectedTimeSignature,
                            subdivision: viewModel.selectedSubdivision,
                            stepIndex: index
                        )
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Beat \(beat + 1)、\(viewModel.selectedSubdivision.accessibilityLabel)、ステップ \(part + 1)"
        )
        .accessibilityValue(emphasis.accessibilityLabel)
        .accessibilityHint("タップして次の状態へ変更")
    }

    private func legend(_ emphasis: StepEmphasis) -> some View {
        Label {
            Text(emphasis.accessibilityLabel)
        } icon: {
            Text(emphasis.symbol)
                .foregroundStyle(color(for: emphasis))
        }
    }

    private func color(for emphasis: StepEmphasis) -> Color {
        switch emphasis {
        case .accent: .orange
        case .normal: .primary
        case .mute: .secondary
        }
    }
}

private struct CurrentPatternStepRing: View {
    @ObservedObject var state: PlaybackPositionState
    let timeSignature: TimeSignature
    let subdivision: Subdivision
    let stepIndex: Int

    private var isCurrent: Bool {
        guard let position = state.current else { return false }
        return position.timeSignature == timeSignature
            && position.subdivision == subdivision
            && position.stepIndex == stepIndex
    }

    var body: some View {
        Circle()
            .stroke(
                isCurrent ? Color.accentColor : Color.clear,
                lineWidth: 2
            )
            .frame(width: 38, height: 38)
            .shadow(
                color: isCurrent ? Color.accentColor.opacity(0.55) : .clear,
                radius: 3
            )
            .accessibilityHidden(true)
    }
}
