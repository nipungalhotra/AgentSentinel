import SwiftUI
import AppKit

struct DashboardView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case audit = "Audit Log"
        case rules = "Rules & Grants"
        case cli = "CLI & Agent Setup"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .overview: return "shield.checkered"
            case .audit: return "list.bullet.rectangle.portrait"
            case .rules: return "slider.horizontal.3"
            case .cli: return "terminal"
            }
        }
    }

    @State private var selectedTab: Tab = .overview
    @State private var manager = SentinelManager.shared
    @State private var rules = RulesEngine.shared

    var body: some View {
        HStack(spacing: 0) {
            // MARK: Sidebar
            VStack(alignment: .leading, spacing: 0) {
                // Brand Header
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 28, height: 28)
                        Image(systemName: "shield.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Agent Sentinel")
                            .font(.system(size: 13, weight: .bold))
                        Text("Permission Gate")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 16)

                Divider()
                    .padding(.bottom, 8)

                // Navigation Items
                VStack(spacing: 3) {
                    ForEach(Tab.allCases) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 13, weight: .medium))
                                    .frame(width: 18)
                                    .foregroundStyle(selectedTab == tab ? .white : .secondary)

                                Text(tab.rawValue)
                                    .font(.system(size: 12.5, weight: selectedTab == tab ? .semibold : .regular))
                                    .foregroundStyle(selectedTab == tab ? .white : .primary)

                                Spacer()

                                if tab == .audit && !rules.auditLogs.isEmpty {
                                    Text("\(rules.auditLogs.count)")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(selectedTab == tab ? Color.white.opacity(0.25) : Color.primary.opacity(0.08), in: Capsule())
                                } else if tab == .rules && !rules.activeGrants.isEmpty {
                                    Text("\(rules.activeGrants.count)")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color.orange.opacity(0.25), in: Capsule())
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedTab == tab ? Color.blue : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)

                Spacer()

                // Sidebar Footer Status
                VStack(spacing: 8) {
                    Divider()
                    HStack(spacing: 8) {
                        Circle()
                            .fill(manager.isProtectionEnabled ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(manager.isProtectionEnabled ? "Sentinel Guarding" : "Protection Paused")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
            .frame(width: 200)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // MARK: Detail View
            VStack(spacing: 0) {
                // Top Detail Header Bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedTab.rawValue)
                            .font(.system(size: 17, weight: .bold))
                    }

                    Spacer()

                    // Port Status Pill
                    HStack(spacing: 6) {
                        Circle()
                            .fill(manager.isProtectionEnabled ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text("Port 9191")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(manager.isProtectionEnabled ? "Active" : "Paused")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(manager.isProtectionEnabled ? .green : .orange)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.05), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // Detail Content
                Group {
                    switch selectedTab {
                    case .overview:
                        OverviewTab()
                    case .audit:
                        AuditLogTab()
                    case .rules:
                        RulesTab()
                    case .cli:
                        CLIIntegrationTab()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 840, minHeight: 560)
    }
}

// MARK: - Overview Tab

struct OverviewTab: View {
    @State private var manager = SentinelManager.shared
    @State private var rules = RulesEngine.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Status Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Agent Sentinel Daemon")
                                .font(.title3.bold())
                            Text("Listening on http://127.0.0.1:9191 • Drops liquid glass permission cards below MacBook camera")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Active", isOn: $manager.isProtectionEnabled)
                            .toggleStyle(.switch)
                    }

                    Divider()

                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text(manager.lastDecisionSummary)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))

                // Metric Cards Grid
                HStack(spacing: 14) {
                    metricCard("Audit Events", count: "\(rules.auditLogs.count)", icon: "list.bullet", color: .purple)
                    metricCard("Active Grants", count: "\(rules.activeGrants.count)", icon: "clock.badge.checkmark", color: .orange)
                    metricCard("Saved Rules", count: "\(rules.storedRules.count)", icon: "checkmark.shield", color: .green)
                    metricCard("Pending", count: "\(manager.pendingCount)", icon: "bell", color: manager.pendingCount > 0 ? .red : .blue)
                }

                // Interactive Simulator Section
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Interactive Popup Simulator")
                            .font(.headline)
                        Text("Trigger real liquid glass permission drop-downs beneath the MacBook camera to test interaction flows:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 10) {
                        ForEach(PermissionRequest.samples) { sample in
                            HStack {
                                Image(systemName: sample.symbol)
                                    .frame(width: 24)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sample.title)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(sample.plainCommand)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                RiskChip(risk: sample.risk)
                                Button("Trigger") {
                                    Task {
                                        _ = await manager.evaluateOrAsk(sample)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.03)))
                        }
                    }
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            }
            .padding(24)
        }
    }

    private func metricCard(_ title: String, count: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(count)
                .font(.system(size: 24, weight: .bold))
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

// MARK: - Audit Log Tab

struct AuditLogTab: View {
    @State private var rules = RulesEngine.shared
    @State private var search: String = ""
    @State private var filterRisk: Risk? = nil

    var filteredLogs: [AuditLogEntry] {
        rules.auditLogs.filter { log in
            let matchesSearch = search.isEmpty ||
                log.request.plainCommand.localizedCaseInsensitiveContains(search) ||
                log.request.requestedBy.localizedCaseInsensitiveContains(search)
            let matchesRisk = filterRisk == nil || log.request.risk == filterRisk
            return matchesSearch && matchesRisk
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Search audit events...", text: $search)
                    .textFieldStyle(.roundedBorder)

                Picker("Risk", selection: $filterRisk) {
                    Text("All Risks").tag(Risk?.none)
                    ForEach(Risk.allCases, id: \.self) { r in
                        Text(r.label).tag(Risk?.some(r))
                    }
                }
                .frame(width: 130)

                Button("Clear") {
                    rules.clearAuditLogs()
                }
                .disabled(rules.auditLogs.isEmpty)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if filteredLogs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No audit log events recorded yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Commands evaluated by Sentinel will appear here in real-time.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredLogs) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.request.title)
                                .font(.system(size: 13, weight: .semibold))
                            RiskChip(risk: entry.request.risk)
                            Spacer()
                            decisionBadge(entry.decision, auto: entry.autoAllowed)
                            Text(entry.timeFormatted)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Text(entry.request.plainCommand)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)

                        HStack(spacing: 14) {
                            Text("By: \(entry.request.requestedBy)").foregroundStyle(.secondary)
                            Text("Dir: \(entry.request.directory)").foregroundStyle(.secondary)
                            Text("Modifies: \(entry.request.modifiesFiles)").foregroundStyle(.secondary)
                        }
                        .font(.system(size: 11))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func decisionBadge(_ decision: Decision, auto: Bool) -> some View {
        HStack(spacing: 4) {
            if auto {
                Text("AUTO")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.2), in: Capsule())
                    .foregroundStyle(.blue)
            }
            Text(decision.summary)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(decision.isAllowed ? Color.green.opacity(0.15) : Color.red.opacity(0.15), in: Capsule())
                .foregroundStyle(decision.isAllowed ? Color.green : Color.red)
        }
    }
}

