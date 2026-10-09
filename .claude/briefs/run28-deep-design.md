# Run 28 — True for iPhone: the deep design pass (NATIVE mode, HIG wins)

**One sentence:** Run 27 made the app *correct*; Run 28 makes it *designed* — the same screens, finished to the standard of a
first-party Apple app, with one structural device repeated everywhere, every state handled, and attention-first ordering.

Sources of truth, in order: `~/.claude/skills/apple-hig/references/*.md` (HIG mirror) · `~/Projects/hig-sample-book/docs/COMPONENT-IDS.md`
(exact SwiftUI per component) · `~/.claude/design/FINISH-STANDARD.md` (states, hierarchy, rhythm, the repeated device, feedback,
edge robustness) · Run 27 spec `.claude/briefs/run27-native-ios.md` (contract + colour doctrine, still binding).

## Design decisions (settled — do not re-litigate)
1. **Controls float, content sits.** Liquid Glass ONLY on: tab bar, nav/toolbars, the + button, the toast, the pane key bar,
   the sheet's bottom action area. Never on rows, tiles, cards, or the terminal. (`materials.md`)
2. **Two colours, two meanings.** App tint = system default (blue) for *interactive* only. `Color.attention` (warm amber) for
   *state* only: Needs you · Failed · offline · uncertain slot · risky. Never amber on a button label, never blue on a status.
   No green anywhere. Everything else is the semantic ramp (`.primary/.secondary/.tertiary`, `.fill.quaternary`).
3. **The one structural device = icon tile + title + detail.** A 44×44 `.fill.quaternary` tile (radius 10, continuous) holding one
   SF Symbol (`.title3`, `.secondary`), then `title` (`.body.semibold`) over `detail` (`.subheadline.secondary`), optional trailing
   status. It already exists as `RowView`. Reuse it — not look-alikes — in: Hub rows, Needs-you rows, Send rows (clipboard, files,
   Photo, File, Paste), Composer plan rows (Does/Where/Project), Pairing steps, Builder sheet header, Pane header menu. Extract it
   to `Views/Components/TileRow.swift` with `TileRow(symbol:title:detail:trailing:)`.
4. **Order by importance.** Needs-you rows float to the top of the Hub in their own section, before projects. (`layout.md`)
5. **Every surface has empty / loading / error / partial / pending.** Loading = redacted rows in the shape of the content, never a
   spinner in a void (except inside a pressed button). Error = plain sentence + the retry affordance. (`FINISH-STANDARD.md` A)
6. **Type = system text styles only**, ≤5 sizes per screen, no light weights, monospaced only inside terminal/log content.
   Tabular digits on elapsed times and counts (`.monospacedDigit()`).
7. **Motion carries meaning or does not ship.** Allowed: the system's own (sheet, zoom navigation transition, swipe); a slow
   `.symbolEffect(.pulse)` on the status dot of *Working* rows only; `.contentTransition(.numericText())` on counts. All gated by
   `@Environment(\.accessibilityReduceMotion)`. Nothing ambient.
8. **Feedback is multi-modal.** `.sensoryFeedback(.success)` on pair / sent / acked; `.warning` on Needs-you rise (exists);
   toast with a leading symbol; VoiceOver announcement (exists).
9. **Hit targets ≥ 44pt**, VoiceOver label + value on every row and icon-only button, layout survives AX3 Dynamic Type
   (status wraps under the title at `dynamicTypeSize.isAccessibilitySize`, never truncates the title).

## Screen by screen (what changes vs Run 27)

### Hub (home)
- `.navigationTitle("Hub")` + `.navigationSubtitle(hub.summary)` (iOS 26 iPhone API) — the summary leaves the section headers.
- **Section "Needs you"** (only when `hub.needsYou > 0`): every `needsYou`/`failed` row across projects, amber status, leading
  `exclamationmark.circle.fill` in the tile for failed builders. Section footer: none.
- Project sections keep title + trailing summary `.secondary`. Rows = `TileRow`. Detail line: seat → cwd (middle-truncated);
  builder → branch or cwd. Trailing: status dot (8pt) + status word; Working adds elapsed `.caption.monospacedDigit().tertiary`
  on a second line when present.
