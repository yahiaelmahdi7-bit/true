# Edit Room ROUND 2 — make the edits good (resume of clip-studio-editroom-20261012-000015)

Round 1 works mechanically (341 tests, all checks PASS) but the proof edit scored 4/10 "would PB Blake approve". Yahia's
ask now: "fire edits" built from proven AI-editing techniques, repos and the approved reels. Same branch/worktree, same rules
(all DISCIPLINE + Hard limits + Honesty rule from round 1 still apply verbatim).

## Read first
- `~/Projects/clip-studio-refs/research/TECHNIQUES.md` (15 ranked moves, params, per-style do/don't) and
  `~/Projects/clip-studio-refs/research/REPOS.md` (top-12 moves; openshorts = MIT core, re-implement ideas, do NOT copy its
  `cloud/` code; hotclip/Clips Kitty are AGPL, template-tiktok/Autocrop-vertical have no license — ideas only).
- `~/Projects/clip-studio-refs/pb-blake/breakdown/NOTES-pass1.md` — MEASURED grammar of the 7 approved clips (+ per-clip
  `words.json`, cuts, crop, ebur128 under `breakdown/example-N/`). A BREAKDOWN.md is being written there by another agent; do
  not touch `breakdown/`. It overrides the round-1 style read where they differ.

## Reviewer's read of round-1 output (presetE-sheet.png)
Hook tiny, top-left, orphan line ("2026."), gone after 1 s -> top band dead for 45 s. Bottom captions flat: same size/colour,
no emphasis, junk chunk breaks ("ONE THAT", "MET HAS"). 16:9 band = ~30% of height -> face tiny. No b-roll: 46 s of one static
talking head. Critic was claude-haiku and never calibrated.

## 1. Calibrate the critic FIRST (nothing else is trusted until this passes)
- Critic model -> `claude-sonnet-5-5` (vision). Anchor every criterion with concrete level descriptions.
- Leave-one-out: for each of the 7 approved refs, build the reference sheet from the OTHER 6 and critique the held-out ref as if
  it were an edit (no filenames/labels that leak "approved"). Also critique >= 3 known-bad edits (round-1 r1, a no-text version,
  a tiny-hook version). Pass = every approved ref overall >= 7 AND every known-bad <= 4. Tune the rubric on refs 1-5, then
  report refs 6-7 untouched as the held-out result. Put the calibration table in result.md. If it cannot separate, say so —
  do not loosen the bar.

## 2. PB Blake grammar (measured — update STYLE.json/STYLE.md and the checks to match)
- Layout: default = 1:1 square, face-tracked crop at full width (bands ~21.9% top and bottom); 5:4 allowed; 16:9 letterbox only
  for wide b-roll. Layout check validates against this.
- Text sits OVER the footage (not in the bands) for presets A-D:
  A: one static sentence-case line, white + soft shadow, centred ~49% height, whole clip (ex 1, 6).
  B-big: EVERY word, one at a time, condensed bold caps, red ~#F00509 + dark shadow, cap height ~8% of frame, centre y ~35.6%,
  ~3.6 words/s, onset within +/-50 ms of the spoken word start (ex 5). B-small: every word, bold geometric sans white, soft
  shadow, cap ~2% frame, at x~28% y~31% (ex 4).
  C: quiet subtitles, 2-7 word cards that build word by word then clear, optional B&W grade (ex 2, 3).
  D: small bold white caps 1-3 word chunks centred, then a text-free hype montage (ex 7).
- Ending move (ex 5, 7): last 8-12 s = text-free b-roll montage at ~1.5 cuts/s.
- Loudness -14.2 +/- 0.5 LUFS, true peak <= -1 dBTP. Never output a black tail > 0.3 s (refs 2/3/5 have them = artefacts).
- Preset E (Yahia's own "dark immersive" ask) stays, fixed: square/4:5 footage band (not 16:9); hook big (cap >= 6% of frame),
  centred in the top band, balanced line breaks (no orphan word), persists the whole clip; kinetic captions above y = 65% of
  frame height (bottom band sits in TikTok's UI zone), emphasis word in accent red with pop scale; <= 1 highlight per 10 words.
- Caption chunking: pixel-width chunking at phrase boundaries (Captacity idea), one event per word; never break inside a noun
  phrase; never end a card on a function word.

## 3. B-roll library (biggest single lift)
- `edit-broll-index --campaign <id>`: scene-detect every source whose campaign_rules.campaign_id matches, keyframe per shot,
  vision-tag (cheap model ok) into a shot catalog: subject (car, cash, city, jet, gym, water, crowd, talking-head, text-card,
  other), motion, brightness, duration. Store in the library DB (new table, additive migration).
- EDL gets b-roll slots: timed queries per 4-5 s window (ShortGPT idea) -> top-k catalog candidates -> Jev ranks/picks (choice
  with no-match) -> code places cutaways as J/L cuts under the voice. Rules: never in the first 1.5 s, <= 40% of talk time,
  same-campaign allowed sources only (rights), never reuse a shot inside one edit. Plus the ending montage from section 2.

## 4. Research moves to implement (params from the research files; tune against the calibrated critic)
- Word-timed punch-ins on emphasis words, talking-head shots only: peak 1.12, rise 0.25 s, hold ~1.3 s, fall 0.55 s, >= 6 s apart.
- Cut padding 0.06 s pre / 0.08 s post; never start or end a cut on a filler/function word; trim gaps > 0.4 s.
- Clip boundaries at topic shifts / complete thoughts; end on the punchline, never mid-thought.
- Hook: frame 0 has text + face or motion; hook resolved inside 3 s; the LLM picks words, code resolves times.
- Added audio (SFX whoosh/impact, music bed): build it, but behind per-campaign `allow_added_audio` (default FALSE, PB Blake
  FALSE until Yahia confirms). With it off, montage keeps the source's own audio.
- Measure motion-design's HTML->frames renderer for the kinetic text (pop/scale curves) vs Pillow: pick by numbers, record them.

## 5. Proof (result.md, replace round-1 section with round-2 + keep round-1 numbers for comparison)
- Do NOT run yt-dlp. Real sources are already in the library: COPY (read-only) up to 3 files from
  `~/Library/Application Support/ClipStudio/media/downloads/` into a TEMP CLIPSTUDIO_HOME and add them there (allow_local in the
  temp home only). Pick the round-1 talking-head source + 2 with b-roll. Never open the real DB for writing.
- Run edit-run on all 3 (presets chosen by Jev; plus one forced B-big and one forced E). Target: calibrated critic overall >= 7
  on >= 2 of 3, all checks PASS. Show before/after sheets next to the leave-one-out ref sheet. Fresh proof sheets (round-1 ones
  predate the hook-size change).
- Swift: if the app has a headless/self-capture mode (`--qa-snapshot`) that works with a temp CLIPSTUDIO_HOME from the worktree
  build, use it to show an approved edit in the clip list. Never kill/relaunch the running ClipStudio app. Else say UNVERIFIED.
- Full pytest green (paste tail), new tests for: square layout, word-onset timing (+/-50 ms), chunking rules, b-roll rules
  (first 1.5 s, 40% cap, no reuse, same-campaign only), punch-in spacing, added-audio flag, no black tail, critic calibration
  harness (mocked).

## LATE ADDENDUM (00:55) — BREAKDOWN.md is now written and WINS for PB Blake
`~/Projects/clip-studio-refs/pb-blake/BREAKDOWN.md` ("What our editor must copy", 10 rules). Where research conflicts, the refs win
for PB Blake: NO punch-ins/zooms on the talking head (make punch-ins a per-campaign STYLE setting, OFF for PB Blake, available for
Solved/others); NO SFX, no outro, no end card; montage music bed only behind allow_added_audio. Text tiers: small ~2% / big 6-8% of
canvas height. Start on the first spoken word, first caption by 0.1-0.2 s; end within 0.2 s of the last word.
