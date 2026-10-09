You are building **True for iPhone — Run 29: QR pairing, terminal text selection/copy, cross-device clipboard** inside the git worktree
`/Users/y/Projects/true.builders/true-mobile-redesign-20261009` (branch `builder/true-mobile-redesign`, HEAD 9afa279 + the spec commit).
This is your cwd. Runs 27–28 built and designed the app in `ios/`; you are adding three features to it, on both the Mac side and the phone.

READ FIRST (in this order, they are the truth):
1. `.claude/briefs/run29-qr-clipboard-select.md` — THE spec for this run: settled decisions, three deliverables, acceptance. Follow it literally.
2. `.claude/briefs/run28-deep-design.md` — the design doctrine (glass only on controls, blue/amber, TileRow, states, AX3). Still binding.
3. `ios/True/Views/{PairView,PaneView,SendView,RootTabs}.swift`, `ios/True/App/*.swift`, `Sources/TrueRemoteClient/*.swift`,
   `Sources/True/Remote/{RemoteAccess,RemoteDrop,RemoteServer,RemoteFilesLive}.swift`, `Tests/TrueTests/RemoteDropTests.swift`
   (`clipCapAndNoClipboardReadRoute` is the invariant you must keep green), `scripts/remote-mock.py`, `ios/README.md`.
4. `.build/checkouts/SwiftTerm/Sources/SwiftTerm/iOS/iOSTerminalView.swift` — the public selection surface (`copy`, `selectAll`, `select`,
   `canPerformAction`, `hasActiveSelection`, `selectionChanged`, `longPress` → `showContextMenu` → `UIMenuController`). Read it before
   touching PaneView; do not patch or vendor SwiftTerm.
5. `~/Projects/hig-sample-book/docs/COMPONENT-IDS.md` and `~/.claude/skills/apple-hig/references/` (grep for edit menus, context menus,
   machine-readable codes / camera, toggles). Read the page, do not recall it.

