import AppKit
import Combine
import SwiftUI

// MARK: - Risk scoring on the app side
//
// The hook sends its own risk level, but anything that can reach the socket or the HTTP port can
// send a request, so the app scores the command again and keeps the higher of the two. Same rules
// as determine_risk() in bin/sentinel-hook.

enum RiskScorer {
    private static let shells = ["sh", "bash", "zsh", "dash", "ksh", "fish"]
    private static let destructiveCode = ["rmtree", "os.remove", "os.unlink", "unlink(", "rimraf", "fs.rm", "rmsync",
                                          "os.system", "subprocess", "child_process", "execsync", "do shell script",
                                          "file.delete", "removedirs"]

    /// Files that switch loggdin off or change what it allows (also in bin/sentinel-hook).
    static let selfProtected = ["/.loggdin/", ".loggdin.json", "Application Support/AgentSentinel", "/.claude/settings",
                                "/.claude.json", "/.codex/hooks.json", "/.codex/config.toml", "/.gemini/config/hooks.json",
                                "/.gemini/settings.json", "/.cursor/mcp.json", "/.copilot/hooks", "claude_desktop_config.json",
                                "/.zshrc", "/.zprofile", "/.bashrc", "/.bash_profile", "sentinel-hook", "Loggdin.app"]

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    static func touchesSelfProtected(_ text: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expanded = text.replacingOccurrences(of: "~/", with: home + "/")
        return selfProtected.contains { expanded.contains($0) }
    }

    static func score(_ command: String) -> Risk {
        let lower = command.lowercased()
        let flat = lower.replacingOccurrences(of: "[\"'`()]", with: " ", options: .regularExpression)
        let tokens = flat.components(separatedBy: CharacterSet(charactersIn: " \t\n;&|")).filter { !$0.isEmpty }
        func shortFlag(_ letter: Character) -> Bool {
            tokens.contains { $0.hasPrefix("-") && !$0.hasPrefix("--") && $0.dropFirst().contains(letter) }
        }
        let rmRecursive = tokens.contains("rm") && (shortFlag("r") || tokens.contains("--recursive"))
        let findDelete = tokens.contains("find") && (tokens.contains("-delete") || matches("-exec(dir)?\\s+rm\\b", flat))
        let sudo = tokens.contains { ["sudo", "doas", "su"].contains($0) }
        let dd = tokens.contains("dd") && flat.contains("of=")
        let disk = ["mkfs", "shutdown", "reboot", "> /dev/sd", ">/dev/sd", "diskutil erase", "diskutil partition",
                    "drop database", "drop table", "truncate table", "chmod -r 777", "chmod 777 /", "launchctl unload",
                    "csrutil"].contains { flat.contains($0) }
        let owner = tokens.contains { $0 == "chmod" || $0 == "chown" } && (shortFlag("r") || tokens.contains("--recursive"))
        let pipeToShell = matches("\\|\\s*(sudo\\s+)?(env\\s+)?(" + shells.joined(separator: "|") + "|python[0-9.]*|node|perl|ruby)\\b", lower)
        let forcePush = tokens.contains("git") && tokens.contains("push") && tokens.contains { $0 == "-f" || $0.hasPrefix("--force") }
        let discard = tokens.contains("git") && ((tokens.contains("reset") && tokens.contains("--hard")) ||
                                                 (tokens.contains("clean") && shortFlag("f")))
        let inlineCode = matches("(^|[\\s;&|(])(python[0-9.]*|node|deno|bun|perl|ruby|php|osascript)\\s+(-[a-z]*[ce]\\b|--eval\\b)", lower)
        let destructive = inlineCode && destructiveCode.contains { lower.contains($0) }

        if rmRecursive || findDelete || sudo || dd || disk || owner || pipeToShell || forcePush || discard || destructive
            || lower.contains(":(){ :|:& };:") || touchesSelfProtected(command) {
            return .high
        }
        let install = ["npm install", "npm i ", "pip install", "pip3 install", "brew install", "gem install",
                       "cargo install", "yarn add", "pnpm add"].contains { lower.contains($0) }
        let gitMod = ["git push", "git reset", "git commit", "git branch -d", "git rebase", "git checkout --",
                      "git restore", "git stash drop"].contains { lower.contains($0) }
        let wrapper = (shells.contains(tokens.first ?? "") && tokens.contains("-c")) || ["eval", "exec", "xargs"].contains(tokens.first ?? "")
        return install || gitMod || inlineCode || wrapper ? .medium : .low
    }

