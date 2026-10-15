import Foundation
#if os(macOS)
import ServiceManagement
#endif

// MARK: - Cross-Platform Startup & Launch-At-Login Manager

@MainActor
public final class StartupManager: @unchecked Sendable {
    public static let shared = StartupManager()

    private init() {}

    /// Check if Launch at Login is enabled
    public var isLaunchAtLoginEnabled: Bool {
        #if os(macOS)
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
        #else
        return checkLinuxOrWindowsAutostart()
        #endif
    }

    /// Toggle Launch at Login state
    @discardableResult
    public func toggleLaunchAtLogin() -> Bool {
        #if os(macOS)
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    return false
                } else {
                    try SMAppService.mainApp.register()
                    return true
                }
            } catch {
                print("[StartupManager] Error toggling login item: \(error)")
                return isLaunchAtLoginEnabled
            }
        }
        return false
        #else
        return toggleLinuxOrWindowsAutostart()
        #endif
    }

    // MARK: - Linux & Windows Autostart Hooks

    private func checkLinuxOrWindowsAutostart() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let autostartDesktop = home.appendingPathComponent(".config/autostart/agent-sentinel.desktop")
        return FileManager.default.fileExists(atPath: autostartDesktop.path)
    }

    private func toggleLinuxOrWindowsAutostart() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let autostartDir = home.appendingPathComponent(".config/autostart", isDirectory: true)
        let autostartDesktop = autostartDir.appendingPathComponent("agent-sentinel.desktop")

        if FileManager.default.fileExists(atPath: autostartDesktop.path) {
            try? FileManager.default.removeItem(at: autostartDesktop)
            return false
        } else {
            try? FileManager.default.createDirectory(at: autostartDir, withIntermediateDirectories: true)
            let entry = """
            [Desktop Entry]
            Type=Application
            Name=Agent Sentinel
            Comment=Universal Permission Gate for AI Coding Agents
            Exec=sentinel daemon
            Terminal=false
            Categories=Development;Security;
            """
            try? entry.write(to: autostartDesktop, atomically: true, encoding: .utf8)
            return true
        }
    }
}
