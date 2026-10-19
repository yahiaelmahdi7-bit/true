# Clip Studio: editorial effects pack — word slam, build line, beat montage, flash-white, cover end card

First read and follow ~/.claude/skills/dispatch-brief/SKILL.md. Repo: ~/Projects/clip-studio (worktree off main AFTER the
depth-captions, style-learner AND caption-flow r3.1 merges — check `git log` shows 9461932 "Merge caption flow r3.1").
Worktrees have no venv: run tests as `PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q` from the
worktree's engine/. The Swift binaries (personmask, framescan) are gitignored: build them in the worktree with
`bash engine/native/<name>/build.sh` before any depth render.

## Ground rules from caption flow r3.1 (already on main — build ON them, do not re-implement)
- `edit_style.frame` square|wide sets ONE picture rect shared by render, depth and b-roll. Every new op (slam, build line,
  montage, end card, punchline captions) positions itself relative to that picture rect, never the raw 1080x1920 canvas,
  and must look right in BOTH frames (proof stills in both).
- Front captions are phrase-chunked, de-duped against depth cards, and SPLIT at every depth card: no front caption is on
  screen while a depth card shows. A word_slam / cover_end_card IS a depth card for this rule (also on depth fallback, when
  the slam goes in front): the punchline/front stream splits around it the same way. Add a test: no front chunk overlaps
  any slam window.
- Pause windows (gaps / b-roll inserts) stay caption-free; the beat montage is a pause window.
- Tests green ≠ right: the r3 de-dupe passed 440 tests while merging words across a card. LOOK at stills at every slam
  onset against the word timings. No push, no merge, never relaunch the ClipStudio
app, never write to the real library (`?mode=ro` only; tests use fixtures / a tmp copy). Never post or queue anything.
Write result.md EARLY and extend it as you go.

## The ask (Yahia)
Make our clips edit the way the reference creator does (ref: ~/Projects/clip-studio-refs/ref-style-1/ref.mp4, measured in
`style.json` next to it). RIGHTS: learn the grammar only — never reuse its footage, audio, words or exact layouts in output,
never copy ref files into the repo or commit them. Every number below comes FROM style.json at render time, not hard-coded
(the measured red is ~#FB0103, slam ~91% width / ~14% height, condensed serif) — so a different learned style drives the
same ops differently.

## Ops to build (each = an Edit Room op the EDL can request, each individually switchable per campaign edit_style)
1. **word_slam** — one word per card, condensed OFL Didone/serif (pick from the learner's font candidates; bundle the OFL
   font + licence file), fill from `text.summary.slam.fill`, ~`width_pct` of frame width, top third, rendered BEHIND the
   head via the depth compositor (reuse its mask + 70% readability gate; on fallback the slam goes in front, never dropped
   silently). Words chosen from the transcript: nouns/verbs carrying the line, not filler.
2. **build_line opener** — bold sans, slam fill colour, builds word by word on word onsets at chest height
   (`build_line.y_center_pct`), held to the first cut.
3. **beat montage** — burst cutting at `rhythm.bursts[].step_s` (~0.9 s) over b-roll from the b-roll index (498 shots,
   PB Blake sources), cut points snapped to music beats when a licensed bed exists, else to word onsets.
4. **flash_white transition** — single-frame white flash + fade from white over `transitions.fades[].t1-t0`; max count per
   clip from style (ref had 1).
5. **punchline captions** — small sans captions (`text.summary.caption`) for lines that are not slammed; colour from style
   but always passes the existing contrast check.
6. **cover_end_card** — one word top + one word bottom, subject between, head occluding the top word (depth again).
7. **music under speech** — bed ducked under speech at the measured floor/speech dB gap when `audio.bed.present`, ONLY via
   the existing licence gate (campaign-source or licence.json; never AI music, commercial tracks, ElevenLabs). If the
   campaign terms forbid a bed, skip and log it. PB Blake: bed only under end montage unless the style pack overrides
   AND the licence gate passes.

## Quality bar (Yahia: "we need HD and clean edits, not low quality") — applies to ALL renders, build it first
- Masters: 1080x1920, ~12-16 Mbps (libx264 CRF ~16-17 slow, or videotoolbox at a bitrate target that measures there;
  today's `venc` videotoolbox `-q:v 62` lands ~2-3 Mbps — too thin). Measure the real output bitrate in a test.
- Upscale guard: compute the scale factor of every picture run (crop → W:H); > ~1.3x = flag in the run record and the
  critic; prefer a layout that does not blow up a small crop. Never upscale silently.
- Output QC on real decoded frames: sharpness (variance of Laplacian on the face box) and blockiness score vs thresholds
  calibrated on our good renders; failing renders are marked, not shipped. Unit-test the measurers.
- Learner/scout inputs: `style.json` records ref quality (w, h, bitrate); refs < 720p or < ~2 Mbps → rhythm/layout/text
  still learned, but `grade` is marked untrusted and not applied. Scout `lab-fetch` must pick best available format.

## Wiring
- A style pack (`edit_style.pack`, from `edit-style-pack`) turns these ops on with the measured values; campaigns without
  a pack keep today's output byte-for-byte (regression test). punch_in/push_in locks unchanged; critic still cannot enable
  locked ops or depth.
- Critic reads `edit-style-score` of the render vs the pack's style.json and may tune knobs WITHIN the pack's ranges.
- Run record logs which ops fired, per-card depth/fallback, music source + licence id.

## Proof (required, local only, never posted)
Render PB Blake moment mom_bab1b6992f (src_c9b497e0d2 195.95-242.25) with the ref-style-1 pack → `docs/proof/kumar/`.
Stills at: first build-line word, 3 slams, the flash, the end card — pulled from the real MP4 with ffmpeg select. Report
`edit-style-score` for this render vs the existing r3 render (higher must be ours, by how much). ffmpeg here has NO
drawtext — any text burned for proof labels uses Pillow PNG overlays.

## Done =
- Whole engine pytest green; new tests per op (graph shape, style-driven params, fallback paths, no-pack = unchanged
  output, licence gate blocks unlicensed bed, critic cannot enable locked ops).
- You LOOKED at the stills: slams readable and behind the head, no halo, flash is one frame, end card word layout right.
  Say plainly anything that looks off.
- result.md: files changed, the two style scores, proof paths, font + licence used, known limits, questions for Yahia.
