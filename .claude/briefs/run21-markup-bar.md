# Brief: Run 21 — overlay markup toolbar: solid, readable, bottom, no overlap

Worktree. Do NOT push, do NOT launch True.app, never read `.claude/heldout/`. Lane: `Sources/True/Views/MarkupEditor.swift`,
`Sources/True/Views/ShotsOverlay*.swift`, `Sources/True/Model/ShotsOverlayLogic.swift`, `Tests/`, `SPEC.md`, `docs/kb/`.
Gate = docs/kb/conventions.md:5-9 exactly; weaken no test. No result.md in the repo.

Yahia (screenshot of the overlay in Markup mode): "u see how the ui on top is hard to see when in edit mode".
Observed: in the full-screen overlay, `MarkupEditor`'s `bar` (MarkupEditor.swift ~131) has NO background and sits at the
top of the viewer area, right on top of the overlay title row ("Shots 17 ↗" visibly collides with the tool icons). Icons
are small grey-on-dark; Save is grey text on a grey capsule, nearly invisible; Cancel is dim.

## Fix
1. `MarkupEditor` gets a style: `.compact` (the floating panel — keep it byte-for-byte as today) and `.overlay`.
2. `.overlay` style: the tools bar becomes a floating capsule at the BOTTOM centre, in the exact place and style of the
   viewer's toolbar (`chrome(...)` in ShotsOverlayViews.swift ~318-360: dark-tinted glass 0.55, 0.75 white stroke,
   shadow, `ToolbarButton` 44 pt targets with labels). So switching Markup on swaps the bottom bar's contents in place.
   Contents: tools (Pen, Arrow, Box, Highlight, Text — labelled, the selected one shown with a filled white-ish pill and
   white icon), colour dots (≥ 20 pt, clear selection ring), Undo/Redo, then Cancel (readable white secondary) and
   **Save as a prominent filled button** (white fill + black text, or accent fill) — obviously the primary action;
   disabled state still legible.
3. Image is fitted ABOVE the bar using the same `viewerArea(... toolbarBand:)` reservation the viewer uses (today markup
   passes `toolbarBand: 0`) — the bar never covers the image and never goes off-screen.
4. Hide (fade out) the overlay title row and the Downloads strip while `markingUp`, and keep the dim behind the viewer,
   so nothing from the grid layer reads through. Close (×) top-left stays and acts as Cancel (respect unsaved-markup rule).
5. Keyboard unchanged (⌘Z/⇧⌘Z, Esc = leave markup).
Taste: read `~/.claude/skills/taste/SKILL.md` FIRST and state in your final answer that you did (last run skipped it).

## Tests
Pure: markup viewer area reserves the band (bar never overlaps image) for portrait/wide/tiny; compact style unaffected
(existing tests stay green). Final answer: files, gate tail, eyeball checklist.
