import SwiftUI

@MainActor
struct TempoDetectorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: TempoDetectorViewModel
    let isMetronomeRunning: Bool

    init(
        isMetronomeRunning: Bool,
        onUseTempo: @escaping @MainActor (Int) -> Void
    ) {
        self.isMetronomeRunning = isMetronomeRunning
        _viewModel = StateObject(
            wrappedValue: TempoDetectorViewModel(tempoCommitHandler: onUseTempo)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("マイク") {
                    LabeledContent("アクセス", value: viewModel.permissionState.displayName)

                    if isMetronomeRunning {
                        Label(
                            "メトロノーム音を検出する可能性があります。ヘッドフォンの使用を推奨します。",
                            systemImage: "headphones"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }

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
                    VStack(spacing: 4) {
                        Text(viewModel.detectedBPM.map(String.init) ?? "—")
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("BPM")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("検出テンポ")
                    .accessibilityValue(viewModel.detectedBPM.map { "\($0) BPM" } ?? "未検出")

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Confidence")
                            Spacer()
                            Text(confidencePercent, format: .percent)
                                .monospacedDigit()
                        }
                        ProgressView(value: viewModel.detectionResult?.confidence ?? 0)
                            .tint(Color("AppAccent"))
                    }

                    if let result = viewModel.detectionResult {
                        ForEach(result.candidates) { candidate in
                            HStack {
                                Text("\(candidate.bpm, format: .number.precision(.fractionLength(1))) BPM")
                                    .monospacedDigit()
                                Spacer()
                                Text(candidate.score, format: .percent.precision(.fractionLength(0)))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }

                        Button("Use This Tempo") {
                            viewModel.useDetectedTempo()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text(viewModel.isListening ? "Listening..." : "Start Listeningで解析を開始します。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button("Reset Detection") {
                        viewModel.resetDetection()
                    }
                    .disabled(viewModel.detectionResult == nil)
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

    private var confidencePercent: Double {
        viewModel.detectionResult?.confidence ?? 0
    }
}

struct TempoDetectorView_Previews: PreviewProvider {
    static var previews: some View {
        TempoDetectorView(isMetronomeRunning: true, onUseTempo: { _ in })
    }
}