    static func higher(_ a: Risk, _ b: Risk) -> Risk {
        func rank(_ r: Risk) -> Int { r == .high ? 2 : r == .medium ? 1 : 0 }
        return rank(a) >= rank(b) ? a : b
    }
}

// MARK: - Live sessions and per-agent pause

@MainActor @Observable
final class SessionTracker {
    static let shared = SessionTracker()

    enum State: String {
        case working = "Working"
        case waiting = "Waiting for you"
        case finished = "Finished"
        case ended = "Ended"
    }

    struct Session: Identifiable {
        let id: String
        let agent: String
        var directory: String
        var state: State
        var lastActivity: Date
        var detail: String

        var folder: String {
            let last = (directory as NSString).lastPathComponent
            return last.isEmpty || directory == "~" ? "home folder" : last
        }
    }

    private(set) var sessions: [String: Session] = [:]
    /// Agent display name → paused until (Date.distantFuture = until resumed).
    private(set) var pausedUntil: [String: Date] = [:]

    private init() {}

    static func agentName(_ raw: String) -> String { PillCatalog.definition(for: raw).name }

    /// Newest first; finished sessions drop off after 2 hours, ended ones after 10 minutes.
    var visible: [Session] {
        let now = Date()
        return sessions.values.filter {
            switch $0.state {
            case .ended: return now.timeIntervalSince($0.lastActivity) < 600
            case .finished: return now.timeIntervalSince($0.lastActivity) < 7200
            default: return now.timeIntervalSince($0.lastActivity) < 6 * 3600
            }
        }.sorted { $0.lastActivity > $1.lastActivity }
    }

    var agentsSeen: [String] { Array(Set(visible.map(\.agent))).sorted() }

    func record(event: String, agent rawAgent: String, sessionId: String?, directory: String?, detail: String? = nil) {
        let agent = Self.agentName(rawAgent)
        let dir = directory ?? "~"
        let key = (sessionId?.isEmpty == false) ? sessionId! : "\(agent)|\(dir)"
        let state: State
        switch event {
        case "SessionEnd": state = .ended
        case "Stop": state = .finished
        case "Notification", "PermissionRequest", "Question", "Reply": state = .waiting
        default: state = .working
        }
        var s = sessions[key] ?? Session(id: key, agent: agent, directory: dir, state: state, lastActivity: Date(), detail: "")
        s.state = state
        s.lastActivity = Date()
        if directory != nil { s.directory = dir }
        if let detail, !detail.isEmpty { s.detail = String(detail.prefix(120)) }
        sessions[key] = s
        scheduleMenuRefresh()
        if sessions.count > 200, let oldest = sessions.values.min(by: { $0.lastActivity < $1.lastActivity }) {
            sessions.removeValue(forKey: oldest.id)
        }
    }

    private var menuRefresh: Task<Void, Never>?

    private func scheduleMenuRefresh() {
        guard menuRefresh == nil else { return }
        menuRefresh = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self?.menuRefresh = nil
            SentinelManager.shared.refreshSessionsMenu()
        }
    }

    func isPaused(_ rawAgent: String) -> Bool {
        let agent = Self.agentName(rawAgent)
        guard let until = pausedUntil[agent] else { return false }
        if until > Date() { return true }
        pausedUntil.removeValue(forKey: agent)
        return false
    }

    func pauseText(_ agent: String) -> String? {
        guard isPaused(agent), let until = pausedUntil[Self.agentName(agent)] else { return nil }
        if until == .distantFuture { return "Paused until you resume" }
        let mins = max(1, Int(until.timeIntervalSinceNow / 60 + 0.5))
        return "Paused · \(mins) min left"
    }

    /// minutes nil = until resumed. High-risk requests still ask while an agent is paused.
    func pause(_ rawAgent: String, minutes: Int?) {
        pausedUntil[Self.agentName(rawAgent)] = minutes.map { Date().addingTimeInterval(Double($0) * 60) } ?? .distantFuture
    }

    func resume(_ rawAgent: String) {
        pausedUntil.removeValue(forKey: Self.agentName(rawAgent))
    }
}

// MARK: - Replies: keep an agent working from the card or loggdin Pocket
//
// When Claude Code finishes a turn its Stop hook asks loggdin for a reply. With replies on and you
// away (or set to always), loggdin shows the agent's last message on the card and on the phone; the
// text you send goes back as {"decision": "block", "reason": text} and the agent continues with it.

