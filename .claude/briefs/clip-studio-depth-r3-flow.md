# Clip Studio: caption flow r3 — same framing for depth, no duplicate words, rhythm + cinematic pauses

First read and follow ~/.claude/skills/dispatch-brief/SKILL.md. Repo: ~/Projects/clip-studio, worktree off main 1290124
(`git log` must show "Merge depth captions"). No push, no merge, never relaunch the ClipStudio app, never write to the real
library (`?mode=ro` only; tests use fixtures / a tmp copy; proof renders use CLIPSTUDIO_HOME=<tmp copy>). Never post or queue
anything. Worktrees have no venv: run `PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q` from the
worktree's engine/. Gitignored Swift binaries: build `engine/native/personmask/build.sh` and `engine/native/framescan/` in the
worktree before tests/proofs, or depth silently skips. Write result.md EARLY and extend it as you go.

## Yahia's feedback (verbatim)
"the normal frame is great for the depth cpations so make sure not to zoom in so much for the depth one also the overall
captions are shitty still but the captions wokr just need better flow and rythem with them and pause for cinamtics and u have
them duped showing at the bottom and behidn the creatro"

He compared [r3 | depth] side by side:
- r3 = /private/tmp/claude-501/-Users-y-Projects-true/4489a952-234e-4e95-aa18-0c1613d64243/scratchpad/show/2-our-pbblake-remake-r3.mp4
- depth = ~/Projects/clip-studio.builders/clip-studio-depth-20261012-092737/docs/proof/depth/pbblake/depth.mp4
- stills: same scratchpad/show/sbs-still1..4.png

## 1. Framing: depth must never zoom differently from the normal render
Root cause (reviewer, verify it): r3.mp4 was rendered 00:25 on early Edit Room code that showed the FULL 16:9 source frame
(picture ~1080x608, letterboxed, head small, room visible). Main's `render_edit` now always crops a face-tracked 1:1 square
(`sq` → scale to PIC=1080 → pad), ~1.8x tighter. So it is a layout change, not a depth bug — a normal render on main is
also zoomed today.
- Add per-campaign `edit_style.frame`: `"square"` (current, default — keeps every existing test) | `"wide"` (full source
  frame scaled to output width, letterboxed, centred like r3). EDL carries `frame`; the render, `_depth_prepare` (mask +
  bg frames + `pic` rect, currently hard-wired to a PIC x PIC square), text_layer bands, eye/mouth zone, punch-in/push-in
  zoom, b-roll cutaways and montage all use the same picture rect. Depth NEVER picks its own crop or zoom.
- layout_square check: `wide` is a legal layout when the EDL says so (bands ~0.34); do not fail it, record the layout.
- Test: same EDL rendered depth off vs depth all → identical picture rect (measure lit-row run on real decoded frames) for
  both `square` and `wide`.
- Report how many depth cards pass in `wide` vs `square` for the PB Blake moment (smaller head in wide = expect fewer;
  the eligibility floor is relative to picture height, so check it still makes sense in wide — do not lower the readability
  gate to inflate the count).

## 2. De-dupe: a word is shown ONCE
Seen: "MAKING" behind the head while "SUPPOSEDLY MAKING" sits in the bottom caption; "CAPITAL" behind + "CAPITAL EXCUSE".
`depth.drop_covered` only drops text whose BOX overlaps the card. Fix: every word token rendered as an accepted depth card is
removed from the front caption stream for its time span (match by word time overlap, not by string — the same word can be
spoken twice). If a front chunk becomes empty, nothing shows at the bottom then (the depth card is the caption). Neighbouring
words that were chunked with it re-chunk on their own (no orphan 1-letter cards; merge into prev/next chunk if < ~0.25 s).
The hook band stays. Fallback cards (front) are unaffected. Test with a synthetic EDL: zero tokens appear in both layers.

## 3. Flow and rhythm
Today: `editcraft.chunk_words`, `sub_chunk` 2, cards abut each other end to start. Style score vs the kumar-method pack
(~/Projects/clip-studio-refs/style-packs/kumar-method) = 54.9, weakest dims text .64 and rhythm .59. Targets come FROM the
pack / style.json at render time (words_per_card_median, card duration distribution, text-free share), not hard-coded.
- Phrase-aware chunking: break at punctuation and at word gaps >= ~0.18 s (named constant); never end a card on an article /
  preposition / conjunction / possessive ("THE", "OF", "AND", "YOUR"…) — pull it into the next card; numbers + units stay
  together ("$100", "10 YEARS").
- Timing: card on at first word onset (allow ~1 frame lead), off at last word end + short tail; never shorter than ~0.30 s
  on screen (merge instead); a stressed/emphasis word may get its own card.
- Cinematic pauses = deliberate text-free windows: b-roll cutaways, the montage/outro, the first ~0.4 s after a hard punch-in
  on an emphasis word, and any kept gap >= ~0.45 s. Captions clear there, they do not hold over. Log the windows in the run
  record.
- Score before/after with `edit-style-score` on the same moment; report text and rhythm dims. Do not tune to the score
  alone — LOOK at the result.

## Proof (real renders, local only, never queued)
PB Blake moment mom_bab1b6992f (src_c9b497e0d2 195.95-242.25), EDL-r3 settings
(~/Projects/clip-studio.builders/clip-studio-editroom-20261012-000015/docs/proof/editroom/EDL-r3.json, preset D), in a tmp
copy of the library, `frame: wide`, music_bed `montage` (outro over the licence-gated campaign-source bed — this merged path
is unverified by a real render: depth + outro + audio input index in `render_edit`; prove it plays, has audio, no black tail):
1. `docs/proof/flow/normal-wide.mp4` (depth off) and `docs/proof/flow/depth-wide.mp4` (depth all).
2. `docs/proof/flow/side-by-side.mp4` [normal-wide | depth-wide], same length, labels via Pillow PNG (ffmpeg has no drawtext).
3. Stills from the real MP4s at every depth-card onset (max 8) + 2 cinematic-pause stills + 1 outro still.
4. Same moment `frame: square`, depth all → card pass counts table wide vs square.
LOOK at every still before finishing: same framing both sides, no word in two places, no letter cut, captions clear on b-roll
and the outro. If anything is off, fix and re-render.

## Done =
Whole engine pytest green incl. new tests for frame parity, de-dupe, chunk rules, pause windows; proofs rendered and looked
at; result.md says plainly what is still off and gives the style-score before/after and the wide vs square card counts.
