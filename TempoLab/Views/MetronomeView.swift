import SwiftUI

struct MetronomeView: View {
    @StateObject private var viewModel = MetronomeViewModel()
    @State private var dragBPM: Int?

    private var displayedBPM: Int {
        dragBPM ?? viewModel.bpm
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Text("TempoLab")
                    .font(.title.bold())

                bpmDisplay
                bpmSlider
                bpmAdjustmentButtons
                timeSignaturePicker
                playbackButton
                tapTempoButton
            }
            .padding()
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .alert(
            "オーディオエラー",
            isPresented: Binding(
                get: { viewModel.audioErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissAudioError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.dismissAudioError()
            }
        } message: {
            Text(viewModel.audioErrorMessage ?? "不明なエラーが発生しました。")
        }
    }

    private var bpmDisplay: some View {
        VStack(spacing: 0) {
            Text(displayedBPM, format: .number)
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("BPM")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var bpmSlider: some View {
        VStack(spacing: 4) {
            BPMDragSlider(
                value: displayedBPM,
                range: MetronomeViewModel.bpmRange,
                onChanged: { value in
                    dragBPM = value
                },
                onEnded: { finalValue in
                    viewModel.setBPM(finalValue)
                    dragBPM = nil
                }
            )

            HStack {
                Text("30")
                Spacer()
                Text("300")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var bpmAdjustmentButtons: some View {
        HStack(spacing: 12) {
            bpmAdjustmentButton(title: "−5", amount: -5)
            bpmAdjustmentButton(title: "−1", amount: -1)
            bpmAdjustmentButton(title: "+1", amount: 1)
            bpmAdjustmentButton(title: "+5", amount: 5)
        }
    }

    private func bpmAdjustmentButton(title: String, amount: Int) -> some View {
        Button(title) {
            viewModel.adjustBPM(by: amount)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("BPMを\(abs(amount))\(amount < 0 ? "下げる" : "上げる")")
    }

    private var timeSignaturePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("拍子")
                .font(.headline)

            Picker("拍子", selection: $viewModel.selectedTimeSignature) {
                ForEach(TimeSignature.supported) { timeSignature in
                    Text(timeSignature.displayName).tag(timeSignature)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var playbackButton: some View {
        Button(viewModel.isRunning ? "Stop" : "Start") {
            viewModel.toggleRunning()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(viewModel.isRunning ? .red : .accentColor)
        .frame(maxWidth: .infinity)
    }

    private var tapTempoButton: some View {
        Button("Tap Tempo") {
            viewModel.registerTap()
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .keyboardShortcut(.space, modifiers: [])
    }
}

struct MetronomeView_Previews: PreviewProvider {
    static var previews: some View {
        MetronomeView()
    }
}
