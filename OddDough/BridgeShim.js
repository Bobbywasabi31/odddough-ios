/* OddDough iOS bridge shim — injected at document start, before app.js loads.
 *
 * The web UI was written against Android's synchronous NativeBridge
 * (addJavascriptInterface). iOS has no synchronous JS->native channel, so:
 *
 *  - SYNC methods go through window.prompt(), which WKWebView delivers to
 *    the native side via runJavaScriptTextInputPanelWithPrompt. The native
 *    side intercepts our "odddough-bridge:" prefix and returns a JSON-encoded
 *    value synchronously. No dialog is ever shown for these.
 *  - ASYNC methods (file pickers, permission prompts, background sync) go
 *    through window.webkit.messageHandlers.odddoughAsync.postMessage().
 *    Results come back via the usual window.cashCompass* callbacks.
 *
 * No changes to app.js / core.js were needed.
 */
(function () {
  'use strict';
  var PREFIX = 'odddough-bridge:';
  var ASYNC = {
    checkForUpdate: 1,
    clearPendingUpdate: 1,
    openCSV: 1,
    openInstallSettings: 1,
    requestNotifications: 1,
    saveCSV: 1,
    syncBills: 1,
    syncWeeklySummary: 1,
    syncWidgets: 1,
    walletSettings: 1
  };

  function syncCall(method, args) {
    var raw = prompt(PREFIX + JSON.stringify({ m: method, a: args }), '');
    if (raw === null || raw === undefined || raw === '') return null;
    try {
      return JSON.parse(raw);
    } catch (e) {
      return raw;
    }
  }

  function makeBridge() {
    return new Proxy({}, {
      get: function (target, method) {
        if (typeof method !== 'string') return undefined;
        return function () {
          var args = Array.prototype.slice.call(arguments);
          if (ASYNC[method]) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.odddoughAsync) {
              window.webkit.messageHandlers.odddoughAsync.postMessage({ m: method, a: args });
            }
            return undefined;
          }
          return syncCall(method, args);
        };
      },
      // so `"method" in NativeBridge` checks behave sanely
      has: function () { return true; }
    });
  }

  if (typeof window.NativeBridge === 'undefined') {
    window.NativeBridge = makeBridge();
  }
})();
