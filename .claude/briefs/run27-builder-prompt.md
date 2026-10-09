You are building **True for iPhone (Run 27)** — a native SwiftUI iOS 26 app — inside the git worktree
`/Users/y/Projects/true.builders/true-mobile-redesign-20261009` (branch `builder/true-mobile-redesign`). This is your cwd.

READ FIRST (in this order, they are the truth):
1. `.claude/briefs/run27-native-ios.md` — the spec: shape, screen → component-ID map, native features, acceptance.
2. `~/Projects/hig-sample-book/docs/COMPONENT-IDS.md` — resolve every component ID in the spec to its exact SwiftUI
   (grep the ID; the table is `| id | what | SwiftUI | UIKit |`). Use REAL system components, never look-alikes.
3. `Sources/TrueRemoteClient/*.swift` — the shared, tested API client you MUST use (RemoteSession, PaneSocket, HubPoller,
   RemoteModels). Do not re-implement networking. Read its doc comments for the Origin rule, 401/4401 → unpair, route expiry.
4. `Resources/Remote/app.js` + `Resources/Remote/app.css` — the Run 26 web app: same flows, same copy, same state handling.
   Match its behaviour exactly where the spec is silent (e.g. newline stripping in the composer, 404 → "tap Route again").
5. `Sources/True/Remote/RemoteAccess.swift` and `RemoteServer.swift` — how TLS/the server certificate and pairing work.
   Decide how the iPhone trusts the Mac's certificate (pin the fingerprint learned at pairing, or whatever the Mac already
   exposes) and WRITE DOWN the choice in `ios/README.md`. Never disable TLS validation globally.
6. `SPEC.md` lines 1-60 and 680-760 for house rules (never launch/quit True.app; phone panes are `--permission-mode auto`).

DISCIPLINE (non-negotiable):
- Lane: you work ONLY in `ios/` (new) plus `.out/run27/` for screenshots. Do not touch, checkout, or revert any file outside it —
  other agents have uncommitted work in this tree. Do NOT edit `Package.swift`, `Sources/`, `Resources/`, `Tests/`.
  If TrueRemoteClient needs a change, STOP and report it as BLOCKED with the exact diff you need.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge,
  NEVER 'ship' — the user pushes, not you. Do not suggest pushing more than once.
- Gates: run builds/tests in the FOREGROUND and wait for them. NO background shells
  (run_in_background), NO watch modes, NO until-loops. Kill anything you started before finishing (including booted simulators
  you booted: `xcrun simctl shutdown all`). Never launch or quit the Mac app True.app.
- Claims: 'done' means you ran the gate and pasted the passing output. Local commit ≠ 'pushed';
  code written ≠ 'working'. Never report a state you didn't verify this session.
- Decisions: if your change adds or touches a classify / route / gate / rank / verify step, make it a Jev
  call through the repo's vendored jev-kit (see the jev skill): code owns the flow, Jev answers narrow
  typed questions, route on confidence, log the decision. No LLM prompt-and-parse, no keyword lists.
  (Routing already lives on the Mac behind /api/route — the phone only displays it. Do not add client-side routing.)
- If blocked or idle: say BLOCKED/IDLE + one line why. Do not invent extra scope.
- Do not `git stash` (shared stack). Do not cd to ~/Projects/true.

TOOLING FACTS:
- Xcode 26.6 at /Applications/Xcode.app, iOS SDK 26.5. `xcodegen` is at /opt/homebrew/bin/xcodegen — generate the project from
  `ios/project.yml`; commit `project.yml`, NOT the generated `.xcodeproj` (add `ios/*.xcodeproj` to `ios/.gitignore`).
- The iOS simulator runtime may still be downloading when you start (`xcodebuild -downloadPlatform iOS` was launched separately).
  Check `xcrun simctl list runtimes | grep iOS`. If none yet: build for `-destination 'generic/platform=iOS Simulator'` first,
  re-check every few steps; when a runtime exists, create an iPhone 16 Pro (`xcrun simctl create`), boot it, run, screenshot.
