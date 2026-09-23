import SwiftUI

struct MetronomeTopBar: View {
    let onOpenTempoDetector: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack {
            Text("TempoLab")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            HStack(spacing: 8) {
                Button(action: onOpenTempoDetector) {
                    Image(systemName: "waveform.badge.mic")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color("AppSurface"), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("テンポ検出")

                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color("AppSurface"), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("設定")
            }
        }
        .frame(height: 44)
    }
}

struct BPMDisplayView: View {
    let bpm: Int
    let compact: Bool
    let onCommit: (Int) -> Void

    @State private var draftBPM = ""
#if os(iOS)
    @State private var isShowingInputDialog = false
#elseif os(macOS)
    @State private var isEditing = false
    @FocusState private var isInputFocused: Bool
#endif

    private var bpmFont: Font {
        .system(size: compact ? 58 : 82, weight: .bold, design: .rounded)
    }

    var body: some View {
        VStack(spacing: compact ? -3 : 0) {
            Group {
#if os(macOS)
                if isEditing {
                    bpmInput
                } else {
                    bpmButton
                }
#else
                bpmButton
#endif
            }
            .font(bpmFont)
            .monospacedDigit()
            .foregroundStyle(.white)

            Text("BPM")
                .font(.caption.weight(.semibold))
                .tracking(2.5)
                .foregroundStyle(Color("AppSecondaryText"))
        }
#if os(iOS)
        .alert("BPMを入力", isPresented: $isShowingInputDialog) {
            TextField("BPM", text: $draftBPM)
                .keyboardType(.numberPad)
            Button("キャンセル", role: .cancel) {}
            Button("OK", action: commitDraftBPM)
        } message: {
            Text("30〜300 BPM")
        }
#endif
    }

