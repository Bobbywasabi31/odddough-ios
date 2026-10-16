# OddDough for iOS

The Apple version of [OddDough](https://github.com/Bobbywasabi31/odddough-android) —
the offline-first cash-flow coach. **Paper-free port, not a rewrite.**

## How the port works

OddDough's UI is a WebView app: the entire interface is 5,500 lines of
HTML/CSS/JS in `www/` (copied verbatim from the Android app's assets — zero
changes). What this repo adds is the iOS shell around it:

- `OddDough/OddDoughApp.swift` — SwiftUI app entry
- `OddDough/WebView.swift` — WKWebView hosting `www/index.html`
- `OddDough/BridgeShim.js` — injected at document start; recreates Android's
  synchronous `window.NativeBridge` on iOS:
  - **sync** methods go through `window.prompt()` interception
    (`odddough-bridge:` prefix — no dialog is ever shown)
  - **async** methods (file pickers, permission prompts) go through
    `window.webkit.messageHandlers.odddoughAsync`, with results returning via
    the existing `window.cashCompass*` callbacks
- `OddDough/NativeBridge.swift` — all 33 bridge methods reimplemented:
  - **Real:** Keychain secure storage, Face ID app lock, document picker
    (statement/CSV import), share-sheet export, backup read/write,
    notification permission, bill reminders + weekly recap via local
    notifications
  - **Stubbed (platform limitations):** wallet notification capture (iOS has
    no notification-listener API), in-app updater (App Store owns updates),
    receipt OCR camera scan (Apple Vision is the v2 path — paste fallback
    works today)
- `OddDough/SecureStore.swift` — Keychain wrapper

## Build

Prerequisites: Xcode 16+, and `xcodegen` (`brew install xcodegen`).

```sh
xcodegen generate
open OddDough.xcodeproj
```

CI (`.github/workflows/ios.yml`) does the same on `macos-15` and builds for
the iPhone 16 simulator on every push.

## Bundle ID

`com.cashcompass.app` — same as Android, so future backend/sync work can treat
them as one product.

## Status

v1 scaffold: the app runs, the full UI works, statement import / export /
backup / notifications / app lock are wired. Deliberately deferred:
WidgetKit widgets, Vision receipt OCR, App Store metadata + screenshots
(needs the $99/yr Apple Developer membership).

## Updating the web UI

`www/` is a verbatim copy of `odddough-android/app/src/main/assets`. When the
Android app ships UI changes, copy the assets over — no Swift changes needed
unless a new `NativeBridge` method was added (check `Bridge` in
`MainActivity.java`).
