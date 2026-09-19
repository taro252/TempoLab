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
            platformContent
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

    @ViewBuilder
    private var platformContent: some View {
        #if os(macOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MacDetectorCard(title: "マイク", systemImage: "mic") {
                    microphoneControls
                }

                MacDetectorCard(title: "Input Level", systemImage: "waveform") {
                    inputLevelContent
                }

                MacDetectorCard(title: "Detected Tempo", systemImage: "metronome") {
                    detectedTempoContent
                }

                if let message = viewModel.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 540, idealWidth: 580, minHeight: 520, idealHeight: 620)
        .background(.background)
        #else
        Form {
            Section("マイク") {
                microphoneControls
            }

            Section("Input Level") {
                inputLevelContent
            }

            Section("Detected Tempo") {
                detectedTempoContent
            }

            if let message = viewModel.message {
                Section {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }
        }
        #endif
    }

    private var microphoneControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                LabeledContent("アクセス", value: viewModel.permissionState.displayName)

                #if os(macOS)
                Button(viewModel.isListening ? "Stop Listening" : "Start Listening") {
                    viewModel.toggleListening()
                }
                .buttonStyle(.borderedProminent)
                #endif
            }

            if isMetronomeRunning {
                Label(
                    "メトロノーム音を検出する可能性があります。ヘッドフォンの使用を推奨します。",
                    systemImage: "headphones"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }

            #if os(iOS)
            Button(viewModel.isListening ? "Stop Listening" : "Start Listening") {
                viewModel.toggleListening()
            }
            .buttonStyle(.borderedProminent)
            #endif
        }
        .accessibilityHint(
            viewModel.isListening
                ? "マイク入力を停止します"
                : "必要に応じてマイクへのアクセスを確認し、入力を開始します"
        )
    }

    private var inputLevelContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: viewModel.normalizedInputLevel)
                .tint(Color("AppAccent"))
                .accessibilityLabel("入力レベル")
                .accessibilityValue(
                    "\(Int((viewModel.normalizedInputLevel * 100).rounded()))パーセント"
                )

            Text("\(viewModel.inputDecibels, format: .number.precision(.fractionLength(1))) dBFS")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var detectedTempoContent: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                Divider()

                Text("Candidates")
                    .font(.subheadline.weight(.semibold))

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

                HStack {
                    Button("Reset Detection") {
                        viewModel.resetDetection()
                    }

                    Spacer()

                    Button("Use This Tempo") {
                        viewModel.useDetectedTempo()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                HStack {
                    Text(viewModel.isListening ? "Listening..." : "Start Listeningで解析を開始します。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Reset Detection") {
                        viewModel.resetDetection()
                    }
                    .disabled(true)
                }
            }
        }
    }

    private var confidencePercent: Double {
        viewModel.detectionResult?.confidence ?? 0
    }
}

#if os(macOS)
private struct MacDetectorCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }
}
#endif

struct TempoDetectorView_Previews: PreviewProvider {
    static var previews: some View {
        TempoDetectorView(isMetronomeRunning: true, onUseTempo: { _ in })
    }
}
