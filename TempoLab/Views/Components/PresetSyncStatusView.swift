import SwiftUI

struct PresetSyncStatusView: View {
    let status: PresetSyncStatus
    let onSync: () async -> Void
    @State private var isRequestingSync = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    if status.phase == .syncing { ProgressView().controlSize(.small) }
                    Label(title, systemImage: symbol)
                        .font(.callout)
                    Spacer(minLength: 8)
                    Button("今すぐ同期") {
                        isRequestingSync = true
                        Task {
                            await onSync()
                            isRequestingSync = false
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isRequestingSync)
                    .frame(minHeight: 44)
                }
                if let date = status.lastSyncDate {
                    Text(String(localized: "最終同期") + ": " + date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let message = status.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .contain)
        }
        .listRowBackground(Color("AppSurface"))
    }

    private var title: String {
        switch status.phase {
        case .waiting: String(localized: "iCloud同期待ち")
        case .syncing: String(localized: "iCloud同期中")
        case .upToDate: String(localized: "iCloud同期済み")
        case .unavailable: String(localized: "iCloud利用不可")
        case .failed: String(localized: "同期エラー")
        }
    }

    private var symbol: String {
        switch status.phase {
        case .waiting, .syncing: "icloud"
        case .upToDate: "checkmark.icloud"
        case .unavailable: "icloud.slash"
        case .failed: "exclamationmark.icloud"
        }
    }
}
