import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var lockFileDescriptor: Int32 = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce single instance: prevent duplicate processes & menu bar icons
        guard acquireSingleInstanceLock() else {
            print("[loggdin] Another instance is already running. Exiting.")
            NSApp.terminate(nil)
            return
        }

        // Set accessory policy so macOS allows floating overlays from background without dock clutter
        NSApp.setActivationPolicy(.accessory)
        SentinelManager.shared.startup()
        // Dashboard is NOT opened automatically; user can open it from the menu bar if desired.
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in the Menu Bar even if dashboard window is closed!
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if lockFileDescriptor >= 0 {
            close(lockFileDescriptor)
        }
    }

    private func acquireSingleInstanceLock() -> Bool {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AgentSentinel", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let lockPath = appSupport.appendingPathComponent("loggdin.lock").path

        let fd = open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return true }

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }
        lockFileDescriptor = fd
        return true
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
