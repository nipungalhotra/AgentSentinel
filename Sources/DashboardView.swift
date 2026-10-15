import SwiftUI
import AppKit

struct DashboardView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case integrations = "Agent Integrations"
        case audit = "Audit Log"
        case rules = "Rules & Grants"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .overview: return "shield.checkered"
            case .integrations: return "sparkles.rectangle.stack.fill"
            case .audit: return "list.bullet.rectangle.portrait"
            case .rules: return "slider.horizontal.3"
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
                    case .integrations:
                        AgentIntegrationsTab()
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

// MARK: - AI Agent & CLI Integrations Tab

struct AgentIntegrationsTab: View {
    @State private var allInstalled = false
    @State private var claudeInstalled = false
    @State private var coworkInstalled = false
    @State private var antigravityInstalled = false
    @State private var cursorInstalled = false
    @State private var codexInstalled = false
    @State private var chatgptInstalled = false
    @State private var copilotInstalled = false
    @State private var zshInstalled = false
    @State private var copiedSnippet = false
    @State private var selectedSnippet = 0

    let pythonSnippet = """
from sentinel import ask_permission, guard

# 1. Ask permission before critical actions
if ask_permission("rm -rf ./cache", requested_by="ChatGPT", risk="high"):
    print("User approved! Proceeding...")

# 2. Or guard command execution automatically
result = guard("npm run build", requested_by="Codex")
print(result.stdout)
"""

    let nodeSnippet = """
const { askPermission } = require('./sentinel');

async function main() {
  const allowed = await askPermission({
    command: 'git push origin main --force',
    requestedBy: 'Claude Code',
    risk: 'high'
  });

  if (allowed) {
    console.log("Approved by user via Liquid Glass popup!");
  }
}
main();
"""

