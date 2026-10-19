# Lane B — timbre-feed: collection upgrades, album gaps, metadata audit (dry-run first)

You are in a git worktree of ~/Projects/timbre-feed (Node >= 24, zero dependencies, `node --test`).
timbre-feed is Yahia's music backend: Prowlarr search -> TorBox -> library at ~/Music/Timbre Library
(2,336 tracks, only 118 lossless, 2,218 lossy stand-ins waiting for lossless), served by Navidrome to the
Timbre app. A LIVE instance runs from ~/Projects/timbre-feed on 127.0.0.1:8795. Never stop, restart or
reconfigure it.

THE LIBRARY IS YAHIA'S REAL COLLECTION. Rule: read-only audit first -> preview of exactly what would change
-> change only with `confirm: true`. In this build you NEVER call a mutating route with confirm against the
real library. You MAY read the real library and the live state read-only to produce the dry-run reports.
Mutations are tested against temp copies only (`TIMBRE_LIBRARY=$(mktemp -d)` + fixture files).

Read FIRST: /Users/y/Projects/true/.claude/briefs/timbre-discovery/CONTRACT.md ("Lane B" section, exact
shapes) and BOARD.md next to it.

## Steps (commit after each, tests green each time)
1. Lossless upgrade. Build on the existing pending-lossless machinery (src/app.js pendingLossless, src/lossy.js,
   src/fill.js) — do not duplicate it. `GET /collection/upgrade/plan` groups stand-ins by album. `losslessFound`
   comes from a Prowlarr search plus a TorBox cached check, run as a background pass that writes a report file;
   the GET returns the last report (null = not checked yet). `POST /collection/upgrade {confirm, limit}` queues at
   most `limit` albums per call and respects TorBox and Prowlarr rate limits.
2. Album gaps. `GET /collection/gaps?maxOwned=N` lists albums where the library holds 1..N of the album's tracks,
   using Spotify album metadata (cached). `POST /collection/gaps/fill` queues lossless album jobs (confirm only).
3. Metadata audit. `GET /collection/audit`:
   - artist-photo: Music/<Artist>/artist.jpg that came from the wrong Spotify artist (known case: Kanye West's
     artist.jpg is a photo of a mountain goat). Find out why src/artistart.js picked it (exact-name match on the
     wrong artist?), fix the picker, and flag every photo whose source artist id does not match the artist ids on
     that artist's tracks.
   - duplicate-artist: case, accent and "feat." variants of one artist split across folders.
   - missing-year, missing-cover, wrong-cover (album folder cover.jpg vs the album's Spotify image).
   Each issue has a proposedFix and a confidence score. `POST /collection/audit/apply {ids, confirm}` applies only
   those ids, never deletes (anything replaced moves to <TIMBRE_FEED_HOME>/trash/<timestamp>/), and writes an undo
   log that `POST /collection/audit/undo` restores from.
4. Produce the real dry-run reports (read-only) for Yahia: `proofs/upgrade-plan.json`, `proofs/gaps.json`,
   `proofs/audit.json`, plus `proofs/COLLECTION-REPORT.md`: counts per issue kind, the 10 most impactful items of
   each, and the exact fixes you would apply.

## Code placement (to keep the merge with Lane A easy)
New logic goes in new files `src/collection.js` (+ `src/audit.js` if it gets big). Register the routes in
server.js with ONE small block that calls into collection.js. Touch app.js only to wire dependencies.

## Gates
`npm test` green (fixture-based, no network); `node --check` clean; a smoke of every new route on your own
instance (`TIMBRE_FEED_PORT=8797 TIMBRE_FEED_HOME=$(mktemp -d) TIMBRE_LIBRARY=<temp copy>`), with the curl output
in your report. No new npm dependencies.

DISCIPLINE (non-negotiable):
- Lane: you work ONLY in your worktree of timbre-feed. Do not touch, checkout, or revert anything outside it —
  Lane A is editing search/get/discovery in another worktree of this repo at the same time.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge into main,
  NEVER 'ship' — the user pushes, not you. Do not suggest pushing more than once.
- Gates: run tests in the FOREGROUND and wait for them. NO background shells (run_in_background), NO watch modes,
  NO until-loops. Kill anything you started (your port-8797 server) before finishing.
- Claims: 'done' means you ran the gate and pasted the passing output. Local commit != 'pushed';
  code written != 'working'. Never report a state you didn't verify this session.
- Decisions: matching and verification is deterministic code (ids, normalized names, image hashes). No LLM
  prompt-and-parse. If a match is ambiguous, give it a low confidence and leave it for Yahia.
- If blocked or idle: say BLOCKED/IDLE + one line why. Do not invent extra scope.