    private var bpmButton: some View {
        Button(action: beginEditing) {
            Text(bpm, format: .number)
                .contentTransition(.numericText(value: Double(bpm)))
                .frame(width: compact ? 200 : 280)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tempo")
        .accessibilityValue("\(bpm) BPM")
        .accessibilityHint("ダブルタップしてBPMを入力")
    }

#if os(macOS)
    private var bpmInput: some View {
        TextField("BPM", text: $draftBPM)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .frame(width: compact ? 200 : 280)
            .focused($isInputFocused)
            .onSubmit(commitBPM)
            .onChange(of: isInputFocused) { _, focused in
                if !focused && isEditing {
                    commitBPM()
                }
            }
            .onAppear { isInputFocused = true }
            .accessibilityLabel("Tempo")
            .onExitCommand(perform: cancelEditing)
    }
#endif

    private func beginEditing() {
        draftBPM = String(bpm)
#if os(iOS)
        isShowingInputDialog = true
#elseif os(macOS)
        isEditing = true
#endif
    }

#if os(macOS)
    private func commitBPM() {
        guard isEditing else { return }
        isEditing = false
        isInputFocused = false
        commitDraftBPM()
    }

    private func cancelEditing() {
        isEditing = false
        isInputFocused = false
    }
#endif

    private func commitDraftBPM() {
        if let newBPM = BPMInputParser.parse(draftBPM) {
            onCommit(newBPM)
        }
    }
}

struct CompactMeterControls: View {
    let timeSignature: TimeSignature
    let subdivision: Subdivision
    let playbackPositionState: PlaybackPositionState
    let onSelectTimeSignature: (TimeSignature) -> Void
    let onSelectSubdivision: (Subdivision) -> Void
    let onOpenPattern: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(TimeSignature.supported) { signature in
                    Button(signature.displayName) {
                        onSelectTimeSignature(signature)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(timeSignature.displayName)
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 58, minHeight: 42)
                .padding(.horizontal, 4)
                .background(Color("AppSurface"), in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("拍子")
            .accessibilityValue(timeSignature.displayName)

            VStack(spacing: 1) {
                HStack(spacing: 2) {
                    ForEach(Subdivision.allCases) { option in
                        Button {
                            onSelectSubdivision(option)
                        } label: {
                            Text(option.symbol)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(option == subdivision ? Color("AppBackground") : .white)
                                .frame(maxWidth: .infinity, minHeight: 29)
                                .background {
                                    if option == subdivision {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color("AppAccent"))
                                    }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.accessibilityLabel)
                        .accessibilityAddTraits(option == subdivision ? .isSelected : [])
                    }
                }

                PlaybackStepIndicator(
                    state: playbackPositionState,
                    timeSignature: timeSignature,
                    subdivision: subdivision
                )
            }
            .padding(3)
            .frame(maxWidth: .infinity)
            .background(Color("AppSurface"), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("音符単位")

            Button(action: onOpenPattern) {
                Image(systemName: "circle.grid.3x3.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color("AppSurface"), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("アクセントパターン")
        }
    }
}

private struct PlaybackStepIndicator: View {
    @ObservedObject var state: PlaybackPositionState
    let timeSignature: TimeSignature
    let subdivision: Subdivision

    private var currentStepIndex: Int? {
        guard let position = state.current,
              position.timeSignature == timeSignature,
              position.subdivision == subdivision else { return nil }
        return position.stepIndex
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<stepCount, id: \.self) { index in
                let isCurrent = index == currentStepIndex
                Circle()
                    .fill(isCurrent ? Color("AppAccent") : Color.white.opacity(0.2))
                    .frame(width: isCurrent ? 5 : 3, height: isCurrent ? 5 : 3)
                    .shadow(
                        color: isCurrent ? Color("AppAccent").opacity(0.8) : .clear,
                        radius: 3
                    )
                    .frame(width: 4, height: 7)
                    .padding(
                        .trailing,
                        isBeatBoundary(after: index) ? 3 : 0
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var stepCount: Int {
        AccentPattern.stepCount(
            timeSignature: timeSignature,
            subdivision: subdivision
        )
    }

    private func isBeatBoundary(after index: Int) -> Bool {
        let isLastStep = index == stepCount - 1
        return !isLastStep
            && (index + 1).isMultiple(of: subdivision.divisionsPerBeat)
    }
}

struct MetronomeTransportControls: View {
    let isRunning: Bool
    let buttonDiameter: CGFloat
    let compact: Bool
    let onTogglePlayback: () -> Void
    let onTapTempo: () -> Void

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 16) {
                    playbackButton
                    tapTempoButton
                        .frame(maxWidth: 210)
                }
                .frame(maxWidth: 320)
            } else {
                VStack(spacing: 10) {
                    playbackButton
                    tapTempoButton
                        .frame(maxWidth: 240)
                }
            }
        }
    }

    private var playbackButton: some View {
        ImmediateButton(
            tint: isRunning ? Color("AppRunning") : Color("AppAccent"),
            isProminent: true,
            circularDiameter: buttonDiameter,
            action: onTogglePlayback
        ) {
            VStack(spacing: 5) {
                Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: buttonDiameter * 0.27, weight: .bold))
                Text(isRunning ? String(localized: "STOP") : String(localized: "START"))
                    .font(.caption2.weight(.bold))
                    .tracking(1)
            }
        }
        .shadow(
            color: (isRunning ? Color("AppRunning") : Color("AppAccent")).opacity(0.34),
            radius: isRunning ? 15 : 10
        )
        .accessibilityLabel(isRunning ? String(localized: "Stop") : String(localized: "Start"))
        .accessibilityValue(isRunning ? String(localized: "再生中") : String(localized: "停止中"))
    }

    private var tapTempoButton: some View {
        ImmediateButton(
            tint: Color("AppAccent"),
            keyboardShortcut: KeyboardShortcut(.space, modifiers: []),
            action: onTapTempo
        ) {
            Text("TAP TEMPO")
                .font(.subheadline.weight(.semibold))
                .tracking(1.2)
        }
        .accessibilityLabel("Tap Tempo")
    }
}
