# Run 29 — True for iPhone: QR pairing · terminal text selection · cross-device clipboard

**One sentence:** three things Yahia asked for after Run 28 — pair by scanning a QR instead of typing, select and copy text
out of a terminal pane (today a long-press does nothing he can use), and a real two-way clipboard between the Mac and the phone.

Yahia's request, verbatim: *"gwt to work on the qr setup and make it so i can copy from the terminals aswell as right now i cant
intwravt with the text. Also add cross device clipbored into the app"*

Sources of truth, in order: Run 28 spec `.claude/briefs/run28-deep-design.md` (design decisions, all still binding) · Run 27 spec
`.claude/briefs/run27-native-ios.md` (contract + colour) · `~/.claude/skills/apple-hig/references/*.md` (read `cameras.md`/`machine-readable-codes.md`
if present, `edit-menus.md`, `context-menus.md`, `copy-and-paste.md`... grep the folder; read the page, do not recall it) ·
`~/Projects/hig-sample-book/docs/COMPONENT-IDS.md`.

## Settled decisions (do not re-litigate)
1. **Design doctrine from Run 28 holds.** Glass only on controls; blue = interactive, amber = state, no green; `TileRow` is the one
   device; system text styles; every state handled; 44pt targets; AX3 survives.
2. **The privacy invariant stays.** `Tests/TrueTests/RemoteDropTests.swift` `clipCapAndNoClipboardReadRoute` asserts that NO route
   reads the Mac clipboard on request and that the route table never contains "clipboard"/"pasteboard". Keep it green. Cross-device
   clipboard is therefore **push from the Mac, by opt-in**, into the existing phone inbox — never a `GET` that reads
   `NSPasteboard` when the phone asks. The server's `routeTable` does not grow.
3. **The pairing code stays single-use, 5-minute, 6-digit.** The QR simply carries what is already shown on screen (address + code),
   so scanning it is exactly as safe as reading it. A new code = a new QR (SwiftUI re-renders from `remote.code`).
4. **The lane widens, carefully.** Run 28 was `ios/` only. Run 29 may edit: `ios/`, `Sources/TrueRemoteClient/`, `Sources/True/Remote/`
   (RemoteAccess.swift, RemoteDrop.swift, RemoteServer.swift inbox JSON only), `Tests/TrueTests/`, `scripts/remote-mock.py`,
   `ios/README.md`. Nothing else under `Sources/True/`. Never launch or quit True.app.
5. **Phone → Mac clipboard is one tap, never automatic.** Reading `UIPasteboard` on iOS shows the system "pasted from…" banner;
   doing it on every foreground would nag. Mac → phone *can* be automatic (writing `UIPasteboard` is silent) behind a phone-side
   toggle, default ON (that is what "cross-device clipboard" means; Universal Clipboard behaves the same).
6. **Realistic SwiftTerm scope.** We are on the meshTerm fork (`.build/checkouts/SwiftTerm`, iOS view at
   `Sources/SwiftTerm/iOS/iOSTerminalView.swift`). `SelectionService` is internal; public surface = `copy(_:)`, `selectAll(_:)`,
   `select(_:)`, `paste(_:)`, `canPerformAction`, `hasActiveSelection`, `selectionChanged(source:)` (open, overridable),
   `getTerminal().getText(start:end:)`. Build on those; do not vendor or patch SwiftTerm.

## Deliverable 1 — QR pairing

### Mac (`Sources/True/Remote/RemoteAccess.swift`)
- The QR (`RemoteAccess.qr`, drawn in the Remote Access sheet ~line 197) currently encodes only `remote.url`. Encode a pair link instead:
  `true://pair?host=<dnsName>:<httpsPort>&code=<6 digits>` (percent-encode values; omit `code` when `remote.code == nil` so the QR
  still gives the address). Regenerate whenever `remote.code` changes (it is `@Observable`; just compute from both).
- Caption under the QR (`.caption .secondary`): "Scan with True on your iPhone — it fills the address and code for you." Keep the
  address text and the big code exactly as they are (manual path stays).
