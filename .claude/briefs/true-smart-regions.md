# True capture — real smart regions for the hover pick (Run 28)

Repo: True, a SwiftPM macOS app. You work ONLY in the worktree `/Users/y/Projects/true.builders/true-smart-regions-20261014`
(branch `builder/true-smart-regions-20261014`). Its baseline commit d9afadd already holds the multi-screen fix
(one selection across screens, `clearHover` / `resetToAiming` / `onEngage` / `mayAim`) and the removal of the magnifier.
Do not revert or restyle either one.

## The problem, measured on Yahia's real screens (3 displays, all 1x, AX trusted)
When you hover in the capture overlay (⌘⇧4), a box should land on the part of the screen under the mouse. Instead it's
almost always the **whole window or page**:
- True (a terminal app, 4 panes split by 1-px dividers): the chain is `[Window]` at 19 of 20 points. Accessibility reports nothing finer.
- Dia (a Chromium browser): the chain is `[Page 1908x990, Window]`. Web content isn't exposed to Accessibility.
- Clip Studio: the chain is `[Section 1920x1091, Window]`.
- The image fallback (`ImageBoxDetector`, Vision rectangles + contours) finds only 2–19 boxes per screen, mostly random big areas.
  In Dia it shows an Area box first, then Accessibility replaces it with the coarser Page. The box jumps to something
  that matches nothing visible.
- `SmartPickLogic.chain` returns the AX chain whenever `ax.count > 1`, so even a coarse AX Page throws away finer image boxes.

Yahia chose: **real smart regions**. Read the layout from the picture itself (panes, panels, sidebars, bars, cards, table
blocks, media, paragraph blocks), so it works in any app. Scroll still steps bigger and smaller, and Tab still jumps to the window.

## Build
1. **`Sources/True/Model/LayoutRegions.swift`**: a pure detector `LayoutRegions.detect(_ image: CGImage) -> [CGRect]`
   (pixels, top-left origin). Classical CV, no ML, no network:
   - Find separator lines: long horizontal and vertical runs of strong luminance step, i.e. 1–2 px rules and borders between
     differently-filled bands.
   - Find uniform gutters: rows and columns of near-constant colour.
   - Recursive XY-cut inside each region (start from the whole still; window rects come later via the chain). Emit every
     region, shrink-wrapped to its content.
   - Paragraph blocks: whitespace cuts must split blocks of text but NOT every text line. Use a gap threshold adaptive to the
     region's line spacing.
   - Keep `VNDetectRectanglesRequest` hits with high confidence (cards, buttons, video frames) if they measurably help.
     Drop the contour pass unless it measurably helps.
   - Min region 40x20 pt, depth cap, de-duplicate.
   - Runtime target **< 120 ms per 1920x1200 still in a release build** on this Mac. Measure it and report it.
     It runs off the main thread, once per screen, when the overlay opens.

   Must handle:
   - thin dividers between terminal panes
   - full-width strips (tab bar, toolbar, sub-nav)
   - dark cards separated by darker gutters (Instagram insights side panel)
   - a video or image block on a uniform background
   - rounded input boxes and buttons on a top bar
   - a block between two horizontal rules
2. **Chain merge** (`SmartPickLogic.chain`): merge the AX elements and the image regions that contain p into ONE nested chain,
   innermost → outermost, with the window last.
   - A coarse AX element must never hide finer image regions.
   - Near-duplicates merge, and the AX name wins over "Area".
   - Keep only boxes that nest: each one contains the previous within ~3 pt.
   - Level 0 = the smallest box.
   - Keep `SmartPickLogic.clean` semantics for AX.
3. **Steady hover** (`CaptureView.updatePick` / `applyAX` / `SmartPicker.replace`):
   - When Accessibility answers, the box must not jump. `replace` keeps the user on the same FRAME if it's still in the new
     chain, otherwise level 0.
   - The instant chain = the ancestors in `lastAX` that still contain p + image regions + the window.
4. **Names**: plain, short labels only (no raw roles). You may add `PickKind` cases "Pane" (full-height column) and
   "Bar" (full-width strip). Everything else stays "Area".
5. **Overlay**: `CaptureController.present()` runs `LayoutRegions` per screen (pixels → points by backing scale) in place of,
   or merged with, `ImageBoxDetector`.
   - Never set `AXEnhancedUserInterface` (deliberate policy, see AXPick.swift).

