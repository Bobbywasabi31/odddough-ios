import SwiftUI
import WebKit

/// Hosts the shared web UI (www/index.html) in a WKWebView and wires the
/// NativeBridge through two channels — see BridgeShim.js.
struct WebViewContainer: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let ucc = config.userContentController
        ucc.add(context.coordinator, name: "odddoughAsync")
        if let shimURL = Bundle.main.url(forResource: "BridgeShim", withExtension: "js"),
           let shim = try? String(contentsOf: shimURL, encoding: .utf8) {
            ucc.addUserScript(WKUserScript(source: shim,
                                           injectionTime: .atDocumentStart,
                                           forMainFrameOnly: true))
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.973, green: 0.965, blue: 0.957, alpha: 1) // #F8F7F4
        webView.scrollView.contentInsetAdjustmentBehavior = .always

        context.coordinator.bridge.webView = webView
        context.coordinator.bridge.refreshNotificationStatus()

        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "www") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
        let bridge = NativeBridge()
        private static let syncPrefix = "odddough-bridge:"

        override init() {
            super.init()
            // Quick Actions ("Add expense"/"Add income") delivered into the page.
            ShortcutRelay.shared.deliver = { [weak self] kind in
                self?.deliverShortcut(kind: kind)
            }
        }

        private func deliverShortcut(kind: String) {
            let script = "window.cashCompassShortcut && window.cashCompassShortcut('\(kind)');"
            DispatchQueue.main.async { [weak self] in
                self?.bridge.webView?.evaluateJavaScript(script, completionHandler: nil)
            }
        }

        // Async channel: window.webkit.messageHandlers.odddoughAsync.postMessage({m, a})
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "odddoughAsync",
                  let body = message.body as? [String: Any],
                  let method = body["m"] as? String else { return }
            let args = body["a"] as? [Any] ?? []
            bridge.handleAsync(method: method, args: args)
        }

        // Sync channel: window.prompt("odddough-bridge:{...}") intercepted here.
        // The completionHandler MUST be called synchronously with the result;
        // no UI is presented for bridge prompts.
        func webView(_ webView: WKWebView,
                     runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            guard prompt.hasPrefix(Self.syncPrefix) else {
                // Not ours: fall back to a plain alert-style prompt.
                let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
                alert.addTextField { $0.text = defaultText }
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                    completionHandler(alert.textFields?.first?.text)
                })
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                    completionHandler(nil)
                })
                topViewController(from: webView)?.present(alert, animated: true)
                return
            }
            let payload = String(prompt.dropFirst(Self.syncPrefix.count))
            var method = ""
            var args: [Any] = []
            if let data = payload.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                method = obj["m"] as? String ?? ""
                args = obj["a"] as? [Any] ?? []
            }
            completionHandler(bridge.handleSync(method: method, args: args))
        }

        // Keep link taps inside the app; the web UI is offline-first and
        // must never navigate to remote URLs.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Flush any Quick Action that fired before the page was ready.
            if let kind = ShortcutRelay.shared.takePending() {
                deliverShortcut(kind: kind)
            }
        }

        private func topViewController(from webView: WKWebView) -> UIViewController? {
            var responder: UIResponder? = webView
            while let r = responder {
                if let vc = r as? UIViewController { return vc }
                responder = r.next
            }
            return nil
        }
    }
}
