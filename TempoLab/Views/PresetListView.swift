import SwiftUI

struct PresetListView: View {
    @ObservedObject var viewModel: MetronomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var nameRequest: PresetNameRequest?
    @State private var overwriteTarget: MetronomePreset?
    @State private var deleteTarget: MetronomePreset?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        nameRequest = PresetNameRequest(
                            presetID: nil,
                            name: "\(viewModel.bpm) BPM・\(viewModel.selectedTimeSignature.displayName)",
                            configuration: viewModel.currentConfiguration
                        )
                    } label: {
                        Label("現在の設定を保存", systemImage: "bookmark.badge.plus")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
                .listRowBackground(Color("AppSurface"))

                if viewModel.presets.isEmpty {
                    ContentUnavailableView(
                        "プリセットがありません",
                        systemImage: "bookmark",
                        description: Text("よく使うテンポや音色を保存して、ワンタップで呼び出せます。")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(viewModel.presets) { preset in
                            presetRow(preset)
                        }
                        .onMove { offsets, destination in
                            viewModel.movePresets(from: offsets, to: destination)
                        }
                    }
                    .listRowBackground(Color("AppSurface"))
                }

                if let error = viewModel.presetErrorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .accessibilityLabel(String(localized: "プリセットエラー") + ": " + error)
                    }
                    .listRowBackground(Color("AppSurface"))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color("AppBackground"))
            .navigationTitle("プリセット")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    EditButton().disabled(viewModel.presets.isEmpty)
                }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .tint(Color("AppAccent"))
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 420, idealHeight: 560)
        #endif
        .sheet(item: $nameRequest) { request in
            PresetNameEditor(viewModel: viewModel, request: request)
        }
        .confirmationDialog(
            "プリセットを上書きしますか？",
            isPresented: Binding(
                get: { overwriteTarget != nil },
                set: { if !$0 { overwriteTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: overwriteTarget
        ) { preset in
            Button("上書き保存", role: .destructive) {
                viewModel.overwritePreset(id: preset.id)
            }
            Button("キャンセル", role: .cancel) {}
        } message: { preset in
            Text(String(format: String(localized: "「%@」を現在の設定で上書きします。この操作は取り消せません。"), preset.name))
        }
        .confirmationDialog(
            "プリセットを削除しますか？",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { preset in
            Button("削除", role: .destructive) { viewModel.deletePreset(id: preset.id) }
            Button("キャンセル", role: .cancel) {}
        } message: { preset in
            Text(String(format: String(localized: "「%@」を削除します。この操作は取り消せません。"), preset.name))
        }
    }

    private func presetRow(_ preset: MetronomePreset) -> some View {
        HStack(spacing: 12) {
            Button {
                if viewModel.applyPreset(id: preset.id) { dismiss() }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(preset.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    PresetSummary(configuration: preset.configuration)
                    if preset.id == viewModel.lastAppliedPresetID {
                        Label(
                            viewModel.isAppliedPresetModified
                                ? String(localized: "変更あり") : String(localized: "適用中"),
                            systemImage: viewModel.isAppliedPresetModified ? "pencil.circle" : "checkmark.circle.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color("AppAccent"))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("プリセットを呼び出します")

            Menu {
                Button("名前変更", systemImage: "pencil") {
                    nameRequest = PresetNameRequest(
                        presetID: preset.id, name: preset.name, configuration: preset.configuration
                    )
                }
                Button("現在の設定で上書き", systemImage: "square.and.arrow.down") {
                    overwriteTarget = preset
                }
                Divider()
                Button("上に移動", systemImage: "arrow.up") { move(preset, by: -1) }
                    .disabled(viewModel.presets.first?.id == preset.id)
                Button("下に移動", systemImage: "arrow.down") { move(preset, by: 1) }
                    .disabled(viewModel.presets.last?.id == preset.id)
                Divider()
                Button("削除", systemImage: "trash", role: .destructive) { deleteTarget = preset }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(String(format: String(localized: "%@の操作"), preset.name))
        }
    }

    private func move(_ preset: MetronomePreset, by offset: Int) {
        guard let index = viewModel.presets.firstIndex(where: { $0.id == preset.id }) else { return }
        viewModel.movePresets(from: IndexSet(integer: index), to: offset < 0 ? index - 1 : index + 2)
    }
}

private struct PresetNameRequest: Identifiable {
    let id = UUID()
    let presetID: UUID?
    let name: String
    let configuration: PresetConfiguration
}

private struct PresetNameEditor: View {
    @ObservedObject var viewModel: MetronomeViewModel
    let request: PresetNameRequest
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var isNameFocused: Bool

    init(viewModel: MetronomeViewModel, request: PresetNameRequest) {
        self.viewModel = viewModel
        self.request = request
        _name = State(initialValue: request.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("プリセット名") {
                    TextField("プリセット名", text: $name)
                        .focused($isNameFocused)
                        .onSubmit(save)
                        .submitLabel(.done)
                }
                Section("保存する設定") {
                    PresetSummary(configuration: request.configuration, showsDetails: true)
                }
                if let error = viewModel.presetErrorMessage {
                    Text(error).foregroundStyle(.orange)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color("AppBackground"))
            .navigationTitle(request.presetID == nil ? String(localized: "現在の設定を保存") : String(localized: "名前変更"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .tint(Color("AppAccent"))
        .preferredColorScheme(.dark)
        .onAppear { isNameFocused = true }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 300, idealHeight: 360)
        #endif
    }

    private func save() {
        let succeeded: Bool
        if let id = request.presetID {
            succeeded = viewModel.renamePreset(id: id, name: name)
        } else {
            succeeded = viewModel.createPreset(name: name)
        }
        if succeeded { dismiss() }
    }
}

private struct PresetSummary: View {
    let configuration: PresetConfiguration
    var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(configuration.bpm) BPM・\(configuration.timeSignature.displayName)・\(configuration.subdivision.displayName)")
            Text(configuration.clickSoundSettings.soundType.displayName)
            if showsDetails {
                LabeledContent("通常クリック", value: "\(configuration.clickSoundSettings.normalFrequency) Hz")
                LabeledContent("アクセントクリック", value: "\(configuration.clickSoundSettings.accentFrequency) Hz")
                LabeledContent("クリック音量") {
                    Text(configuration.clickSoundSettings.volume, format: .percent.precision(.fractionLength(0)))
                }
                Text(configuration.accentPattern.steps.map(\.symbol).joined(separator: " "))
                    .accessibilityLabel("アクセントパターン")
                    .accessibilityValue(configuration.accentPattern.steps.map(\.accessibilityLabel).joined(separator: ", "))
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}
