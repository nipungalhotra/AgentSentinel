import SwiftUI
import AppKit

// MARK: - Face State

enum FaceState: Equatable {
    case idle, pleased, worried, happy, sad, sleepy

    var color: Color {
        switch self {
        case .sad: return Color(red: 0.725, green: 0.404, blue: 0.302)
        case .sleepy: return Color(red: 0.561, green: 0.353, blue: 0.278)
        default: return Color(red: 0.851, green: 0.467, blue: 0.341)
        }
    }

    var eyeHeight: CGFloat {
        switch self {
        case .happy: return 4
        case .sad: return 7
        case .sleepy: return 2
        default: return 9
        }
    }

    var eyeShift: CGFloat {
        switch self {
        case .happy, .sad: return 2
        case .sleepy: return 3
        default: return 0
        }
    }

    var blinks: Bool { self == .idle || self == .pleased || self == .worried }
    var showBrows: Bool { self == .worried || self == .sad }
    var browAngle: Double { self == .sad ? 24 : 16 }
    var cheeks: Bool { self == .happy || self == .pleased }

    var mouthWidth: CGFloat {
        switch self {
        case .idle: return 12
        case .pleased: return 16
        case .happy: return 22
        case .worried: return 10
        case .sad: return 14
        case .sleepy: return 8
        }
    }

    var mouthDepth: CGFloat {
        switch self {
        case .idle, .sleepy: return 0
        case .pleased: return 3
        case .happy: return 8
        case .worried: return -2.5
        case .sad: return -4
        }
    }

    var mouthY: CGFloat {
        switch self {
        case .idle, .sleepy: return 8
        case .pleased: return 7.5
        case .happy: return 6.5
        case .worried: return 10
        case .sad: return 11
        }
    }
}

struct MouthShape: Shape {
    var width: CGFloat
    var depth: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, depth) }
        set { width = newValue.first; depth = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let y = rect.midY
        p.move(to: CGPoint(x: rect.midX - width / 2, y: y))
        p.addQuadCurve(to: CGPoint(x: rect.midX + width / 2, y: y),
                       control: CGPoint(x: rect.midX, y: y + depth * 2))
        return p
    }
}

struct FaceView: View {
    var state: FaceState
    var look: CGSize

    @State private var blink = false
    @State private var zFloat = false
    private let ink = Color(red: 0.17, green: 0.07, blue: 0.03)

    var body: some View {
        ZStack {
            Circle().fill(state.color)
            Circle().strokeBorder(.white.opacity(0.4), lineWidth: 0.8)

            Ellipse()
                .fill(.white.opacity(0.45))
                .frame(width: 15, height: 7)
                .rotationEffect(.degrees(-20))
                .offset(x: -9, y: -16)
                .blur(radius: 1)

            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse()
                    .fill(Color(red: 1, green: 0.6, blue: 0.64))
                    .frame(width: 8, height: 5)
                    .offset(x: side * 15, y: 8.5)
                    .opacity(state.cheeks ? 0.55 : 0)

                Capsule()
                    .fill(ink)
                    .frame(width: 9, height: 2)
                    .rotationEffect(.degrees(state.browAngle * side))
                    .offset(x: side * 8.5, y: -12)
                    .opacity(state.showBrows ? 1 : 0)
            }

            HStack(spacing: 12) {
                eye
                eye
            }
            .offset(x: look.width * 3, y: -1.5 + look.height * 3 + state.eyeShift)

            MouthShape(width: state.mouthWidth, depth: state.mouthDepth)
                .stroke(ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 30, height: 20)
                .offset(y: state.mouthY)

            Text("zZ")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .offset(x: 28, y: -28 + (zFloat ? -4 : 0))
                .opacity(state == .sleepy ? 1 : 0)
        }
        .frame(width: 48, height: 48)
        .shadow(color: state.color.opacity(0.4), radius: 8, y: 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: state)
        .animation(.easeOut(duration: 0.12), value: look)
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { zFloat = true }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 2.5...5)))
                withAnimation(.easeInOut(duration: 0.07)) { blink = true }
                try? await Task.sleep(for: .milliseconds(110))
                withAnimation(.easeInOut(duration: 0.09)) { blink = false }
            }
        }
    }

    private var eye: some View {
        Capsule()
            .fill(ink)
            .frame(width: 7, height: state.eyeHeight)
            .scaleEffect(y: (blink && state.blinks) ? 0.1 : 1)
    }
}

struct FaceFX {
    var scale = 1.0
    var rotation = 0.0
    var x = 0.0
}

