import SwiftUI
import AppKit

// MARK: - Dashboard View

struct DashboardView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case integrations = "Agent Integrations"
        case audit = "Audit Log"
        case rules = "Rules & Grants"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .overview: return "shield.lefthalf.filled"
            case .integrations: return "sparkles.rectangle.stack.fill"
            case .audit: return "clock.arrow.circlepath"
            case .rules: return "slider.horizontal.3"
            }
        }
    }

    @State private var selectedTab: Tab = .overview
    @State private var manager = SentinelManager.shared
    @State private var rules = RulesEngine.shared
    @State private var socketCopied = false

    var body: some View {
        HStack(spacing: 0) {
            // MARK: Modern Glass Sidebar
            VStack(alignment: .leading, spacing: 0) {
                // Window traffic light offset
                Color.clear.frame(height: 38)

                // Brand Header
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#3B82F6"), Color(hex: "#8B5CF6"), Color(hex: "#06B6D4")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                            .shadow(color: Color.blue.opacity(0.4), radius: 8, y: 3)

                        Image(systemName: "shield.checkered")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Agent Sentinel")
                            .font(.system(size: 14, weight: .bold))
                        HStack(spacing: 6) {
                            Text("PERMISSION GATE")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("PRO")
                                .font(.system(size: 8.5, weight: .black))
                                .padding(.horizontal, 4.5)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.18), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)

                Divider()
                    .opacity(0.5)
                    .padding(.bottom, 12)

                // Navigation Items
                VStack(spacing: 4) {
                    ForEach(Tab.allCases) { tab in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 14, weight: .medium))
                                    .frame(width: 20)
                                    .foregroundStyle(selectedTab == tab ? .white : .secondary)

                                Text(tab.rawValue)
                                    .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                                    .foregroundStyle(selectedTab == tab ? .white : .primary)

                                Spacer()

                                if tab == .integrations {
                                    Text("8")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(selectedTab == tab ? Color.white.opacity(0.25) : Color.green.opacity(0.2), in: Capsule())
                                        .foregroundStyle(selectedTab == tab ? .white : .green)
                                } else if tab == .audit && !rules.auditLogs.isEmpty {
                                    Text("\(rules.auditLogs.count)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(selectedTab == tab ? Color.white.opacity(0.25) : Color.primary.opacity(0.08), in: Capsule())
                                        .foregroundStyle(selectedTab == tab ? .white : .secondary)
                                } else if tab == .rules && !rules.activeGrants.isEmpty {
                                    Text("\(rules.activeGrants.count)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(selectedTab == tab ? Color.white.opacity(0.25) : Color.orange.opacity(0.25), in: Capsule())
                                        .foregroundStyle(selectedTab == tab ? .white : .orange)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background {
                                if selectedTab == tab {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.blue, Color.blue.opacity(0.85)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .shadow(color: Color.blue.opacity(0.3), radius: 6, y: 2)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)

                Spacer()

                // Sidebar Footer: Sentinel Engine Radar Card
                VStack(spacing: 10) {
                    Divider().opacity(0.5)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            PulsingRadarBeacon(isGuarding: manager.isProtectionEnabled)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(manager.isProtectionEnabled ? "Sentinel Guarding" : "Protection Paused")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(manager.isProtectionEnabled ? .primary : .secondary)
                                Text("Port 9191 • Socket Ready")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()

                            Toggle("", isOn: $manager.isProtectionEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                        }

                        Button {
                            Task {
                                _ = await manager.evaluateOrAsk(PermissionRequest.samples[0])
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11))
                                Text("Test Notch Card")
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .frame(width: 235)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.75))

            Divider().opacity(0.5)

            // MARK: Detail View Area
            ZStack {
                // Cosmic Ambient Gradient Mesh Backdrop
                ZStack {
                    Color(NSColor.windowBackgroundColor)

                    // Sapphire glow top right
                    RadialGradient(
                        colors: [Color.blue.opacity(0.12), Color.clear],
                        center: .topTrailing,
                        startRadius: 20,
                        endRadius: 420
                    )

                    // Amethyst glow bottom left
                    RadialGradient(
                        colors: [Color.purple.opacity(0.09), Color.clear],
                        center: .bottomLeading,
                        startRadius: 40,
                        endRadius: 480
                    )
                }
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top Navigation Bar
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Agent Sentinel")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Text("/")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                Text(selectedTab.rawValue)
                                    .font(.system(size: 15, weight: .bold))
                            }
                        }

                        Spacer()

                        // Port 9191 Pill
                        HStack(spacing: 6) {
                            Circle()
                                .fill(manager.isProtectionEnabled ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            Text("127.0.0.1:9191")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text(manager.isProtectionEnabled ? "Live" : "Paused")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(manager.isProtectionEnabled ? .green : .orange)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8))

                        // Quick Test Trigger
                        Button {
                            Task {
                                _ = await manager.evaluateOrAsk(PermissionRequest.samples[0])
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 11))
                                Text("Quick Test")
                                    .font(.system(size: 11.5, weight: .semibold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.blue.opacity(0.15), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.blue.opacity(0.3), lineWidth: 0.8))
                            .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)

                        // Copy Socket Path
                        Button {
                            let socket = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                                .appendingPathComponent("AgentSentinel/sentinel.sock").path
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(socket, forType: .string)
                            socketCopied = true
                            SoundEngine.shared.playTick()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                socketCopied = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: socketCopied ? "checkmark" : "link")
                                    .font(.system(size: 11))
                                Text(socketCopied ? "Copied Socket" : "Socket")
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.8))
                            .foregroundStyle(socketCopied ? Color.green : Color.secondary)
                        }
                        .buttonStyle(.plain)

                        // GitHub Link
                        Button {
                            if let url = URL(string: "https://github.com/nipungalhotra/AgentSentinel") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Image(systemName: "safari")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .padding(6)
                                .background(Color.primary.opacity(0.06), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("View on GitHub")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial.opacity(0.85))

                    Divider().opacity(0.4)

                    // Tab View Content
                    Group {
                        switch selectedTab {
                        case .overview:
                            OverviewTab()
                        case .integrations:
                            AgentIntegrationsTab()
                        case .audit:
                            AuditLogTab()
                        case .rules:
                            RulesTab()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 920, minHeight: 620)
    }
}

