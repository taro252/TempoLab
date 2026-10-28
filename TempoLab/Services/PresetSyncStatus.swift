import Combine
import Foundation

nonisolated struct PresetSyncStatus: Equatable, Sendable {
    enum Phase: Sendable { case waiting, syncing, upToDate, unavailable, failed }
    var phase: Phase = .waiting
    var lastSyncDate: Date?
    var message: String?
}

@MainActor
final class PresetSyncMonitor: ObservableObject {
    static let shared = PresetSyncMonitor()
    @Published private(set) var status = PresetSyncStatus()

    func update(_ status: PresetSyncStatus) {
        self.status = status
    }
}

nonisolated protocol PresetSyncing: Sendable {
    func refresh() async
}