extension View {
    func faceEffects(pop: Int, wiggle: Int, shake: Int) -> some View {
        self
            .keyframeAnimator(initialValue: FaceFX(), trigger: pop) { content, v in
                content.scaleEffect(v.scale)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    MoveKeyframe(0.5)
                    SpringKeyframe(1.0, duration: 0.55, spring: .bouncy(duration: 0.55, extraBounce: 0.2))
                }
            }
            .keyframeAnimator(initialValue: FaceFX(), trigger: wiggle) { content, v in
                content.rotationEffect(.degrees(v.rotation)).scaleEffect(v.scale)
            } keyframes: { _ in
                KeyframeTrack(\.rotation) {
                    LinearKeyframe(-12, duration: 0.1)
                    LinearKeyframe(12, duration: 0.2)
                    LinearKeyframe(-12, duration: 0.2)
                    LinearKeyframe(12, duration: 0.2)
                    LinearKeyframe(0, duration: 0.1)
                }
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.1, duration: 0.2)
                    CubicKeyframe(1.1, duration: 0.6)
                    CubicKeyframe(1.0, duration: 0.2)
                }
            }
            .keyframeAnimator(initialValue: FaceFX(), trigger: shake) { content, v in
                content.offset(x: v.x)
            } keyframes: { _ in
                KeyframeTrack(\.x) {
                    LinearKeyframe(-3, duration: 0.07)
                    LinearKeyframe(3, duration: 0.14)
                    LinearKeyframe(-3, duration: 0.14)
                    LinearKeyframe(0, duration: 0.07)
                }
            }
    }
}

struct SparkleBurst: View {
    let color: Color
    @State private var fly = false

    var body: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                let angle = Double(i) / 10 * .pi * 2
                let distance = 30.0 + Double(i % 2) * 9
                Circle()
                    .fill(i % 3 == 0 ? Color.white : color)
                    .frame(width: 5, height: 5)
                    .offset(x: fly ? cos(angle) * distance : 0,
                            y: fly ? sin(angle) * distance : 0)
                    .scaleEffect(fly ? 0.2 : 1)
                    .opacity(fly ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) { fly = true }
        }
    }
}

// MARK: - Glass Helpers

extension View {
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
        } else {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.28), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        }
    }

    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: .capsule)
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1))
        }
    }

    @ViewBuilder
    func glassButton(prominent: Bool) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Permission Model

@MainActor @Observable
final class PermissionModel {
    enum Phase: Equatable { case asking, resolved(Decision) }
    enum HoverTarget { case allow, deny }

    let request: PermissionRequest

    var scope: AllowScope = .once
    var face: FaceState = .idle
    var phase: Phase = .asking
    var detailsOpen = false
    var warn = false
    var appeared = false
    var ringRemaining: CGFloat = 1
    var holdProgress: CGFloat = 0
    var popTrigger = 0
    var wiggleTrigger = 0
    var shakeTrigger = 0
    var burstID: Int?

    @ObservationIgnored var onFinish: ((Decision) -> Void)?
    @ObservationIgnored private var runner: Task<Void, Never>?
    @ObservationIgnored private var burstCount = 0

    init(request: PermissionRequest) {
        self.request = request
    }

    var isAsking: Bool {
        if case .asking = phase { return true }
        return false
    }

    var isHigh: Bool { request.risk == .high }
    var timeout: Double { isHigh ? 30 : 20 }
    var baseFace: FaceState { (warn || isHigh) ? .worried : .idle }

    var titleText: String {
        switch phase {
        case .asking: return request.title
        case .resolved(.allow): return "Allowed"
        case .resolved(.deny): return "Denied"
        case .resolved(.timeout): return "Timed out"
        }
    }

    var subtitleText: String {
        switch phase {
        case .asking: return request.subtitle
        case .resolved(.allow(let scope)): return scope.resolvedText
        case .resolved(.deny): return "Nothing was run"
        case .resolved(.timeout): return "Treated as denied"
        }
    }

    var ringColor: Color {
        switch phase {
        case .resolved(.allow): return .green
        case .resolved(.deny): return .red
        case .resolved(.timeout): return .gray
        case .asking:
            if warn { return .orange }
            return isHigh ? .red : Color(red: 0.851, green: 0.467, blue: 0.341)
        }
    }

    func start() {
        runner?.cancel()
        runner = Task { [weak self] in
            guard let self else { return }
            guard await Self.pause(0.2) else { return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) { appeared = true }
            popTrigger += 1
            face = baseFace

            guard await Self.pause(0.7) else { return }
            withAnimation(.linear(duration: timeout)) { ringRemaining = 0 }

            guard await Self.pause(timeout - 5) else { return }
            warn = true
            face = .worried

            guard await Self.pause(5) else { return }
            decide(.timeout)
        }
    }

