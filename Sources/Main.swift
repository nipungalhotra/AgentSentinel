import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var lockFileDescriptor: Int32 = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = appLaunchDate   // globals are lazy: pin the launch time now
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
        let rawAction = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let action = rawAction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let rawScope = queryItems.first(where: { $0.name == "scope" })?.value?.lowercased() ?? "once"
        let reqId = queryItems.first(where: { $0.name == "id" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch action {
        case "allow":
            let scope = AllowScope.parse(rawScope)
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
                let sanitizedName = name.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
                if !sanitizedName.isEmpty {
                    Task { @MainActor in
                        SoundEngine.shared.popupSoundName = sanitizedName
                        SoundEngine.shared.playPopup()
                    }
                }
            }
        default:
            print("[loggdin] Received unhandled custom URL action: \(action)")
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
            lockFileDescriptor = -1
        }
    }

    private func acquireSingleInstanceLock() -> Bool {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AgentSentinel", isDirectory: true) else {
            print("[loggdin] Warning: Could not locate Application Support directory.")
            return true
        }
        do {
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        } catch {
            print("[loggdin] Warning: Could not create Application Support directory: \(error)")
        }
        let lockPath = appSupport.appendingPathComponent("loggdin.lock").path

        let fd = open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            print("[loggdin] Warning: Could not open lockfile at \(lockPath): errno \(errno)")
            return true
        }

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
        // The real dashboard lives in SentinelManager's own window. A full DashboardView here was a
        // second, hidden copy whose animations kept rendering in the background (high idle CPU),
        // so the Settings scene only forwards to that window if it is ever opened.
        Settings {
            SettingsRedirectView()
        }
    }
}

/// Opens the real dashboard and closes the Settings window that hosted this view.
struct SettingsRedirectView: View {
    var body: some View {
        WindowCloser()
            .frame(width: 1, height: 1)
            .onAppear {
                // SwiftUI may instantiate the Settings scene at launch: just close it then.
                // Later (e.g. Cmd-,) it means the user asked for settings, so show the dashboard.
                if Date().timeIntervalSince(appLaunchDate) > 3 {
                    SentinelManager.shared.openDashboard()
                }
            }
    }
}

/// Process start time, used to tell launch-time scene creation from a user request.
let appLaunchDate = Date()

private struct WindowCloser: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.close() }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
