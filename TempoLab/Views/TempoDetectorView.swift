import SwiftUI

struct TempoDetectorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = TempoDetectorViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("マイク") {
                    LabeledContent("アクセス", value: viewModel.permissionState.displayName)

                    Button(viewModel.isListening ? "Stop Listening" : "Start Listening") {
                        viewModel.toggleListening()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint(
                        viewModel.isListening
                            ? "マイク入力を停止します"
                            : "必要に応じてマイクへのアクセスを確認し、入力を開始します"
                    )
                }

                Section("Input Level") {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: viewModel.normalizedInputLevel)
                            .tint(Color("AppAccent"))
                            .accessibilityLabel("入力レベル")
                            .accessibilityValue("\(Int((viewModel.normalizedInputLevel * 100).rounded()))パーセント")

                        Text("\(viewModel.inputDecibels, format: .number.precision(.fractionLength(1))) dBFS")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Detected Tempo") {
                    HStack {
                        Text("BPM")
                        Spacer()
                        Text(viewModel.detectedBPM.map(String.init) ?? "—")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    Text("テンポ解析はPhase 8で追加します。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let message = viewModel.message {
                    Section {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Tempo Detector")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        viewModel.stopListening()
                        dismiss()
                    }
                }
            }
        }
        .onDisappear {
            viewModel.stopListening()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                viewModel.applicationBecameInactive()
            }
        }
    }
}

struct TempoDetectorView_Previews: PreviewProvider {
    static var previews: some View {
        TempoDetectorView()
    }
}
