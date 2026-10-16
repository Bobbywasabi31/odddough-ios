import SwiftUI
import UIKit

/// Relays home-screen Quick Actions ("Add expense" / "Add income",
/// Android's launcher shortcuts) into the web UI's window.cashCompassShortcut.
/// The web view may not be loaded yet when the action fires, so a pending
/// kind is stashed and delivered on page load.
final class ShortcutRelay {
    static let shared = ShortcutRelay()
    private init() {}

    /// Set by the WebView coordinator when it's ready to receive.
    var deliver: ((String) -> Void)?
    private var pending: String?

    func handle(kind: String) {
        if let deliver {
            deliver(kind)
        } else {
            pending = kind
        }
    }

    func takePending() -> String? {
        defer { pending = nil }
        return pending
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    private func kind(for item: UIApplicationShortcutItem) -> String {
        item.type.hasSuffix("add-income") ? "income" : "expense"
    }

    // Cold start from a Quick Action.
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem {
            ShortcutRelay.shared.handle(kind: kind(for: item))
        }
        return UISceneConfiguration(name: "Default Configuration",
                                      sessionRole: connectingSceneSession.role)
    }

    // Quick Action while the app is running.
    func application(_ application: UIApplication,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        ShortcutRelay.shared.handle(kind: kind(for: shortcutItem))
        completionHandler(true)
    }
}

@main
struct OddDoughApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            WebViewContainer()
                .ignoresSafeArea(.keyboard)
        }
    }
}
