import Foundation
import LocalAuthentication

// MARK: - Biometric & System Authentication Manager

@MainActor
public final class BiometricAuthManager: @unchecked Sendable {
    public static let shared = BiometricAuthManager()

    private init() {}

    /// Whether biometric authentication (Touch ID / Face ID) is supported and enrolled
    public var isBiometricAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// User-friendly label for current biometric capability (e.g. Touch ID or Passcode)
    public var biometricName: String {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return "Touch ID"
        }
        return "Password"
    }

    /// Prompt user to authenticate via Touch ID or device passcode
    public func authenticate(reason: String = "Authorize high-risk agent action") async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            ) { success, _ in
                Task { @MainActor in
                    continuation.resume(returning: success)
                }
            }
        }
    }
}
