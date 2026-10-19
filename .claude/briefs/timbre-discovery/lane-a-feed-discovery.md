# Lane A — timbre-feed: true search, trackable get, discovery endpoints

You are in a git worktree of ~/Projects/timbre-feed (Node >= 24, zero dependencies, `node --test`).
timbre-feed is Yahia's music backend: Prowlarr search -> TorBox -> library at ~/Music/Timbre Library,
served by Navidrome (127.0.0.1:4533) to the Timbre Mac app. A LIVE instance runs from ~/Projects/timbre-feed
on 127.0.0.1:8795 (launchd). Never stop, restart or reconfigure it. Never write into ~/Music/Timbre Library.
For live checks, start YOUR build on another port with a temp home and temp library:
`TIMBRE_FEED_PORT=8796 TIMBRE_FEED_HOME=$(mktemp -d) TIMBRE_LIBRARY=$(mktemp -d) node bin/timbre-feed.js serve`
(read-only calls to Spotify through the live instance's /find are fine for recording fixtures).

Read FIRST: /Users/y/Projects/true/.claude/briefs/timbre-discovery/CONTRACT.md (the API you must ship,
exact shapes) and BOARD.md next to it. Implement the "Lane A" section exactly.

## Steps (commit after each, tests green each time)
0. Merge branch `builder/timbre-discover-weekly-20261012-20261012-151521` into your branch (taste profile,
   similar artists via Deezer + ListenBrainz, weekly picks, Discovery/ folder, `discover --dry-run`, POST /discover).
   Review it as you merge: the weekly job must stay OFF by default; promote/expire must stay hard-guarded to
   Discovery/. Run the dry run against your temp setup if possible, otherwise against the live read-only data
   with --dry-run, and save its output to `proofs/discover-dry-run.txt`. Do NOT run a real discover batch.
1. True search. Yahia: "when i do a search i want to find real results of the song i searched".
   Today `GET /find?q=frank ocean blonde` returns A$AP Rocky and random tracks mixed in. Add relevance scoring:
   split the query into artist/title candidates, normalized exact and prefix matches on title and artist,
   popularity as a tie-break, and sink junk editions (karaoke, tribute, slowed, sped up, nightcore, 8D,
   "originally performed by") unless the query asks for them. Return `top`, `score`, `artists`, and `localPath`
   for owned tracks. Keep the call fast (it is ~1.4 s today; do not add serial network round-trips).
   Validate on UNSEEN queries: record >= 30 real queries (Spotify responses saved as fixtures; mix of
   "artist song", "song artist", song only, album only, artist only, typos, features). Tune on 20 and report the
   top-1 hit rate on the other 10 held out. Put the table in your final report.
2. Trackable get (tickets), exactly as in the contract. Today the lossy stand-in fetch is fire-and-forget
   (src/app.js `get`). Tickets persist in the state file. `playable` the moment the stand-in file is on disk
   (atomic publish already exists in jobs.js), `lossless` when the replacement lands. Ask Navidrome to rescan
   after a file lands. An already-owned track resolves immediately. Measure time-to-playable on 3 real tracks
   against your TEMP library and report the numbers.
3. `GET /artist/:id`, `GET /similar`, `GET /new-releases`, `GET /discover/weekly` per the contract,
   reusing the discover branch's sources and caches. Owned flags come from the existing library index.
4. Tests for every new route and for the ranking (fixture-based, no network in `npm test`).

## Gates
`npm test` green; `node --check` clean; a live smoke of every new route on your port-8796 instance, with the
curl output pasted into your report. No new npm dependencies.

## Definition of done
Report includes: the held-out search table, time-to-playable numbers, smoke output, and anything in the
contract you could not do (also written to BOARD.md under "Contract questions").

DISCIPLINE (non-negotiable):
- Lane: you work ONLY in your worktree of timbre-feed. Do not touch, checkout, or revert anything outside it —
  other agents have uncommitted work in other worktrees of this repo (Lane B edits src/collection*.js).
  Keep your server.js / app.js edits small and local, so the merge with Lane B stays easy.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge into main,
  NEVER 'ship' — the user pushes, not you. Do not suggest pushing more than once.
- Gates: run tests in the FOREGROUND and wait for them. NO background shells (run_in_background), NO watch modes,
  NO until-loops. Kill anything you started (your port-8796 server) before finishing.
- Claims: 'done' means you ran the gate and pasted the passing output. Local commit != 'pushed';
  code written != 'working'. Never report a state you didn't verify this session.
- Decisions: search ranking is deterministic scoring owned by code (no LLM prompt-and-parse, no hand keyword
  lists beyond the junk-edition terms named above).
- If blocked or idle: say BLOCKED/IDLE + one line why. Do not invent extra scope.
