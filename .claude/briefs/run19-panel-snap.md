# Brief: Run 19 — draggable screenshot chip that snaps to corners

Worktree you are in. Do NOT push, do NOT launch True.app, never read `.claude/heldout/`. Lane: `Sources/True/`,
`Tests/`, `SPEC.md`, `docs/kb/`. Small commits, tests with code. Gate = docs/kb/conventions.md:5-9 exactly. Every
existing test stays green; weaken none. Do not commit a result.md into the repo root (write it only as your final answer).

Why: the floating screenshot panel (`Views/TrayPanel.swift`, geometry `Model/TrayPanelFrame.swift` `topRight`) is pinned
top-right and covers True's own tab-bar "Restart to update" pill (`Views/RestartPill.swift`). Yahia chose:
**drag + snap to corners, like Picture-in-Picture** — drag the chip anywhere, release, it glides to the nearest of the
4 corners of the visible frame (same inset as today), remembered across restarts (UserDefaults, per-corner, not raw
coords). The expanded panel and zoom open anchored from whichever corner it is in (grow toward screen centre, still
clamped on-screen). Default corner stays top-right for first run.

## Details
- Panel is `isMovableByWindowBackground = false` today; implement drag yourself (mouseDown/Dragged/Up on the panel or
  a SwiftUI DragGesture on the chip) so a plain click still toggles expand — treat < 4 pt movement as a click.
- Glide: short spring/ease (~250 ms) via `NSAnimationContext` `animator().setFrame`; Reduce Motion → jump.
- Snap respects the screen the chip is released on (multi-monitor) and that screen's visibleFrame (menu bar, Dock).
- Re-snap on screen-parameter change (display unplugged) to the remembered corner on the main screen.
- Non-activating behaviour, Esc, the Run 18 expand button and everything else unchanged.

## Tests (pure, in TrayPanelFrame)
nearestCorner for points in each quadrant + exact centre tie (pick top-right); frame for each corner incl. clamping
when larger than room; expanded frame anchors to each corner; corner persistence round-trip; click-vs-drag threshold.
Short SPEC.md note + docs/kb decision line. Final answer: files, gate tail, eyeball checklist.