enum ReplySettings {
    /// "away" (default): only when the Mac is locked or idle. "always": every time. "off": never.
    static var mode: String {
        get { UserDefaults.standard.string(forKey: "loggdin_reply_mode") ?? "away" }
        set { UserDefaults.standard.set(newValue, forKey: "loggdin_reply_mode") }
    }
    /// How long a finished agent waits for a reply, in minutes.
    static var waitMinutes: Int {
        get { (UserDefaults.standard.object(forKey: "loggdin_reply_wait") as? Int) ?? 10 }
        set { UserDefaults.standard.set(max(1, min(newValue, 30)), forKey: "loggdin_reply_wait") }
    }
}

struct AgentReply {
    let id = UUID().uuidString
    let agent: String
    let directory: String
    let sessionId: String
    let message: String

    init(json: [String: Any]) {
        agent = (json["agent"] as? String) ?? "An agent"
        directory = (json["directory"] as? String) ?? "~"
        sessionId = (json["sessionId"] as? String) ?? ""
        message = String(((json["message"] as? String) ?? "Finished its turn.").prefix(1500))
    }

    var folder: String {
        let last = (directory as NSString).lastPathComponent
        return last.isEmpty || directory == "~" ? "your home folder" : last
    }
}

@MainActor @Observable
final class ReplyModel {
    let reply: AgentReply
    var text = ""
    var appeared = false
    var remaining: Double = 1
    var onFinish: ((String?) -> Void)?

    init(reply: AgentReply) { self.reply = reply }

    func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        finish(t)
    }

    func finish(_ result: String?) {
        let done = onFinish
        onFinish = nil
        done?(result)
    }
}

@MainActor
final class ReplyController {
    static let shared = ReplyController()

    private var queue: [(AgentReply, CheckedContinuation<String?, Never>)] = []
    private var busy = false
    private(set) var activeModel: ReplyModel?
    private var panel: FloatingPanel?

    /// Whether a finished agent should wait for a reply right now.
    var shouldAsk: Bool {
        switch ReplySettings.mode {
        case "always": return true
        case "away": return PhoneRelay.shared.userAway
        default: return false
        }
    }

    /// Returns the text to continue with, or nil to let the agent stop.
    func ask(_ reply: AgentReply) async -> String? {
        guard shouldAsk else { return nil }
        return await withCheckedContinuation { cont in
            queue.append((reply, cont))
            pump()
        }
    }

    func isAsking(id: String) -> Bool { activeModel?.reply.id == id }

    /// The agent stopped waiting (its hook timed out or was killed): drop its card on the Mac and the phone.
    func cancel(id: String) {
        if let model = activeModel, model.reply.id == id {
            model.finish(nil)
        } else if let i = queue.firstIndex(where: { $0.0.id == id }) {
            queue.remove(at: i).1.resume(returning: nil)
        }
    }

    /// Text typed in loggdin Pocket, already opened and checked with the pairing key (nil = let it stop).
    @discardableResult
    func submitFromPhone(id: String, text: String?) -> Bool {
        guard let model = activeModel, model.reply.id == id else { return false }
        guard let text else {
            model.finish(nil)
            return true
        }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        model.finish(String(t.prefix(4000)))
        return true
    }

    private func pump() {
        guard !busy, !queue.isEmpty else { return }
        busy = true
        let (reply, cont) = queue.removeFirst()
        let model = ReplyModel(reply: reply)
        activeModel = model
        let timeout = Double(ReplySettings.waitMinutes * 60)

        if !PhoneRelay.shared.isPhoneOnly { showCard(model) }
        PhoneRelay.shared.replyPresented(reply)

        model.onFinish = { [weak self] result in
            guard let self else { return }
            if let panel = self.panel {
                panel.orderOut(nil)
                panel.contentView = nil
                panel.close()
                self.panel = nil
            }
            PhoneRelay.shared.replyFinished(reply)
            if result != nil {
                SoundEngine.shared.playAllow()
                SessionTracker.shared.record(event: "UserPromptSubmit", agent: reply.agent, sessionId: reply.sessionId,
                                             directory: reply.directory, detail: "Continuing with your reply")
            }
            self.activeModel = nil
            cont.resume(returning: result)
            self.busy = false
            self.pump()
        }

        Task { @MainActor [weak model] in
            withAnimation(.linear(duration: timeout)) { model?.remaining = 0 }
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            model?.finish(nil)
        }
    }

    private func showCard(_ model: ReplyModel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let geometry = IslandScreenGeometry(screen: screen)
        SoundEngine.shared.playPopup()
        let panel = FloatingPanel(contentRect: geometry.frame(forContentSize: CGSize(width: 420, height: 300), morphProgress: 0.1))
        let host = NSHostingView(rootView: ReplyCardRoot(model: model, maxHeight: screen.maxCardHeight) { [weak panel] size in
            guard let panel, size != .zero else { return }
            panel.setFrame(geometry.frame(forContentSize: size, morphProgress: 1.0), display: true, animate: true)
        })
        host.sizingOptions = []
        panel.contentView = host
        panel.level = .modalPanel
        // Not made key: keys typed into another app must never land in the reply. Clicking the text
        // box focuses it.
        panel.orderFrontRegardless()
        self.panel = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { model.appeared = true }
        }
    }
}