- Working dot pulses (`.symbolEffect(.pulse, options: .repeating)` on `circle.fill`) unless Reduce Motion. Needs you / Failed are
  static amber. Asleep / Idle / Done `.tertiary`.
- Swipe trailing: `Label("Wake", systemImage: "sunrise")` / `Label("Sleep", systemImage: "moon.zzz")` (tint `.gray`), builders
  `Label("Ack", systemImage: "checkmark")`. Swipe leading on seats: `Label("Open", systemImage: "terminal")`, full swipe opens.
- Context menu (`.contextMenu`): Open · Wake/Sleep · Copy name · Copy path.
- Row → pane uses `.navigationTransition(.zoom(sourceID: row.id, in: ns))` with `.matchedTransitionSource` on the row.
- Offline/empty/loading as Run 27, but loading = 6 redacted `TileRow`s in grouped sections (already) and the reconnecting pill
  becomes `ToolbarItem(.principal)` glass `Label("Reconnecting", systemImage: "arrow.triangle.2.circlepath")`
  `.symbolEffect(.rotate)` (motion-gated).
- Tab badge stays (`badge.numeric`).

### Pane (terminal)
- Inline title = seat name; `.navigationSubtitle(status)` tinted amber when Needs you.
- Trailing toolbar: `Menu` (`ellipsis.circle`): Wake/Sleep · Copy name · Copy path. One group, no text labels next to symbols.
- Keyboard accessory bar (UIToolbar, system): `escape` → "esc" text, "tab" text, "⌃C" text, `arrow.up`, `arrow.down`, `return`,
  `doc.on.clipboard`. Symbols where a symbol exists, text where it does not. ≥44pt each; `accessibilityLabel`s.
- When the keyboard is hidden show a bottom `safeAreaInset` glass circle button `keyboard` (`.buttonStyle(.glass)`) that makes the
  terminal first responder; hide it while the keyboard is up (observe `UIResponder.keyboardWillShow/Hide`).
- Terminal: black, SF Mono via `monospacedSystemFont`, font fit-to-columns as now but floor 9pt; `.ignoresSafeArea(.keyboard)`
  handled by SwiftTerm. Status capsule (Reconnecting / closed) = glass, bottom, with symbol.

### Composer (sheet, "Start work")
- Text field focused on open (`@FocusState` + `.task { focused = true }`), `.textInputAutocapitalization(.sentences)`.
- Route (prominent until a route exists, then bordered) stays in the first section. Error sentence under it with
  `exclamationmark.triangle` amber `Label`.
- Plan rows = `TileRow` with symbols: Does → `sparkles`, Where → `rectangle.split.2x1`, Project → `folder`, Model → `cpu`,
  Effort → `gauge.with.dots.needle.33percent` (check with symbols.py; fall back to `dial.low`). Uncertain slot: amber title +
  trailing `chevron.up.chevron.down` and the segmented/menu picker as now.
- Recent = plain list rows with `clock.arrow.circlepath` tile, `.secondary` text, tap fills.
- **Run** moves to a bottom `safeAreaInset` action area: `Button("Run")` `.buttonStyle(.glassProminent)` `.controlSize(.large)`
  full width; left of it a `Toggle` is wrong — use a `Menu` labelled by the current mode ("In a pane" / "In the background",
  symbol `rectangle.on.rectangle` / `hammer`). Only one primary on screen at any time (Route demotes when Run appears).
- Danger alert unchanged (system alert, destructive role).

### Shots
- Grid 3-up, 1pt gaps, square `.clipped()`, grouped by day with `Section` headers "Today / Yesterday / <date>" using
  `.formatted(.relative(presentation: .named))` when `created` parses as ISO-8601, else one ungrouped grid.
- Tap → full-screen viewer: black, `.navigationTransition(.zoom)`, toolbar `ShareLink` + "Save" (`square.and.arrow.down`),
  caption bar bottom glass `created · w×h` `.caption.monospacedDigit()`. Tap toggles chrome (`.toolbarVisibility`).
- Context menu on tiles: Share · Save (no Delete — there is no endpoint; do not show a dead item).
- Empty: `camera.viewfinder`, "No screenshots yet", "Screenshots your seats take on the Mac appear here."
- Loading: 9 redacted squares. Error: `ContentUnavailableView` with retry button.

