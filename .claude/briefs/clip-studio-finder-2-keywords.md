PASS 2 — same worktree/branch. Keyword triggers: "ayo mods clip that" (or any keyword) on a live stream clips the moment.

Yahia (verbatim): "also can we make a system for key word detection so like ayo mods clip that triggers a clip to be taken when
on a live stream or any keywored and it wil lclip the moment"

GOAL (one sentence): when the streamer says a trigger phrase, or enough viewers type one in chat, the moment that JUST happened
becomes a draft clip within one live chunk, and Yahia gets a ping.

## Names
Trigger = a keyword Finder filter that fires a clip. Trigger phrase = the words. Look-back = how far before the trigger the
clip starts. Viewer clip = a Twitch clip a viewer made on the live channel.

## HARD SAFETY RULE (unchanged, and a sibling builder broke it today)
Never open/write/migrate the real library (~/Library/Application Support/ClipStudio). Everything runs with CLIPSTUDIO_HOME
pointed at a sandbox copy inside your worktree (sqlite3 ".backup" is the only allowed touch). Report the real library mtime
before/after.

## Build (extend finder.py; keep the existing phrase kind working)
K1. kind "keyword": {phrases:[...], source:["speech","chat"], chat_min_users (default 3), chat_window_s (default 20),
    look_back_s (default 35), post_s (default 2), keep_trigger:false, cooldown_s (default 60)}.
    - Speech: match on WORD timings, not the 12 s window text. Normalise (lowercase, strip punctuation, collapse
      repeats) and match fuzzily: token edit distance + a small variant table (ayo/a yo/ayy yo, clip/clipped/clip it/clip dat,
      mods/mod/mos). Report precision/recall of the matcher on your test set. Match time = first word of the phrase.
    - Chat: a phrase (or "!clip") typed by ≥ chat_min_users DISTINCT users within chat_window_s fires; one user spamming
      never does. Match time = first of those messages minus 5 s (chat lags the stream).
    - Clip window: end = trigger time (keep_trigger false → cut before the phrase's first word) + post_s; start = trigger
      − look_back_s, then snapped to the nearest sentence/segment start (or loudness/scene boundary) inside the look-back
      so it doesn't open mid-word. The clip must contain what happened BEFORE the phrase, not after.
    - cooldown_s: repeated "clip that clip that" = one clip.
K2. A built-in Finder "Clip that" (disabled until armed) with phrases: "clip that", "clip it", "mods clip that", "ayo mods
    clip that", "somebody clip that", "chat clip that", "!clip". finder-chat must be able to make keyword Finders from plain
    English ("clip whenever I say 'that's crazy'").
K3. Viewer clips (if the channel-feed Twitch listing code is NOT on this branch, skip and say so): while live, poll the
    live channel's newest Twitch clips every 60 s; each new one = a trigger at its offset (dedupe against K1 hits within 30 s).
K4. Output = DRAFT moments (never auto-post), tagged finder id + trigger kind + the matched words/users. Ping: macOS
    notification ("Clipped — 'ayo mods clip that' at 1:23:45") via osascript, and a `trigger` event line on stdout for the app.
K5. Replay proof: `live --replay <file>` (or reuse an existing file-as-stream path if live.py has one) feeds a local file
    through the real live loop at ≥ 4x speed. Make a test file: take a real sandbox source (e.g. src_5cbf5b5f26 Malik Dead by
    Daylight, 37 s, or a longer podcast source), splice in macOS `say -v Samantha "ayo mods clip that"` audio at 2 known
    times + 1 near-miss ("I'll clip the car later"), plus a synthetic chat log with 4 users typing "CLIP IT" at one time and
    1 user spamming it at another. Run the armed "Clip that" Finder over it.
    Report: every trigger (time, kind, words/users), each draft's start/end vs the planted moment, trigger-to-draft latency
    in stream seconds, false positives (the near-miss and the spammer must not fire), and one rendered draft still.
K6. Tests: fuzzy matcher (variants + near-misses), chat distinct-user rule, look-back window + snapping + keep_trigger cut,
    cooldown, spec validation. Full pytest green (per-file runs OK). No Sources/ diff. Commit; NO push/merge/launchctl.

State plainly anything not done or not proven (e.g. real live stream not tested).
