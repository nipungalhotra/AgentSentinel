import Foundation
import SwiftUI
import AppKit

@MainActor @Observable
final class SentinelManager: NSObject {
    static let shared = SentinelManager()

    var isProtectionEnabled: Bool = true
    var lastDecisionSummary: String = "Sentinel online. Monitoring active."
    var pendingCount: Int = 0
    var dashboardWindow: NSWindow?

    private var statusItem: NSStatusItem?
    private var rulesEngine = RulesEngine.shared
    private var ipcServer = LocalIPCServer.shared

    override private init() {
        super.init()
    }

    func startup() {
        // Deploy universal hook script
        HookInstaller.shared.deployHookScript()

        // Setup IPC Server (HTTP + Unix Socket)
        ipcServer.onRequestReceived = { [weak self] req in
            guard let self else { return .deny }
            return await self.evaluateOrAsk(req)
        }
        ipcServer.start(port: 9191)

        // Setup Menu Bar
        setupMenuBar()
    }

    func evaluateOrAsk(_ request: PermissionRequest, forcePrompt: Bool = false) async -> Decision {
        guard isProtectionEnabled else {
            rulesEngine.recordDecision(request: request, decision: .allow(.once), autoAllowed: true)
            return .allow(.once)
        }

        // 1. Check rules and active grants (bypassed if forcePrompt is true)
        if !forcePrompt, let autoDecision = rulesEngine.evaluate(request: request) {
            lastDecisionSummary = "Auto-\(autoDecision.summary): \(request.plainCommand)"
            return autoDecision
        }

        // 2. Deliver System Notification & Trigger Notch Popup
        pendingCount += 1
        updateMenuBar()

        deliverSystemNotification(for: request)

        let decision = await PermissionPopupController.shared.ask(request)
        rulesEngine.recordDecision(request: request, decision: decision, autoAllowed: false)

        pendingCount = max(0, pendingCount - 1)
        lastDecisionSummary = "\(decision.summary): \(request.plainCommand)"
        updateMenuBar()

        return decision
    }

    private func deliverSystemNotification(for request: PermissionRequest) {
        let notif = NSUserNotification()
        notif.title = request.title
        notif.subtitle = "\(request.requestedBy) • \(request.risk.label) Risk"
        notif.informativeText = request.plainCommand
        notif.soundName = nil // Silent notification banner; SoundEngine handles the elegant notch chime
        NSUserNotificationCenter.default.deliver(notif)
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        updateMenuBar()
    }

    private func updateMenuBar() {
        updateMenuBarIcon()
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        let headerItem = NSMenuItem(title: "loggdin • Agent Sentinel", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        if pendingCount > 0 {
            let needsYouItem = NSMenuItem(title: "⚠️ Needs you (\(pendingCount) pending)", action: #selector(openDashboardAction), keyEquivalent: "")
            needsYouItem.target = self
            menu.addItem(needsYouItem)
        }

        menu.addItem(NSMenuItem.separator())

        let agentsHeader = NSMenuItem(title: "CONNECTED AGENTS", action: nil, keyEquivalent: "")
        agentsHeader.isEnabled = false
        menu.addItem(agentsHeader)

        let claudeItem = NSMenuItem(title: "● Claude Code (Active)", action: nil, keyEquivalent: "")
        claudeItem.isEnabled = false
        menu.addItem(claudeItem)

        let antigravityItem = NSMenuItem(title: "● Antigravity (Gated)", action: nil, keyEquivalent: "")
        antigravityItem.isEnabled = false
        menu.addItem(antigravityItem)

        let cursorItem = NSMenuItem(title: "● Cursor (Idle)", action: nil, keyEquivalent: "")
        cursorItem.isEnabled = false
        menu.addItem(cursorItem)

        menu.addItem(NSMenuItem.separator())

        let prefsHeader = NSMenuItem(title: "PREFERENCES", action: nil, keyEquivalent: "")
        prefsHeader.isEnabled = false
        menu.addItem(prefsHeader)

        let newFaceItem = NSMenuItem(title: "✓ New face every time", action: nil, keyEquivalent: "")
        newFaceItem.isEnabled = false
        menu.addItem(newFaceItem)

        let floatingDockItem = NSMenuItem(title: "  Floating dock (off)", action: nil, keyEquivalent: "")
        floatingDockItem.isEnabled = false
        menu.addItem(floatingDockItem)

        menu.addItem(NSMenuItem.separator())

        let dashboardItem = NSMenuItem(title: "Open Sessions Hub & Rules...", action: #selector(openDashboardAction), keyEquivalent: "d")
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        // Submenu: Simulate Requests by Category (Faces by Need)
        let simMenu = NSMenu()
        for (i, sample) in PermissionRequest.samples.enumerated() {
            let item = NSMenuItem(title: "\(sample.category.label): \(sample.title)", action: #selector(simulateAction(_:)), keyEquivalent: "")
            item.tag = i
            item.target = self
            simMenu.addItem(item)
        }
        let simParent = NSMenuItem(title: "Test Faces by Need Simulator", action: nil, keyEquivalent: "")
        simParent.submenu = simMenu
        menu.addItem(simParent)

        menu.addItem(NSMenuItem.separator())

        let toggleProtection = NSMenuItem(title: isProtectionEnabled ? "Pause Protection" : "Resume Protection",
                                          action: #selector(toggleProtectionAction), keyEquivalent: "p")
        toggleProtection.target = self
        menu.addItem(toggleProtection)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit loggdin", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        if pendingCount > 0 {
            button.image = NSImage(systemSymbolName: "face.smiling.fill", accessibilityDescription: "loggdin - Needs you")
            button.title = " 🔔"
        } else if isProtectionEnabled {
            button.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "loggdin")
            button.title = ""
        } else {
            button.image = NSImage(systemSymbolName: "face.dashed", accessibilityDescription: "loggdin - Paused")
            button.title = ""
        }
    }

    // MARK: - Actions

    @objc private func openDashboardAction() {
        openDashboard()
    }

    @objc private func simulateAction(_ sender: NSMenuItem) {
        let index = sender.tag
        if index >= 0 && index < PermissionRequest.samples.count {
            let sample = PermissionRequest.samples[index]
            Task {
                _ = await evaluateOrAsk(sample, forcePrompt: true)
            }
        }
    }

    @objc private func toggleProtectionAction() {
        isProtectionEnabled.toggle()
        updateMenuBar()
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }

    func openDashboard() {
        if let window = dashboardWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "loggdin Dashboard"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: DashboardView())
        window.isReleasedWhenClosed = false
        self.dashboardWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