- Accessibility label of the image: "QR code with the Remote Access address and pairing code".
- Unit test (`Tests/TrueTests/`): a pure function `RemoteAccess.pairLink(host:code:) -> String` → test it encodes/omits code correctly,
  and that `PairLink.parse(URL)` (shared, see below) round-trips it.

### Shared parser (`Sources/TrueRemoteClient/PairLink.swift`, new)
`public struct PairLink { public let address: String; public let code: String?; public init?(url: URL) }` — accepts `true://pair?host=…&code=…`.
Address normalisation goes through the existing `SharedConfig.normalize` on the phone (it already turns `host:port` into `https://`).
Rejects non-`true` schemes, hosts with paths, codes that are not exactly 6 digits.

### iPhone
- `ios/project.yml` → `info.properties`: `NSCameraUsageDescription: "True uses the camera only to scan the pairing code shown on your Mac."`
  Regenerate the project (`cd ios && xcodegen generate`).
- `PairView`: above the three-step section, a primary `TileRow(symbol: "qrcode.viewfinder", title: "Scan the code on your Mac",
  detail: "Fills the address and code for you")` as a `Button` (tint `.primary`, chevron trailing). It presents `ScanSheet`.
  The three manual steps stay beneath as the fallback ("Or do it by hand" header).
- `ScanSheet` (`ios/True/Views/ScanSheet.swift`, new): `UIViewControllerRepresentable` around VisionKit `DataScannerViewController`
  (`recognizedDataTypes: [.barcode(symbologies: [.qr])]`, `isHighlightingEnabled: true`). Guard `DataScannerViewController.isSupported
  && .isAvailable`; if not (the simulator, or camera denied) show a system-styled unavailable state: `ContentUnavailableView`
  ("Camera isn't available", symbol `camera.fill`, description tells them to type the address and code instead) with a "Type it
  instead" button that dismisses. Camera permission denied → the same view with "Open Settings" (`UIApplication.openSettingsURLString`).
  Sheet: `.presentationDetents([.large])`, nav title "Scan", `Button(role: .close)` in the toolbar.
  On first recognised QR that `PairLink` parses → haptic `.success`, dismiss, fill `address` + `code`, and call `pair()` immediately
  (busy state shows on the Pair button). A QR that does not parse → one-line footer under the scanner "That's not a True pairing code"
  (amber `.attention`), keep scanning.
- `AppModel.handle(url:)`: also accept `true://pair?…` (scanned with the system Camera app → opens True → pairs if unpaired; if already
  paired, toast "Already paired with your Mac"). Keep the existing `true://pane/<id>` branch.
- Debug `-uiState pair-scan` → PairView with the ScanSheet presented (in the sim this shows the unavailable state — that is the
  screenshot we want: it must look designed, not broken).

## Deliverable 2 — Terminal text selection and copy (`ios/True/Views/PaneView.swift`)

### Diagnose first, then fix (report what you found)
SwiftTerm's iOS view installs a 0.7 s `UILongPressGestureRecognizer` whose handler calls `showContextMenu`, which uses
`UIMenuController.shared.showMenu(from:rect:)` — deprecated since iOS 16 and, on iOS 26, expected to show nothing. That is the
likely "I can't interact with the text". Verify in the simulator on `-uiState pane` (mock: `MOCK_STATE=normal`): long-press the
terminal body. Record what happens (nothing / menu / selection) in the report.

### Fix: our own edit menu on top of SwiftTerm's selection machinery
- Subclass: `final class SelectableTerminalView: TerminalView` (in PaneView.swift or `Views/Components/`). `PaneController.terminal`
  becomes this type (`TerminalRepresentable` signature follows).
- Add a `UIEditMenuInteraction` (iOS 16+) to the view, delegate = the view. Add our own `UILongPressGestureRecognizer`
  (`minimumPressDuration = 0.7`, `delegate` allowing simultaneous recognition with SwiftTerm's) that, on `.began`, calls
  `becomeFirstResponder()` and `editMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: location))`.
  The system builds the menu from `canPerformAction` → it offers **Select / Select All / Paste**, and **Copy** once a selection exists.
  SwiftTerm's own long-press handler still runs first and records `lastLongSelect`, so the system "Select" maps to SwiftTerm's
  `select(_:)` → word selection + drag handles. If the deprecated `UIMenuController` *does* still appear on this SDK and would double
  up, cancel SwiftTerm's recogniser from our delegate (`gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` returning false
  and ours requiring theirs to fail is the wrong way round — instead find theirs in `gestureRecognizers` by target/action class and
  set `isEnabled = false`). Document which branch you took.
