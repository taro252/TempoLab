import SwiftUI

struct MetronomeView: View {
    @StateObject private var viewModel = MetronomeViewModel()
    @State private var bpmAnimationRequest: BPMAnimationRequest?

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Text("TempoLab")
                    .font(.title.bold())

                BPMControlView(
                    bpm: viewModel.bpm,
                    range: MetronomeViewModel.bpmRange,
                    animationRequest: bpmAnimationRequest,
                    onCommit: viewModel.setBPM
                )
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
            adjustBPM(by: amount)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("BPMを\(abs(amount))\(amount < 0 ? "下げる" : "上げる")")
    }

    private func adjustBPM(by amount: Int) {
        let previousBPM = viewModel.bpm
        viewModel.adjustBPM(by: amount)
        let newBPM = viewModel.bpm

        guard previousBPM != newBPM else { return }
        bpmAnimationRequest = BPMAnimationRequest(
            id: (bpmAnimationRequest?.id ?? 0) + 1,
            fromBPM: previousBPM,
            toBPM: newBPM
        )
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