    let mcpJsonSnippet = """
{
  "mcpServers": {
    "sentinel": {
      "command": "node",
      "args": ["/Users/nipun/.gemini/antigravity-ide/scratch/AgentSentinel/bin/sentinel-mcp.js"],
      "env": { "SENTINEL_PORT": "9191" }
    }
  }
}
"""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Universal AI Agent Hub & Integrations")
                                .font(.title3.bold())
                            Text("Modeled after Coucou: seamlessly intercepts actions across Claude Code, Cowork, Antigravity, Cursor, Codex, ChatGPT, Copilot, and Terminal.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()

                        Button(allInstalled ? "✓ All Agents Guarded" : "🚀 1-Click Setup All") {
                            _ = HookInstaller.shared.installAll()
                            checkStatus()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(allInstalled ? .green : .blue)
                    }
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))

                // Integration Cards Grid (8 Core Agents & Tools)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    // 1. Claude Code
                    let pClaude = PillCatalog.definition(for: "claude-code")
                    agentCard(
                        pill: pClaude,
                        details: "Native hook in ~/.claude/settings.json (PermissionRequest, PreToolUse, AskUserQuestion)",
                        isInstalled: claudeInstalled,
                        onInstall: {
                            try? HookInstaller.shared.installClaudeCodeHooks()
                            checkStatus()
                        },
                        onTest: {
                            triggerTest(
                                title: "Execute Destructive Cleanup?",
                                subtitle: "Claude Code • Bash",
                                command: "rm -rf node_modules && npm test",
                                risk: .high,
                                agent: "Claude Code",
                                symbol: pClaude.iconSystemName
                            )
                        }
                    )

                    // 2. Cowork (Claude Desktop)
                    let pCowork = PillCatalog.definition(for: "cowork")
                    agentCard(
                        pill: pCowork,
                        details: "Model Context Protocol in claude_desktop_config.json",
                        isInstalled: coworkInstalled,
                        onInstall: {
                            try? HookInstaller.shared.installCoworkMCP()
                            checkStatus()
                        },
                        onTest: {
                            triggerTest(
                                title: "Read SSH Private Key?",
                                subtitle: "Cowork • KeyAccess",
                                command: "cat ~/.ssh/id_rsa | base64",
                                risk: .high,
                                agent: "Cowork",
                                symbol: pCowork.iconSystemName
                            )
                        }
                    )

                    // 3. Antigravity & IDE
                    let pAgy = PillCatalog.definition(for: "antigravity")
                    agentCard(
                        pill: pAgy,
                        details: "Native hooks in ~/.gemini/config/hooks.json & Antigravity MCP tool registry",
                        isInstalled: antigravityInstalled,
                        onInstall: {
                            try? HookInstaller.shared.installAntigravityHooks()
                            checkStatus()
                        },
                        onTest: {
                            triggerTest(
                                title: "Deploy Service to Cloud Run?",
                                subtitle: "Antigravity • CloudRun",
                                command: "gcloud run deploy agent-sentinel --region=us-central1",
                                risk: .medium,
                                agent: "Antigravity",
                                symbol: pAgy.iconSystemName
                            )
                        }
                    )

                    // 4. Cursor
                    let pCursor = PillCatalog.definition(for: "cursor")
                    agentCard(
                        pill: pCursor,
                        details: "Workspace MCP server configured in ~/.cursor/mcp.json",
                        isInstalled: cursorInstalled,
                        onInstall: {
                            try? HookInstaller.shared.installCursorMCP()
                            checkStatus()
                        },
                        onTest: {
                            triggerTest(
                                title: "Force Push to Main Branch?",
                                subtitle: "Cursor • GitSync",
                                command: "git push origin main --force",
                                risk: .high,
                                agent: "Cursor",
                                symbol: pCursor.iconSystemName
                            )
                        }
                    )

                    // 5. Codex
                    let pCodex = PillCatalog.definition(for: "codex")
                    agentCard(
                        pill: pCodex,
                        details: "Native hook in ~/.codex/hooks.json (PermissionRequest)",
                        isInstalled: codexInstalled,
                        onInstall: {
                            try? HookInstaller.shared.installCodexHooks()
                            checkStatus()
                        },
                        onTest: {
                            triggerTest(
                                title: "Install System Dependencies?",
                                subtitle: "Codex • PipInstaller",
                                command: "python3 -m pip install -r requirements.txt",
                                risk: .low,
                                agent: "Codex",
                                symbol: pCodex.iconSystemName
                            )
                        }
                    )

                    // 6. ChatGPT Desktop
                    let pGpt = PillCatalog.definition(for: "chatgpt")
                    agentCard(
                        pill: pGpt,
                        details: "Custom Agent SDK & Codex Gateway Bridge",
                        isInstalled: chatgptInstalled,
                        onInstall: {
                            try? HookInstaller.shared.installCodexHooks()
                            checkStatus()
                        },
                        onTest: {
                            triggerTest(
                                title: "Execute Database Migration?",
                                subtitle: "ChatGPT • SchemaMigrator",
                                command: "DROP TABLE legacy_users; ALTER TABLE accounts ADD COLUMN tier TEXT;",
                                risk: .high,
                                agent: "ChatGPT",
                                symbol: pGpt.iconSystemName
                            )
                        }
                    )

                    // 7. Copilot CLI
                    let pCopilot = PillCatalog.definition(for: "copilot")
                    agentCard(
                        pill: pCopilot,
                        details: "GitHub Copilot hooks in ~/.copilot/hooks/sentinel.json",
                        isInstalled: copilotInstalled,
                        onInstall: {
                            try? HookInstaller.shared.installCopilotHooks()
                            checkStatus()
                        },
                        onTest: {
                            triggerTest(
                                title: "Create Pull Request & Auto-Merge?",
                                subtitle: "Copilot CLI • GitHubAction",
                                command: "gh pr merge 42 --auto --squash",
                                risk: .medium,
                                agent: "Copilot CLI",
                                symbol: pCopilot.iconSystemName
                            )
                        }
                    )

                    // 8. Terminal Shell Gate
                    let pTerm = PillCatalog.definition(for: "terminal")
                    agentCard(
                        pill: pTerm,
                        details: "ZSH preexec auto-interceptor in ~/.zshrc",
                        isInstalled: zshInstalled,
                        onInstall: {
                            try? HookInstaller.shared.installZshHook()
                            checkStatus()
                        },
                        onTest: {
                            triggerTest(
                                title: "Delete Build Cache Permanently?",
                                subtitle: "Terminal • Shell Gate",
                                command: "rm -rf ~/Projects/old-build",
                                risk: .high,
                                agent: "Terminal",
                                symbol: pTerm.iconSystemName
                            )
                        }
                    )
                }

                // SDK & Code Snippets Section (for custom ChatGPT / Codex agents)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Custom Agent SDK (ChatGPT, Codex, LangChain)")
                                .font(.headline)
                            Text("Use 1 line of code in Python or Node.js to trigger the Liquid Glass popup from any custom AI pipeline:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()

                        Picker("Language", selection: $selectedSnippet) {
                            Text("Python SDK").tag(0)
                            Text("Node.js SDK").tag(1)
                            Text("MCP Config (JSON)").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 320)
                    }

                    VStack(alignment: .trailing, spacing: 8) {
                        let activeCode = selectedSnippet == 0 ? pythonSnippet : (selectedSnippet == 1 ? nodeSnippet : mcpJsonSnippet)

                        Text(activeCode)
                            .font(.system(size: 11.5, design: .monospaced))
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        Button(copiedSnippet ? "✓ Copied to Clipboard" : "Copy Code Snippet") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(activeCode, forType: .string)
                            copiedSnippet = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedSnippet = false
                            }
                        }
                        .controlSize(.small)
                    }
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            }
            .padding(24)
        }
        .onAppear {
            checkStatus()
        }
    }

    private func agentCard(
        pill: PillDefinition,
        details: String,
        isInstalled: Bool,
        onInstall: @escaping () -> Void,
        onTest: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(pill.color.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: pill.iconSystemName)
                        .font(.system(size: 15))
                        .foregroundStyle(pill.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(pill.name)
                        .font(.system(size: 13, weight: .bold))
                    Text(pill.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isInstalled {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Active & Guarded")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.green.opacity(0.12), in: Capsule())
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 6, height: 6)
                        Text("Not Configured")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }

            Text(details)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Divider()

            HStack {
                Button("Test Notch Popup", action: onTest)
                    .controlSize(.small)

                Spacer()

                Button(isInstalled ? "Reconfigure" : "Configure Hook", action: onInstall)
                    .buttonStyle(.borderedProminent)
                    .tint(isInstalled ? .secondary : pill.color)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isInstalled ? pill.color.opacity(0.25) : Color.primary.opacity(0.07), lineWidth: 1))
    }

    private func triggerTest(title: String, subtitle: String, command: String, risk: Risk, agent: String, symbol: String) {
        Task {
            let req = PermissionRequest(
                title: title,
                subtitle: subtitle,
                symbol: symbol,
                command: command,
                risk: risk,
                requestedBy: agent,
                directory: "~/Projects/workspace",
                modifiesFiles: risk == .high ? "Yes, permanently" : "No"
            )
            _ = await SentinelManager.shared.evaluateOrAsk(req)
        }
    }

    private func checkStatus() {
        let installer = HookInstaller.shared
        claudeInstalled = installer.isClaudeCodeInstalled()
        coworkInstalled = installer.isCoworkInstalled()
        antigravityInstalled = installer.isAntigravityInstalled()
        cursorInstalled = installer.isCursorInstalled()
        codexInstalled = installer.isCodexInstalled()
        chatgptInstalled = installer.isCodexInstalled()
        copilotInstalled = installer.isCopilotInstalled()
        zshInstalled = installer.isZshInstalled()
        allInstalled = claudeInstalled && coworkInstalled && antigravityInstalled && cursorInstalled && codexInstalled && zshInstalled
    }
}

