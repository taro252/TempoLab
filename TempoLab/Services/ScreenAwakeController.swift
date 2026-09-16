import Foundation

#if os(iOS)
import UIKit
#endif

nonisolated enum ScreenAwakePolicy {
    static func shouldPreventSleep(
        keepScreenAwake: Bool,
        isRunning: Bool
    ) -> Bool {
        keepScreenAwake && isRunning
    }
}

@MainActor
protocol ScreenAwakeControlling: AnyObject {
    func setPreventSleep(_ shouldPreventSleep: Bool)
}

@MainActor
final class ScreenAwakeController: ScreenAwakeControlling {
    private var isPreventingSleep = false

    func setPreventSleep(_ shouldPreventSleep: Bool) {
        guard isPreventingSleep != shouldPreventSleep else { return }
        isPreventingSleep = shouldPreventSleep

        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = shouldPreventSleep
        #endif
    }

    deinit {
        #if os(iOS)
        if isPreventingSleep {
            MainActor.assumeIsolated {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
        #endif
    }
}
