# Clip Studio — Finder: filters + custom plain-English filters, configured by chat (engine)

GOAL (one sentence): Yahia can say "clip every time I welcome someone" in a chat, get a saved Finder (filters + clip
rules) he can test on past videos, then arm it on a live stream or a VOD so every match becomes a draft clip.

Yahia (verbatim): "how can we make it so its a real moment finder with filters and custom filters we can prompt it with a chat
bot that can configre it to find like oh every time i welcome someone it clips and a chat layer with ai will configre it n clip
it up in that mode so lets set that up aswell"

## Names (one per thing — use exactly these in code, CLI, events, docs)
Finder = a saved mode. Filter = one rule inside a Finder. Custom filter = a filter written as a plain-English condition.
Match = a span where the Finder fires. Test = running a Finder over past transcripts.

## Context (do not re-derive)
- Engine ~/Projects/clip-studio/engine/clipengine (Python); you are in a worktree. Tests:
  `PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q` from the worktree's engine/.
- Live loop: live.py (class Live, cmd_live :336). Per chunk: livesig.fuse (:102) → triggers [{t,start,signals[],z{},score}]
  (a trigger opens when ANY of chat / loudness / motion crosses threshold, start = 20-40 s pre-roll) → moments.find(...,
  triggers=trig) at live.py:151 → moments.windows (:12) uses triggers → claude_candidates (:51, CLAUDE_MODEL
  claude-sonnet-5-5) + jev_score (:98). VOD path: cmd_moments (:222) → find (:153). Stream chat reader: chat.py.
  Signals available: transcript segments (word timings), chat events + chat_z_series, loudness, motion, OCR (livesig :122).
- Jev: clipengine/jev.py (MODEL jev-latest, FLOOR_DEFAULT). Claude client pattern: moments.py :61.
- Other builders are editing engine/ in their own worktrees (channel-feed touches onboarding + moment ranking; vibes touches
  style packs). Keep your changes additive and in new modules where possible to keep the merge clean.

## Build
A. Finder spec + storage: table `finders` (id, name, spec JSON, armed, created, updated) + `finder_labels` (finder_id,
   source_id, t0, t1, verdict ✓/✗, at). Spec (validate strictly; reject unknown keys):
   {name, applies_to:["live","vod"], combine:"any"|"all",
    filters:[ {kind:"custom", condition:"<plain English>", look_at:["speech","chat","screen_text"]} |
              {kind:"chat_spike", min_z} | {kind:"loud", min_z} | {kind:"motion", min_z} | {kind:"money_mention"} |
              {kind:"phrase", any:[...]} (literal, user-chosen) | {kind:"duration", min_s, max_s} ],
    clip:{pre_s:3, post_s:20, min_s:7, max_s:60}, cooldown_s:45, max_per_hour:20, output:"draft"}
B. Evaluator (new finder.py): slide a 12 s window (step 4 s) over transcript (+ chat text + OCR text when look_at asks).
   Built-in filters reuse existing livesig/moments signals. Custom filters = ONE Jev noul per window per condition
   ("Does this window show: <condition>?") batched per call; state = the window's spoken text with speaker-neutral
   wording, chat lines, screen text — no verdicts in state. Threshold per custom filter = calibrated from finder_labels
   (≥8 labels: pick the floor that maximises precision at ≥0.8 recall on held-out labels); fewer labels = FLOOR_DEFAULT and
   every match carries `uncalibrated: true`. Merge overlapping matches; apply cooldown and max_per_hour. Pure functions,
   Jev mocked in tests.
C. Chat configurator (finder_chat.py): `finder-chat` reads a JSON conversation on stdin, returns {reply, spec?,
   questions?} — Claude (CLAUDE_MODEL) with a tool/JSON-schema output that can only emit a valid spec (validated by A; on
   invalid, one repair turn, then a plain reply asking Yahia). It may ask ONE clarifying question when the request is
   ambiguous ("welcome = new followers, raiders, or guests?"). It edits an existing Finder when given its id
   ("make it 30 seconds", "also when chat spikes").
D. Test: `finder-test --id X [--sources N=5]` runs the evaluator over the newest N transcribed sources/live recordings,
   prints matches (source, t0-t1, quote of what was said, which filters fired, Jev p) for Yahia to ✓/✗;
   `finder-label --id X --source S --t0 --t1 --verdict yes|no` stores labels and recalibrates.
E. Arm: live.py — when a Finder is armed for live, its matches become triggers (start = t - pre_s) that bypass the
   "is it viral" Claude pick (the Finder IS the selection) and create moments tagged finder_id; those auto-render as DRAFTS
   through the existing draft path. VOD: `finder-run --id X --source S` does the same for a source. Never post, never queue
   for publish automatically — drafts only. Keep the normal moment pipeline running alongside (Finder adds, never replaces).
F. CLI: finder-chat, finder-save, finder-list, finder-test, finder-label, finder-run, finder-arm/--disarm; `live --finder X`.
   One JSON event per line like the other commands so the app can drive it later (UI is a separate build after the redesign
   merges — do NOT touch Sources/).

## PROOF (decides done)
- Unit tests: spec validation, window sliding, combine any/all, cooldown, calibration math on fixture labels, chat
  configurator (Claude mocked) emits a valid "welcomes" spec and edits it on "make it 30 seconds", live trigger injection.
- LIVE on a COPY of the real library (`T=$(mktemp -d); sqlite3 "$HOME/Library/Application Support/ClipStudio/library.sqlite" ".backup $T/library.sqlite"`,
  CLIPSTUDIO_HOME=$T always; NEVER the real dir — the engine migrates schema on open):
  1) finder-chat with "clip every time I welcome someone" → paste the spec. 2) finder-test over the real transcripts in the
  copy → paste matches with quotes (if the library has no welcomes, also run a second Finder "every time he mentions money
  he made" and paste those). 3) finder-run on one source → paste the draft events. Read 3 of the matched quotes yourself and
  say honestly whether they are real matches.
- Full pytest green (paste tail). No Sources/ diffs.

DISCIPLINE (non-negotiable):
- Lane: ONLY engine/ + docs/ in your worktree branch. Never Sources/, .live, LaunchAgents, the real library.
- Commits: atomic, one logical change per commit, what+why. NEVER push, NEVER merge, NEVER 'ship'.
- Gates: FOREGROUND only. NO background shells, watch modes, until-loops. Kill anything you started.
- Claims: 'done' = gate output + live test output pasted. Never report a state you didn't verify.
- Decisions: classify/gate/rank steps = Jev via clipengine/jev.py (custom filters ARE this). Claude only for the chat
  configurator (a generation step). No keyword lists for judgments (the user-chosen `phrase` filter is a literal, fine).
- If blocked or idle: say BLOCKED/IDLE + one line why. Do not invent extra scope.

## Report
Files changed · the welcomes spec · test matches with quotes + your honest read · draft events · pytest tail · NOT done.