- No Apple Development signing identity exists on this Mac yet. Use `CODE_SIGNING_ALLOWED=NO` for simulator builds; set
  `DEVELOPMENT_TEAM` empty + automatic signing in project.yml so Yahia can pick his team in Xcode for a device install.
- Mock server for screenshots: `MOCK_PORT=8899 MOCK_STATE=normal python3 scripts/remote-mock.py` (states: normal|empty|offline;
  run it in the foreground with `timeout 120` per screenshot batch, never detached). It is plain http on localhost: add an ATS
  exception for `localhost` ONLY in a Debug-configuration Info.plist override, never in Release.
- SwiftTerm iOS: SPM package https://github.com/migueldeicaza/SwiftTerm (from 1.2.0); its iOS `TerminalView` is a UIView —
  wrap in UIViewRepresentable. Feed PaneSocket `.output` bytes to `feed(byteArray:)`; send typed bytes via `PaneSocket.send`.

BUILD (in this order; commit after each step that builds):
1. `ios/project.yml` → targets `True` (iOS app, bundle `net.prismlens.true`, deployment iOS 26.0, SwiftUI lifecycle) and
   `TrueShare` (share extension, `net.prismlens.true.share`). Local package dependency on the repo root (`path: ..`, product
   `TrueRemoteClient`) + SwiftTerm. App group `group.net.prismlens.true` for the Keychain/token shared with the extension.
   Gate: `xcodebuild -project ios/True.xcodeproj -scheme True -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`.
2. `ios/True/Services/KeychainTokenStore.swift` (conforms to TrueRemoteClient's `TokenStore`, access group = the app group,
   `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) + `AppModel` (@Observable: session, poller, hub snapshot, pairing state).
3. Screens per the spec, as system components: `PairView` (6 cells, oneTimeCode, Pair = button.prominent large),
   `RootTabs` (TabView Hub/Shots/Send + floating glass + via toolbar bottom placement), `HubView` (List inset grouped,
   Section per project, rows, swipe actions, refreshable, ContentUnavailableView for empty/offline, badge on tab),
   `BuilderSheet`, `ComposerSheet` (text-field axis vertical, Route→Run single-primary rule, slot pickers, background toggle,
   danger alert), `PaneView` (SwiftTerm + keyboard accessory bar Esc/Tab/⌃C/↑/↓/paste, black background), `ShotsView`
   (3-up grid, zoom transition viewer, context menu), `SendView` (Form grouped: From your Mac / To your Mac / Clipboard).
   Colour: system semantic colours + ONE asset colour `Attention` (warm amber #D97A1F light / #E8A23C dark) for Needs you /
   Failed / unread / danger / offline only. Terminal background black. Follows system Light/Dark.
4. Native extras: `BGAppRefreshTask` (identifier `net.prismlens.true.refresh`) that calls hub() and posts a local notification
   when HubPoller-style needsYouRose is true (tap → that pane via deep link `true://pane/<id>`); haptic on Needs you in foreground.
   `TrueShare`: accepts text, images, files → POST `/api/drop` via RemoteSession using the shared token; shows a one-line result.
5. Screenshots to `.out/run27/` for: pairing, hub-normal, hub-empty, hub-offline, composer, builder-sheet, shots, send, pane
   — each Light AND Dark (`xcrun simctl ui booted appearance dark`), iPhone 16 Pro. Use `xcrun simctl io booted screenshot`.
   Drive the app into each state with the mock (MOCK_STATE) and launch arguments (`-uiState composer` etc. you define).
6. `ios/README.md`: how to open, pick a team, run on device, the cert-trust decision, launch args, how to regenerate the project.

ACCEPTANCE (paste outputs):
- Final `xcodebuild … build` succeeds for the simulator with zero warnings in `ios/` sources.
- `swift test` in the repo root (with the CLT flags in SPEC.md:33-37) still passes — you must not have changed anything there.
- All 18 screenshots exist and you looked at each one (Read tool) and fixed anything that is not Apple-native: wrong fonts,
  custom chrome where a system component exists, glass on content, missing large title, truncated text at Dynamic Type Large.
- Report ≤25 lines: commits (hash + title), gate outputs, the cert-trust decision, what is NOT done and why.
