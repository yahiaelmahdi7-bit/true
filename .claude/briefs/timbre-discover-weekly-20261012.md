# timbre-feed: Discover Weekly — a taste profile + a weekly batch of new music

Repo: ~/Projects/timbre-feed (Node >=24, ESM, zero deps, LOCAL ONLY). You run in your OWN worktree.
The LIVE daemon runs from the main checkout — never restart, signal or reinstall it (no launchd install/uninstall).
Yahia is a non-coder who directs; he picked every decision below. Report at the end with gate output pasted.

## What Yahia asked for (2026-10-12)
"populate with other music also, it shouldn't just be all my liked music from Spotify ... use our current
system ... tailored to our taste profile". He chose: AUTO WEEKLY BATCH (~25 tracks/week, fetched on their own
into a "Discover Weekly" playlist) and RANGE = ~70% close to what he plays, ~30% one step further out.
His lanes today (from his library): Afrobeats (Burna Boy, Asake, Wizkid, Ruger), Brazilian funk / MTG,
amapiano, R&B/rap (PARTYNEXTDOOR, Drake, The Weeknd). Derive the real profile from data, not this list.

## Build (in order, one commit per step)
1. **Taste profile** (`src/taste.js`): seeds from Navidrome (Subsonic API, same auth as `src/likes.js`):
   starred songs + play counts + recency (getAlbumList2 frequent/recent, song playCount). Artist weights =
   f(likes, plays, recency). Persist to `config.home/taste.json` with a `generatedAt`. Pure scoring functions, unit-tested.
2. **Similar-artist sources** (`src/similar.js`). PROBE which work before relying on any; record results in your report:
   ListenBrainz labs similar-artists (needs MBIDs; MusicBrainz 1 req/s with the existing UA), Deezer public API
   (search/artist, /artist/{id}/related, /artist/{id}/top — no key), Spotify via the existing client (related-artists /
   recommendations are closed to many apps since late 2024 — use only if the probe returns 200). Cache responses
   in config.home; respect rate limits; 15 s timeouts like `discovery.js`.
3. **Pick the batch** (`src/discover.js`): 25 tracks. ~18 CLOSE (1 hop from top-weighted seeds, high similarity)
   + ~7 STRETCH (2nd hop or lower similarity / adjacent scene). Max 2 per artist; mostly artists NOT already in the
   library; never anything `matchLocal` finds; never anything in `state.discovery.passed`. Each pick carries a
   one-line `why` ("because you replay Asake"). Deterministic given the same inputs + seed (seed = ISO week).
4. **Fetch + place**: acquire through the EXISTING acquirer path (`createAcquirer`, same quality rules, singles via
   `selectSingles`). Discovery tracks live under `Discovery/<AlbumArtist>/<Album>/` (NOT `Music/`), so they stay
   separable. Write `Playlists/Discover Weekly.m3u8` (replace each week; reuse `layout.js` m3u8 + playlistPath).
   A pick that fails to acquire is skipped and back-filled from the ranked remainder.
5. **Promote / clean up** (runs before each new batch): a Discovery track Yahia STARRED -> moved into the normal
   `Music/` layout (atomic, `atomicPublish`/`mergeReplace` patterns), index rebuilt. Unstarred Discovery tracks older
   than 28 days -> deleted, ONLY inside `Discovery/`, and recorded in `state.discovery.passed` so they never return.
   Hard guard in code + test: the cleanup refuses any path outside `<library>/Discovery/`.
6. **Schedule + CLI**: `timbre-feed discover --dry-run` prints the batch (bucket, artist, title, why) and touches
   nothing. `timbre-feed discover` runs one real batch. Daemon: weekly job (Monday 06:00 local) wired in `app.js`,
   but SHIPPED DISABLED behind `config.discoverWeekly = false` — the lead enables it after Yahia sees the first list.

## Discipline / hard lines
- Lane: only ~/Projects/timbre-feed (src/, test/, bin/). Never touch ~/Projects/timbre.
- You may run `discover --dry-run` LIVE (read-only network: Navidrome, ListenBrainz/MusicBrainz, Deezer, Spotify
  search) and paste its full output. NEVER run a real batch, never write into `/Users/y/Music/Timbre Library`.
- Unit tests mock fetch (no network in `npm test`). Never print secrets (Navidrome password, Spotify/TorBox tokens).
- Commits: atomic, on your builder branch, message what+why, end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. NEVER push, NEVER merge into main.
- Gates in the FOREGROUND. 'done' = gate run + output pasted. If blocked: BLOCKED + one line why. No extra scope.

GATE: `npm test` all passing (report count before/after) + the live `discover --dry-run` output.
Report: which similar sources work (probe results), the taste profile's top 15 artists + weights, the dry-run list,
files changed, commits.