// MARK: - Pulsing Radar Beacon

struct PulsingRadarBeacon: View {
    var isGuarding: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            if isGuarding {
                Circle()
                    .stroke(Color.green.opacity(0.6), lineWidth: 1.5)
                    .frame(width: pulse ? 22 : 8, height: pulse ? 22 : 8)
                    .opacity(pulse ? 0 : 0.8)

                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .shadow(color: Color.green.opacity(0.6), radius: 4)
            } else {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: 24, height: 24)
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

// MARK: - Overview Tab

struct OverviewTab: View {
    @State private var manager = SentinelManager.shared
    @State private var rules = RulesEngine.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Hero Status Banner
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.25), Color.purple.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 52, height: 52)
                                .overlay(Circle().strokeBorder(Color.blue.opacity(0.35), lineWidth: 1))

                            Image(systemName: "shield.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(
                                    LinearGradient(colors: [.blue, .cyan], startPoint: .top, endPoint: .bottom)
                                )
                                .shadow(color: Color.blue.opacity(0.5), radius: 6)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text("Zero-Trust Agent Defense Active")
                                    .font(.system(size: 17, weight: .bold))
                                HStack(spacing: 4) {
                                    Circle().fill(Color.green).frame(width: 6, height: 6)
                                    Text("ENFORCING")
                                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.green)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12), in: Capsule())
                            }

                            Text("Guarding terminal commands, tool invocations, and MCP actions across Claude Code, Cowork, Antigravity, Cursor, Codex, ChatGPT, Copilot, and Terminal.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Toggle("Guarding", isOn: $manager.isProtectionEnabled)
                            .toggleStyle(.switch)
                    }

                    // Real-Time Event Readout Box
                    HStack(spacing: 10) {
                        Image(systemName: "terminal")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(manager.lastDecisionSummary)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8))
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .white.opacity(0.1), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)

                // Bento Metric Cards Grid
                HStack(spacing: 14) {
                    metricBento(
                        title: "Audit Events",
                        count: "\(rules.auditLogs.count)",
                        sub: "Real-time logged",
                        icon: "list.bullet.rectangle.portrait.fill",
                        color: Color.purple
                    )
                    metricBento(
                        title: "Active Grants",
                        count: "\(rules.activeGrants.count)",
                        sub: "10-min passes",
                        icon: "clock.badge.checkmark.fill",
                        color: Color.orange
                    )
                    metricBento(
                        title: "Saved Rules",
                        count: "\(rules.storedRules.count)",
                        sub: "Permanent whitelist",
                        icon: "checkmark.shield.fill",
                        color: Color.green
                    )
                    metricBento(
                        title: "Pending Requests",
                        count: "\(manager.pendingCount)",
                        sub: manager.pendingCount > 0 ? "Awaiting decision" : "Queue clear",
                        icon: "bell.badge.fill",
                        color: manager.pendingCount > 0 ? Color.red : Color.blue
                    )
                }

                // Interactive Simulator Section
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Liquid Glass Notch Simulator")
                                .font(.system(size: 16, weight: .bold))
                            Spacer()
                            Text("6 Scenarios Ready")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Text("Trigger fluid permission cards directly beneath your MacBook camera notch to test the prompt experience:")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 10) {
                        ForEach(PermissionRequest.samples) { sample in
                            let pill = PillCatalog.definition(for: sample.requestedBy)
                            HStack(spacing: 14) {
                                // Agent Pill Icon
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(pill.color.opacity(0.18))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: sample.symbol)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(pill.color)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(sample.title)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(sample.requestedBy)
                                            .font(.system(size: 10.5, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(pill.color.opacity(0.15), in: Capsule())
                                            .foregroundStyle(pill.color)
                                    }
                                    Text(sample.plainCommand)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                RiskChip(risk: sample.risk)

                                Button {
                                    Task {
                                        _ = await manager.evaluateOrAsk(sample)
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 9))
                                        Text("Trigger")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue, in: Capsule())
                                    .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(12)
                            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                        }
                    }
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8))
            }
            .padding(24)
        }
    }

    private func metricBento(title: String, count: String, sub: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(color.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(color)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(count)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(sub)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8))
        .shadow(color: color.opacity(0.06), radius: 8, y: 3)
    }
}

