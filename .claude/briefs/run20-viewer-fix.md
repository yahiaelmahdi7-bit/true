# Brief: Run 20 — Shots overlay viewer: fix zoom-back + make controls visible

Worktree. Do NOT push, do NOT launch True.app, never read `.claude/heldout/`. Lane: `Sources/True/Views/ShotsOverlay*.swift`,
`Sources/True/Model/ShotsOverlayLogic.swift`, `Tests/`, `SPEC.md`, `docs/kb/`. Do NOT touch TrayPanel*.swift or
TrayPanelFrame.swift (another builder owns them). Gate = docs/kb/conventions.md:5-9 exactly; weaken no test. No result.md in repo.

Yahia, verbatim (Run 18 overlay works): "the zoom back looks off and the ui is hard to see as its all the same when i
zom in to a pic i cant see the bottom ui for the edit and send and so on".

## Fix 1 — zoom back
The close morph via matchedGeometryEffect inside the LazyVGrid is unreliable (slot may be off-screen / not laid out /
detached after arrowing). Replace with a robust approach: record each tile's frame in overlay coordinates
(GeometryReader + PreferenceKey / onGeometryChange), and animate the viewer image with an explicit frame
interpolation from the tile rect → fitted viewer rect and back. If the target tile is scrolled off-screen, scroll it
into view first (ScrollViewReader) or fall back to a shrink+fade toward centre. Same spring both ways; no flicker, no
double image (hide the grid tile while its viewer copy is up). Reduce Motion → crossfade.

## Fix 2 — controls always visible and distinct
- Viewer layout reserves space: image is fitted into (overlay area minus a fixed bottom toolbar band minus margins), so
  the toolbar can NEVER be off-screen or covered, for any aspect ratio (tall portrait, ultra-wide, tiny).
- Toolbar: a floating capsule centred at the bottom, clearly separated from the image: stronger glass (`.regular`
  tinted dark) with a subtle border + shadow, labels under or beside icons (Send, Copy, Markup, Finder, Remove),
  44 pt hit targets, readable white text. Add a top-left Close (×) and ← → chevron buttons at the sides for mouse users.
- Dim the grid behind the open viewer more strongly (~0.6 black) so the viewer layer reads as separate from the grid.
- Make the grid chrome (title row, section labels, downloads strip) contrast with the blurred backdrop too: legible
  white text, slightly darker glass; check against a bright white wallpaper and a dark one.
Taste: re-read `~/.claude/skills/taste/SKILL.md` + apple-hig materials guidance.

## Tests
Pure fitting function: image rect for given container/aspect/toolbar band — toolbar never overlaps, image never
exceeds, for portrait/ultra-wide/tiny/huge. Interpolation endpoints. Final answer: files, gate tail, eyeball checklist.
