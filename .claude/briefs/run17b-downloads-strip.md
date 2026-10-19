# Brief: Run 17b — a "Downloads" strip in the floating screenshot panel

Worktree you are in. Do NOT push, do NOT launch True.app, never read `.claude/heldout/`. Lane: `Sources/True/Model/`,
`Sources/True/Views/`, `Tests/`, `SPEC.md`, `docs/kb/`. Commit in small steps (tests with the code they cover). Gate =
docs/kb/conventions.md:5-9 exactly (plain `swift test` fails). Every existing test stays green; weaken none.

Why (Yahia, verbatim): "also a way to drop in file location from my recent downloads folder so i can attach them to my
session". He chose BOTH a `/dl` command in his Claude Code mod (done separately, not your lane) AND a Downloads strip in
True's floating panel (this run). Run 17 (merged, 4e0b7ec) built the panel: `Views/TrayPanel.swift`,
`Views/TrayPanelViews.swift` (`GridPanel` at ~line 76), `Model/ScreenshotWatcher.swift` (`send`, `paste(path:)` ~308-330),
`Terminal/TerminalDrop.swift` (`pastePath(for:)`), `fileProvider(_:)` for drag-out.

## What to build
1. **Model — `Model/DownloadsList.swift`.** Pure, testable: `static func recent(_ entries: [DownloadItem], limit: Int = 8)
   -> [DownloadItem]` where `DownloadItem { name, url, isDirectory, size, modified: Date }`. Keep entries from the TOP LEVEL
   of `~/Downloads` only; skip names starting with `.`; skip partial downloads by suffix, case-insensitive:
   `.crdownload .download .part .partial .tmp` (this must match the mod's filter exactly: files AND folders kept,
   nothing else). Newest `modified` first, then name for ties. A lister that reads the directory with
   `contentsOfDirectory(at:includingPropertiesForKeys:[.isDirectoryKey,.fileSizeKey,.contentModificationDateKey])`, with
   the directory URL injectable for tests. Missing or unreadable `~/Downloads` → empty list + `unreadable` flag, never a
   crash.
2. **Refresh.** Re-list when the panel expands, and live while expanded via a `DispatchSource` file-system object on the
   Downloads directory (`.write`), the same way `ScreenshotWatcher` watches its folder. No polling timer. No refresh
   work while collapsed.
3. **View — a "Downloads" section in `GridPanel`, below the screenshot grid.** Header row "Downloads" + count + a folder
   button (open ~/Downloads in Finder). Up to 8 compact rows: file icon (`NSWorkspace.shared.icon(forFile:)`), name
   (middle-truncated), size + relative age in secondary text. Per row: **drag-out** gives the file URL (reuse
   `fileProvider`), **Send to session** pastes the shell-escaped path into the focused True pane (reuse the existing
   paste path, `TerminalDrop.pastePath(for:)`; do NOT write to `outbox.jsonl`, which is for tray shots only), **Copy path**
   (plain path to the pasteboard). Empty state: "No recent downloads". Unreadable: same Privacy Settings pattern the
   screenshot section already uses. The screenshot grid keeps its current height; the panel grows to fit the strip.
4. **Never copy or move Downloads files.** The strip only points at them. TrayStore is untouched.

## Design bar
Read `~/.claude/skills/taste/SKILL.md` first and match Run 17's panel exactly (same type sizes, `IconButton`, spacing,
Theme tokens). Quiet, native, dark-first. In result.md list exactly what Yahia must eyeball (you cannot launch the app).

## Tests (unit-level, no app launch)
`DownloadsList.recent`: newest-first order, limit 8, dotfiles skipped, each partial suffix skipped (incl. upper-case),
folders kept, empty dir → [], missing dir → [] + unreadable. Use a temp directory with files whose mtimes you set.

## SPEC / KB
Add a short "Downloads strip" paragraph under the Run 17 "Screenshot panel" section in SPEC.md, and one line in
docs/kb/decisions.md (points at files, never copies; filter mirrors the mod's `/dl`). Final: gate output tail in result.md.