// MARK: - Rules & Grants Tab

struct RulesTab: View {
    @State private var rules = RulesEngine.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Active 10-Minute Temporary Grants
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active Temporary Grants (10 min)")
                            .font(.headline)
                        Text("Commands granted short-term permission without repeated prompts")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if rules.activeGrants.isEmpty {
                        Text("No active temporary grants right now.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(rules.activeGrants) { grant in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(grant.commandPrefix)
                                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        Text("Directory: \(grant.directory)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Label(grant.remainingFormatted, systemImage: "timer")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.orange)

                                    Button("Revoke") {
                                        rules.revokeGrant(id: grant.id)
                                    }
                                    .controlSize(.small)
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                            }
                        }
                    }
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.03)))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))

                // Persistent Rules
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Persistent Whitelist Rules")
                            .font(.headline)
                        Text("Rules configured via 'Always allow' or saved manually")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if rules.storedRules.isEmpty {
                        Text("No persistent rules saved yet. When you click 'Always allow', rules appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(rules.storedRules) { rule in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(rule.pattern)
                                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        Text(rule.notes)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Delete", role: .destructive) {
                                        rules.revokeRule(id: rule.id)
                                    }
                                    .controlSize(.small)
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                            }
                        }
                    }
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.03)))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
            }
            .padding(24)
        }
    }
}

// MARK: - CLI & Agent Setup Tab

struct CLIIntegrationTab: View {
    @State private var copiedCurl = false
    @State private var scriptInstalled = false

    let curlSample = """
    curl -s -X POST http://localhost:9191/ask \\
      -H "Content-Type: application/json" \\
      -d '{"command": "npm install express", "requestedBy": "Claude Code"}'
    """

    let wrapperScript = """
    #!/usr/bin/env bash
    # sentinel wrapper: checks Agent Sentinel before executing command
    CMD="$*"
    RESPONSE=$(curl -s -X POST http://localhost:9191/ask \\
      -H "Content-Type: application/json" \\
      -d "{\\"command\\": \\"$CMD\\", \\"requestedBy\\": \\"$USER\\"}")

    if echo "$RESPONSE" | grep -q '"allowed": true'; then
      echo "🛡️ Sentinel approved: executing..."
      eval "$CMD"
    else
      echo "❌ Sentinel denied permission."
      exit 1
    fi
    """

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Integrate Agent Sentinel into your CLI & Tools")
                        .font(.title3.bold())
                    Text("Agent Sentinel runs a local lightweight HTTP daemon on port 9191. Any shell script, CLI tool, or AI agent can request permission before executing actions.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // 1. One-Click CLI Wrapper Script Installation
                VStack(alignment: .leading, spacing: 10) {
                    Text("1. Install `sentinel` Shell Wrapper")
                        .font(.headline)
                    Text("Installs a handy `sentinel` command to `~/.local/bin/sentinel` so you can guard any command with `sentinel <command>`.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(scriptInstalled ? "✓ Installed to ~/.local/bin/sentinel" : "Install 'sentinel' CLI Script") {
                        installScript()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(scriptInstalled ? .green : .blue)
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))

                // 2. HTTP API Reference
                VStack(alignment: .leading, spacing: 10) {
                    Text("2. Direct HTTP API Hook")
                        .font(.headline)
                    Text("Call this endpoint from Python, Node.js, Go, or shell scripts:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .trailing, spacing: 8) {
                        Text(curlSample)
                            .font(.system(size: 11.5, design: .monospaced))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button(copiedCurl ? "Copied!" : "Copy cURL") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(curlSample, forType: .string)
                            copiedCurl = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedCurl = false
                            }
                        }
                        .controlSize(.small)
                    }
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
            }
            .padding(24)
        }
    }

    private func installScript() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let binDir = home.appendingPathComponent(".local/bin")
        try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let scriptPath = binDir.appendingPathComponent("sentinel")
        try? wrapperScript.write(to: scriptPath, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+x", scriptPath.path]
        try? process.run()
        process.waitUntilExit()
        scriptInstalled = true
    }
}
