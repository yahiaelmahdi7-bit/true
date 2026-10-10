# Run 30 — True for iPhone: nearby pairing over Bluetooth (the AirPods card)

**One sentence:** when an unpaired iPhone running True comes physically near the Mac, the Mac pops a card in the top-right
with the QR code and the 6-digit code, the phone shows "Your Mac is nearby", and one scan pairs them — after which everything
runs over Tailscale from anywhere, exactly as today.

Yahia's request, verbatim: *"the app should be linked like apple airplay systems where when nearby it prompts the qr code on the
top right like a pop up to pair"* and *"lets do the bluetooth one as i dont want to be on the same wifi and this is just for the
first pair as i need this to work once i leave the house and my laptop is at home so i can have true on my phone working fine
from anywhere"*.

Sources of truth, in order: this file · `.claude/briefs/run29-qr-clipboard-select.md` (QR/PairLink contract, still binding) ·
`.claude/briefs/run28-deep-design.md` (design doctrine) · `~/.claude/skills/apple-hig/references/` (grep for "nearby",
"proximity", "panels", "notifications"; read the page, do not recall it) · `~/Projects/hig-sample-book/docs/COMPONENT-IDS.md`.

## Settled decisions (do not re-litigate)
1. **Bluetooth is the nearby signal, nothing else.** No Bonjour, no same-Wi-Fi assumption. CoreBluetooth on both sides: the Mac is
   the peripheral (advertises), the phone is the central (scans). Bluetooth carries discovery and the Mac's address only; it never
   carries the pairing code and never replaces the HTTPS pairing call. Pairing itself is unchanged: `POST` over Tailscale with the
   6-digit code (`RemoteSession.pair(code:)`, `PairingCodes.issue`). The QR / typed code remains the proof of presence.
2. **Only for the first pair.** The phone scans only while unpaired (`AppModel.paired == false`) and only while True is in the
   foreground; it stops the moment it pairs. The Mac advertises only while Remote Access is on. A paired phone never triggers the card.
