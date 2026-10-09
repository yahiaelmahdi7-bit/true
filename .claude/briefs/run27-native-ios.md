# Run 27 — True for iPhone (native SwiftUI), built from the Apple Design Hub components

**One sentence:** a sideloaded iOS 26 app that does everything the phone web app does (Hub · Shots · Send · Start work ·
live panes) with the two things a web page cannot: background "Needs you" notifications and a Share Extension.
The web app (Run 26) stays as the no-install fallback and keeps the same /api + WS contract.

## Source of truth for the look
`~/Projects/hig-sample-book` (Apple Design Hub). Every control below is named by its registry ID; resolve an ID
to exact SwiftUI with `docs/COMPONENT-IDS.md` (or `docs/component-ids.json`). Rules: **system components, never
look-alikes**; glass only on the controls layer (tab bar, toolbar, floating +), never in content; content scrolls
under glass; verify Light, Dark, Reduce Transparency, Reduce Motion, Dynamic Type AX3.
Colour doctrine carries over from Run 26: monochrome system colours, ONE accent (warm amber, `Color("Attention")`)
for Needs you / Failed / unread / danger / offline only. No green. Terminal background always black.

## Shape
```
TabView (tab-view.default)          tabs: Hub · Shots · Send          floating + = toolbar.default glass capsule
└ NavigationStack (navigation-stack) large title per tab, collapses on scroll (system)
   Hub   : List inset grouped (list.style-inset + section-header.standard), one Section per project, rows → PaneView
   Shots : LazyVGrid 3-up, tap → fullscreen viewer, context-menu.default (Copy · Save · Delete)
   Send  : Form (form.grouped): From your Mac (clip/drop rows with swipe-actions) · To your Mac (ShareLink/PhotosPicker) · Clipboard (text-field.axis-vertical)
   +     : sheet.default with .presentationDetents([.medium,.large]) + .presentationDragIndicator(.visible) → Composer
```

## Screens → component IDs
| Screen | Element | ID | Notes |
|---|---|---|---|
| Pairing | title/subtitle | `navigation-stack` large title "Pair this phone" | 6 digit cells = one hidden `text-field` + `.textContentType(.oneTimeCode)`, cells drawn with `.fill.quaternary`; Pair = `button.prominent` + `controlSize(.large)` |
| Hub | project groups | `list.style-inset` + `section-header.standard` | header trailing = group summary `.secondary` |
| Hub | row | `labeled-content.default` | icon tile 44pt `.fill.quaternary`, title `.body` semibold, path `.subheadline .secondary`, status = `label.secondary` with 8pt dot; Needs you/Failed use the accent |
| Hub | counts | `badge.numeric` | on the tab icon: unread Needs you count |
| Hub | refresh | `refreshable.default` | plus WS push; 10 s poll fallback |
| Hub | empty | `content-unavailable-view.custom-actions` | "Nothing running" · action "Start work" |
| Hub | offline | `content-unavailable-view.default` after 3 failed polls; transient = system `.toolbar` status pill (`toolbar.default` glass) | never a banner |
| Hub | row actions | `swipe-actions.default` | Wake/Sleep seat · Ack builder |
| Builder sheet | log | `sheet.default` + `Text` in `.monospaced` inside `group-box.default` | Ack = `button.prominent` |
| Composer | text | `text-field.axis-vertical` lineLimit(3...6), `.submitLabel(.go)`, newline stripped (SPEC rule) | Recent = `list.style-plain` |
| Composer | Route / Run | Route = `button.bordered` once a route is shown, `button.prominent` before; Run = `button.prominent` (single primary) | |
| Composer | slot chips | `segmented-control.enabled` when ≤3 candidates else `Menu` (`context-menu.default` grammar) | uncertain slot = `.tint(.attention)` |
| Composer | background toggle | `form-row.default` + `Toggle` | |
| Composer | danger confirm | `alert.default` with destructive role | fail-closed, matches phone confirm rule |
| Pane | terminal | SwiftTerm iOS `TerminalView` | black bg; keyboard accessory = `toolbar.item-group` (Esc · Tab · ⌃C · ↑ ↓ · paste) |
| Shots | grid | `LazyVGrid` 3-up, 1pt gaps, no radius (Photos grammar) | viewer = `.navigationTransition(.zoom)` |
| Shots | empty | `content-unavailable-view.default` | |
| Send | lists | `form.grouped` sections | Copy/Save = `button.borderless` row trailing |
| Send | share out | `share-link.custom-preview` + PhotosPicker | |
| Everywhere | progress | `progress.circular-indeterminate` | skeleton = `.redacted(reason: .placeholder)` |
| Everywhere | toast | top glass capsule (`toolbar.default` grammar), 2.4 s, VoiceOver announce | |

## Native-only capabilities (the reason to go native)
1. **Needs you notifications** — BGAppRefreshTask every ~15 min + local notification when `needsYou` rises; tap → that pane.
   Push (APNs) is out of scope (no server). Live Activity for a running builder = stretch.
2. **Share Extension** — share text/image/file from any app → `/api/drop` (replaces the Shortcut token dance).
3. **Keychain** token (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), Face ID gate optional.
4. **Keyboard accessory bar** over the terminal, haptics on Needs you.

## Architecture
```
Package.swift (True)                      ← add library target TrueRemoteClient (Foundation only, macOS+iOS)
  Sources/TrueRemoteClient/               ← pairing, Bearer, /api/* typed calls, WS client, polling; tested on macOS
ios/True.xcodeproj  (NEW, Xcode)          ← app + ShareExtension targets, depends on TrueRemoteClient + SwiftTerm
  True/App, Views/{Pair,Hub,Pane,Shots,Send,Composer}, Services/{Notifications,Keychain,Background}
```
Contract = what `Resources/Remote/app.js` already speaks: Bearer header never cookie, 401 → unpair, WS close 4401 →
unpair, route ids expire (404 → "tap Route again"), 429 backoff, phone panes run `--permission-mode auto`.

## Sideload reality
- Needs **Xcode** (App Store, ~15 GB) — NOT installed on this Mac (CLT only). Install → `sudo xcode-select -s /Applications/Xcode.app`.
- Free Apple ID: builds expire after 7 days, 3 apps max, no Push/Background-modes? (Background fetch IS allowed; APNs is not.)
- Paid account: 1-year signing, TestFlight, APNs later.

## Acceptance
- All Run 26 flows reachable natively; `RemoteTests` untouched and green; TrueRemoteClient tests green on macOS.
- Light/Dark/Reduce Transparency screenshots at iPhone 16 Pro via `xcodebuild test` + XCUITest snapshots (`.out/run27/`).
- /taste pass + HIG step 2 (components: real system ones; glass only on controls) before Yahia sees it.
- Never launch/quit True.app on the Mac (SPEC hard rule).
