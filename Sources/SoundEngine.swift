import Foundation
import AppKit

@MainActor
final class SoundEngine {
    static let shared = SoundEngine()

    var isSoundEnabled: Bool = true

    private init() {}

    /// Elegant, subtle chime when the notch card appears (Tink is gentle and crisp, not harsh)
    func playPopup() {
        guard isSoundEnabled else { return }
        NSSound(named: "Tink")?.play()
        performHaptic(.alignment)
    }

    /// Delightful soft bubble pop when action is allowed
    func playAllow() {
        guard isSoundEnabled else { return }
        NSSound(named: "Pop")?.play()
        performHaptic(.alignment)
    }

    /// Soft, low feedback on denial (Purr / gentle haptic, no harsh buzz)
    func playDeny() {
        guard isSoundEnabled else { return }
        NSSound(named: "Purr")?.play()
        performHaptic(.levelChange)
    }

    /// Subtle mechanical click
    func playTick() {
        guard isSoundEnabled else { return }
        NSSound(named: "Tink")?.play()
    }

    private func performHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
