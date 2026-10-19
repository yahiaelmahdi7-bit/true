# Brief: Run 18 — full-screen "Shots" overlay (Apple-grade, fun)

Worktree you are in. Do NOT push, do NOT launch True.app, never read `.claude/heldout/`. Lane: `Sources/True/`,
`Tests/`, `SPEC.md`, `docs/kb/`. Commit in small steps (tests with the code they cover). Gate =
docs/kb/conventions.md:5-9 exactly (plain `swift test` fails). Every existing test stays green; weaken none.

Why (Yahia, verbatim, about the floating screenshot panel): "i want this to be a full screen tile like a real mac app
with real desing features that are from apple and have it a fun experiance". Asked to choose, he picked a
**full-screen overlay** (summoned over everything, like Mission Control / Quick Look; Esc dismisses) and these fun
touches: **zoom-open transitions**, **living icons + hover**, **pinch & drag**. He did NOT pick new-shot arrival
sound/bounce — leave that out.

Existing (Runs 17/17b, merged): `Views/TrayPanel.swift` (non-activating floating NSPanel, collapse/expand),
`Views/TrayPanelViews.swift` (`GridPanel`, `IconButton`, Downloads section), `Model/TrayStore.swift` (own copies, last
24), `Model/ScreenshotWatcher.swift` (send/paste), `Model/DownloadsList.swift` (+ kqueue refresh),
`Views/MarkupEditor.swift`, `Terminal/TerminalDrop.swift` (`pastePath(for:)`), `fileProvider(_:)` for drag-out.
**Reuse all of it.** The overlay is a new VIEW over the same stores — no second watcher, no second copy of data.

## Keep the floating panel
The panel stays exactly as it is (quick glance). Add one expand button (SF Symbol
`arrow.up.left.and.arrow.down.right`) to its header that opens the overlay.

## The overlay
1. **Window.** A borderless `NSPanel` covering the full frame of the screen the mouse is on, level above normal windows
   (`.statusBar` or similar; not `.screenSaver`), `collectionBehavior` `[.canJoinAllSpaces, .fullScreenAuxiliary,
   .transient]`, CAN become key (it needs Esc / Space / arrows), does not appear in the Dock or ⌘-Tab. Backdrop =
   behind-window blur of the desktop (`NSVisualEffectView`, `.behindWindow`, `.fullScreenUI` or `.hudWindow`) plus a
   light dim. Click on empty backdrop = dismiss. Esc = close the viewer if open, else dismiss. Losing key (user clicks
   another app) = dismiss.
2. **Summon.** (a) the panel's expand button; (b) a GLOBAL hotkey **⌃⌥⌘S** via Carbon `RegisterEventHotKey` (needs no
   Accessibility permission) — toggles the overlay from any app; (c) a True menu item "Show Shots" with the same
   shortcut displayed. Put the key combo in one constant so it is easy to change.
3. **Layout.** Title row ("Shots" + count, folder button, close button) in Liquid Glass chrome. A big adaptive grid of
   all tray screenshots (newest first, grouped "Today / Yesterday / Earlier" with sticky-ish section labels). Downloads
   as a horizontal glass strip pinned along the bottom (same 8 items, same rows' actions as icon buttons, drag-out).
   Respect safe areas / the notch / menu bar. Comfortable margins; nothing touches screen edges.
4. **Open animation.** Overlay fades in while grid items spring in with a short stagger (< 350 ms total). Dismiss is
   faster (~180 ms). Reduce Motion → plain crossfade, no stagger, no tilt.

## Fun touches (the three he picked)
- **Zoom-open.** Click a thumbnail → it grows in place into a large viewer (`matchedGeometryEffect` /
  `navigationTransition(.zoom)` style; image keeps its aspect, rounded corners morph). Click outside / Esc → shrinks
  back into its exact grid slot. Inside the viewer: ← → move between shots (with a slide), Space toggles a Quick-Look
  style peek from the grid, toolbar in glass: Send to session, Copy, Markup (opens existing `MarkupEditor`), Show in
  Finder, Delete (from tray only, with undo toast — never deletes the user's original file).
- **Living icons + hover.** Use SF Symbol effects: Send → arrow `.symbolEffect(.bounce)` then flies off before the
  overlay dismisses; Copy → `link` morphs to `checkmark` (`.contentTransition(.symbolEffect(.replace))`) for ~1.2 s;
  folder → bounce on hover. Thumbnails lift on hover (scale ~1.04, soft shadow) with a SMALL 3-D tilt following the
  cursor (`onContinuousHover` → `rotation3DEffect`, max ~6°). Keep it subtle — Apple-subtle, not a toy.
- **Pinch & drag.** Trackpad pinch (`MagnifyGesture`) on the grid resizes thumbnails smoothly between ~3 and ~9
  columns; ⌘+ / ⌘- do the same; the size persists (UserDefaults). Drag-out of any shot or download gives the file URL
  (reuse `fileProvider`). **Drag-in:** dropping image files onto the overlay adds them to the tray as own copies through
  the same TrayStore path a new screenshot uses (so the 24-cap applies); non-image drops are rejected with a brief
  toast. Show a glass drop-target highlight while dragging over.

## Send to session
Send pastes the shell-escaped path into the focused True pane via the existing path (same as the panel), then
dismisses the overlay and brings True forward so he lands where the path went.

## Design bar (non-negotiable)
Read first: `~/.claude/skills/taste/SKILL.md` and `~/.claude/skills/apple-hig/SKILL.md` (then the HIG pages it points
to for materials / Liquid Glass, motion, SF Symbols, drag and drop). Target is macOS 26: use the real system APIs —
`.glassEffect(...)`, `GlassEffectContainer`, `.buttonStyle(.glass)`, `symbolEffect`, system fonts and semantic colors.
Dark-first, quiet chrome, the images are the hero. Check Reduce Motion and Reduce Transparency (fallback to solid
material). Self-check the result against /taste before you finish and write the verdict in result.md.

## Tests (unit-level, no app launch)
Pure logic gets tests: day grouping (Today/Yesterday/Earlier across midnight + timezone), column-count clamp from pinch
scale, hotkey constant → Carbon keycode/modifier mapping, overlay screen-frame choice (mouse screen), drag-in filter
(image UTTypes accepted, others rejected), viewer next/prev index wrap-or-stop rule (pick stop-at-ends). Update
SPEC.md with a short section and a decision note in docs/kb.

## result.md
What was built, files touched, gate output tail, and an exact **eyeball checklist** for Yahia (hotkey, open animation,
zoom-open/close, arrows, Space peek, hover tilt, pinch, drag-out, drag-in, Send, Esc/backdrop dismiss, Reduce Motion).
