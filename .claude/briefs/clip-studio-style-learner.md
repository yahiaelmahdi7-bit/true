# Clip Studio: style learner — drop in a reference video, get a measured style file

First read and follow ~/.claude/skills/dispatch-brief/SKILL.md. Repo: ~/Projects/clip-studio (worktree off main 1f29a5b).
No push/merge, never relaunch the ClipStudio app, real library read-only (`?mode=ro`), tests on fixtures/tmp copies.
Write result.md EARLY and extend it.

## The ask (Yahia)
"we need edits like this and skills and clips like these so learn from this and execute this style with ease in our
system" — reference: ~/Projects/clip-studio-refs/ref-style-1/ref.mp4 (third-party TikTok, @thekumarmethod).
RIGHTS: the reference is someone else's video. Learn the GRAMMAR only. Never copy its frames, audio or words into the
repo, into any render, or into tests. Measurements (numbers) are fine; crops/sheets stay in clip-studio-refs (not git).

## What the reference does (my read — your measurer must confirm or correct each with numbers)
26.7 s, 576x1024 30 fps, -21.7 LUFS, music under the voice the whole time (only 3 silences >=0.25 s at -40 dB).
Cuts at ~0.9 s steps in bursts (2.27, 3.17, 4.07, 4.97, 5.87, 6.77, 11.87, 12.8, 13.73, 15.5 ... 19.07, 24.5).
1. Opener: red bold SANS line that builds word by word at chest height ("This is a message to all finance bros").
2. Word slams: ONE word per card, giant red (~#E30507) condensed high-contrast Didone serif, all caps, ~90% frame
   width, top third; the speaker's HEAD IS IN FRONT of the letters (depth). Hard cut per word on the word onset.
3. Studio b-roll montage interleaved, cut ~0.9 s on the beat; low-key high-contrast grade.
4. White flash (~20.1 s) then fade from white into a tonal shift (normal-lit two-shot = the punchline).
5. Punchline captions: small plain yellow sans, black edge, 1-4 words.
6. End card = magazine cover: "KUMAR'S" top, "DEBUT" bottom, full-body subject between, head overlapping the top word.

## Context
This is module 1 of a "Style Lab" (Yahia: a lab that learns editing styles from many references, finds trending ones
and implements them). So `style.json` gets `"schema": 1`, a stable documented shape, the source path + sha256 of the
reference, and a `measured_at`; many style files will be stored and compared later.

## Build
1. **`clipengine/stylelearn.py` + CLI `edit-style-learn <video> --name <slug>`** → `style.json` + `style-sheet.png` in
   a refs dir. Measures: duration; shot lengths (scene detect) + rhythm (median, bursts, beat alignment if a bed is
   detected); transitions (white/black flash = frame-mean luma spikes, fades); grade stats (mean luma, contrast,
   saturation per shot); audio (LUFS, music-under-speech via silence gaps + spectral steadiness, speech share);
   TEXT per card: words per card, on/off times vs word onsets if a transcript exists, bbox position/height as % of
   frame, fill colour (glyph pixels), stroke/outline, case, font class (serif/sans, condensed ratio = glyph w/h,
   stroke contrast), and DEPTH = share of glyph box covered by the person mask while the card is up.
2. **Text + person reading via Apple Vision** (engine venv has no pyobjc/torch/onnx). A Swift CLI
   `engine/native/framescan/` → `framescan <video> --fps 10 --out scan.jsonl` emitting per sampled frame:
   `VNRecognizeTextRequest` (accurate) boxes+strings+confidence, and person mask coverage stats per text box
   (`VNGeneratePersonSegmentationRequest`). NOTE another builder is creating `engine/native/personmask/` in parallel —
   do not edit that dir; keep framescan self-contained (own Package/compile script).
3. **Score our output against a style** — `edit-style-score <video> --style <style.json>`: runs the same measurer on
   one of OUR renders and returns per-dimension distance (rhythm, text size/pos/colour/words-per-card, depth share,
   transitions, grade, loudness) + one overall 0-100 "style match". This is how the system learns: render → score →
   adjust knobs. Add it as an input the Edit Room critic can read (additive; critic still cannot enable locked-off
   features like punch_in or depth_captions).
4. **Style pack → Edit Room knobs.** `edit-style-pack <style.json>` writes a named style pack the Edit Room can select
   (`edit_style.pack = "<slug>"`), mapping measured values onto existing knobs (sub_chunk, hook_size, hold, accent,
   band, montage cut length) and recording the ones the renderer cannot do yet as `unsupported: [...]` (e.g. word_slam
   serif, build_line opener, flash_white, cover_end_card) — list them honestly; a later round builds them.
   Campaign policy always beats a learned style (PB Blake: no bed under speech, no SFX, punch-ins off) — encode that
   precedence in code with a test.
5. **Fonts:** propose (do not install system-wide) the closest OFL/free-commercial condensed Didone for the slams and a
   bold sans for the opener; compare rendered samples against crops of the reference; put candidates + licences in
   result.md. Never use Apple system fonts (Didot etc.) for burned-in output.
6. **Skill:** add a "Learn a style from a reference" section to ~/.claude/skills/clip-edit/SKILL.md (read it first):
   the three commands, where refs live, rights rule, how to read style.json and the score.

## Proof
Run `edit-style-learn` on the reference → `~/Projects/clip-studio-refs/ref-style-1/style.json` + sheet; LOOK at the
sheet and check every claim in "What the reference does" (confirm / correct with numbers in result.md).
Run `edit-style-score` of the reference against itself (should be ~100) and of the existing Edit Room render
`~/Projects/clip-studio.builders/clip-studio-editroom-20261012-000015/docs/proof/editroom/r3.mp4` against it
(expected low) — report both.

## Done =
Whole engine pytest green + new tests (measurer on synthetic fixtures you generate: known cuts, known flash, known
text card with known colour/position, known music-under-speech; style-pack precedence; score ~100 on self).
result.md: files changed, measured style table for the reference, the two scores, font candidates, unsupported list.
