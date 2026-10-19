# Clip Studio: Trend Scout r2 — hunt trending EDITS, editing methods and templates (not topics)

First read and follow ~/.claude/skills/dispatch-brief/SKILL.md. Repo: ~/Projects/clip-studio, worktree off main 1290124. No push,
no merge, never relaunch the ClipStudio app, never write to the real library or the real lab home (tests: fixtures / tmp;
live proof: CLIPSTUDIO_LAB_HOME=<tmp>, CLIPSTUDIO_HOME=<tmp copy>). Never post or queue anything. Worktrees have no venv: run
`PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q` from the worktree's engine/. Build
`engine/native/framescan/` in the worktree before learning. Another builder is editing editroom/depth/editcraft right now —
stay out of those files. Write result.md EARLY and extend it as you go.

## The ask (Yahia)
Asked what the scout should look for: "like trending edits and edintg methods and templets to follow".
Today the scout (engine/clipengine/trendscout.py: scout → fetch → learn → trends) searches topics ("finance", "trading", "edit")
plus YouTube mostPopular charts (cats 27/28), so its first live run picked generic viral shorts (movie clips, phone memes).
We clip talking-head / podcast / commentary creators (PB Blake trading, Solved, Alpha), so "trending edits" = editing styles
that work on a person talking: captions, text cards, cuts, punch-ins, b-roll, music, transitions, layouts.
Yahia, follow-up: "fan edits work aswell as t hey get views and the audince aswell" → ALSO hunt fan edits (beat-synced /
velocity / phonk-style edits of a person, character, athlete or creator). Two genres, tracked separately everywhere below:
`talking` and `fan_edit`. We LEARN fan-edit grammar from any public fan edit (grammar only). We only ever PRODUCE edits from
footage a campaign licenses (our creators' own clips, where the campaign allows an edit format) — never film/anime/sport
footage we hold no rights to. Producing fan edits (and their music, which must pass the licence gate) is a later build;
this build only scouts, measures, and templates them.

## Build
1. **Edit-hunting queries.** Replace the default query set with phrases that surface edited talking-head / podcast / interview
   shorts (e.g. podcast clips, interview clip, motivational speech edit, business advice short, storytelling short, captions,
   kinetic captions, "text behind" edit, documentary style short) AND fan-edit phrases (e.g. edit, velocity edit, phonk edit,
   beat sync edit, creator/podcaster edit, motivation edit, athlete edit) — config-editable list per genre, in DEFAULT config. mostPopular
   charts OFF by default (config flag to re-enable). "Follow what works": channels whose refs pass both gates below go on a
   watch list; next scouts pull their recent shorts (search.list channelId, order=date) within the quota floor.
2. **Gate A (pre-download, Jev, metadata only).** state = {title, description[:400], channel, tags[:15], duration_s}.
   choice `genre` (instructions: "Based on `title`, `description`, `channel` and `tags`, what kind of short is this most
   likely to be?"): talking = "a real person talking — to camera, in a podcast, interview or speech — cut with captions or
   text"; fan_edit = "a fan edit: footage of a person, character, athlete or creator cut to music with beat-synced cuts,
   speed ramps or effects"; other = "a plain movie or TV scene, meme, music video, gameplay, sports highlight without editing,
   animal clip, animation, or anything else". Keep if the choice is talking/fan_edit with confidence over a named floor. Rejects stay in lab_refs with status `rejected_gate_a` + the score (audit trail).
   Use the engine's jev.py helpers (site="trendscout.gate_a"); Jev down → fall through to download, logged, never crash.
3. **Gate B (post-learn, measured, no model).** From the real style.json keys (READ a real style.json first — the last bug
   here was guessed keys): it is an "edit" only if it has on-screen text/captions over a minimum share of its runtime AND a face
   on screen for a minimum share. Fan edits instead need a high cut rate and/or cuts aligned to the audio beat (or speed/effect
   signals if the learner measures them); captions and face optional. Otherwise status `not_edited` and it never counts
   toward trends/templates.
4. **Methods.** Map style.json features to named editing methods that match our Edit Room op names (word-by-word captions,
   phrase captions, word slam, text behind subject, punch-in, push-in, b-roll cutaway, beat montage, flash transition, music bed
   under speech, square vs wide layout, end card …) plus fan-edit methods (beat-synced cuts, cut rate, speed ramps, shake,
   zoom punch on beat, flash, colour grade, overlays/text, music-led with no speech …). Only methods the learner actually measures — list the unmeasurable ones as
   such, do not guess. `lab-trends` reports per method: share of this week's passing outlier refs vs last week's, rising/falling.
5. **Templates.** Per genre, group passing refs by a bucketed style signature (layout × caption style × pace × music); a group of ≥ 3 refs
   = a template: a style pack built from the group's medians (extend stylepack.build to take several style.json files), named
   from its features (e.g. "square · white word-by-word · fast cuts · bed under speech"), with member ref ids + outlier scores.
   Saved under the lab home's style-packs. Campaign policy still wins over a pack (existing precedence). Templates are
   suggestions — applying one to a campaign is Yahia's call, never automatic.
6. **CLI.** `lab-templates` (list + members + methods) and `lab-trends` gains the methods table; JSON events like the others.

## Rights (settled — never change)
Grammar only: never reuse ref footage, audio or words; downloads are local measurement only; never copy refs into the repo or
commit them. Official sources only: YouTube Data API key (keychain item `youtube-api`), oEmbed, drop folder; no logins, cookies
or proxies. TikTok/Instagram stay metadata-only unless Yahia drops the video in the inbox. Quota floor respected.

## Calibration (before trusting Gate A's floor)
Run one live scout into the tmp lab home. Hand-label >= 40 candidates from their thumbnails (official API thumbnail URL; look at
each) as talking / fan_edit / other BEFORE looking at Jev's answers (at least 10 of each kept genre); report precision/recall per genre at 3 floors on those labels and pick the
floor. State plainly that 40 labels is a first cut.

## Proof
Live run (tmp lab home), both genres: candidates per query, Gate A per genre + reject with 10 example titles each, downloaded, learned, Gate B
pass/reject, the methods table, every template found (name, members, one contact frame per member). Contact sheet
`docs/proof/scout-edits/accepted-<genre>.png` (1 frame per accepted ref) — LOOK at it: if unedited movie clips/memes get through, fix and
rerun. Quota units used. Unit tests: query config, both gates (Jev mocked), method mapping on real-key fixtures, template grouping,
pack-from-many medians.

## Done =
Whole engine pytest green incl. new tests; live proof in result.md with the contact sheet looked at; result.md says plainly
what is still weak (e.g. methods the learner cannot measure yet).