DISCIPLINE (non-negotiable):
- Lane: `ios/`, `Sources/TrueRemoteClient/`, `Sources/True/Remote/` (only RemoteAccess.swift, RemoteDrop.swift, RemoteFilesLive.swift,
  RemoteServer.swift's inbox JSON, plus the new ClipboardShare.swift), `Tests/TrueTests/`, `scripts/remote-mock.py`, `ios/README.md`,
  `.out/run29/`. Nothing else under `Sources/True/`. Do NOT touch `Package.swift` unless a new file needs a target entry (it should not —
  targets are directory-based). Never launch or quit the Mac app True.app. Never read or print anything from the Mac's real clipboard
  in a test — inject a fake pasteboard reader.
- Commits: atomic, one deliverable step per commit, message says what + why. NEVER push, NEVER merge. Do not `git stash`.
  Do not cd to ~/Projects/true.
- Gates in the FOREGROUND, wait for them. No background shells, no watch modes. Shut down simulators you booted
  (`xcrun simctl shutdown all`) before finishing. Mock server: run with `timeout` per screenshot batch and wait for it to exit;
  no detached processes across steps.
- Claims: "done" = you ran the gate and pasted the passing output. Never report a state you did not verify this session.
- No new Homebrew installs. Use what is on the Mac.

TOOLING FACTS:
- Xcode 26.6, iOS SDK 26.5, iOS 26.5 simulator runtime installed. `xcodegen` at /opt/homebrew/bin/xcodegen; `ios/True.xcodeproj` is
  git-ignored — regenerate with `cd ios && xcodegen generate` after adding files or editing `project.yml`.
- iOS build gate: `cd ios && xcodebuild -project True.xcodeproj -scheme True -destination 'generic/platform=iOS Simulator' build
  CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation`.
- Mac gates at repo root: `swift build`; tests need the CommandLineTools flags:
  `FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks; LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib;
  nice -n 10 swift test -j 4 -Xswiftc -F$FW -Xlinker -F$FW -Xlinker -rpath -Xlinker $FW -Xlinker -rpath -Xlinker $LIB`.
  Run the whole suite once at the end; run `--filter RemoteDrop` and your new tests after each Mac step.
- Symbol gate: `python3 ~/.claude/skills/apple-hig/bin/symbols.py check <file.swift>` on every Swift file you touch (exit 1 = invented
  symbol; `symbols.py find <word>` to search real names).
- Simulator: iPhone 16 Pro, iOS 26.5, udid B4962775-232E-4A2B-B365-4948B63AEF8B exists (boot it; create one if missing). Build for it with
  `-destination 'id=<udid>' -derivedDataPath ../.out/run29/dd`, then `xcrun simctl install`. Bundle id `net.prismlens.true`.
  Launch args: `-baseURL http://localhost:8899 -autoPair 123456 -uiState <screen>`; AX type:
  `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL`. `xcrun simctl ui booted appearance dark|light`;
  screenshots `xcrun simctl io booted screenshot <path>`. `.out/run28/shoot.sh <mockstate> <uiState> <out> [dark|light]` exists —
  `export BID=net.prismlens.true` first, copy it to `.out/run29/shoot.sh` and point it at the run29 derived data.
  The mock prints the builder log 6× and the address shows localhost because of `-autoPair` — not bugs.
- The simulator has no camera: `DataScannerViewController.isSupported` is false there. That IS the `pair-scan` screenshot (the
  unavailable state). Do not fake a camera.
- iOS 26 APIs you may rely on: `.navigationSubtitle`, `.buttonStyle(.glass)` / `.glassProminent`, `.glassEffect`, `Button(role: .close)`,
  `ContentUnavailableView`, `UIEditMenuInteraction`, `.sensoryFeedback`, `.symbolEffect`, `@AppStorage`. If one does not compile on this
  SDK, use the nearest system equivalent and note it.

BUILD ORDER (commit after each step that builds):
1. Shared `PairLink` parser in `Sources/TrueRemoteClient/` + Mac QR encodes `true://pair?host=…&code=…` + caption + unit test.
   `swift build` + filtered `swift test`.
2. iPhone: `NSCameraUsageDescription` in project.yml, `ScanSheet` (VisionKit, unavailable + denied states), Scan row in PairView,
   `handle(url:)` accepts `true://pair`, `-uiState pair-scan`. iOS build gate.
3. Terminal selection: DIAGNOSE first in the sim on `-uiState pane` (what does a 0.7 s long-press do today? write it down), then
   `SelectableTerminalView` + `UIEditMenuInteraction` + `selectionChanged` override + Copy key + pane-menu items. iOS build gate.
   Verify by hand in the Simulator app: long-press → menu → Select → handles → Copy → paste into the composer text field proves the
   pasteboard got it. Screenshot the selection state.
4. Mac clipboard share: `PhoneInboxItem.source`, `RemoteInbox.replaceSharedClipboard`, `ClipboardShare` watcher with injected reader,
   toggle in the Remote Access sheet, inbox JSON `source`/`created`, tests. `swift build` + filtered `swift test` incl.
   `clipCapAndNoClipboardReadRoute`.
5. iPhone Send tab: `InboxItem.source/created`, Clipboard section on top (Mac item · Send phone clipboard · auto toggle), "Type for your Mac"
   section moved down, remove the duplicate Paste row, scenePhase auto-copy in AppModel, mock updated. iOS build gate.
6. Screenshots to `.out/run29/` exactly as the spec's acceptance lists. LOOK at every one (Read tool) and fix what is not first-party
   quality. Then `ios/README.md`. Final gates: iOS build (zero warnings in ios/), symbols check on all touched files, full `swift test`.

REPORT (≤25 lines): commits (hash + title) · gate outputs (summary lines) · the long-press diagnosis and which gesture branch you took ·
which screenshots you reviewed and what you fixed · anything NOT done and why · any API that did not exist on this SDK and its replacement.