## Evaluate. Measure before and after; never claim "better" without numbers
- **Eval harness** `Tests/TrueTests/RegionEvalTests.swift`, enabled only when env `TRUE_REGION_EVAL=<dir>` is set
  (swift-testing `.enabled(if:)`, the same style as `SmartPickDiagnosticTests`).
  - Input: `<dir>/labels.json` plus images. Format:
    `{"images":[{"file":"x.png","window":[x,y,w,h],"probes":[{"name":"…","p":[x,y],"accept":[[x,y,w,h],…]}]}]}`
    (pixels == points at 1x; scale by image/window if not).
  - Per probe: run the detector on the image, then
    `SmartPickLogic.chain(ax: [], window: <window>, boxes: <regions>, at: p)`.
    PASS if ANY level has IoU ≥ 0.8 with ANY accept box.
  - Print one line per probe: name, pass, matched level index, chain length, level-0 box.
  - Totals: pass rate, median matched level, mean detector ms.
  - Write `<env TRUE_REGION_EVAL_OUT or dir>/eval-<file>.png` with each probe's level-0 box and its matched box.
  - Never fail on findings, only on setup errors.
  - Run it in BOTH modes:
    - the OLD pipeline: `ImageBoxDetector` + `filterBoxes` + old chain. Keep a switch, or compute the baseline before changing code.
    - the NEW pipeline.
- **Dev set (yours)**:
  - Synthetic screens drawn in unit tests: commit these as tests with exact expectations.
  - Plus 2–3 fresh real captures you take yourself with `screencapture -x a.png b.png c.png` (Screen Recording is granted),
    with ~15 probes you label by eye. Keep the captures UNCOMMITTED in `$WT/.claude/dev-regions/` (private screen content).
- **Held-out**: the orchestrator has a separate labelled held-out set and will run your harness on it. Do NOT search for,
  open or read any `heldout` directory anywhere. Tuning on it voids the evaluation.
- Also run the real-display diagnostic and report its totals:
  `TRUE_PICK_DIAG=1 TRUE_PICK_DIAG_OUT=$WT/.claude/dev-regions/diag swift test --filter SmartPickDiagnosticTests`.
  Update it to use the new pipeline.

## Stills, spec, tests
- Re-render the capture stills: `TRUE_SNAPSHOT_DIR=$PWD/proofs/capture-p1 swift test --filter CaptureSnapshotTests`.
  - 11–14 change only if the picker changes them.
  - Add `15-smart-regions-panes.png`: a synthetic 4-pane terminal-like screen, with the hovered pane's box and "Pane" label.
  - No other visual changes.
- SPEC.md: update the Smart selection paragraph in "Run 27 — Capture + annotate" (~line 739+), and add a short
  "### Run 28 — Capture fixes" entry covering:
  - one selection across screens
  - no stale hover box
  - keyboard follows the mouse
  - magnifier removed
  - layout regions + merged chain + steady hover
  Include the eval numbers.
- Gates (FOREGROUND, serially):
  - `swift build`
  - `swift test --filter 'Capture|SmartPick|Highlighter|RectHandle|Hotkey|Region'`
  - Both must pass. Paste the output.
  - Known unrelated full-suite flakes: NovaSpeculative raceBrain, NovaSecurity26f tellLatency, ControlSocketTests.

DISCIPLINE (non-negotiable):
- Lane: you work ONLY in `/Users/y/Projects/true.builders/true-smart-regions-20261014` on branch
  `builder/true-smart-regions-20261014`. Never touch `/Users/y/Projects/true` (the main tree; another session works there)
  or any other worktree. Never quit, kill or relaunch the running True app. Never run `scripts/package.sh` or install anything.
- Commits: atomic, one logical change per commit, message says what+why, on this branch only. NEVER push, NEVER merge,
  NEVER 'ship'. The user pushes, not you. Do not suggest pushing more than once.
- Gates: run lint/tsc/tests in the FOREGROUND and wait for them. NO background shells (run_in_background), NO watch modes,
  NO until-loops. Kill anything you started before finishing.
- Claims: 'done' means you ran the gate and pasted the passing output. Local commit ≠ 'pushed'; code written ≠ 'working'.
  Never report a state you didn't verify this session.
- Decisions: this is per-mouse-move pixel geometry (it must be offline and ~0 ms on hover), so the region detector and chain
  are deterministic code, NOT Jev calls. Do not add network calls to the capture path.
- If blocked or idle: say BLOCKED/IDLE + one line why. Do not invent extra scope.

## Report back
- What changed (files)
- Eval totals OLD vs NEW on your dev set, and the diagnostic totals
- Detector ms (release)
- Still paths
- The pasted gate output
- Anything that still fails, honestly
