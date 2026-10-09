# True for iPhone (Run 27)

Native SwiftUI iOS 26 app: Hub · Shots · Send · Start work · live panes, plus Needs-you notifications and a Share Extension.
Same `/api` + WebSocket contract as the Run 26 web app (`Resources/Remote`), which stays as the no-install fallback.

## Open it
```
brew install xcodegen          # once
cd ios && xcodegen generate    # regenerates True.xcodeproj from project.yml (the .xcodeproj is git-ignored)
open True.xcodeproj
```
Edit `project.yml`, never the generated project. Re-run `xcodegen generate` after adding/removing files.

## Run on your iPhone
1. In Xcode select the **True** target → *Signing & Capabilities* → pick your Team (project.yml leaves `DEVELOPMENT_TEAM` empty, automatic signing). Do the same for **TrueShare**.
2. Both targets use the app group `group.net.prismlens.true` (Keychain token sharing). Xcode registers it for your team automatically.
3. Plug in the phone (Developer Mode on), choose it as the destination, Run. Free Apple ID: the build expires after 7 days.
4. In True on the Mac open Remote Access, then on the phone enter the Mac address (`<mac>.<tailnet>.ts.net:8444`) and the 6-digit code.

## Certificate trust decision
The Mac server listens on `127.0.0.1:8801` only; **`tailscale serve --https=8444` terminates TLS** and presents a real, publicly trusted
Let's Encrypt certificate for the machine's `*.ts.net` name (see `RemoteAccess.swift`). So the phone uses **normal system trust**:
no pinning, no custom `URLSessionDelegate`, no ATS exception in Release. TLS validation is never disabled.
Debug builds only add an ATS exception for `localhost` (the plain-http mock server). If the Mac ever serves a self-signed certificate,
add pinning in a dedicated delegate (pass that `URLSession` to `RemoteSession`/`PaneSocket`, both accept one) rather than loosening ATS.

## How TrueRemoteClient is linked
`Package.swift` declares no library product, so Xcode cannot depend on it as a package. The iOS targets instead compile
`../Sources/TrueRemoteClient/*.swift` in place (same files the macOS tests cover). Cleaner alternative needing a root change:
`products: [.library(name: "TrueRemoteClient", targets: ["TrueRemoteClient"])]` in `Package.swift`, then depend on it from `project.yml`.

## Launch arguments (screenshots / dev)
`-baseURL http://localhost:8899 -autoPair 123456` pair against the mock · `-uiState composer|composer-routed|builder|shots|viewer|send|pane|pane-select|pair-scan` jump to a screen ·
`-composerText "…"` prefill · `-composerRoute 1` route on open.
Mock: `MOCK_PORT=8899 MOCK_STATE=normal|empty|offline python3 scripts/remote-mock.py` (it has no WebSocket; `-uiState pane` feeds demo text, DEBUG only).

## Layout
`True/App` lifecycle + `AppModel` · `True/Views` screens · `True/Services` Keychain, shared config, background refresh · `TrueShare` share extension.
Colour: system semantic colours plus one asset colour `Attention` (amber) for Needs you / Failed / unread / danger / offline.

## Pairing by QR, terminal selection, shared clipboard (run 29)
- **QR pairing.** The Mac's pairing QR encodes `true://pair?host=…&code=…` (shared `PairLink` parser in `TrueRemoteClient`). The Scan row in Pair opens `ScanSheet`
  (VisionKit); `true://pair` deep links work too. Camera string: `NSCameraUsageDescription` in `project.yml`. The simulator has no camera, so `-uiState pair-scan` shows the unavailable state.
- **Terminal selection.** Long-press uses SwiftTerm's own gesture and system edit menu; `SelectableTerminalView` reports selection changes so the Copy key enables while text is selected.
  The pane menu has Select text and Copy everything. `-uiState pane-select` pre-selects a span for screenshots. Not verified interactively (no Simulator GUI in the headless run).
- **Clipboard sharing.** Mac: toggle "Share my Mac's copies with paired phones" in Remote Access (default off). It pushes one replaceable inbox item (`source`, `created`); there is no clipboard read route.
  Phone: Send tab top section shows that item with Copy, "Send phone clipboard" is one tap, and "Copy Mac clipboard automatically" (default on) applies the newest Mac copy when True opens.

## Not done / needs a device
Background refresh cadence, Keychain access-group sharing and the Share Extension need a signed device build to verify.
Screenshot Delete (Shots context menu) is absent: the client has no delete-shot call.

## Build note
SwiftTerm ships a build-tool plugin; pass `-skipPackagePluginValidation` to command-line `xcodebuild` (Xcode asks once to trust it).

## App icon
Layers live in `ios/Design/Icon/` (`background.svg` warm near-black, `foreground.svg` amber prompt chevron + 60 % cursor block). The shipped
`AppIcon-1024.png` is rendered from the same geometry: `swift ios/Design/Icon/render.swift ios/True/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`.
Icon Composer (two minutes): open Icon Composer, drag `background.svg` then `foreground.svg` in as two layers, leave Liquid Glass defaults, export
`AppIcon.icon` into `ios/True/`, and select it as the app icon in the target. This gives the iOS 26 tinted/clear/dark variants.
