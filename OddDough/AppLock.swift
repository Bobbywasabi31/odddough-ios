import SwiftUI
import LocalAuthentication
import UIKit

/// Enforces the web UI's app-lock setting (UserDefaults "odddough.applock",
/// written through the bridge's setAppLock and reported by appLockStatus).
/// Until 2026-11-01 the flag was stored and reported but never enforced —
/// the app opened straight into the user's financial data. Now a cold
/// start with the lock on begins locked, and the app re-locks whenever it
/// resigns active (which also keeps the app-switcher snapshot private).
final class AppLockManager: ObservableObject {
    @Published var locked: Bool
    private var authenticating = false
    private var observers: [NSObjectProtocol] = []

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "odddough.applock")
    }

    init() {
        locked = AppLockManager.isEnabled
        let lockIfEnabled: (Notification) -> Void = { [weak self] _ in
            if AppLockManager.isEnabled { self?.locked = true }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main, using: lockIfEnabled))
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main, using: lockIfEnabled))
    }

    func authenticate() {
        guard !authenticating else { return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode or biometrics configured on the device: there is
            // nothing to verify against, so don't lock the owner out of
            // their own data. (appLockStatus reports mode "none" here.)
            locked = false
            return
        }
        authenticating = true
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: "Unlock OddDough") { [weak self] success, _ in
            DispatchQueue.main.async {
                self?.authenticating = false
                if success { self?.locked = false }
            }
        }
    }
}

/// Full-screen gate shown while locked. Auto-prompts on appear; the
/// button re-prompts after a cancel or failure.
struct LockScreen: View {
    @ObservedObject var lock: AppLockManager

    var body: some View {
        VStack(spacing: 16) {
            Text("🔒").font(.system(size: 44))
            Text("OddDough is locked").font(.headline)
            Text("Use Face ID or your passcode to continue.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Unlock") { lock.authenticate() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.973, green: 0.965, blue: 0.957)) // #F8F7F4, the app background
        .onAppear { lock.authenticate() }
    }
}