struct ReplyCardRoot: View {
    @Bindable var model: ReplyModel
    var maxHeight: CGFloat = 640
    var onSize: (CGSize) -> Void

    var body: some View {
        ReplyCard(model: model, maxHeight: maxHeight)
            .background(GeometryReader { Color.clear.preference(key: CardSizeKey.self, value: $0.size) })
            .onPreferenceChange(CardSizeKey.self, perform: onSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct ReplyCard: View {
    @Bindable var model: ReplyModel
    var maxHeight: CGFloat = 640

    var body: some View {
        let pill = PillCatalog.definition(for: model.reply.agent)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
                    Circle().trim(from: 0, to: model.remaining)
                        .stroke(pill.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(pill.color)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.reply.agent) finished")
                        .font(.system(size: 16, weight: .semibold))
                    Text("In \(model.reply.folder) · reply to keep it working")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            CappedScroll(maxHeight: max(120, maxHeight - 260)) {
                Text(model.reply.message)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            TextField("Tell \(model.reply.agent) what to do next…", text: $model.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .lineLimit(2...6)
                .padding(10)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("Reply to \(model.reply.agent)")

            HStack {
                Button("Let it stop") { model.finish(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Send") { model.send() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 28, y: 14)
        }
        .scaleEffect(model.appeared ? 1 : 0.9, anchor: .top)
        .offset(y: model.appeared ? 0 : -24)
        .opacity(model.appeared ? 1 : 0)
    }
}

// MARK: - Dashboard: sessions, pause and reply settings

struct SessionsSection: View {
    @State private var tracker = SessionTracker.shared
    @State private var replyMode = ReplySettings.mode
    @State private var replyWait = ReplySettings.waitMinutes
    @State private var tick = Date()
    private let timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Live sessions").font(.system(size: 15, weight: .semibold))
                let sessions = tracker.visible
                if sessions.isEmpty {
                    Text("No agent sessions yet. They show up here as soon as a connected agent starts working.")
                        .font(.system(size: 12.5)).foregroundStyle(.secondary)
                } else {
                    ForEach(sessions) { s in
                        HStack(spacing: 10) {
                            Circle().fill(color(for: s.state)).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(s.agent) · \(s.folder)").font(.system(size: 13, weight: .medium))
                                Text(s.detail.isEmpty ? s.state.rawValue : "\(s.state.rawValue) · \(s.detail)")
                                    .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(s.lastActivity, style: .relative).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if !tracker.agentsSeen.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pause protection per agent").font(.system(size: 15, weight: .semibold))
                    Text("While paused, low and medium risk requests from that agent are allowed and logged. High-risk requests still ask.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    ForEach(tracker.agentsSeen, id: \.self) { agent in
                        HStack {
                            Text(agent).font(.system(size: 13, weight: .medium))
                            if let text = tracker.pauseText(agent) {
                                Text(text).font(.system(size: 11.5)).foregroundStyle(.orange)
                            }
                            Spacer()
                            if tracker.isPaused(agent) {
                                Button("Resume") { tracker.resume(agent) }
                            } else {
                                Button("10 min") { tracker.pause(agent, minutes: 10) }
                                Button("1 hour") { tracker.pause(agent, minutes: 60) }
                                Button("Until resumed") { tracker.pause(agent, minutes: nil) }
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Reply when an agent finishes").font(.system(size: 15, weight: .semibold))
                Text("Claude Code shows its last message on the card and in loggdin Pocket; what you type keeps it working.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Picker("Ask for a reply", selection: $replyMode) {
                    Text("When I'm away").tag("away")
                    Text("Always").tag("always")
                    Text("Off").tag("off")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                .onChange(of: replyMode) { _, v in ReplySettings.mode = v }
                Stepper("Wait up to \(replyWait) min for a reply", value: $replyWait, in: 1...30)
                    .frame(maxWidth: 360)
                    .onChange(of: replyWait) { _, v in ReplySettings.waitMinutes = v }
            }
        }
        .id(tick)
        .onReceive(timer) { tick = $0 }
    }

    private func color(for state: SessionTracker.State) -> Color {
        switch state {
        case .working: return .green
        case .waiting: return .orange
        case .finished: return .blue
        case .ended: return .secondary
        }
    }
}
