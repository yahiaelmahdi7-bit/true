# Timbre discovery build — shared board

All three lanes read this file at start and after every major step. The orchestrator writes notices
here once instead of messaging each lane.

Contract: /Users/y/Projects/true/.claude/briefs/timbre-discovery/CONTRACT.md

## Notices
- (none yet)

## Contract questions (lanes append; orchestrator answers)
- **[Lane A]** Spotify quota lockout: `tracks/:id`, `albums/:id`, `artists/:id` return 429 with retry-after ~41,000 s (~11.5 h, seen 2026-10-14 ~22:00 local); `search` and `artists/:id/albums` still work; `artists/:id/top-tracks` is 403 (removed). `POST /get {kind:track|album}` needs tracks/albums lookups, so it fails fast ("Spotify rate-limited ... retry in N min") until the lockout clears (the old code slept the whole retry-after = a hung request). Needs a decision: stop the live feed's sync/fill from hammering those endpoints?
- **[Lane A]** `artists/:id/albums` and `search` accept limit <= 10 for this app (50 gives HTTP 400): /artist/:id pages 3x10 = 30 releases max.
- **[Lane A]** `/artist/:id` topTracks: no popularity field and no top-tracks endpoint, so Spotify search results for the artist are ordered by Deezer's artist chart (title match); unmatched sort last.
- **[Lane A]** `albums[].owned` is boolean "fully owned" (ownedCount >= trackCount > 0); ownedCount/trackCount carry the partial case.
- **[Lane A]** mb:* track ids have no title/ISRC at get time, so their ticket has no file matcher: it only resolves from the album job (done -> checks nothing -> stays fetching/failed). Spotify ids are fully supported.
- **[Lane A]** time-to-playable is ~18 s (target ~15 s): yt-dlp search+download+remux dominates; not tuned.
- **[Lane A]** /discover/weekly picks come from state.discovery.lastBatch (artist/title only); ids are resolved with one Spotify search each (cached 12 h), falling back to `local:<artist - title>` ids if Spotify fails.
