import Foundation

nonisolated final class PlaybackPositionReporter: @unchecked Sendable {
    typealias Handler = @MainActor @Sendable (PlaybackPosition?) -> Void

    private enum PendingUpdate {
        case position(PlaybackPosition?)
    }

    private let lock = NSLock()
    private var handler: Handler?
    private var pendingUpdate: PendingUpdate?
    private var isDeliveryScheduled = false

    func begin(handler: @escaping Handler) {
        lock.withLock {
            self.handler = handler
            pendingUpdate = nil
        }
    }

    func report(_ position: PlaybackPosition) {
        enqueue(.position(position))
    }

    func end() {
        enqueue(.position(nil))
    }

    private func enqueue(_ update: PendingUpdate) {
        let shouldScheduleDelivery = lock.withLock {
            pendingUpdate = update
            guard !isDeliveryScheduled else { return false }
            isDeliveryScheduled = true
            return true
        }

        guard shouldScheduleDelivery else { return }
        DispatchQueue.main.async { [weak self] in
            self?.deliverLatestUpdate()
        }
    }

    @MainActor
    private func deliverLatestUpdate() {
        let delivery: (Handler, PlaybackPosition?)? = lock.withLock {
            defer {
                pendingUpdate = nil
                isDeliveryScheduled = false
            }

            guard let handler,
                  case let .position(position)? = pendingUpdate else {
                return nil
            }
            return (handler, position)
        }

        guard let delivery else { return }
        delivery.0(delivery.1)
    }
}