- Override `selectionChanged(source:)`: when `hasActiveSelection` becomes true, re-present the edit menu anchored on the selection
  (use the touch point you stored; `UIEditMenuInteraction` needs a point, not a rect). When it becomes false, dismiss the menu.
- Haptic `.selection` when selection starts (UIKit `UISelectionFeedbackGenerator`).
- **Pane actions menu** (`ellipsis.circle`): add a section with `Select text` (= `terminal.selectAll(nil)`; handles appear, user
  shrinks it) and `Copy everything` (= `selectAll` then `copy` → toast "Copied"). Symbols: `text.cursor` / `doc.on.doc` — run the
  symbols gate.
- **Key row**: add a `Copy` glass button that is enabled only while `hasActiveSelection` (observe via the `selectionChanged`
  override → a `@Observable` flag on `PaneController`). Keep the row scrolling; it is already wider than the phone.
- Scrolling vs selection: SwiftTerm swaps its pan recogniser between scroll and selection itself (`enableSelectionPanGesture`).
  Do not add a UIScrollView. Verify: with a selection active, dragging a handle extends it; with none, dragging scrolls.
- `allowMouseReporting` stays default `true` (TUIs like vim/htop need it). Note in the report if a mouse-reporting program swallows
  the long-press; that is expected and out of scope.
- Verify in the simulator (`xcrun simctl io booted screenshot` cannot show the live menu reliably — use `simctl` + a long-press via
  `xcrun simctl io booted sendkey`? no such thing; instead drive it by hand with the Simulator app's mouse while the mock pane is open,
  then screenshot the selection + handles + Copy key state). Screenshot `pane-selection-dark.png`.

## Deliverable 3 — Cross-device clipboard

### Mac: opt-in clipboard sharing (`Sources/True/Remote/`)
- `RemoteAccess` gains `shareClipboard: Bool` (UserDefaults `remote.shareClipboard`, default **off**) with a Toggle in the Remote Access
  sheet under the Paired phones block: "Share my Mac's copies with paired phones" + caption "Text you copy on this Mac appears on the
  phone's Send tab (and lands on its clipboard if the phone allows). Passwords and concealed copies are never shared."
  Only enabled when `remote.enabled`.
- `ClipboardShare` (new file `Sources/True/Remote/ClipboardShare.swift`): a 1 s `Timer` (main run loop, `.common` modes) polling
  `NSPasteboard.general.changeCount` — macOS has no change notification; this is the standard pattern. On change:
  - skip if the pasteboard carries `org.nspasteboard.ConcealedType` or `org.nspasteboard.TransientType` (the convention already
    honoured at RemoteAccess.swift:256) or `org.nspasteboard.AutoGeneratedType`;
  - take `string(forType: .string)` only; skip empty, skip > `RemoteFiles.maxClipBytes`, skip if identical to the last shared text;
  - skip if the change came from our own `POST /api/clip` (the phone's push sets the Mac pasteboard — remember its text and don't echo it back);
  - call `RemoteFilesLive.inbox.replaceSharedClipboard(text:)`.
- `RemoteInbox.replaceSharedClipboard(text:)` (RemoteDrop.swift): removes the previous *shared* clipboard item (track it by a
  `source: Source?` field on `PhoneInboxItem`, `enum Source: String, Codable { case clipboardShare }`, `decodeIfPresent` so old
  items decode) then `add(name: "Clipboard", kind: .text, data:)` with `source = .clipboardShare`. At most ONE auto item ever lives
  in the inbox, so sharing never evicts files (max 20 items / 24 h cap unchanged). Manual "Send Clipboard to Phone" (TrueApp.swift:65)
  keeps adding ordinary items as today.
- `GET /api/inbox` rows: add `"source"` (when present) and `"created"` (epoch seconds) if `created` is not already serialised.
  The route table is unchanged; `preview` already exists for text.
