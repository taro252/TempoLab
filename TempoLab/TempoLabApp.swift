//
//  TempoLabApp.swift
//  TempoLab
//
//  Created by 吉田 太郎 on 2026/09/15.
//

import SwiftUI

@main
struct TempoLabApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(CloudNotificationRegistration.self) private var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(CloudNotificationRegistration.self) private var appDelegate
    #endif
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { await CloudPresetSyncService.shared.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await CloudPresetSyncService.shared.refresh() }
                    }
                }
        }
    }
}
