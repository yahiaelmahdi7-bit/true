# Timbre: artist circles show the artist's photo, not their first album cover

Repo: ~/Projects/timbre (SwiftPM macOS app, Swift 6, LOCAL ONLY). You run in your OWN worktree off main.
Other builders may be editing the main checkout — stay in your lane. Report at the end with gate output pasted.

## The bug (Yahia, live app, 2026-10-12)
Home "Artists" row: The Weeknd shows a music-note placeholder, Kanye West a black circle. Cause (verified by the
lead): every artist circle uses `artist.cover.cover` = the artist's FIRST ALBUM cover
(`ArtworkViews.swift:218` ArtistCard -> CardCover; `HomeView.swift` artist river -> `RiverItem(artData: artist.cover.cover.artworkData)`).
The Weeknd's first album has no cover; Kanye's is Donda (a black square). Meanwhile timbre-feed has saved a real
photo for 256 of 270 artists at `<library>/Music/<Artist>/artist.jpg` (640x640), and Timbre never reads it.

## Build
1. `ArtistImageStore` (@MainActor @Observable, in-memory cache, file reads OFF the main thread): resolve
   `artist.(jpg|jpeg|png|webp)` in the artist folder derived from any of the artist's local tracks (album dir's
   parent — mirror `VibeDiscovery`'s library-root guard so the library root itself is never treated as an artist dir).
   Streamed/remote tracks (RemoteCache, Navidrome): use Subsonic `getCoverArt` with Navidrome's artist id
   (`ar-<artistId>`) if Timbre already has the artist id; otherwise skip. Fallback = today's first-album cover.
2. Use it everywhere an artist is drawn as a circle: ArtistCard, the Home artists river (RiverItem artData — the river
   must update when the photo arrives, without re-shuffling or a visible pop; fade it in), ArtistView hero, Search artist results.
3. Tests: resolver picks artist.jpg over album cover; falls back cleanly; never reads the library root; a missing file
   costs no main-thread I/O.
Instant playback and scroll smoothness must not regress (time-to-sound test stays green).

## Discipline
- Lane: Sources/Timbre/Views/{ArtworkViews,HomeView,ArtistView,SearchView}.swift + a new ArtistImageStore file + tests.
  Do NOT touch AlbumDetailView/Pointer/Theme (another builder) or RootView/Audio/* (another builder).
- Never write into `/Users/y/Music/Timbre Library` (read-only). Never touch other repos.
- Do NOT launch GUI Timbre, do NOT kill/signal Yahia's running copy, no osascript.
- Swift 6: GeometryProxy closures -> nonisolated static funcs; NotificationCenter closures must not capture `note`.
- Commits: atomic, on your builder branch, end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  NEVER push, NEVER merge into main. Gates in the FOREGROUND. If blocked: BLOCKED + one line why.

GATE: `swift build -c release` 0 warnings AND `swift test` all passing. Paste both tails + counts.
