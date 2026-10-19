# Brief: Run 17 — the screenshot tray becomes an always-on floating panel with its own memory and markup

Worktree you are in. Do NOT push, do NOT launch True.app, never read `.claude/heldout/`. Lane: `Sources/True/Model/`,
`Sources/True/Views/`, `Sources/True/TrueApp.swift`, `Tests/`, `SPEC.md`, `docs/kb/`. Commit in small steps (tests
with the code they cover). Gate = docs/kb/conventions.md:5-9 exactly (plain `swift test` fails). Every existing test
stays green; weaken none.

Why (Yahia, verbatim): "keep the screenshot tray always alive on the top right and also have it memory persistent and
survives reset" · "make it so it has motion to toggle expanded zoom into the image with direct editing controls to mark
up and interact with in my claude code sessions". His choices: shape = floating panel at the top right of the SCREEN,
above all apps; persistence = True keeps its own copies (last 24), surviving Desktop cleanup / app restart / reset.

Today: `Views/ScreenshotTray.swift` is a 1pt tab-bar slot (`Views/TabBar.swift:22`) with a popover that closes on
click-away; `Model/ScreenshotWatcher.swift` watches the folder (kqueue), keeps nothing, and does not scan at launch, so
the tray is empty after every restart. The macOS screenshot folder is now `~/Pictures/Screenshots` (was Desktop).

## T1 — TrayStore: True's own copies (pure, fully unit-tested)
New `Model/TrayStore.swift`. Root = `~/Library/Application Support/True/ScreenshotTray/` (injectable root URL for tests).
THE CONTRACT (a Claude Code mod reads these files; keep the names and fields exactly):
- `shots/<id>.png|jpg|...` — copies. `id` = `yyyyMMdd-HHmmss-<4 hex>` (sortable, unique).
- `index.json`, written atomically (temp file + rename), newest first, at most 24 entries:
  `{"version":1,"updated":"<ISO8601>","shots":[{"id":"…","file":"shots/<id>.png","created":"<ISO8601>",
  "kind":"original"|"markup","parent":"<id>"|null,"source":"<original path>"|null,"width":0,"height":0}]}`
- `outbox.jsonl` — append-only, one line per "Send": `{"ts":"<ISO8601>","id":"…","path":"<absolute copy path>",
  "action":"send"}`. Never rewritten; trim to the last 200 lines only when it passes 1000.
Rules: ingest COPIES (never moves or touches the original); dedupe by source path + size + mtime; prune beyond 24 by
moving the oldest copies to the Trash (`FileManager.trashItem`), never a hard delete; missing or corrupt index →
rebuild from `shots/` by file date without losing a file; all IO off the main thread; never throws to callers.
First run: backfill the newest 24 screenshot-named images from the current folder AND `~/Desktop`.

## T2 — the watcher feeds the store and follows the folder setting
`ScreenshotWatcher`: on launch, ingest anything newer than the newest index entry (one listing). Every new shot is
ingested into TrayStore. Re-read `currentFolder()` at launch, on `NSApplication.didBecomeActiveNotification`, and when
the panel expands; restart the watch if it changed. The panel's data source becomes TrayStore (not the raw folder).
Keep ⌥⌘V (paste latest) working from the store.

## T3 — the floating panel (non-activating NSPanel, top right of the screen)
- `NSPanel` subclass: `.nonactivatingPanel`, borderless, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces,
  .fullScreenAuxiliary]`, `hidesOnDeactivate = false`; becomes key only when the editor needs typing. Shown at launch;
  pinned to the top-right of the screen under the mouse (`visibleFrame`, 12pt inset), re-pinned on screen changes.
  Pure function `TrayPanelFrame.topRight(visible:size:inset:) -> CGRect`, unit-tested.
- Collapsed: a small pill (latest 3 thumbnails fanned + count, fresh-dot for unseen). Click → expanded grid
  (4 columns, scroll, all 24) with a spring animation of panel frame + content; click-away/Esc → collapse (never hide).
- Click a tile → zoom view: the thumbnail grows into the full image (`matchedGeometryEffect`), panel grows to ~55% of
  the screen width, anchored top-right. Toolbar: Mark up · Copy image (⌘C) · Send to session · Copy path · Reveal in
  Finder · Remove from tray (Trash, with undo toast). Drag a tile or the zoomed image out = file URL drag (works into
  Terminal / Claude Code / Finder).
- "Send to session": paste into True's focused pane (reuse `ScreenshotWatcher.paste(path:)` logic) AND append the
  outbox line.
- Menu: "Screenshots…" (⇧⌘S) toggles expanded/collapsed; new "Show Screenshot Panel" toggles visibility, persisted in
  UserDefaults `screenshotTray.panelVisible` (default true). Remove the tab-bar slot (`TabBar.swift:22`) and the
  popover view.

## T4 — markup editor (inside the zoom view)
Pure value model `Model/Markup.swift`: `enum Mark { pen([CGPoint]), arrow(from,to), rect(CGRect), highlight([CGPoint]),
text(String, at: CGPoint) }` + colour + width, in image-pixel coordinates; `MarkupDoc` with add / undo / redo / clear
(standard undo semantics: a new mark after undo drops the redo stack). Unit-test it.
View: SwiftUI `Canvas` over the image; tools pen, arrow, rect, highlight (wide translucent), text; 3 colours (red,
amber, blue, from the app's existing theme tokens if they exist); ⌘Z / ⇧⌘Z; Save → render at the image's PIXEL size
(`ImageRenderer`, scale 1 over pixel dims) to PNG → TrayStore adds it as `kind:"markup", parent:<id>`, newest first;
Cancel discards. The original copy is never modified.

## Design bar
Before writing UI read `~/.claude/skills/taste/SKILL.md` and match the existing True views. Quiet, native, dark-first;
motion is spring-based and short (≤ 0.35 s), never bouncy for its own sake. In result.md list exactly what Yahia must
eyeball (he verifies visually; you cannot launch the app).

## Tests (unit-level, no app launch)
TrayStore: ingest copies (original untouched), dedupe, prune to 24 → Trash (inject a trash function), index
round-trip, atomic write leaves no partial file, corrupt index rebuild keeps every file, outbox append format + trim,
first-run backfill picks newest 24 across two folders. Markup: add/undo/redo/clear semantics, redo dropped after a new
mark, coordinates stay in pixel space. `TrayPanelFrame.topRight` for two screen sizes + an offset secondary screen.
Folder follow: changed `location` value → watcher reports the new folder (use the existing `folder(fromDefaultsValue:)`).

## SPEC / KB
Add a short "Screenshot panel" section to SPEC.md (behaviour + the T1 contract verbatim). Add one decision note in
docs/kb (why own copies, why non-activating panel, the contract). Final: gate output tail in result.md.
