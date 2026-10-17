import Foundation
import AppKit

@MainActor
final class SoundEngine {
    static let shared = SoundEngine()

    var isSoundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "loggdin_sound_enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "loggdin_sound_enabled") }
    }

    var popupSoundName: String {
        get { UserDefaults.standard.string(forKey: "loggdin_popup_sound") ?? "Glass" }
        set { UserDefaults.standard.set(newValue, forKey: "loggdin_popup_sound") }
    }

    private init() {}

    /// Elegant, crystal chime when the notch card appears (Defaults to "Glass", crisp and soothing)
    func playPopup() {
        guard isSoundEnabled else { return }
        if let sound = NSSound(named: popupSoundName) {
            sound.play()
        } else {
            NSSound(named: "Glass")?.play()
        }
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
        NSSound(named: "Ping")?.play()
    }

    private func performHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
