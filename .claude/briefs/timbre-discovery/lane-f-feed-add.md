# Lane F — "Get" works without Spotify + Navidrome rescan on every landing (timbre-feed, Node)
Repo: this worktree (branched from timbre-feed main). Commit locally, never push/merge, never restart the live launchd service net.prismlens.timbre-feed (port 8795), never touch ~/Music, ~/.timbre-feed or the real library — tests and smokes use temp dirs (TIMBRE_FEED_HOME, TIMBRE_LIBRARY) and another port.

## Why
Yahia: "if I add it the library grabs it and adds it". Today `POST /get {kind:"track", id:<spotify id>}` fails outright when Spotify is rate-limited (live right now: "Spotify rate-limited /v1/tracks/…: retry in 583 min"), because `app.get` (src/app.js ~122) and `planGet` (src/discovery.js ~151) both call `spotify.api('tracks/…')` / `albumMeta(<spotify album id>)`. The caller already knows title/artist/album/duration from the search row.

## Contract (the app lane builds against this — do not change names)
`POST /get {kind, id, allowLossy?, confirm?, hint?}` where `hint = {title, artist, album?, duration? (seconds, number), year?}`. Response shape unchanged (`{queued, tickets:[{ticket,...}], note, ...}`).

## Do
1. Hint fallback: when Spotify is unlinked, currently locked out (lane A's fail-fast lockout state — skip the call entirely, don't wait), or the lookup throws, and `hint` is present:
   - track: ticket `match = {title, artists:[artist], durationMs: duration*1000}` (no isrc); lossless album plan via MusicBrainz (find the release group for artist+album, else the recording artist+title → its release group) → `albumMeta('mb:'+rg)` (the mb: path already exists); stand-in chain TorBox→YouTube→SoundCloud by text "artist title" when allowLossy, same skip-filters + ±10% duration window.
   - album: MusicBrainz release group from hint artist+album → `albumMeta('mb:'+rg)`.
   - No hint + Spotify failing → today's error, unchanged. Spotify OK → today's path, unchanged.
   - If MusicBrainz finds nothing, the track still gets its stand-in (ticket must not fail while a stand-in can land).
2. Navidrome rescan on EVERY landing: today only `tickets.standIn()` calls `rescan()`. Make any ticket transition into `playable` or `lossless` (advance()/reconcile, album jobs finishing) call the existing single-flight `rescan()`.
3. Tests (node:test, mocked fetch/yt-dlp like test/soundcloud.test.js): Spotify throwing rate-limit + hint → ticket created with hint match, MB lookup used, stand-in path taken; no hint → error unchanged; album hint path; rescan called on a lossless transition and on a playable transition (single-flight respected). `npm test` all green.
4. Live smoke (real MusicBrainz + real yt-dlp, NO Spotify: temp home has no tokens) on port 8799 with temp home + temp library: `POST /get` with a hint for one real single (e.g. {"title":"Dai Dai","artist":"Shakira, Burna Boy","album":"Dai Dai","duration":180}) → poll `/tickets/:id` → playable with a file in the temp library. Write proofs/GET-HINT.md (commands, timings, ticket states). Stop the server after; delete nothing outside temp dirs.

Done when: tests green, smoke proof written, one or more commits. Report: commits, test count, smoke timings, anything the app lane must know.
