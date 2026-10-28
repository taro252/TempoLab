import SwiftUI
#if os(iOS)
import UIKit

final class CloudNotificationRegistration: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            application.registerForRemoteNotifications()
        }
        return true
    }
}
#elseif os(macOS)
import AppKit

final class CloudNotificationRegistration: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            NSApplication.shared.registerForRemoteNotifications()
        }
    }
}
#endif