// MARK: - Agent Integrations Tab

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

# 1. Interactively ask permission before executing commands
if ask_permission("rm -rf ./cache", requested_by="ChatGPT", risk="high"):
    print("User approved via liquid glass notch card!")

# 2. Or guard tool invocations automatically with audit trails
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
    console.log("Approved by user via Liquid Glass notch card!");
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

    let zshSnippet = """
# Agent Sentinel ZSH Shell Interceptor (in ~/.zshrc)
autoload -Uz add-zsh-hook
sentinel_preexec() {
  local cmd="$1"
  if [[ "$cmd" =~ ^(rm -rf|git push.*--force|sudo|dd ) ]]; then
    sentinel ask "$cmd" --risk high || return 1
  fi
}
add-zsh-hook preexec sentinel_preexec
"""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Header Banner
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Universal AI Agent Hub & Integrations")
                                .font(.system(size: 18, weight: .bold))
                            Text("Inspired by Coucou: seamlessly intercepts actions across Claude Code, Cowork, Antigravity, Cursor, Codex, ChatGPT, Copilot, and Terminal.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()

                        Button {
                            _ = HookInstaller.shared.installAll()
                            checkStatus()
                            SoundEngine.shared.playAllow()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: allInstalled ? "checkmark.circle.fill" : "bolt.shield.fill")
                                Text(allInstalled ? "All Agents Guarded" : "1-Click Setup All")
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(allInstalled ? Color.green : Color.blue, in: Capsule())
                            .foregroundStyle(.white)
                            .shadow(color: (allInstalled ? Color.green : Color.blue).opacity(0.4), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8))

                // 8 Core Agent Integration Bento Grid
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
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

                // SDK & Code Snippets Drawer
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Universal Developer SDK & Code Snippets")
                                .font(.system(size: 15, weight: .bold))
                            Text("Integrate the liquid glass permission gate into any custom agent pipeline:")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()

                        Picker("Language", selection: $selectedSnippet) {
                            Text("Python SDK").tag(0)
                            Text("Node.js SDK").tag(1)
                            Text("MCP Config").tag(2)
                            Text("ZSH Hook").tag(3)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 380)
                    }

                    VStack(alignment: .trailing, spacing: 8) {
                        let activeCode = selectedSnippet == 0 ? pythonSnippet : (selectedSnippet == 1 ? nodeSnippet : (selectedSnippet == 2 ? mcpJsonSnippet : zshSnippet))

                        VStack(alignment: .leading, spacing: 0) {
                            // Mini terminal header
                            HStack(spacing: 5) {
                                Circle().fill(Color.red.opacity(0.8)).frame(width: 7, height: 7)
                                Circle().fill(Color.yellow.opacity(0.8)).frame(width: 7, height: 7)
                                Circle().fill(Color.green.opacity(0.8)).frame(width: 7, height: 7)
                                Text("code-preview")
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 4)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.5))

                            Text(activeCode)
                                .font(.system(size: 11.5, design: .monospaced))
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(Color.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(activeCode, forType: .string)
                            copiedSnippet = true
                            SoundEngine.shared.playTick()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedSnippet = false
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: copiedSnippet ? "checkmark" : "doc.on.doc")
                                Text(copiedSnippet ? "Copied to Clipboard" : "Copy Code Snippet")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                            .foregroundStyle(copiedSnippet ? Color.green : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(pill.color.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: pill.iconSystemName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(pill.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(pill.name)
                        .font(.system(size: 13.5, weight: .bold))
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
                        Text("Guarded")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.14), in: Capsule())
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 6, height: 6)
                        Text("Not Configured")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }

            Text(details)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Divider().opacity(0.5)

            HStack {
                Button {
                    onTest()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                        Text("Test Notch")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    onInstall()
                } label: {
                    Text(isInstalled ? "Reconfigure" : "Configure Hook")
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(isInstalled ? Color.primary.opacity(0.1) : pill.color, in: Capsule())
                        .foregroundStyle(isInstalled ? Color.primary : Color.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(15)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isInstalled ? pill.color.opacity(0.3) : Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: isInstalled ? pill.color.opacity(0.08) : Color.clear, radius: 10, y: 4)
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

// MARK: - Audit Log Tab

struct AuditLogTab: View {
    @State private var rules = RulesEngine.shared
    @State private var search: String = ""
    @State private var filterRisk: Risk? = nil
    @State private var copiedLogId: UUID? = nil

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
            // Search & Filter Header
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    TextField("Search audit commands, agents, directories...", text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))

                    if !search.isEmpty {
                        Button {
                            search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))

                Picker("Risk", selection: $filterRisk) {
                    Text("All Risks").tag(Risk?.none)
                    ForEach(Risk.allCases, id: \.self) { r in
                        Text(r.label).tag(Risk?.some(r))
                    }
                }
                .frame(width: 130)

                Button("Clear Logs") {
                    rules.clearAuditLogs()
                    SoundEngine.shared.playTick()
                }
                .disabled(rules.auditLogs.isEmpty)
                .controlSize(.small)
            }
            .padding(16)
            .background(.ultraThinMaterial.opacity(0.9))

            Divider().opacity(0.4)

            if filteredLogs.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "shield.slash")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("No audit log events recorded yet")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("Commands evaluated by Sentinel across Claude Code, Cowork, Antigravity, and other agents will appear here live.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredLogs) { entry in
                    let pill = PillCatalog.definition(for: entry.request.requestedBy)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            // Agent badge
                            HStack(spacing: 4) {
                                Image(systemName: pill.iconSystemName)
                                    .font(.system(size: 10, weight: .bold))
                                Text(entry.request.requestedBy)
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(pill.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(pill.color)

                            Text(entry.request.title)
                                .font(.system(size: 13, weight: .semibold))

                            RiskChip(risk: entry.request.risk)

                            Spacer()

                            decisionBadge(entry.decision, auto: entry.autoAllowed)

                            Text(entry.timeFormatted)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        // Monospaced Command Container with Copy Button
                        HStack(spacing: 8) {
                            Text(entry.request.plainCommand)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Spacer()

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.request.plainCommand, forType: .string)
                                copiedLogId = entry.id
                                SoundEngine.shared.playTick()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    if copiedLogId == entry.id {
                                        copiedLogId = nil
                                    }
                                }
                            } label: {
                                Image(systemName: copiedLogId == entry.id ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10))
                                    .foregroundStyle(copiedLogId == entry.id ? Color.green : Color.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(9)
                        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 0.8))

                        HStack(spacing: 16) {
                            Text("Dir: \(entry.request.directory)").foregroundStyle(.secondary)
                            Text("Modifies: \(entry.request.modifiesFiles)").foregroundStyle(.secondary)
                        }
                        .font(.system(size: 11))
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func decisionBadge(_ decision: Decision, auto: Bool) -> some View {
        HStack(spacing: 4) {
            if auto {
                Text("AUTO")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.blue.opacity(0.2), in: Capsule())
                    .foregroundStyle(.blue)
            }
            Text(decision.summary)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2.5)
                .background(decision.isAllowed ? Color.green.opacity(0.16) : Color.red.opacity(0.16), in: Capsule())
                .foregroundStyle(decision.isAllowed ? Color.green : Color.red)
        }
    }
}

