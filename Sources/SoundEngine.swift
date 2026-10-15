import Foundation
import AppKit

@MainActor
final class SoundEngine {
    static let shared = SoundEngine()

    var isSoundEnabled: Bool = true

    private init() {}

    func playPopup() {
        guard isSoundEnabled else { return }
        NSSound(named: "Glass")?.play()
        performHaptic(.alignment)
    }

    func playAllow() {
        guard isSoundEnabled else { return }
        NSSound(named: "Pop")?.play()
        performHaptic(.alignment)
    }

    func playDeny() {
        guard isSoundEnabled else { return }
        NSSound(named: "Basso")?.play()
        performHaptic(.levelChange)
    }

    func playTick() {
        guard isSoundEnabled else { return }
        NSSound(named: "Tink")?.play()
    }

    private func performHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
