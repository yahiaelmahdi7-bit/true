# Clip Studio — editing styles in AUTOPILOT (rotation) + podcast `card` layout

Repo ~/Projects/clip-studio, engine/ (venv engine/.venv). You start from branch of builder cs-two-speaker (depth wired into render_moment + `stack` two-speaker layout). Read its docs/proof/two-speaker/README.md first. Worktree branch only. Never merge, push, touch installed ClipStudio.app, or change post.golive / autopilot.pause in the real library.

## Problem
Autopilot (autopilot.cut_one -> agent._render -> render.render_moment) renders every clip in one default look. Style systems exist but only in the Edit Room: stylepack.py (style packs, ~/Projects/clip-studio-refs/style-packs/kumar-method.json), vibepack.py (data/vibepacks: hype, looksmax, wellbeing — DRAFT), caption presets quiet/loud (captions.py ~231), editroom.edit_style. Templates layout `card` (templates.py: blur_band + cam_card + badge, layoutcli.py:61) exists only for livestream/facecam clips.

## Build
1. **Style = named recipe** an autopilot clip can render in: layout (crop | stack | card), caption preset/look (+ vibe pack row), depth on/off, accent, transitions allowed by campaign. Campaign policy always wins (music banned, required tags, face first 5 s, subtitles whole clip, credit overlay).
2. **Wire into render_moment** (the autopilot path): honour a per-campaign style config `edit_style:<cid>.styles` = list of style names + `mode: "rotate"` (default) . Rotation: deterministic, spreads styles evenly across a campaign's clips, never the same style twice in a row. Record `style` name in clip features (and autopilot_meta if cheap) so later analytics can compare styles by views.
3. **Podcast `card` layout**: top = sharp rounded face-tracked card of the ACTIVE speaker over a blurred+darkened copy of the same shot (match templates.py card look); badge under card bottom-left = platform icon (YouTube red / Instagram gradient — drawn, not a trademark asset download) + campaign credit handle (first unprefixed required tag, e.g. @solvedpodcast); hook/caption line under the card; bottom half = the OTHER speaker (face-tracked) when two people are in shot, else the wide shot. Depth captions where they pass, else front. When card badge shows the credit, don't also draw the overlay credit pill.
4. Ship at least 4 styles for podcasts: `clean-depth` (crop, loud yellow caps, depth), `two-speaker` (stack), `card` (above), `calm` (quiet subtitle preset, crop). Default "off"/no styles config must stay byte-identical to today.
5. Tests for rotation, policy-wins, card graph; full engine suite green (baseline after builder 1).

## Proof
Sandbox exactly like docs/proof/two-speaker (CLIPSTUDIO_HOME = .backup copy + symlinks, never media/clips). Set styles for cmp_6fe50dcdb4 in the copy. Render mom_8f399fa883, mom_6ef3c64af7, mom_9358c25556, mom_4dc7ab17af through the autopilot path so all 4 styles appear. docs/proof/styles/: mp4s, contact sheet (3 timestamps per clip, style name labelled), README verdict-first with per clip: style, layout, depth share %, QC result. Look at your stills before claiming done; credit/tags/subtitles present on every clip.

## Done =
tests green, proof, files-changed summary, commit on branch.

## ADDED 2026-10-14 (Yahia): burned-in show logo must never be cut
Yahia flagged S-renders on mom_8f399fa883 where the "Solved." corner logo is sliced at the right edge ("Solve") and the bottom-left source credit ("…italist. Random House.") is half-cut. Rule: the vertical crop either contains a burned-in logo/credit WHOLE or excludes it entirely — never slices it. The show logo should stay visible whole (campaign branding). Detect via framescan text boxes near frame edges; shift/widen crop to fit. Proof: before/after frames of that moment with the full "Solved." logo.

## STYLE GRADES (Yahia, blind, 2026-10-14, moment mom_8f399fa883)
doac B+ (MAIN) · flagrant B (rotation) · jre C+ (bland, no depth — drop) · hormozi C- (poor title capture — drop).
Rotation = doac primary, flagrant secondary. Packs: ~/Projects/clip-studio-refs/style-packs/{doac,flagrant}.json. Builder self-score ranked hormozi top — trust Yahia's eye, not the self-score.

## ADDED (Yahia 2026-10-14): stack bottom panel cuts the speaker's head (mom_8f399fa883 ~0:08) — panel framing must keep whole head + eyes ~1/3 from top in BOTH panels.
