import AppKit
import SwiftUI

// MARK: - Agent questions and "waiting for you" notices
//
// When an agent asks the user a multiple-choice question (Claude Code's AskUserQuestion), the hook
// sends it here instead of letting it sit in a terminal nobody is watching. It is shown where the
// Ask-on setting says (notch card at the Mac, loggdin Pocket when away) and the chosen labels go back
// to the agent as its answer. "Answer in terminal" or no answer in time returns nil, and the agent
// shows its own question box as before. Notices are one-way: "Claude Code is waiting for you".

struct AgentQuestion {
    struct Option { let label: String; let description: String }
    struct Item { let question: String; let header: String; let multiSelect: Bool; let options: [Option] }

    let id = UUID().uuidString
    let agent: String
    let directory: String
    let items: [Item]

    /// loggdin Pocket can answer one single-choice question; anything else is answered on the Mac.
    var phoneAnswerable: Bool { items.count == 1 && !items[0].multiSelect }

    var folder: String {
        let last = (directory as NSString).lastPathComponent
        return last.isEmpty || directory == "~" ? "your home folder" : last
    }

    init?(json: [String: Any]) {
        agent = (json["agent"] as? String) ?? "An agent"
        directory = (json["directory"] as? String) ?? "~"
        items = ((json["questions"] as? [[String: Any]]) ?? []).prefix(4).compactMap { q in
            guard let text = q["question"] as? String else { return nil }
            let options = ((q["options"] as? [[String: Any]]) ?? []).prefix(6).compactMap { o -> Option? in
                guard let label = o["label"] as? String, !label.isEmpty else { return nil }
                return Option(label: label, description: (o["description"] as? String) ?? "")
            }
            return options.isEmpty ? nil : Item(question: text, header: (q["header"] as? String) ?? "",
                                                multiSelect: (q["multiSelect"] as? Bool) ?? false, options: Array(options))
        }
        if items.isEmpty { return nil }
    }
}

@MainActor @Observable
final class QuestionModel {
    let question: AgentQuestion
    var index = 0
    var answers: [String: String] = [:]
    var picked: Set<Int> = []
    var appeared = false
    var remaining: Double = 1
    var onFinish: (([String: String]?) -> Void)?

    init(question: AgentQuestion) { self.question = question }

    var item: AgentQuestion.Item { question.items[index] }

    func choose(_ option: Int) {
        if item.multiSelect {
            if picked.contains(option) { picked.remove(option) } else { picked.insert(option) }
            return
        }
        record([option])
    }

    func confirmMulti() {
        guard !picked.isEmpty else { return }
        record(picked.sorted())
    }

    private func record(_ options: [Int]) {
        answers[item.question] = options.map { item.options[$0].label }.joined(separator: ", ")
        picked = []
        if index + 1 < question.items.count {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { index += 1 }
        } else {
            finish(answers)
        }
    }

    func finish(_ result: [String: String]?) {
        let done = onFinish
        onFinish = nil
        done?(result)
    }
}

@MainActor
final class QuestionController {
    static let shared = QuestionController()

    private var queue: [(AgentQuestion, CheckedContinuation<[String: String]?, Never>)] = []
    private var busy = false
    private var activeModel: QuestionModel?
    private var panel: FloatingPanel?

    /// Shows the question and returns the chosen answers, or nil to let the agent ask in its own UI.
    func ask(_ question: AgentQuestion) async -> [String: String]? {
        await withCheckedContinuation { cont in
            queue.append((question, cont))
            pump()
        }
    }

    func isAsking(id: String) -> Bool { activeModel?.question.id == id }

    /// An option tapped in loggdin Pocket (single-question requests only).
    @discardableResult
    func submitFromPhone(id: String, option: Int) -> Bool {
        guard let model = activeModel, model.question.id == id, model.question.items.count == 1,
              model.item.options.indices.contains(option) else { return false }
        model.answers[model.item.question] = model.item.options[option].label
        model.finish(model.answers)
        return true
    }

    private func pump() {
        guard !busy, !queue.isEmpty else { return }
        busy = true
        let (question, cont) = queue.removeFirst()
        let model = QuestionModel(question: question)
        activeModel = model
        let timeout: Double = PhoneRelay.shared.isActive ? 110 : 60

        // Phone only still shows the card when the phone can't answer this question.
        let phoneOnly = PhoneRelay.shared.isPhoneOnly && question.phoneAnswerable
        if !phoneOnly { showCard(model) }
        PhoneRelay.shared.questionPresented(question, forceNow: phoneOnly)

        model.onFinish = { [weak self] result in
            guard let self else { return }
            if let panel = self.panel {
                panel.orderOut(nil)
                panel.contentView = nil
                panel.close()
                self.panel = nil
            }
            PhoneRelay.shared.questionFinished(question)
            if result != nil { SoundEngine.shared.playAllow() }
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

    private func showCard(_ model: QuestionModel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let geometry = IslandScreenGeometry(screen: screen)
        SoundEngine.shared.playPopup()
        let panel = FloatingPanel(contentRect: geometry.frame(forContentSize: CGSize(width: 400, height: 300), morphProgress: 0.1))
        let host = NSHostingView(rootView: QuestionCardRoot(model: model) { [weak panel] size in
            guard let panel, size != .zero else { return }
            panel.setFrame(geometry.frame(forContentSize: size, morphProgress: 1.0), display: true, animate: true)
        })
        host.sizingOptions = []
        panel.contentView = host
        panel.level = .modalPanel
        // Not made key: a question must never be answered by keys typed into another app. Clicking the
        // card focuses it, and then 1-4, Return and Esc work.
        panel.orderFrontRegardless()
        self.panel = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { model.appeared = true }
        }
    }
}

struct QuestionCardRoot: View {
    @Bindable var model: QuestionModel
    var onSize: (CGSize) -> Void

