import SwiftUI

struct MetronomeView: View {
    @StateObject private var viewModel = MetronomeViewModel()
    @State private var bpmAnimationRequest: BPMAnimationRequest?
    @State private var isShowingClickSettings = false
    @State private var isShowingPatternEditor = false
    @State private var isShowingTempoDetector = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color("AppBackgroundHighlight"),
                    Color("AppBackground"),
                    Color("AppBackground")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            GeometryReader { geometry in
                let compact = geometry.size.height < 680
                let contentSpacing: CGFloat = compact ? 4 : 12

                VStack(spacing: contentSpacing) {
                    MetronomeTopBar(
                        onOpenTempoDetector: { isShowingTempoDetector = true },
                        onOpenSettings: { isShowingClickSettings = true }
                    )

                    Spacer(minLength: compact ? 0 : 2)

                    BPMDisplayView(bpm: viewModel.bpm, compact: compact)

                    BPMControlView(
                        bpm: viewModel.bpm,
                        range: MetronomeViewModel.bpmRange,
                        animationRequest: bpmAnimationRequest,
                        compact: compact,
                        onCommit: viewModel.setBPM
                    )
                    .padding(.horizontal, compact ? 0 : 8)

                    bpmAdjustmentButtons(compact: compact)

                    CompactMeterControls(
                        timeSignature: viewModel.selectedTimeSignature,
                        subdivision: viewModel.selectedSubdivision,
                        playbackPositionState: viewModel.playbackPositionState,
                        onSelectTimeSignature: { viewModel.selectedTimeSignature = $0 },
                        onSelectSubdivision: viewModel.setSubdivision,
                        onOpenPattern: { isShowingPatternEditor = true }
                    )

                    Spacer(minLength: compact ? 0 : 4)

                    MetronomeTransportControls(
                        isRunning: viewModel.isRunning,
                        buttonDiameter: compact ? 68 : 88,
                        compact: compact,
                        onTogglePlayback: viewModel.toggleRunning,
                        onTapTempo: registerTap
                    )
                }
                .padding(.horizontal, compact ? 14 : 20)
                .padding(.vertical, compact ? 4 : 12)
                .frame(maxWidth: 640, maxHeight: .infinity)
                .frame(maxWidth: .infinity)
            }
        }
        .tint(Color("AppAccent"))
        .preferredColorScheme(.dark)
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
        .sheet(isPresented: $isShowingClickSettings) {
            ClickSoundSettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingPatternEditor) {
            AccentPatternEditorView(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingTempoDetector) {
            TempoDetectorView(
                isMetronomeRunning: viewModel.isRunning,
                onUseTempo: viewModel.setBPM
            )
        }
    }

    private func bpmAdjustmentButtons(compact: Bool) -> some View {
        HStack(spacing: 8) {
            bpmAdjustmentButton(title: "−5", amount: -5, compact: compact)
            bpmAdjustmentButton(title: "−1", amount: -1, compact: compact)
            bpmAdjustmentButton(title: "+1", amount: 1, compact: compact)
            bpmAdjustmentButton(title: "+5", amount: 5, compact: compact)
        }
    }

    private func bpmAdjustmentButton(
        title: String,
        amount: Int,
        compact: Bool
    ) -> some View {
        Button {
            adjustBPM(by: amount)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: compact ? 38 : 42)
                .background(Color("AppSurface"), in: RoundedRectangle(cornerRadius: 11))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func registerTap() {
        let touchDownTime = ProcessInfo.processInfo.systemUptime
        viewModel.registerTap(at: touchDownTime)
    }
}

struct MetronomeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MetronomeView()
                .previewDisplayName("iPhone Portrait")
                .previewLayout(.fixed(width: 393, height: 852))
            MetronomeView()
                .previewDisplayName("iPad")
                .previewLayout(.fixed(width: 820, height: 1_080))
        }
    }
}
