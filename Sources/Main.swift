import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        SentinelManager.shared.startup()
        
        // Open the dashboard and trigger a sample popup on first launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            SentinelManager.shared.openDashboard()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in the Menu Bar even if dashboard window is closed!
        return false
    }
}

@main
struct AgentSentinelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
