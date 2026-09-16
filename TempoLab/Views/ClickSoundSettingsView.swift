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
            Form {
                #if os(iOS)
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
                #endif

                Section("音色") {
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

                Section("音程") {
                    FrequencySettingRow(
                        title: "通常クリック",
                        accessibilityLabel: "通常クリックの音程",
                        frequency: viewModel.clickSoundSettings.normalFrequency,
                        range: ClickSoundSettings.normalFrequencyRange,
                        onCommit: viewModel.setNormalFrequency
                    )

                    FrequencySettingRow(
                        title: "アクセントクリック",
                        accessibilityLabel: "アクセントクリックの音程",
                        frequency: viewModel.clickSoundSettings.accentFrequency,
                        range: ClickSoundSettings.accentFrequencyRange,
                        onCommit: viewModel.setAccentFrequency
                    )
                }

                Section("音量") {
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
                            "\(Int((displayedVolume * 100).rounded())) percent"
                        )
                    }
                }

                Section("プレビュー") {
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
}

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
            .accessibilityValue("\(displayedFrequency) Hertz")
        }
    }
}