// MARK: - Rules & Grants Tab

struct RulesTab: View {
    @State private var rules = RulesEngine.shared
    @State private var newRulePattern: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Active 10-Minute Temporary Grants
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Active Temporary Grants (10-Minute Pass)")
                                .font(.system(size: 16, weight: .bold))
                            Spacer()
                            Text("\(rules.activeGrants.count) Active")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Text("Commands granted short-term permission without repeated prompts. Bypassed automatically until expiration.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }

                    if rules.activeGrants.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.badge.xmark")
                                .foregroundStyle(.secondary)
                            Text("No active temporary grants right now.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(rules.activeGrants) { grant in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(grant.commandPrefix)
                                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        Text("Directory: \(grant.directory)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Label(grant.remainingFormatted, systemImage: "timer")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.orange)

                                    Button("Revoke") {
                                        rules.revokeGrant(id: grant.id)
                                        SoundEngine.shared.playTick()
                                    }
                                    .controlSize(.small)
                                }
                                .padding(12)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8))

                // Persistent Whitelist Rules
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Persistent Whitelist Rules")
                                .font(.system(size: 16, weight: .bold))
                            Spacer()
                            Text("\(rules.storedRules.count) Saved")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Text("Commands configured via 'Always allow' or added manually. Permanently trusted commands.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }

                    // Add Custom Rule Field
                    HStack(spacing: 10) {
                        TextField("Add command pattern to whitelist (e.g. npm test, git status, cargo check)...", text: $newRulePattern)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.8))

                        Button("Add Rule") {
                            rules.addManualRule(pattern: newRulePattern)
                            newRulePattern = ""
                            SoundEngine.shared.playAllow()
                        }
                        .disabled(newRulePattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    if rules.storedRules.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.shield")
                                .foregroundStyle(.secondary)
                            Text("No persistent rules saved yet. When you click 'Always allow' on any popup, rules appear here.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(rules.storedRules) { rule in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(rule.pattern)
                                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        Text(rule.notes)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Delete", role: .destructive) {
                                        rules.revokeRule(id: rule.id)
                                        SoundEngine.shared.playTick()
                                    }
                                    .controlSize(.small)
                                }
                                .padding(12)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8))
            }
            .padding(24)
        }
    }
}