    func decide(_ decision: Decision) {
        guard isAsking else { return }
        runner?.cancel()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { phase = .resolved(decision) }

        switch decision {
        case .allow:
            face = .happy
            wiggleTrigger += 1
            burstCount += 1
            burstID = burstCount
        case .deny:
            face = .sad
            shakeTrigger += 1
        case .timeout:
            face = .sleepy
            popTrigger += 1
        }
        withAnimation(.easeOut(duration: 0.4)) { ringRemaining = 1 }

        runner = Task { [weak self] in
            guard await Self.pause(2.0) else { return }
            guard let self else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { appeared = false }
            guard await Self.pause(0.55) else { return }
            onFinish?(decision)
        }
    }

    func hovering(_ target: HoverTarget, _ over: Bool) {
        guard isAsking else { return }
        if over {
            face = (target == .allow && !isHigh) ? .pleased : .worried
        } else {
            face = baseFace
        }
    }

    func stepScope(_ delta: Int) {
        guard isAsking, !isHigh else { return }
        let all = AllowScope.allCases
        guard let i = all.firstIndex(of: scope) else { return }
        let next = min(max(i + delta, 0), all.count - 1)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { scope = all[next] }
    }

    func holdChanged(pressing: Bool) {
        guard isAsking, isHigh else { return }
        if pressing {
            face = .worried
            shakeTrigger += 1
            withAnimation(.linear(duration: 1.0)) { holdProgress = 1 }
        } else {
            withAnimation(.easeOut(duration: 0.25)) { holdProgress = 0 }
        }
    }

    func holdCompleted() {
        decide(.allow(.once))
    }

    func authenticateWithTouchID() {
        guard isAsking, isHigh else { return }
        Task {
            let success = await BiometricAuthManager.shared.authenticate(
                reason: "Authorize high-risk action: \(request.plainCommand)"
            )
            if success {
                SoundEngine.shared.playAllow()
                decide(.allow(.once))
            }
        }
    }

    nonisolated private static func pause(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(max(seconds, 0)))
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

// MARK: - Root & Card

struct CardSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

struct PermissionPopupRoot: View {
    @Bindable var model: PermissionModel
    var geometry: IslandScreenGeometry? = nil
    var onSize: (CGSize) -> Void

