import SwiftUI

struct ClickSoundSettingsView: View {
    @ObservedObject var viewModel: MetronomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draftVolume: Double?

    private var displayedVolume: Double {
        draftVolume ?? viewModel.clickSoundSettings.volume
    }

    var body: some View {
        NavigationStack {
            platformContent
                .navigationTitle("設定")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完了") {
                            dismiss()
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var platformContent: some View {
        #if os(macOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MacSettingsCard(title: String(localized: "音色"), systemImage: "waveform") {
                    soundTypePicker
                }

                MacSettingsCard(title: String(localized: "音程"), systemImage: "tuningfork") {
                    frequencyControls
                }

                MacSettingsCard(title: String(localized: "音量"), systemImage: "speaker.wave.2") {
                    volumeControl
                }

                MacSettingsCard(title: String(localized: "プレビュー"), systemImage: "play.circle") {
                    previewControls
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 540, idealWidth: 580, minHeight: 500, idealHeight: 560)
        .background(.background)
        #else
        Form {
            Section("一般") {
                Toggle(
                    "再生中は画面をスリープしない",
                    isOn: Binding(
                        get: { viewModel.keepScreenAwake },
                        set: viewModel.setKeepScreenAwake
                    )
                )
                .accessibilityHint("メトロノームの再生中だけ自動ロックを無効にします")
            }

            Section("音色") {
                soundTypePicker
            }

            Section("音程") {
                frequencyControls
            }

            Section("音量") {
                volumeControl
            }

            Section("プレビュー") {
                previewControls
            }
        }
        #endif
    }

    private var soundTypePicker: some View {
        Picker(
            "クリック音色",
            selection: Binding(
                get: { viewModel.clickSoundSettings.soundType },
                set: viewModel.setClickSoundType
            )
        ) {
            ForEach(ClickSoundType.allCases) { soundType in
                Text(soundType.displayName).tag(soundType)
            }
        }
        .accessibilityLabel("クリック音色")
    }

    private var frequencyControls: some View {
        VStack(spacing: 12) {
            FrequencySettingRow(
                title: String(localized: "通常クリック"),
                accessibilityLabel: String(localized: "通常クリックの音程"),
                frequency: viewModel.clickSoundSettings.normalFrequency,
                range: ClickSoundSettings.normalFrequencyRange,
                onCommit: viewModel.setNormalFrequency
            )

            Divider()

            FrequencySettingRow(
                title: String(localized: "アクセントクリック"),
                accessibilityLabel: String(localized: "アクセントクリックの音程"),
                frequency: viewModel.clickSoundSettings.accentFrequency,
                range: ClickSoundSettings.accentFrequencyRange,
                onCommit: viewModel.setAccentFrequency
            )
        }
    }

    private var volumeControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("クリック音量")
                Spacer()
                Text(displayedVolume, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { displayedVolume },
                    set: { draftVolume = $0 }
                ),
                in: ClickSoundSettings.volumeRange,
                step: 0.01
            ) { isEditing in
                if isEditing {
                    draftVolume = viewModel.clickSoundSettings.volume
                } else {
                    let finalVolume = displayedVolume
                    viewModel.setClickVolume(finalVolume)
                    draftVolume = nil
                }
            }
            .accessibilityLabel("クリック音量")
            .accessibilityValue(
                String(format: String(localized: "%d percent"), Int((displayedVolume * 100).rounded()))
            )
        }
    }

    private var previewControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button("通常音を確認") {
                    viewModel.previewNormalClick()
                }
                .frame(maxWidth: .infinity)

                Button("アクセントを確認") {
                    viewModel.previewAccentClick()
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isRunning)

            if viewModel.isRunning {
                Text("メトロノーム再生中はプレビューを利用できません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if os(macOS)
private struct MacSettingsCard<Content: View>: View {
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
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }
}
#endif

private struct FrequencySettingRow: View {
    let title: String
    let accessibilityLabel: String
    let frequency: Int
    let range: ClosedRange<Int>
    let onCommit: (Int) -> Void

    @State private var draftFrequency: Int?

    private var displayedFrequency: Int {
        draftFrequency ?? frequency
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(displayedFrequency) Hz")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(displayedFrequency) },
                    set: { draftFrequency = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 5
            ) { isEditing in
                if isEditing {
                    draftFrequency = frequency
                } else {
                    let finalFrequency = displayedFrequency
                    onCommit(finalFrequency)
                    draftFrequency = nil
                }
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(String(format: String(localized: "%d Hertz"), displayedFrequency))
        }
    }
}