    var body: some View {
        QuestionCard(model: model)
            .background(GeometryReader { Color.clear.preference(key: CardSizeKey.self, value: $0.size) })
            .onPreferenceChange(CardSizeKey.self, perform: onSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct QuestionCard: View {
    @Bindable var model: QuestionModel
    @FocusState private var focused: Bool

    var body: some View {
        let pill = PillCatalog.definition(for: model.question.agent)
        let item = model.item
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
                    Circle().trim(from: 0, to: model.remaining)
                        .stroke(pill.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "questionmark.bubble.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(pill.color)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(model.question.agent) asks")
                            .font(.system(size: 16, weight: .semibold))
                        if !item.header.isEmpty {
                            Text(item.header)
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 7).padding(.vertical, 2.5)
                                .background(pill.color.opacity(0.18), in: Capsule())
                                .foregroundStyle(pill.color)
                        }
                    }
                    Text(model.question.items.count > 1
                         ? "In \(model.question.folder) · question \(model.index + 1) of \(model.question.items.count)"
                         : "In \(model.question.folder)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text(item.question)
                .font(.system(size: 14.5, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(Array(item.options.enumerated()), id: \.offset) { i, option in
                    Button { model.choose(i) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .frame(width: 20, height: 20)
                                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label).font(.system(size: 13.5, weight: .semibold))
                                if !option.description.isEmpty {
                                    Text(option.description)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 0)
                            if item.multiSelect {
                                Image(systemName: model.picked.contains(i) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(model.picked.contains(i) ? pill.color : .secondary)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(model.picked.contains(i) ? 0.12 : 0.06),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.description.isEmpty ? option.label : "\(option.label). \(option.description)")
                }
            }

            HStack {
                Button("Answer in terminal") { model.finish(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if item.multiSelect {
                    Button("Done") { model.confirmMulti() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(model.picked.isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 400)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 28, y: 14)
        }
        .scaleEffect(model.appeared ? 1 : 0.9, anchor: .top)
        .offset(y: model.appeared ? 0 : -24)
        .opacity(model.appeared ? 1 : 0)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress { press in
            guard let n = Int(press.characters), n >= 1, n <= item.options.count else { return .ignored }
            model.choose(n - 1)
            return .handled
        }
    }
}

// MARK: - Notices

@MainActor
final class NoticeController {
    static let shared = NoticeController()
    private var panel: FloatingPanel?
    private var hideTask: Task<Void, Never>?
    private var recent: [String: Date] = [:]

    /// "Claude Code is waiting for you": a short notch notice at the Mac, and loggdin Pocket when away.
    func show(agent: String, title: String, message: String, directory: String) {
        // Agents repeat themselves: show the same alert at most once every 30 seconds.
        let key = "\(agent)|\(title)|\(message)"
        let now = Date()
        recent = recent.filter { now.timeIntervalSince($0.value) < 30 }
        if recent[key] != nil { return }
        recent[key] = now

        PhoneRelay.shared.noticePresented(agent: agent, title: title, message: message, directory: directory)
        // Never cover a card that is waiting for an answer, and stay quiet in phone-only mode.
        guard !PhoneRelay.shared.isPhoneOnly, PermissionPopupController.shared.currentPendingRequest() == nil else { return }

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let geometry = IslandScreenGeometry(screen: screen)
        hideTask?.cancel()
        panel?.orderOut(nil)

        let size = CGSize(width: 360, height: 76)
        let panel = FloatingPanel(contentRect: geometry.frame(forContentSize: size))
        panel.contentView = NSHostingView(rootView: NoticeView(agent: agent, title: title, message: message) { [weak self] in
            self?.hide()
        })
        panel.level = .statusBar
        panel.orderFrontRegardless()
        self.panel = panel
        SoundEngine.shared.playTick()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if !Task.isCancelled { self?.hide() }
        }
    }

    private func hide() {
        hideTask?.cancel()
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }
}

struct NoticeView: View {
    let agent: String
    let title: String
    let message: String
    var onClose: () -> Void
    @UIState private var shown = false

    var body: some View {
        let pill = PillCatalog.definition(for: agent)
        Button(action: onClose) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(pill.color)
                    .frame(width: 32, height: 32)
                    .background(pill.color.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(agent) \(title)").font(.system(size: 13.5, weight: .semibold))
                    Text(message).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(width: 360, height: 76, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.3), lineWidth: 1)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(agent) \(title). \(message)")
        .scaleEffect(shown ? 1 : 0.92, anchor: .top)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { shown = true } }
    }
}
