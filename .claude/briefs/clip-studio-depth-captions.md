# Clip Studio: depth captions — words sit BEHIND the speaker

First read and follow ~/.claude/skills/dispatch-brief/SKILL.md. Repo: ~/Projects/clip-studio (you are in a worktree off
main 09b0107). No push, no merge, never relaunch the ClipStudio app, never write to the real library
(~/Library/Application Support/ClipStudio/library.sqlite — open it `?mode=ro` only; tests use fixtures / a tmp copy).
Never post or queue anything. Write result.md EARLY and extend it as you go.

## The ask (Yahia)
"captions behind the speaker with depth effect". The person is cut out of each frame with a mask; the caption is drawn
onto the background; the person goes back on top, so letters disappear behind head/shoulders and feel part of the shot.

## Where it plugs in (read these first)
- `engine/clipengine/captions.py` — Pillow RGBA caption cards (`band_card`, `render_cards`, `contrast_ratio`).
- `engine/clipengine/render.py` — ffmpeg overlay composition, `CAPTION_BAND=(1300,1580)`, face tracking
  (`face_path`, `group_box`, `face_out_box`, `hook_place`), `overlay_graph`.
- `engine/clipengine/editstyle.py` / per-campaign `edit_style` (punch_in/push_in are locked-off there and the critic
  cannot enable them — copy that exact lock pattern).
- `engine/clipengine/editroom.py` (layout / picture_run) and `editcritique.py` (critic).

## Build
1. **Person mask — native helper.** The engine venv (Python 3.14) has cv2/numpy/PIL only: no pyobjc, torch, onnx,
   mediapipe. Use Apple Vision via a small Swift CLI (macOS 26.5, Swift 6.3 available):
   `engine/native/personmask/` → binary `personmask <in.mp4> <out_mask.mkv> [--quality accurate|balanced]`.
   AVAssetReader frames → `VNGeneratePersonSegmentationRequest` (OneComponent8) → grayscale mask video at the input
   size (lossless: ffv1/mkv, or pipe raw gray to ffmpeg). Benchmark against `VNGenerateForegroundInstanceMaskRequest`
   on 2 clips; pick by edge quality + flicker, record ms/frame for both in result.md. Build script compiles with
   `swiftc -O`; the engine finds the binary at a fixed path and caches masks by (input hash, quality).
   Temporal steadiness: light EMA across frames + 1-2 px feather so edges do not shimmer.
2. **Compositor.** One ffmpeg graph: `[v]split[bg][fgsrc]; [bg][cap]overlay[vc]; [fgsrc][mask]alphamerge[fg];
   [vc][fg]overlay`. Normal captions, hook line, logo, end card stay ON TOP as today; only depth cards go between.
3. **Depth card style.** 1-3 words per card, large heavy type, placed so it overlaps the head/shoulders region
   (from the face box), not the lower-third band. Same glyph sanitising / tofu assert as `card()`.
4. **Readability gate (the important part).** Per depth card, using the mask at that card's frames: visible share of
   each word's glyph pixels must be >= 70% (tunable constant). If not: nudge the card up/down within limits; if still
   failing, that card falls back to a normal front caption. Also reuse the contrast check. Never ship an unreadable word.
5. **When it is allowed.** Only on single-speaker talking frames: mask present, mask area 8-70% of the frame, steady
   across the card. B-roll, screen recordings, montage, `layout_square` runs, multi-person frames → normal captions.
   Helper missing / errors / slow → normal captions, render never fails; log the reason in the run record.
6. **Per-campaign switch.** `edit_style.depth_captions: "off" | "hook" | "all"`, default `"off"` for every campaign
   (including PB Blake and Solved). `hook` = only the opening title words; `all` = every eligible card. The critic can
   NOT turn it on (same lock as punch_in). CLI flag `--depth-captions hook|all` for proof renders only.
7. **So it learns.** Record per clip which caption mode actually rendered (depth / front / fallback + reason, occlusion
   % per card) in the run record and an additive clip field/column (schema additive only), so the critic and later
   retention numbers can compare depth vs front. Add a critic rubric line that grades depth cards on readability and
   "feels part of the shot" — it may only veto depth, never enable it.

## Proof (required, local only, never posted)
Render 3 clips from existing campaign moments with `--depth-captions all` into `docs/proof/depth/`: one close
talking head, one wider shot, one with hands/movement near the face. For each: contact sheet, stills at 4 word onsets
(take them from the real MP4 with ffmpeg select, not a sheet), occlusion % per card, fallbacks + reasons, mask ms/frame,
total render time vs a normal render. Also one matching normal-caption render of the same moment for side by side.

## Done =
- pytest (whole engine suite) green; new tests: graph builder, readability gate, fallback when helper missing,
  default off for every campaign, critic cannot enable, run record fields.
- Proof files exist and you LOOKED at the stills: letters really go behind the person, edges do not halo or flicker,
  every word readable. Say plainly in result.md anything that looks off.
- result.md: what changed (files), benchmark numbers, proof paths, known limits, open questions for Yahia.
