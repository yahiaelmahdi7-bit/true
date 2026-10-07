# Run 18 — full-screen Shots overlay

**Built:** borderless full-screen overlay over the screen under the mouse, same stores as the floating panel (panel unchanged except one expand button). Glass title row, grid grouped Today/Yesterday/Earlier with pinned labels, Downloads glass strip, zoom-open viewer (← → stop at ends, Space peek, Send/Copy/Markup/Finder/Remove+Undo), hover lift + ≤6° tilt, symbol effects (send bounce+fly, copy→checkmark, folder bounce), pinch / ⌘+ ⌘- (3–9 cols, persisted), drag-out, drag-in (images only, via TrayStore.ingest), global hotkey ⌃⌥⌘S + Shell ▸ Show Shots.

**Files:** new `Model/ShotsOverlayLogic.swift`, `Views/ShotsOverlay.swift`, `Views/ShotsOverlayViews.swift`, `Tests/TrueTests/ShotsOverlayTests.swift`. Edited `TrayPanelViews.swift` (expand button), `MarkupEditor.swift` (host protocol instead of concrete controller), `ScreenshotWatcher.swift` (`ingestDropped`), `TrueApp.swift` (menu + hotkey), SPEC.md, docs/kb/decisions.md.

**Gate:** `swift build` clean; full test gate: `Test run with 579 tests in 102 suites passed` (9 new, none weakened); `scripts/package.sh debug` → `OK: built True.app (not launched)`.

**/taste self-check:** monochrome only (True's colour doctrine), system font, real Liquid Glass (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`), images are the hero, no decorative gradients/serifs/emoji, motion carries meaning. Reduce Transparency → solid backdrop; Reduce Motion → crossfade, no stagger, no tilt, no fly-off. NOT eyeballed in a running app (not launched) — visual polish is unverified.

## Eyeball checklist
1. Press ⌃⌥⌘S from another app: overlay appears on the screen with the mouse; press again: it closes.
2. Open animation: fade + tiles spring in with a short stagger; dismiss is quicker.
3. Click a tile: it grows into the viewer; Esc (or click outside) shrinks it back into its exact slot.
4. In viewer: ← → slide between shots and stop at first/last. Space from the grid peeks the hovered shot; Space closes.
5. Hover a tile: lifts, soft shadow, slight tilt toward the cursor.
6. Pinch on the trackpad: 3–9 columns, smooth; ⌘+ / ⌘- too; quit and reopen — size remembered.
7. Drag a tile / download chip into Finder or a chat: file arrives.
8. Drag image files in from Finder: glass highlight, tiles added (max 24). Drag a .txt: toast "Only images can be added".
9. Send (paperplane): bounces, flies off, overlay closes, True comes forward with the path in the focused pane.
10. Copy image / Copy path: icon morphs to a checkmark ~1.2 s. Folder icons bounce on hover.
11. Remove: toast with Undo; original file untouched.
12. Markup from the viewer; Save returns to the new markup shot.
13. Esc order: markup → viewer → overlay. Backdrop click and clicking another app dismiss.
14. System Settings ▸ Accessibility: Reduce Motion (crossfade, no tilt/stagger), Reduce Transparency (solid backdrop).
15. Shell ▸ Show Shots shows ⌃⌥⌘S; panel header has the expand button.

**Risks:** hotkey silently does nothing if another app owns ⌃⌥⌘S; arrow slides detach from the grid slot (only open/close morph); matchedGeometry behaviour inside LazyVGrid and the viewer-close shrink are unverified without a running app.
