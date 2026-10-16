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
`-baseURL http://localhost:8899 -autoPair 123456` pair against the mock · `-uiState composer|composer-routed|builder|shots|viewer|send|sites|browser|pane|pane-select|pair-scan` jump to a screen ·
`-composerText "…"` prefill · `-composerRoute 1` route on open.
Mock: `MOCK_PORT=8899 MOCK_STATE=normal|empty|offline python3 scripts/remote-mock.py` (it has no WebSocket; `-uiState pane` feeds demo text, DEBUG only).

UI test (`TrueUITests`, proves long-press → Select All → Copy on the terminal): start the mock, then
`xcodebuild test -project True.xcodeproj -scheme True -destination "id=<sim>" -only-testing:TrueUITests CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation TEST_RUNNER_SHOT_DIR=$PWD/../.out/run29`
(`TEST_RUNNER_` is stripped by xcodebuild; the runner sees `SHOT_DIR` and writes `pane-menu-dark.png` / `pane-selection-live-dark.png`).
Verify the copy from the host, never inside the runner (iOS pops a paste-permission alert): `xcrun simctl pbpaste <sim> | grep "tests passed"`.

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

## Nearby pairing over Bluetooth (run 30)

The Mac (Remote Access on + "Show pairing card when a phone is nearby", default on) advertises a Bluetooth service.
When the Pair screen is open, the phone scans for it, and if the Mac is within about the same room (RSSI >= -70 dBm)
it reads the Mac's address and writes a hello (`<phone name>|<install id>`). The Mac then pops the pairing QR card
top-right. Bluetooth carries discovery and the address only, never the code: pairing is still the HTTPS call with the
6-digit code, so scanning or typing it remains the proof you are in front of the Mac.

- Phone: `NearbyScanner.swift` (`NearbyScanning` protocol, `CoreBluetoothScanner`, `FakeNearbyScanner`). Scanning starts
  when PairView appears and the app is active, stops when it disappears, backgrounds, or pairing succeeds. The Bluetooth
  prompt appears only then, not at launch. The simulator has no Bluetooth, so it never creates a real scanner.
- Mac: `NearbyAdvertiser.swift`, `NearbyPairCard.swift`. Anti-spam: one card per phone id per 5 minutes, and at least
  5 seconds between any two cards. Card auto-hides after 60 s; on pairing it flips to "Paired" and a notify tells the phone.
- Screenshots: `-uiState pair-nearby` (fake Mac in range) and `pair-nearby-bt-off` (Bluetooth line); `.out/run30/`.

Hardware checklist (real iPhone + Mac): 1) Mac: Remote Access on, card toggle on; accept the Bluetooth prompt.
2) iPhone: open True unpaired; accept the Bluetooth prompt when the Pair screen appears. 3) Within the room the card
appears on the Mac and the phone shows "<Mac> is nearby". 4) Scan the Mac QR from the phone; both flip to paired.
5) Walk to another room: no card. 6) Repeat quickly: no second card for 5 min. 7) Bluetooth off: the phone shows the hint line.

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

## Sites + Browser tabs
**Sites** lists dev servers running in True panes on the Mac (`/api/sites`); tapping one shares it over Tailscale (`tailscale serve`, True-owned ports only) and opens it in-app, with a copy-paste fix if Vite/Next rejects the `*.ts.net` host. **Browser** streams a separate "True Chrome" on the Mac (`/api/browser/stream`): tap, drag-scroll, pinch-zoom, keyboard, tabs; `localhost:<port>` works because the browser runs on the Mac. Toggle in True's Settings ("Phone browser"). `-uiState sites|browser` shows demo data (DEBUG).
