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
        
        // Register URL scheme handler for Apple Shortcuts and external triggers (loggdin://allow, etc.)
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        SentinelManager.shared.startup()
        // Dashboard is NOT opened automatically; user can open it from the menu bar if desired.

        // Automatically suppress and close any default SwiftUI window created on startup
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows {
                if !(window is FloatingPanel) && window !== SentinelManager.shared.dashboardWindow {
                    window.orderOut(nil)
                    window.close()
                }
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleCustomURL(url)
        }
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }
        handleCustomURL(url)
    }

    private func handleCustomURL(_ url: URL) {
        guard url.scheme?.lowercased() == "loggdin" else { return }
        let action = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let scopeParam = queryItems.first(where: { $0.name == "scope" })?.value?.lowercased() ?? "once"
        let reqId = queryItems.first(where: { $0.name == "id" })?.value

        switch action.lowercased() {
        case "allow":
            let scope: AllowScope
            switch scopeParam {
            case "10m", "tenminutes", "10_minutes":
                scope = .tenMinutes
            case "always":
                scope = .always
            default:
                scope = .once
            }
            Task { @MainActor in
                PermissionPopupController.shared.submitExternalDecision(.allow(scope), forRequestId: reqId)
            }
        case "deny":
            Task { @MainActor in
                PermissionPopupController.shared.submitExternalDecision(.deny, forRequestId: reqId)
            }
        case "dashboard":
            Task { @MainActor in
                SentinelManager.shared.openDashboard()
            }
        case "sound":
            if let name = queryItems.first(where: { $0.name == "name" })?.value {
                Task { @MainActor in
                    SoundEngine.shared.popupSoundName = name
                    SoundEngine.shared.playPopup()
                }
            }
        default:
            break
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in the Menu Bar even if dashboard window is closed!
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Prevent opening the default Settings window on dock click or external open event
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
            DashboardView()
                .frame(minWidth: 920, minHeight: 620)
        }
    }
}