    var body: some View {
        PermissionCard(model: model, geometry: geometry)
            .background(GeometryReader { Color.clear.preference(key: CardSizeKey.self, value: $0.size) })
            .onPreferenceChange(CardSizeKey.self, perform: onSize)
            .padding(PermissionPopupController.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct PermissionCard: View {
    @Bindable var model: PermissionModel
    var geometry: IslandScreenGeometry? = nil
    @State private var look: CGSize = .zero
    @State private var copiedCommand = false
    @FocusState private var focused: Bool

    private let faceCenter = CGPoint(x: 44, y: 44)

    var body: some View {
        let pill = PillCatalog.definition(for: model.request.requestedBy)
        VStack(spacing: 0) {
            if geometry?.mode == .physicalNotch {
                // Notch Bridge Anchor (Physical Notch Hugger for MacBook Pro/Air)
                ZStack {
                    Capsule()
                        .fill(Color.black)
                        .frame(width: max(geometry?.notchWidth ?? 154, 154), height: 7)
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
                        .frame(width: max(geometry?.notchWidth ?? 154, 154), height: 7)
                    Circle()
                        .fill(Color(white: 0.2))
                        .frame(width: 4, height: 4)
                }
                .offset(y: -7)
            } else {
                // Universal Dynamic Island Pill (External monitors, Windows, Linux)
                Capsule()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: 70, height: 4)
                    .offset(y: -6)
            }

            header

            if model.isAsking {
                VStack(spacing: 12) {
                    commandBox
                    if model.detailsOpen { details }
                    ScopePicker(selection: $model.scope, locked: model.isHigh)
                    actions.padding(.top, 4)
                }
                .padding(.top, 14)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(width: 400)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
                // Specular rim gradient border (outer)
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.55), .white.opacity(0.18), .clear, .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
                // Specular rim gradient border (inner reflection sheen)
                RoundedRectangle(cornerRadius: 31, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.24), .clear, .white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
                    .padding(1)
                // Dynamic ambient glow matching agent pill color
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [pill.color.opacity(model.isHigh ? 0.28 : 0.16), .clear],
                            center: .topLeading,
                            startRadius: 20,
                            endRadius: 320
                        )
                    )
            }
            .shadow(color: .black.opacity(0.4), radius: 32, y: 16)
            .shadow(color: pill.color.opacity(model.isHigh ? 0.35 : 0.18), radius: 24, y: 8)
        }
        .scaleEffect(model.appeared ? 1 : 0.88, anchor: .top)
        .offset(y: model.appeared ? 0 : -26)
        .opacity(model.appeared ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: model.isAsking)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: model.detailsOpen)
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                let dx = p.x - faceCenter.x, dy = p.y - faceCenter.y
                let d = max(hypot(dx, dy), 1)
                let k = min(1, d / 54)
                look = CGSize(width: dx / d * k, height: dy / d * k)
            case .ended:
                look = .zero
            }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.leftArrow) {
            guard model.isAsking, !model.isHigh else { return .ignored }
            model.stepScope(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard model.isAsking, !model.isHigh else { return .ignored }
            model.stepScope(1)
            return .handled
        }
    }

    private var header: some View {
        let pill = PillCatalog.definition(for: model.request.requestedBy)
        return HStack(spacing: 14) {
            orb

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.titleText)
                        .font(.system(size: 17, weight: .semibold))
                        .contentTransition(.opacity)

                    // Agent Brand Pill Badge
                    HStack(spacing: 4) {
                        Image(systemName: pill.iconSystemName)
                            .font(.system(size: 10, weight: .bold))
                        Text(pill.name)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(pill.color.opacity(0.18), in: Capsule())
                    .overlay(Capsule().strokeBorder(pill.color.opacity(0.4), lineWidth: 0.8))
                    .foregroundStyle(pill.color)
                }

                HStack(spacing: 8) {
                    Text(model.subtitleText)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                    if model.isAsking {
                        RiskChip(risk: model.request.risk)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.2), value: model.titleText)
    }

    private var orb: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
                .frame(width: 58, height: 58)
            Circle()
                .trim(from: 0, to: model.ringRemaining)
                .stroke(model.ringColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 58, height: 58)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: model.ringColor)

            FaceView(state: model.face, look: look)
                .faceEffects(pop: model.popTrigger, wiggle: model.wiggleTrigger, shake: model.shakeTrigger)

            if let id = model.burstID {
                SparkleBurst(color: .green).id(id)
            }
        }
        .frame(width: 48, height: 48)
    }

    private var commandBox: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Circle().fill(Color(red: 1, green: 0.36, blue: 0.34)).frame(width: 7.5, height: 7.5)
                Circle().fill(Color(red: 1, green: 0.76, blue: 0.2)).frame(width: 7.5, height: 7.5)
                Circle().fill(Color(red: 0.18, green: 0.82, blue: 0.38)).frame(width: 7.5, height: 7.5)

                Text(model.request.requestedBy.lowercased())
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 3)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.request.plainCommand, forType: .string)
                    copiedCommand = true
                    SoundEngine.shared.playTick()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        copiedCommand = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copiedCommand ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 8.5, weight: .bold))
                        Text(copiedCommand ? "Copied" : "Copy")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundStyle(copiedCommand ? Color.green : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    model.detailsOpen.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Text(model.detailsOpen ? "Hide" : "Details")
                            .font(.system(size: 9.5, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .rotationEffect(.degrees(model.detailsOpen ? 180 : 0))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Image(systemName: model.request.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(model.request.commandText)
                    .font(.system(size: 12.5, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
        )
    }

    private var details: some View {
        VStack(spacing: 2) {
            detailRow("Requested by", model.request.requestedBy)
            detailRow("Directory", model.request.directory)
            detailRow("Modifies files", model.request.modifiesFiles)
        }
        .padding(.horizontal, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.system(size: 12.5))
        .frame(height: 22)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                model.decide(.deny)
            } label: {
                HStack(spacing: 7) {
                    Text("Deny").font(.system(size: 14, weight: .semibold))
                    KeyHint("esc")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .keyboardShortcut(.cancelAction)
            .glassButton(prominent: false)
            .buttonBorderShape(.capsule)
            .onHover { model.hovering(.deny, $0) }

            if model.isHigh {
                HStack(spacing: 8) {
                    HoldToConfirmButton(model: model, title: "Hold to allow")

                    if BiometricAuthManager.shared.isBiometricAvailable {
                        Button {
                            model.authenticateWithTouchID()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "touchid")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.orange)
                                Text("Touch ID")
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                            .frame(height: 38)
                            .padding(.horizontal, 10)
                        }
                        .glassCapsule(tint: Color.orange.opacity(0.18), interactive: true)
                        .buttonStyle(.plain)
                        .help("Authorize with Touch ID or Passcode")
                    }
                }
            } else {
                Button {
                    model.decide(.allow(model.scope))
                } label: {
                    HStack(spacing: 7) {
                        Text(model.scope.allowLabel).font(.system(size: 14, weight: .semibold))
                        KeyHint("\u{21A9}")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                }
                .keyboardShortcut(.defaultAction)
                .glassButton(prominent: true)
                .buttonBorderShape(.capsule)
                .tint(.blue)
                .onHover { model.hovering(.allow, $0) }
            }
        }
    }
}

struct RiskChip: View {
    let risk: Risk

    var body: some View {
        Text(risk.label)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 2)
            .foregroundStyle(risk.color)
            .background(risk.color.opacity(0.2), in: Capsule())
    }
}

struct KeyHint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct ScopePicker: View {
    @Binding var selection: AllowScope
    var locked: Bool
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AllowScope.allCases) { scope in
                let disabled = locked && scope != .once
                Text(scope.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selection == scope ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background {
                        if selection == scope {
                            Capsule()
                                .fill(Color.primary.opacity(0.14))
                                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                                .matchedGeometryEffect(id: "thumb", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { selection = scope }
                    }
                    .opacity(disabled ? 0.3 : 1)
                    .allowsHitTesting(!disabled)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .help(locked ? "High-risk actions can only be allowed once" : "")
    }
}

struct HoldToConfirmButton: View {
    @Bindable var model: PermissionModel
    let title: String

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let fillWidth = max(0, geo.size.width * model.holdProgress)
                ZStack(alignment: .leading) {
                    LinearGradient(
                        colors: [Color.red.opacity(0.85), Color.red, Color.orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: fillWidth)

                    if model.holdProgress > 0 && model.holdProgress < 1 {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 4)
                            .offset(x: max(0, fillWidth - 4))
                            .blur(radius: 1.2)
                    }
                }
            }
            .clipShape(Capsule())

            HStack(spacing: 7) {
                Text(title).font(.system(size: 14, weight: .semibold))
                KeyHint("hold")
            }
            .foregroundStyle(model.holdProgress > 0.55 ? Color.white : Color.red)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .glassCapsule(tint: Color.red.opacity(0.25), interactive: true)
        .contentShape(Capsule())
        .onHover { model.hovering(.allow, $0) }
        .onLongPressGesture(minimumDuration: 1.0, maximumDistance: 60) {
            SoundEngine.shared.playAllow()
            model.holdCompleted()
        } onPressingChanged: { pressing in
            if pressing {
                SoundEngine.shared.playTick()
            }
            model.holdChanged(pressing: pressing)
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Panel + Controller

final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Allow panel to hug the notch and menu bar area without macOS forcing it down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

@MainActor
final class PermissionPopupController {
    static let shared = PermissionPopupController()
    static let margin: CGFloat = 28

    private var panel: FloatingPanel?
    private var queue: [(PermissionRequest, CheckedContinuation<Decision, Never>)] = []
    private var busy = false

    func ask(_ request: PermissionRequest) async -> Decision {
        await withCheckedContinuation { continuation in
            queue.append((request, continuation))
            pump()
        }
    }

    private func pump() {
        guard !busy, !queue.isEmpty else { return }
        busy = true
        let (request, continuation) = queue.removeFirst()
        present(request) { [weak self] decision in
            continuation.resume(returning: decision)
            self?.busy = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                self?.pump()
            }
        }
    }

    private func present(_ request: PermissionRequest, completion: @escaping (Decision) -> Void) {
        let model = PermissionModel(request: request)
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        let geometry = IslandScreenGeometry(screen: screen)
        SoundEngine.shared.playPopup()

        let initialRect = geometry.frame(forContentSize: CGSize(width: 400, height: 280), margin: Self.margin, morphProgress: 0.1)
        let panel = FloatingPanel(contentRect: initialRect)

        let host = NSHostingView(rootView: PermissionPopupRoot(model: model, geometry: geometry) { [weak panel] size in
            guard let panel, size != .zero else { return }
            let targetRect = geometry.frame(forContentSize: size, margin: Self.margin, morphProgress: 1.0)
            panel.setFrame(targetRect, display: true, animate: true)
        })
        host.sizingOptions = []
        panel.contentView = host

        model.onFinish = { [weak self] decision in
            if decision.isAllowed {
                SoundEngine.shared.playAllow()
            } else {
                SoundEngine.shared.playDeny()
            }
            panel.orderOut(nil)
            self?.panel = nil
            completion(decision)
        }

        self.panel = panel
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.start()
    }
}