3. **The card is a non-activating floating panel in the top-right**, modelled on `Sources/True/Views/TrayPanel.swift` (same
   `NSPanel` level, inset, every Space, never steals focus). Content: Mac's name as the title, "YOSHII iPhone wants to pair"
   as the subtitle (the phone's name, sent over Bluetooth), the QR (`RemoteAccess.qr(RemoteAccess.pairLink(host:code:))`), the
   6-digit code under it in the existing large monospaced style, a Dismiss button. Auto-hides 60 s after it appears, or 1.5 s after
   pairing succeeds with the title flipping to "Paired with YOSHII iPhone" + a checkmark `symbolEffect`. One card per phone per
   5 minutes (rate-limit by the phone's identifier, not its name).
4. **Showing the card issues a fresh code** (`RemoteAccess.newCode()`), the same as opening the Remote Access sheet does today.
   Codes stay single-use, 5 minutes, 6 digits.
5. **Phone side has two ways in, neither new in trust.** The phone's Pair screen gets a card at the top when the Mac is in range:
   "<Mac name> is nearby" with two buttons: **Scan the code** (opens the existing `ScanSheet`) and **Type the code** (the address
   field is prefilled from the Bluetooth advertisement; the user types the 6 digits shown on the Mac card). No code ever travels
   over Bluetooth, so the second path is exactly the manual path with the address filled in.
6. **Proximity threshold:** treat RSSI ≥ −70 dBm as "nearby" (roughly the same room); below that, ignore. Make the threshold a
   constant in the shared package with a comment, not a magic number.
7. **No simulator Bluetooth.** `CBCentralManager` reports `.unsupported` in the simulator. Everything that touches CoreBluetooth
   sits behind a small protocol (`NearbyScanner` on the phone, `NearbyAdvertiser` on the Mac) with a fake used by tests and by
   `-uiState pair-nearby` (the fake reports a Mac named "Yahia's MacBook" at −55 dBm with host `yoshii-mac.tail1234.ts.net:8444`).
   The real transport is verified on hardware afterwards by Yahia, not by you; say so in the report instead of claiming it.
8. **Permissions, both sides, with honest copy.** Mac: `NSBluetoothAlwaysUsageDescription` added to the plist in `scripts/package.sh`
   ("True uses Bluetooth only to notice your iPhone nearby so the pairing code can appear."). iPhone: the same key in
   `ios/project.yml` (`INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription`, "True uses Bluetooth only to find your Mac when you first
   pair."). Request Bluetooth on the phone only when the Pair screen appears, not at launch. Handle `.poweredOff`, `.unauthorized`
   and `.unsupported` with one quiet secondary-text line under the card slot ("Turn on Bluetooth to find your Mac automatically");
   the manual path is never blocked by Bluetooth state.
9. **Lane.** `ios/`, `Sources/TrueRemoteClient/` (new `NearbyPairing.swift`: service/characteristic UUIDs, RSSI threshold, the
   advertisement payload codec), `Sources/True/Remote/` (new `NearbyAdvertiser.swift`, new `NearbyPairCard.swift`, small hooks in
   `RemoteAccess.swift`), `scripts/package.sh` (one plist key), `Tests/TrueTests/`, `scripts/remote-mock.py` only if needed,
   `ios/README.md`, `.out/run30/`. Nothing else. `Package.swift` untouched unless a target genuinely needs it (it should not).
   Never launch or quit True.app on the Mac.

## Protocol (GATT)
- Service UUID: one fixed UUID generated once and written into `NearbyPairing.swift` with a comment. Advertise it with the local
  name "True · <Mac computer name>".
- Characteristic `address` (read): the Mac's Tailscale host and port, `host:port`, UTF-8. Nothing else is readable.
- Characteristic `hello` (write without response): the phone writes `"<phone name>|<stable phone id>"` once per discovery
  (`UIDevice.current.name`, and an identifier stored in the phone's Keychain/UserDefaults on first run). This is the trigger for the card.
- Characteristic `paired` (notify): the Mac notifies `1` when `RemoteAccess.devices` grows while the card is up, so the phone's
  card can collapse on its own even if the user paired by typing.
- The Mac stops advertising when Remote Access is switched off and restarts when it is switched on.

## Mac deliverables
- `NearbyAdvertiser` (`CBPeripheralManager`): start/stop with Remote Access; serves the three characteristics; on `hello`,
  calls `NearbyPairCard.shared.present(phoneName:phoneID:)` on the main actor. Injected protocol so tests drive it with a fake.
- `NearbyPairCard`: the panel controller + SwiftUI content as decision 3. Re-renders the QR whenever `RemoteAccess.shared.code`
  changes. Observes `RemoteAccess.shared.devices` for the "Paired" flip.
- `RemoteAccess`: `startIfEnabled` / `setEnabled` start and stop the advertiser; a toggle in the Remote Access sheet
  "Show a pairing card when my iPhone is nearby" (default ON) gates advertising; a `.caption .secondary` line under it explains
  Bluetooth is used only to notice the phone.
- Tests: hello → card presented with a fresh code; second hello from the same id within 5 min → no second card; different id →
  card; card auto-dismiss timer; pairing while the card is up flips it; advertiser starts/stops with the toggle and with
  Remote Access. All with the fake transport. Keep `clipCapAndNoClipboardReadRoute` and the whole suite green.

## iPhone deliverables
- `NearbyScanner` (`CBCentralManager`): scans for the service UUID only while unpaired and foregrounded (scenePhase); on discovery
  with RSSI ≥ threshold, connects, reads `address`, writes `hello`, subscribes to `paired`, and publishes a `NearbyMac(name:address:)`
  to `AppModel`. Disconnects and stops scanning on pair, on background, or on leaving the Pair screen.
- `PairView`: the nearby card at the top (decision 5) on `axonBezel`-equivalent styling of Run 28 (`TileRow` device, blue =
  interactive). When no Mac is nearby the slot is empty, not a placeholder. Bluetooth state line per decision 8.
- `-uiState pair-nearby` drives the fake scanner. Screenshots: `pair-nearby-light.png`, `pair-nearby-dark.png`,
  `pair-nearby-bt-off-light.png`. Plus the Mac card rendered in a SwiftUI preview-sized window via a unit test that snapshots the
  view to `.out/run30/mac-card.png` (use `ImageRenderer`), light and dark.
- `ios/README.md`: the Bluetooth pairing flow, the fake transport, the `-uiState pair-nearby` flag, and the hardware checklist for
  Yahia (both permission prompts, then the card).

## Acceptance
- Mac `swift build` clean; full `swift test` green including the new Nearby tests; iOS build zero warnings; symbols gate clean on
  every touched Swift file.
- Screenshots listed above exist and were LOOKED at (Read tool) and fixed to first-party quality before the report.
- The report states plainly that real Bluetooth was not exercised and lists the exact hardware steps for Yahia.
