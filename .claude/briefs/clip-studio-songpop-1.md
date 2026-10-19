BUILD — "Song library ranked by real popularity" (ENGINE ONLY, clip-studio, your worktree). The Swift Sound page comes in a
later pass; your job is the data + a stable JSON contract it will read.

Yahia (verbatim): "we need a better sound page with liabry of songs based on views n listents to add to our clips"

## Step 0 — base
`git merge builder/clip-studio-music-1-20261012-142616` into your branch first (engine-only; musiclib.py = track maps for the
443 files in /Users/y/Music/Timbre Library, musiccut.py). Read its docs/proof/music + musiclib.py before writing anything.
Use a CLIPSTUDIO_HOME sandbox (copy the real library with `sqlite3 "<real>" ".backup <sandbox>/library.sqlite"`; real =
~/Library/Application Support/ClipStudio/library.sqlite — NEVER open it read-write, never write it). Music folder = read-only.

## Build (engine/clipengine/, additive only)
1. `music-popular [--refresh] [--track ID] [--limit N] [--sort score|views|listens|uses] --json` → event "music_popular",
   one row per library track: track_id, title, artist, length_sec, bpm, path, and REAL signals only:
   - yt_views, yt_url, yt_title, yt_channel — keyless `yt-dlp -J --flat-playlist "ytsearch5:<artist> <title>"`; accept a
     result only if title matches (normalized: lowercase, strip feat./(Official Video)/punctuation) AND duration within ±8 s of
     the local file when both are known; prefer "<Artist> - Topic" / VEVO / artist channel; take the max-views accepted
     result. No match → null + reason. No YouTube API key (quota too small for 443 tracks).
   - lastfm_listeners, lastfm_plays — Last.fm track.getInfo if Keychain service app.clipstudio account lastfm exists
     (clipengine/common.get_key pattern), else keyless public page last.fm/music/<Artist>/_/<Title> (Listeners + Scrobbles).
     Polite: ≤1 req/s, real User-Agent, back off on 429.
   - tiktok_uses, tiktok_rank, tiktok_trend (up/down/new from rank_diff) — match the track to `sounds` / `sound_obs` rows by
     normalized title+artist (exact first, then fuzzy ≥0.9, log every fuzzy match). Uses = usage_count, never estimated.
   - your_plays — ONLY if a real local play-count store exists (look: Navidrome API/DB, Timbre DJ data under ~/Projects or
     ~/Library, Music.app library). Report what you found; absent → field omitted, status "no source".
   - score 0–1 = mean of the available signals' log-percentile ranks within the library; null when no signal → sorted last.
   - per-signal status {ok|no_match|blocked:<reason>|no_key|no_source} + fetched_at. Never fake or fill a number.
   Cache in an additive table (musiclib.sqlite `track_pop`, keyed track_id+signal). Default reads cache; --refresh refetches
   rows older than 7 days (or all with --track). Full refresh of 443 tracks must be resumable (crash mid-way = continue).
2. The real trending-sound feed is EMPTY: the real library has 0 rows in `sounds` and `sound_obs`, and no settings keys
   `sounds_src_*` (sources never ran). In the sandbox: run `sounds sources` / `sounds run`, find out why nothing landed
   (blocked source? never scheduled? needs the browser path?), fix what's fixable in code, and report the exact one command
   that fills it. Do NOT add LaunchAgents or touch ~/Library/LaunchAgents — just report the command for the schedule.
3. Tests (stubs/fixtures only, no network): title normalization + match/reject rules, duration gate, last.fm page parse,
   score math with missing signals, cache freshness, resume after partial refresh.

## Proof (docs/proof/songpop/)
- Real refresh in the sandbox for the whole library (or ≥150 tracks if rate-limited — say which). Table: coverage per signal
  (n ok / no_match / blocked), top 25 by score with every number, 10 random rows hand-checked: open the yt_url in
  `yt-dlp -J` again and confirm views + that it is the same song; flag any wrong match.
- The `sounds` feed: row count after your fix + 10 sample rows (title, artist, uses, rank).
- JSON contract for the Swift page in docs/songpop.md (exact field names, null meanings, status values).

## Rules
Full pytest green (file by file is fine). Commit on your branch; no push, no merge to main. No Swift changes. No LaunchAgents.
Never quit or launch ClipStudio.app. Licence rule stays: library music is preview-only; nothing here changes posting.
