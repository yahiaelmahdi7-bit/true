You are building **True for iPhone — Run 30: nearby pairing over Bluetooth (the AirPods card)** inside the git worktree
`/Users/y/Projects/true.builders/true-mobile-redesign-20261009` (branch `builder/true-mobile-redesign`, HEAD 623eaaa + the spec commit).
This is your cwd. Runs 27–29 built, designed and extended the app in `ios/`; you are adding ONE feature on both sides: a Bluetooth "nearby" trigger that pops the pairing QR card on the Mac.

READ FIRST (in this order, they are the truth):
1. `.claude/briefs/run30-nearby-pair.md` — THE spec for this run: settled decisions, protocol, deliverables, acceptance. Follow it literally. Then `.claude/briefs/run29-qr-clipboard-select.md` for the QR/PairLink contract.
2. `.claude/briefs/run28-deep-design.md` — the design doctrine (glass only on controls, blue/amber, TileRow, states, AX3). Still binding.
3. `Sources/True/Views/TrayPanel.swift` (the floating top-right NSPanel pattern to copy), `Sources/True/Remote/{RemoteAccess,RemoteAuth}.swift`
   (`newCode`, `PairingCodes`, `devices`, the Remote Access sheet), `Sources/TrueRemoteClient/{PairLink,SharedConfig}.swift`,
   `ios/True/Views/{PairView,ScanSheet}.swift`, `ios/True/App/AppModel.swift` (`pair`, `handle(url:)`, `paired`), `scripts/package.sh`
   (the Mac Info.plist lives there), `Tests/TrueTests/{PairLinkTests,ClipboardShareTests}.swift` (test style), `ios/README.md`.
4. Apple's CoreBluetooth docs for `CBPeripheralManager` / `CBCentralManager` on macOS 26 and iOS 26 — use context7 or the SDK headers,
   do not recall API names. The simulator has NO Bluetooth; everything real sits behind the protocols the spec names.
5. `~/Projects/hig-sample-book/docs/COMPONENT-IDS.md` and `~/.claude/skills/apple-hig/references/` (grep for edit menus, context menus,
   machine-readable codes / camera, toggles). Read the page, do not recall it.

DISCIPLINE (non-negotiable):
- Lane: `ios/`, `Sources/TrueRemoteClient/` (new NearbyPairing.swift), `Sources/True/Remote/` (new NearbyAdvertiser.swift +
  NearbyPairCard.swift, small hooks in RemoteAccess.swift only), `scripts/package.sh` (one plist key), `Tests/TrueTests/`, `ios/README.md`,
  `.out/run30/`. Nothing else under `Sources/True/`. Do NOT touch `Package.swift` unless a new file needs a target entry (it should not —
  targets are directory-based). Never launch or quit the Mac app True.app. Never touch real Bluetooth hardware from a test; drive the fakes. Never read the Mac clipboard
  in a test.
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
  `-destination 'id=<udid>' -derivedDataPath ../.out/run30/dd`, then `xcrun simctl install`. Bundle id `net.prismlens.true`.
  Launch args: `-baseURL http://localhost:8899 -autoPair 123456 -uiState <screen>`; AX type:
  `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL`. `xcrun simctl ui booted appearance dark|light`;
  screenshots `xcrun simctl io booted screenshot <path>`. `.out/run28/shoot.sh <mockstate> <uiState> <out> [dark|light]` exists —
  `export BID=net.prismlens.true` first, copy it to `.out/run30/shoot.sh` and point it at the run30 derived data.
  The mock prints the builder log 6× and the address shows localhost because of `-autoPair` — not bugs.
- The simulator has no camera: `DataScannerViewController.isSupported` is false there. That IS the `pair-scan` screenshot (the
  unavailable state). Do not fake a camera.
- iOS 26 APIs you may rely on: `.navigationSubtitle`, `.buttonStyle(.glass)` / `.glassProminent`, `.glassEffect`, `Button(role: .close)`,
  `ContentUnavailableView`, `UIEditMenuInteraction`, `.sensoryFeedback`, `.symbolEffect`, `@AppStorage`. If one does not compile on this
  SDK, use the nearest system equivalent and note it.

BUILD ORDER (commit after each step that builds):
1. Shared `Sources/TrueRemoteClient/NearbyPairing.swift`: service + characteristic UUIDs, RSSI threshold constant, hello payload
   codec (`"<name>|<id>"` encode/decode with tests). `swift build` + filtered `swift test`.
2. Mac `NearbyAdvertiser` behind a protocol + fake; `RemoteAccess` hooks (start/stop with Remote Access and the new toggle);
   plist key in `scripts/package.sh`. Tests for start/stop. `swift build` + filtered `swift test`.
3. Mac `NearbyPairCard` (panel + content per spec decision 3) + the hello → present path + rate limit + auto-hide + paired flip.
   Tests with the fake. `ImageRenderer` snapshot test writes `.out/run30/mac-card-{light,dark}.png`. LOOK at them.
4. iPhone `NearbyScanner` behind a protocol + fake; `AppModel.nearbyMac`; plist key in `project.yml`; `xcodegen generate`. iOS build gate.
5. iPhone `PairView` nearby card + Bluetooth state line + `-uiState pair-nearby`. iOS build gate. Screenshots per the spec; LOOK at them.
6. `ios/README.md` section. Final gates: iOS build (zero warnings in ios/), symbols check on all touched files, full `swift test`.

REPORT (≤25 lines): commits (hash + title) · gate outputs (summary lines) · which screenshots you reviewed and what you fixed ·
the exact hardware checklist for Yahia (he will run the real Bluetooth test on his iPhone 17 + this Mac) · anything NOT done and why ·
any API that did not exist on this SDK and its replacement.