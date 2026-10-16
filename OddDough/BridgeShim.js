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

  /* ---- iOS platform polyfills (WKWebView gaps) ---- */

  // 1. Receipt photo inputs: WKWebView cannot open file pickers, so route
  //    taps through the native image picker. Native returns a JPEG data URL
  //    via cashCompassReceiptImage, then Vision OCR results via the existing
  //    window.cashCompassReceiptOCR (same {text, blocks:[{t,h,y}]} shape as
  //    Android's ML Kit payload).
  document.addEventListener('click', function (e) {
    var input = e.target && e.target.closest ? e.target.closest('input[type=file]') : null;
    if (input && input.name === 'receipt') {
      e.preventDefault();
      e.stopPropagation();
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.odddoughAsync) {
        window.webkit.messageHandlers.odddoughAsync.postMessage({ m: 'pickReceipt', a: [] });
      }
    }
  }, true);

  window.cashCompassReceiptImage = function (dataUrl) {
    var form = document.querySelector('#transactionForm');
    if (!form || !dataUrl) return;
    var hidden = form.querySelector('[name=receiptData]');
    if (hidden) hidden.value = dataUrl;
    var preview = form.querySelector('.receipt-preview');
    if (!preview) {
      preview = document.createElement('div');
      preview.className = 'receipt-preview';
      var input = form.querySelector('[name=receipt]');
      if (input && input.parentNode) input.parentNode.appendChild(preview);
      else form.appendChild(preview);
    }
    preview.innerHTML = '<img src="' + String(dataUrl).replace(/"/g, '&quot;') +
      '" alt="Receipt" style="max-width:120px;border-radius:8px">';
  };

  // 2. Voice entry: no SpeechRecognition in WKWebView. Provide a compatible
  //    shim backed by SFSpeechRecognizer; startVoice() in app.js works
  //    unchanged (it only uses new SR(), .lang, .start(), .onresult/.onerror).
  if (!window.SpeechRecognition && !window.webkitSpeechRecognition) {
    window.__odVoiceRec = null;
    window.SpeechRecognition = function () {
      var rec = this;
      rec.lang = 'en-US';
      rec.interimResults = false;
      rec.continuous = false;
      rec.onresult = null;
      rec.onerror = null;
      rec.onend = null;
      rec.start = function () {
        window.__odVoiceRec = rec;
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.odddoughAsync) {
          window.webkit.messageHandlers.odddoughAsync.postMessage({ m: 'startVoiceInput', a: [rec.lang || 'en-US'] });
        }
      };
      rec.stop = function () {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.odddoughAsync) {
          window.webkit.messageHandlers.odddoughAsync.postMessage({ m: 'stopVoiceInput', a: [] });
        }
      };
    };
    window.cashCompassVoiceResult = function (text) {
      var rec = window.__odVoiceRec;
      window.__odVoiceRec = null;
      if (rec) {
        if (typeof rec.onresult === 'function') rec.onresult({ results: [[{ transcript: String(text) }]] });
        if (typeof rec.onend === 'function') rec.onend();
      }
    };
    window.cashCompassVoiceError = function () {
      var rec = window.__odVoiceRec;
      window.__odVoiceRec = null;
      if (rec) {
        if (typeof rec.onerror === 'function') rec.onerror({});
        if (typeof rec.onend === 'function') rec.onend();
      }
    };
  }

  // 3. Share sheet: navigator.share doesn't exist in WKWebView.
  if (!navigator.share) {
    navigator.share = function (data) {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.odddoughAsync) {
        window.webkit.messageHandlers.odddoughAsync.postMessage({
          m: 'shareText',
          a: [(data && data.title) || '', (data && data.text) || '']
        });
      }
      return Promise.resolve();
    };
  }
})();
