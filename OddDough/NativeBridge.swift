import Foundation
import WebKit
import UserNotifications
import LocalAuthentication
import UIKit
import UniformTypeIdentifiers

/// iOS mirror of Android's `NativeBridge` (MainActivity.Bridge).
/// The web UI (www/*) is shared verbatim with the Android app; this class
/// reimplements every bridge method against iOS APIs.
///
/// Two channels (see BridgeShim.js):
///  - SYNC: invoked via window.prompt() interception in the WKUIDelegate.
///    Must be fast and must never present UI.
///  - ASYNC: invoked via window.webkit.messageHandlers.odddoughAsync.
///    May present UI; results return through window.cashCompass* callbacks.
final class NativeBridge: NSObject {

    weak var webView: WKWebView?

    /// Cached notification authorization (refreshed at startup and after
    /// requestNotifications). getNotificationSettings has no synchronous
    /// form, and blocking the main thread for it risks deadlock, so the
    /// sync bridge method serves the cached value.
    private var cachedNotificationsAllowed = false

    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] s in
            self?.cachedNotificationsAllowed = s.authorizationStatus == .authorized
                || s.authorizationStatus == .provisional
        }
    }

    /// Resolved lazily from the responder chain — there is no view controller
    /// to hold at WKWebView creation time under the SwiftUI App lifecycle.
    private func presentingVC() -> UIViewController? {
        var responder: UIResponder? = webView
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }

    // MARK: - Helpers

    /// Encode a return value the way the shim expects: JSON text that the
    /// shim JSON.parses back into a JS value.
    private func encode(_ value: Any?) -> String {
        if value == nil { return "null" }
        if let b = value as? Bool { return b ? "true" : "false" }
        if let s = value as? String,
           let data = try? JSONSerialization.data(withJSONObject: [s]),
           var text = String(data: data, encoding: .utf8) {
            // ["s"] -> "s"
            text.removeFirst(); text.removeLast()
            return text
        }
        return "null"
    }

    /// Quote a Swift string as a JS single-quoted string literal.
    private func jsQuote(_ s: String) -> String {
        "'" + s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            + "'"
    }

    private func jsCallback(_ function: String, _ argument: String) {
        let script = "window.\(function) && window.\(function)(\(argument));"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    private func notice(_ text: String) { jsCallback("cashCompassNotice", jsQuote(text)) }

    private func arg(_ args: [Any], _ i: Int) -> Any? { i < args.count ? args[i] : nil }
    private func strArg(_ args: [Any], _ i: Int) -> String? { arg(args, i) as? String }
    private func boolArg(_ args: [Any], _ i: Int) -> Bool { (arg(args, i) as? Bool) ?? false }

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Sync dispatch (prompt() interception)

    func handleSync(method: String, args: [Any]) -> String {
        switch method {
        case "aiKeyLoad": return encode(SecureStore.load(account: SecureStore.Account.aiKey))
        case "aiKeySave":
            let ok = SecureStore.save(strArg(args, 0) ?? "", account: SecureStore.Account.aiKey)
            return encode(ok ? "ok" : nil)

        case "appVersion":
            let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            let c = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
            return encode("{\"versionName\":\(jsonString(v)),\"versionCode\":\(c)}")

        case "appLockStatus":
            let enabled = UserDefaults.standard.bool(forKey: "odddough.applock")
            let mode = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) ? "biometric" : "none"
            return encode("{\"enabled\":\(enabled),\"mode\":\(jsonString(mode))}")
        case "setAppLock":
            UserDefaults.standard.set(boolArg(args, 0), forKey: "odddough.applock")
            return encode(true)

        case "secureStateLoad": return encode(SecureStore.load(account: SecureStore.Account.secureState))
        case "secureStateSave": return encode(SecureStore.save(strArg(args, 0) ?? "", account: SecureStore.Account.secureState))
        case "secureAutoLoad": return encode(SecureStore.load(account: SecureStore.Account.autoBackup))
        case "secureAutoSave": return encode(SecureStore.save(strArg(args, 0) ?? "", account: SecureStore.Account.autoBackup))
        case "secureVaultStatus": return encode("{\"available\":true,\"backend\":\"keychain\"}")

        case "notificationsAllowed":
            return encode(cachedNotificationsAllowed)

        // iOS has no notification-listener API: wallet capture is Android-only.
        // The web UI degrades gracefully on {enabled:false,...}.
        case "walletStatus":
            return encode("{\"enabled\":false,\"granted\":false,\"bankEnabled\":false,\"queue\":[],\"supported\":false}")
        case "walletEnable", "walletBankEnable": return encode(false)
        case "walletAck": return encode(false)
        case "walletReset": return encode(true)

        // In-app updater is Android-only; the App Store owns updates on iOS.
        case "canRequestInstalls": return encode("no")
        case "pendingUpdate": return encode(nil)
        case "updateDownloadProgress": return encode("{\"unsupported\":true}")
        case "startUpdateDownload": return encode("{\"unsupported\":true}")
        case "installUpdate": return encode("{\"unsupported\":true}")

        case "readBackupFile":
            guard let name = strArg(args, 0), !name.isEmpty else { return encode(nil) }
            let url = documentsURL.appendingPathComponent(name)
            return encode(try? String(contentsOf: url, encoding: .utf8))
        case "writeUpdateBackup":
            guard let json = strArg(args, 0) else { return encode(nil) }
            let tag = strArg(args, 1) ?? "backup"
            let name = "odddough-\(tag).json"
            do {
                try json.write(to: documentsURL.appendingPathComponent(name), atomically: true, encoding: .utf8)
                return encode(name)
            } catch { return encode(nil) }

        default:
            return encode(nil)
        }
    }

    private func jsonString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              var text = String(data: data, encoding: .utf8) else { return "\"\"" }
        text.removeFirst(); text.removeLast()
        return text
    }

    // MARK: - Async dispatch (messageHandlers)

    func handleAsync(method: String, args: [Any]) {
        switch method {
        case "openCSV": presentDocumentPicker()
        case "saveCSV": shareCSV(strArg(args, 0) ?? "")
        case "requestNotifications": requestNotifications()
        case "syncBills": syncBills(strArg(args, 0))
        case "syncWeeklySummary": syncWeeklySummary(strArg(args, 0))
        case "syncWidgets":
            // v1: persist for a future WidgetKit extension; silent like Android.
            if let json = strArg(args, 0) {
                UserDefaults.standard.set(json, forKey: "odddough.widgetPayload")
            }
        case "walletSettings":
            notice("Wallet capture needs Android notification access and isn't available on iOS.")
        case "checkForUpdate":
            notice("Updates come from the App Store on iOS.")
        case "clearPendingUpdate", "openInstallSettings":
            break // Android-only updater; no-op on iOS.
        default:
            break
        }
    }

    // MARK: - Async implementations

    private func presentDocumentPicker() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let vc = self.presentingVC() else {
                self?.notice("No file picker available. Paste CSV text instead.")
                return
            }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.plainText, .commaSeparatedText, .pdf], asCopy: true)
            picker.delegate = self
            vc.present(picker, animated: true)
        }
    }

    private func shareCSV(_ text: String) {
        if text.isEmpty || text.count > 8_000_000 { notice("Export is too large."); return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let vc = self.presentingVC() else { return }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("OddDough-transactions.csv")
            do {
                try text.write(to: tmp, atomically: true, encoding: .utf8)
                let sheet = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
                if let pop = sheet.popoverPresentationController {
                    pop.sourceView = vc.view
                    pop.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.midY, width: 0, height: 0)
                }
                vc.present(sheet, animated: true)
            } catch {
                self.notice("Could not prepare the export.")
            }
        }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            self?.cachedNotificationsAllowed = granted
            if !granted { self?.notice("Notifications stay off. You can enable them in Settings.") }
        }
    }

    /// payload: {"enabled":Bool,"bills":[{"date":"YYYY-MM-DD","repeat":"none|monthly|...","anchorDay":Int,"reminderDays":Int}]}
    private func syncBills(_ raw: String?) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["odddough.bills"])
        guard let raw, let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["enabled"] as? Bool) == true,
              let bills = obj["bills"] as? [[String: Any]], !bills.isEmpty else { return }
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            for (i, b) in bills.prefix(20).enumerated() {
                guard let dateStr = b["date"] as? String else { continue }
                let reminderDays = (b["reminderDays"] as? Int) ?? 3
                let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.timeZone = TimeZone.current
                guard let date = fmt.date(from: dateStr) else { continue }
                let fire = Calendar.current.date(byAdding: .day, value: -reminderDays, to: date) ?? date
                if fire <= Date() { continue }
                let content = UNMutableNotificationContent()
                content.title = "Bill due soon"
                content.body = "A bill is due on \(dateStr)."
                content.sound = .default
                var dc = Calendar.current.dateComponents([.year, .month, .day], from: fire)
                dc.hour = 9
                let req = UNNotificationRequest(identifier: "odddough.bills.\(i)", content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: false))
                center.add(req)
            }
        }
    }

    /// payload: {"enabled":Bool,"title":String,"text":String} — weekly money recap.
    private func syncWeeklySummary(_ raw: String?) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["odddough.weekly"])
        guard let raw, let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["enabled"] as? Bool) == true else { return }
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = (obj["title"] as? String) ?? "Weekly money recap"
            content.body = (obj["text"] as? String) ?? "Open OddDough for your weekly recap."
            content.sound = .default
            var dc = DateComponents()
            dc.weekday = 2 // Monday
            dc.hour = 9
            let req = UNNotificationRequest(identifier: "odddough.weekly", content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true))
            center.add(req)
        }
    }
}

// MARK: - UIDocumentPickerDelegate

extension NativeBridge: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            jsCallback("cashCompassCSV", jsQuote(text))
        } else if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
            jsCallback("cashCompassCSV", jsQuote(text))
        } else {
            notice("Couldn't read that file as text.")
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { /* no-op */ }
}

// MARK: - CSV / document content type

extension UTType {
    static var commaSeparatedText: UTType { UTType("public.comma-separated-values-text") ?? .plainText }
}
