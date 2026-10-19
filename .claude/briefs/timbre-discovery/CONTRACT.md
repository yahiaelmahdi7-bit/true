# timbre-feed API v2 — the contract between the feed lanes and the app lane

Owner: orchestrator (Claude in the True session). Lanes MUST NOT change shapes here; if a field is
impossible, write it in BOARD.md under "Contract questions" and keep going with the rest.

Server: timbre-feed, `http://127.0.0.1:8795` (the app reads `timbre.feedURL` from UserDefaults,
default that URL). JSON in/out. Existing routes keep working unchanged (backward compatible).
Mutating routes without `"confirm": true` return the plan only (dry run) and change nothing.

## Shared shapes

Result (a song/album/artist from anywhere; existing /find fields kept, new ones added):
```
{ kind: "track"|"album"|"artist", id: "<spotify id or mb:…>", title, artist, artistId?, album, albumId?,
  year, duration /*s*/, source: "spotify"|"musicbrainz"|"itunes"|"local", art /*https url|null*/,
  local: bool, quality: "lossless"|"lossy"|null,
  score: 0..1,            // NEW relevance to the query (1 = exact song asked for)
  localPath: string|null  // NEW library-relative file path when local && kind=="track"
}
```
Owned: `"all"|"some"|"none"` for albums (with `ownedCount`, `trackCount`), bool for tracks/artists.

## Lane A — search + get + discovery

`GET /find?q=&type=all|track|album|artist` →
`{ query, top: Result|null, results: Result[] /*relevance-ordered, top first*/, artists: Result[] }`
- `top` = the thing the user most likely meant. "frank ocean nights" → the track Nights by Frank Ocean.
  "blonde" → the album Blonde. Junk editions (karaoke, tribute, slowed, sped up, nightcore, 8D,
  "originally performed by") sink unless the query asks for them.

`POST /get {kind, id, allowLossy?, confirm?}` → existing fields PLUS
`tickets: [{ ticket, kind, id, title, artist }]` (one per requested track; one per album for albums).

`GET /tickets/:ticket` →
```
{ ticket, kind, id, state: "queued"|"fetching"|"playable"|"lossless"|"failed",
  quality: "lossy"|"lossless"|null, path: string|null /*library-relative*/, progress: 0..1|null,
  error: string|null, updatedAt: iso8601 }
```
- `playable` = a file is on disk at `path` and can be played right now (lossy stand-in or better).
- `lossless` = the lossless file replaced the stand-in; `path` updates to the new file.
- A track already in the library returns a ticket that is immediately `playable`/`lossless`.
- Tickets persist (state file) for 7 days. Target: `playable` within ~15 s for a normal pop track.
- After a file lands, Navidrome is asked to rescan (Subsonic `startScan`).

`GET /artist/:id` →
`{ artist: {id, name, art, genres: [], local: bool}, topTracks: Result[],
   albums: [{ id, title, year, type: "album"|"single"|"compilation", art, owned, ownedCount, trackCount }] }`

`GET /similar?artist=<id>` or `?track=<id>` →
`{ artists: [{ id, name, art, local: bool, why: string }], tracks: Result[] }` (Deezer + ListenBrainz
sources from the Discover branch; cached)

`GET /new-releases?limit=30` →
`{ releases: [{ id, title, artist, artistId, releaseDate, type, art, owned }] }` (last 90 days, from the
top taste artists; cached 12 h)

`GET /discover/weekly` → `{ week: "2026-W42", picks: Result[], fetched: bool }`

## Lane B — collection (all dry-run first)

`GET /collection/upgrade/plan` → `{ albums: [{ albumId, artist, album, lossyTracks, losslessFound: bool|null }], total }`
`POST /collection/upgrade {confirm, limit}` → `{ queued: [...] }` (rate-limited drain; never more than `limit`)

`GET /collection/gaps?maxOwned=2` → `{ albums: [{ albumId, artist, album, have, total, missing: [title] }] }`
`POST /collection/gaps/fill {albumIds: [], confirm}` → `{ queued: [...] }`

`GET /collection/audit` →
`{ issues: [{ id, kind: "artist-photo"|"duplicate-artist"|"missing-year"|"missing-cover"|"wrong-cover",
   subject, detail, proposedFix, confidence: 0..1 }] }`
`POST /collection/audit/apply {ids: [], confirm}` → `{ applied: [...], undoLog: path }`
`POST /collection/audit/undo {undoLog}` → `{ restored: [...] }`
