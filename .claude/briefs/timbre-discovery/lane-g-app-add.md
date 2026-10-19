# Lane G — Get finishes, library picks it up at once (Timbre app, Swift)
Repo: this worktree (branched from release/20261012 @ 6857dd2). Commit locally, never push/merge. NEVER launch Timbre or install anything; never touch ~/Music or the real library; tests use fakes/temp dirs. After `swift test`, restore any proofs/ you didn't mean to change (`git checkout proofs/<file>`); timing tests LikedScrollTests/PerfTests are known-flaky — compare against base before blaming yourself.

## Why
Yahia: "if I add it the library grabs it and adds it". Today in Sources/Timbre/Feed/Feed.swift:
- `get(kind:id:)` (the Get button) fires `POST /get` and sets `.fetching(nil)` forever — never polls the ticket, never says done.
- `run()` (Play) polls and plays, but nothing tells the Library a file landed. The app runs CONNECTED to Navidrome (Library.albums = remoteAlbums); `refreshRemote()` (Remote/LibraryRemote.swift ~101) only runs every 60 s AND only while `NSApplication.shared.isActive` — so a gotten song shows up late or not until focus.
- Navidrome (Docker, music folder = the library) picks files up within ~5–60 s; the feed asks it to rescan when a file lands.

## Contract with the feed (lane F builds the other side — use exactly this)
`POST /get {kind, id, allowLossy, confirm:true, hint:{title, artist, album, duration (seconds), year}}` — send `hint` from the FeedResult on every get (track and album). Response/ticket shapes unchanged.

## Do
1. FeedClient.get gains `hint` (FeedResult → hint dict, omit nil fields); HTTPFeedClient sends it; FakeFeedClient records it.
2. Get button = add to library: poll the ticket like `run()` (no playback). Deadline: track 15 min, album 3 h; keep the existing miss/offline handling. New FeedJob state for done (e.g. `.added`); LiveRow / FeedAlbumTile show "Added" (plain, short — UI copy rule: no raw engine text). Progress shows while fetching.
3. Library refresh on landing: add `Library.refreshSoon(until:)` — coalesced (one in flight, later requests extend it), runs regardless of app focus, calls `refreshRemote()` with backoff ~[2, 6, 15, 30, 60, 90] s and stops early once the predicate sees the new track (match by Feed.key(title, artist) against library tracks/albums). Call it when a ticket becomes playable/lossless from BOTH Play and Get. Local (not connected) mode: scan just the landed file into `tracks` instead (LibraryScanner single-file load; keep the extension set as is).
4. After the library changes, Feed's `owned` map must be recomputed so the row flips from Get/Added to an owned row that plays from the library (check how `owned` is rebuilt today — Feed.swift ~60 — and hook it to library changes if it isn't).
5. Tests (XCTest, fakes): Get → polls → `.added`; failure path; hint present in the request body (URLProtocol stub for HTTPFeedClient); refreshSoon coalesces, stops on found, gives up after the schedule; owned flips after a refresh. Full `swift test` green apart from the known-flaky timing pair.
6. Still: proofs/add-flow.png — search rows in three states (Getting it… with progress, Added, owned), rendered like DiscoveryRenderTests.

Done when: tests green, still written, one or more commits. Report: commits, tests, what the still shows, anything unverified.