### Send
- "From your Mac": clipboard = `TileRow(doc.on.clipboard, "Clipboard", preview)` trailing `Copy` borderless; files =
  `TileRow(doc / photo / zipper by kind, name, size)` trailing `Save`; tap a file row → `.quickLookPreview`.
- "To your Mac": `TileRow(photo.badge.plus, "Photo")` (PhotosPicker), `TileRow(doc.badge.plus, "File")` (fileImporter),
  **new** `TileRow(doc.on.clipboard, "Paste", "Send what's on this phone's clipboard")` — one tap, uses `UIPasteboard.general`.
- "Clipboard" text section stays (axis vertical, Send borderless trailing, disabled when empty).
- After any send: `.sensoryFeedback(.success)` + toast "Sent to your Mac". Pending state on the row (ProgressView replaces trailing).
- Empty "From your Mac": footer text "Copy something on the Mac or drop a file in True to see it here." — not a blank group.

### Pairing (first run)
- Large title "Pair this phone"; under it the three steps as `TileRow`s in an inset-grouped `Form` section:
  `macbook.and.iphone` "Open True on your Mac" / "Remote Access in the menu" · `network` "Type the Mac's address" /
  "your-mac.tailnet.ts.net:8444" · `number` "Enter the 6-digit code" / "Shown on the Mac for 5 minutes".
- Section "Mac address": `TextField` (`.textContentType(.URL)`, no autocap). Section "Pairing code": the six cells (exists),
  `.textContentType(.oneTimeCode)`.
- Error: amber `Label(error, systemImage: "exclamationmark.triangle")` footer under the code section.
- Pair = bottom `safeAreaInset` `.glassProminent` `.controlSize(.large)`, disabled until valid; pressed → ProgressView inside.
- Success: `.sensoryFeedback(.success)` then the root swaps to tabs with the default cross-fade.

### Global
- `RootTabs`: unchanged structure. Toast gains a leading symbol (`checkmark.circle` / `exclamationmark.circle` amber for errors).
- `ToastView` and `StartWorkButton` move to `Views/Components/`.
- **App icon**: produce `ios/True/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` rendered from two vector layers you also
  save as `ios/Design/Icon/background.svg` + `foreground.svg` (for Icon Composer later): background = warm near-black
  `#1A1A18`; foreground = an amber (`#E8A23C`) prompt chevron `>` centred-left plus a translucent amber cursor block
  (60 % opacity) to its right, geometric, no text, no gradient. Render the PNG with `rsvg-convert` if present, else `qlmanage`/
  `sips` from a PDF, else a tiny Swift script using CoreGraphics — pick what works, no new Homebrew installs. README gets the
  two-minute Icon Composer step (drag the two SVGs in, export `.icon`).
- Accessibility: every `TileRow` is `.accessibilityElement(children: .combine)` with the status as `.accessibilityValue`;
  icon-only buttons get labels; `-dynamicTypeSize` screenshots at `accessibility3` must show no truncated titles.

## Acceptance (paste outputs)
- `xcodebuild … build CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation` succeeds, zero warnings in `ios/`.
- `python3 ~/.claude/skills/apple-hig/bin/symbols.py check <file>` exit 0 for every Swift file in `ios/` (no invented symbols).
- `swift test` in the repo root (CLT flags, SPEC.md:33-37) still passes — nothing outside `ios/` changed.
- Screenshots in `.out/run28/`: pairing, hub-normal, hub-needsyou (mock has needsYou>0 → section on top), hub-empty, hub-offline,
  composer-before-route, composer-routed, builder-sheet, shots, shot-viewer, send, pane — Light AND Dark; plus hub-normal and
  composer-routed at `-dynamicTypeSize accessibility3` (`xcrun simctl` launch arg `-UIPreferredContentSizeCategoryName
  UICTContentSizeCategoryAccessibilityL`) and hub-normal with Reduce Transparency on (`xcrun simctl spawn booted defaults write
  com.apple.Accessibility ReduceTransparencyEnabled 1` or the a11y settings in Settings app). You looked at every file (Read tool)
  and fixed anything that is not first-party-Apple quality before reporting.