- Tests (`Tests/TrueTests/ClipboardShareTests.swift`): drive `ClipboardShare` with an injected pasteboard reader closure + injected
  inbox: change → one item; same text again → no new item; concealed type → nothing; second distinct change → still exactly one
  `clipboardShare` item (replaced); toggle off → the timer stops. Keep `clipCapAndNoClipboardReadRoute` green (run it).

### iPhone: Send tab becomes the clipboard surface (`ios/True/Views/SendView.swift`, `AppModel.swift`, `Sources/TrueRemoteClient/`)
- `InboxItem` (RemoteModels.swift) gains `source: String?`, `created: Date?` (both optional; the mock gets `source: "clipboardShare"`
  on its text item and a `created`).
- Section **"Clipboard"** moves to the TOP of Send:
  - Row 1 — latest Mac clipboard (the inbox item with `source == clipboardShare`, else the newest `kind == text`): `TileRow(symbol:
    "doc.on.clipboard", title: <preview, 2 lines, monospaced only if it looks like a command — no, keep body text>, detail:
    "From your Mac · <relative time>")`. Tap → `UIPasteboard.general.string = full text` (fetch `/api/inbox/<id>`), toast "Copied",
    haptic `.success`. Empty: a quiet `TileRow` "Nothing from your Mac yet" with footer "Turn on 'Share my Mac's copies' under Remote
    Access on the Mac, or use Send Clipboard to Phone there."
  - Row 2 — `TileRow(symbol: "iphone.and.arrow.forward", title: "Send phone clipboard", detail: "Puts what you copied here on the Mac")`
    → existing `pasteFromPhone()`; toast "On your Mac's clipboard"; pending spinner; `.error` haptic when empty. (Delete the old
    "Paste" row from "To your Mac" — one home per action.)
  - Row 3 — `Toggle("Copy Mac clipboard automatically", isOn: model.autoClipboard)` (`@AppStorage("autoClipboard")`, default true),
    footer: "When True opens, the newest text copied on your Mac goes straight to this phone's clipboard."
  - The "Clipboard" TextField section is renamed **"Type for your Mac"** and moves below "To your Mac" (it still POSTs `/api/clip`).
- Auto-copy: `AppModel` observes `scenePhase` (inject from `TrueApp` with `.onChange(of: scenePhase)`). On `.active` and on each hub
  poll tick while the Send tab is visible: fetch `/api/inbox`; if the shared clipboard item's `id` differs from `lastAppliedClipId`
  (persisted `@AppStorage`) and `autoClipboard` is on → fetch its text, set `UIPasteboard.general.string`, remember the id, toast
  "Clipboard from your Mac" (leading `doc.on.clipboard`). Never on first launch after pairing for an item older than 10 minutes (don't
  surprise with stale text). Writing the phone pasteboard is silent — no system banner — confirm in the sim and say so.
- The pane key row's existing **Paste** key is the third leg (phone clipboard → terminal). Leave it.
- Mock: `scripts/remote-mock.py` `/api/inbox` text item gets `source="clipboardShare"`, `created=<now-120>`; `MOCK_STATE=empty` has none.

## Acceptance (all in `.out/run29/`, Light + Dark where it matters; LOOK at each with Read)
- `pairing-light.png` — Scan row above the three steps; `pair-scan-light.png` — ScanSheet unavailable state in the simulator (designed,
  not broken); `pair-scan-ax3-light.png`.
- `pane-selection-dark.png` — a selection with handles, Copy key enabled; `pane-menu-dark.png` — the pane actions menu showing
  Select text / Copy everything.
- `send-light.png` + `send-dark.png` — Clipboard section at top with the Mac item, Send phone clipboard, the toggle; `send-empty-light.png`.
- Gates: iOS build (zero warnings in `ios/`), symbols check on every touched Swift file, `swift build` at repo root, `swift test` with
  the CLT flags (`SPEC.md:33-37`) — paste the summary line; `clipCapAndNoClipboardReadRoute` named as passing.
- `ios/README.md`: new launch arg, the QR flow, clipboard sharing (both toggles, the privacy stance in one sentence).
- Report: what the long-press actually did before the fix, which gesture branch you took, any VisionKit/iOS 26 API that did not
  compile and its replacement, anything NOT done and why.
