You are building **True for iPhone — Run 28, the deep design pass** inside the git worktree
`/Users/y/Projects/true.builders/true-mobile-redesign-20261009` (branch `builder/true-mobile-redesign`, HEAD ba8dd19). This is your cwd.
Run 27 already built a working app in `ios/`; you are finishing its design to first-party-Apple quality. Do not rebuild from scratch.

READ FIRST (in this order, they are the truth):
1. `.claude/briefs/run28-deep-design.md` — THE spec for this run: settled decisions, per-screen changes, acceptance. Follow it literally.
2. `ios/True/Views/*.swift`, `ios/True/App/*.swift`, `ios/README.md` — what exists. Keep working behaviour; change the design.
3. `~/Projects/hig-sample-book/docs/COMPONENT-IDS.md` — resolve any component to its exact SwiftUI (grep the id). Real system
   components, never look-alikes.
4. `~/.claude/skills/apple-hig/references/` — the HIG mirror. Read `materials.md`, `lists-and-tables.md`, `sheets.md`, `toolbars.md`,
   `app-icons.md`, `typography.md`, `motion.md` BEFORE touching the matching screen. Read the page, do not recall it.
5. `~/.claude/design/FINISH-STANDARD.md` sections A–G — what "finished" means (states, hierarchy, rhythm, one repeated device, feedback,
   edge robustness).
6. `.claude/briefs/run27-native-ios.md` — the contract and colour doctrine from Run 27, still binding.

DISCIPLINE (non-negotiable):
- Lane: ONLY `ios/` and `.out/run28/`. Do NOT touch `Package.swift`, `Sources/`, `Resources/`, `Tests/`, `scripts/`. If the mock server
  needs a new state for a screenshot (e.g. needsYou > 0 is already in `normal`), use what it has; if truly blocked, report BLOCKED with the
  exact diff — do not edit it.
- Commits: atomic, one screen or one component per commit, message says what + why. NEVER push, NEVER merge. Do not `git stash`.
  Do not cd to ~/Projects/true. Never launch or quit the Mac app True.app.
- Gates in the FOREGROUND, wait for them. No background shells, no watch modes. Shut down simulators you booted
  (`xcrun simctl shutdown all`) before finishing. Mock server: `timeout 180 env MOCK_PORT=8899 MOCK_STATE=normal python3 scripts/remote-mock.py &`
  is NOT allowed as a detached process across steps — run it with `timeout` per screenshot batch and wait for it to exit.
- Claims: "done" = you ran the gate and pasted the passing output. Never report a state you did not verify this session.
- No new Homebrew installs. Use what is on the Mac.

TOOLING FACTS:
- Xcode 26.6, iOS SDK 26.5, iOS 26.5 simulator runtime installed. `xcodegen` at /opt/homebrew/bin/xcodegen; `ios/True.xcodeproj` is
  git-ignored — regenerate with `cd ios && xcodegen generate` after adding files (add new files under `ios/True/Views/Components/`).
- Build gate: `cd ios && xcodebuild -project True.xcodeproj -scheme True -destination 'generic/platform=iOS Simulator' build
  CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation` (the plugin flag is required on the command line).
- Symbol gate: `python3 ~/.claude/skills/apple-hig/bin/symbols.py check <file.swift>` on every Swift file you touch (exit 1 = invented
  symbol; `symbols.py find <word>` to search 9.5k real names).
- Simulator: create/boot an iPhone 16 Pro on iOS 26.5; `xcrun simctl ui booted appearance dark|light`; screenshots via
  `xcrun simctl io booted screenshot`. Launch args: `-baseURL http://localhost:8899 -autoPair 123456 -uiState <screen>`; AX type size:
  `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL`. Add `-uiState needsyou|viewer|composer-routed` if you need
  new states (Debug only, as Run 27 did).
- iOS 26 APIs you may rely on: `.navigationSubtitle`, `.buttonStyle(.glass)` / `.glassProminent`, `.glassEffect`, `Button(role: .close)`,
  `.navigationTransition(.zoom(sourceID:in:))` + `.matchedTransitionSource`, `.sensoryFeedback`, `.symbolEffect`, `.quickLookPreview`,
  `.contentTransition(.numericText())`. If one does not compile on this SDK, use the nearest system equivalent and note it.

BUILD ORDER (commit after each step that builds):
1. `Views/Components/TileRow.swift` (the one device) + move `ToastView`/`StartWorkButton` into `Views/Components/`; refactor `RowView`
   callers onto `TileRow`. Build gate.
2. Hub: subtitle, Needs-you section, status/elapsed treatment, pulse (motion-gated), swipe + context menus, zoom transition.
3. Pane: subtitle, menu, accessory bar with symbols, keyboard summon button, glass status capsule.
4. Composer: focus on open, plan TileRows, Run in bottom glass action area with the mode Menu, single-primary rule.
5. Shots: day sections, viewer with share/save + caption, context menu without Delete, states.
6. Send: TileRows, Paste row, QuickLook, pending + success feedback, empty footer.
7. Pairing: step TileRows in a Form, glassProminent Pair in safeAreaInset, error footer, success haptic.
8. App icon: SVG layers in `ios/Design/Icon/`, rendered 1024 PNG into the appiconset, README Icon Composer step.
9. Screenshots to `.out/run28/` exactly as the spec's acceptance lists (Light + Dark + AX3 + Reduce Transparency). LOOK at every one
   (Read tool) and fix what is not first-party quality: custom chrome where a system component exists, glass on content, amber on a
   control, truncated titles at AX3, missing states.
10. Update `ios/README.md` (launch args, icon step). Final gates: build (zero warnings in ios/), symbols check on all files, `swift test`
    at repo root with the CLT flags from SPEC.md:33-37.

REPORT (≤25 lines): commits (hash + title) · gate outputs · which screenshots you reviewed and what you fixed · anything NOT done and why ·
any API that did not exist on this SDK and what you used instead.
