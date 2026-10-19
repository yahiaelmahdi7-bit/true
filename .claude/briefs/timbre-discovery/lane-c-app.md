# Lane C — Timbre app: live search, play-in-seconds, artist pages, discovery shelves, immersive covers

You are in a git worktree of Timbre (SwiftUI macOS app, SwiftPM; `swift build`, `swift test`), branched off
release/20261012 @ ec0d29f. Timbre plays Yahia's library (~/Music/Timbre Library on disk + Navidrome at
localhost:4533 through Remote/SubsonicClient). Its backend, timbre-feed (127.0.0.1:8795), can search the whole
Spotify catalog live and fetch music, but the app never calls it: Views/SearchView.swift only filters the
local library. Two other lanes are extending timbre-feed right now to the API in CONTRACT.md.

Read FIRST: /Users/y/Projects/true/.claude/briefs/timbre-discovery/CONTRACT.md (the exact API; build against it)
and BOARD.md next to it. Endpoints may not exist on the live 8795 yet: build a `FeedClient` protocol + a real
HTTP client + a fake for tests and stills. Base URL from UserDefaults `timbre.feedURL`, default
http://127.0.0.1:8795.

## Yahia's words (what this must feel like)
- "a true search system that shows real results even if we dont have it indexed yet so it grabs it live"
- "when i do a search i want to find real results of the song i searched"
- "real music discovery": Discover Weekly, full artist pages, more like this, new from your artists.
- "get cover art and album work covers done for playlists and take a nice immersive approach to the whole thing"
- Picked: clicking a song you don't own = PLAY IN SECONDS (quick stand-in first, lossless swaps in later).

## Build (commit after each part; stills after each UI part)
1. FeedClient + models for every contract route (Codable, tolerant of unknown fields). Feed offline = the app
   behaves exactly as today, plus one quiet line in search ("Live search offline").
2. Search. Local results stay instant, as today. Live results arrive underneath ("Everywhere"), debounced
   ~250 ms, stale requests cancelled. A Top Result card shows the song actually asked for (contract `top`). Every
   live row shows owned state (in library / lossy / get). Owned rows play the local track exactly like today.
   Unowned rows: Play = POST /get {kind:"track", id, allowLossy:true} -> poll the ticket (~500 ms, stop when
   playable/failed/view gone) -> play the file at <library>/<path> the moment it is `playable`, with inline
   progress on the row and a clear failure state. When it later turns `lossless`, the library picks it up through
   the normal refresh; never interrupt what is playing.
3. Artist pages (Views/ArtistView.swift exists, extend it): full discography from GET /artist/:id, owned albums in
   full color, missing ones dimmed with a Get button, top tracks, a "More like this" row (GET /similar?artist=),
   and the artist's new releases.
4. More like this: on songs (context menu) and artists — a page from GET /similar with playable/gettable rows.
5. Home shelves: "Discover Weekly" (GET /discover/weekly + existing DJ/DiscoverWeekly.swift) and "New from your
   artists" (GET /new-releases). They fit the existing Home rhythm; no new card styles invented.
6. Playlist covers + immersive: every playlist without its own art gets a generated cover (a composition of its
   distinct album covers, never a flat grey tile), and playlist and artist pages get an art-tinted, full-bleed
   header world, built from the existing language: ArtWorld.swift, ImmersiveView.swift, NowPlayingWash.swift,
   CrateArt.swift, Theme.swift tokens. Extend that language; do not invent a new visual system.

## Hard rules
- Time-to-sound must not regress: nothing on the click -> sound path for owned tracks touches the network or the
  feed. TimeToSoundTests must stay green (timing tests are flaky under load: if one fails, rerun it alone and
  on the base commit before blaming your change, and report both).
- STILLS, NOT INSTALL: produce PNG stills of every new or changed screen with the existing render-test approach
  (see Tests/TimbreTests/*RenderTests.swift writing proofs/*.png) at 1440x900, using the fake FeedClient with
  realistic data (real artist/album names, covers from the local library). Name them proofs/discovery-*.png. Do
  NOT run scripts/package.sh, do NOT install, launch or quit Timbre. Yahia approves the stills first.
- Restore any tracked proofs/*.png that tests rewrite as a side effect (git checkout those files only).

## Gates
`swift build` with zero new warnings in touched files; full `swift test` green (flaky timing handled as above);
the list of stills with a one-line description each in your final report.

DISCIPLINE (non-negotiable):
- Lane: you work ONLY in your Timbre worktree. Do not touch, checkout, or revert anything outside it.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge, NEVER 'ship'.
- Gates: run build/tests in the FOREGROUND and wait for them. NO background shells, NO watch modes, NO until-loops.
  Kill anything you started before finishing.
- Claims: 'done' means you ran the gate and pasted the passing output. Never report a state you didn't verify.
- Decisions: no LLM prompt-and-parse in the app; ranking comes from the feed's `score`/`top`.
- If blocked or idle: say BLOCKED/IDLE + one line why. Do not invent extra scope.
