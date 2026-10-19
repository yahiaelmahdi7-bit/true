# Timbre: Liked Songs page stops scrolling — reproduce, prove the cause, fix

Repo: ~/Projects/timbre (SwiftPM macOS app, Swift 6, LOCAL ONLY). You run in your OWN worktree off main
(HEAD b922155). Another builder is editing the main checkout right now (uncommitted: RootView.swift,
AudioPlayer.swift, EnvelopeAnalyzer.swift, BeatGrid*). Do NOT touch those files.
Yahia is a non-coder who directs. Report at the end with the gate output pasted.

## The bug (Yahia, live app, 2026-10-12)
Liked Songs (`playlist:liked`, 330 tracks) opens in `Sources/Timbre/Views/AlbumDetailView.swift`.
He scrolls down ~300pt (hero gone, mini header half faded in, row ~16 "Am I Wrong" half under the
player bar) and "can't scroll past this". The rest of the 330 rows are unreachable.

What the lead already checked by reading (do not re-derive, but DO verify by measurement):
- `album.tracks` holds all 330 (LibraryPanel `LikedSongsRow` -> `Playlist.asAlbum`; PageHost passes the stale snapshot).
- No frame/height cap in `pageColumn`, `softTopFade`, `stagger` (Theme.swift). `Flight.rects` is @ObservationIgnored.
- `RiverInput` only eats HORIZONTAL wheel events over Home rivers; `Pointer`'s monitor passes everything through.
Unverified suspects, in the lead's order of suspicion:
 a) The page is a NON-lazy `VStack` of 330 `TrackRow`s. Every scroll tick sets `@State offset` (onScrollGeometryChange)
    -> the whole AlbumDetailView body re-evaluates (ForEach over Array(enumerated()) of 330) AND all 330 rows'
    `PointerHover.onGeometryChange` fire -> main thread saturates, wheel events coalesce, scroll "sticks".
    Plus 330 per-row `.task` DurationStore loads and a serial 330-duration sum on open.
 b) `MissingLikesSection` = `LazyVStack` nested in a non-lazy VStack in the ScrollView (content-size estimate jumps).
 c) Something else capping the NSScrollView document height.

## Step 1 — reproduce in a test BEFORE changing code
Host `AlbumDetailView` in an offscreen NSWindow (pattern: Tests/TimbreTests/PerfTests.swift:12) at 1600x1000 with
330 synthetic tracks (album id "playlist:liked"; fixture data generated in-test, never Yahia's files) and the
environments it needs (AudioPlayer, Flight, Library, Navigator, pageInsets…). Find the NSScrollView. Record:
- documentView height vs expected (~ topBar + 340 hero + header + 330*56 + bottom padding);
- can you programmatically scroll to the bottom and is the last row's frame inside the visible rect;
- main-thread cost per scroll step (e.g. 60 steps of 40pt, median + p95 ms), and how many TrackRow bodies /
  PointerHover geometry callbacks fire per step if you can count them cheaply.
State which suspect the numbers prove. If none reproduces, say so plainly and report what you measured.

## Step 2 — fix the proven cause, keep every behaviour
Likely direction (adjust to what Step 1 proves): `LazyVStack` for the track rows (stagger only the first ~10);
isolate scroll-driven state (offset/progress) so the rows don't re-evaluate on every tick (e.g. a small child view
or @Observable box read only by hero/mini-header/ArtWorld); keep MissingLikesSection reachable at the bottom.
MUST keep: hero parallax + scale, sticky mini header + play-button handoff, Flight hero rect (return flight),
hover with no flicker (Pointer system), stagger entrance, double-click play, selection.
The Step 1 test becomes the regression test: last row reachable + per-step cost under a budget you set from the
measured after-fix number x1.5 (write both numbers in the test comment).

## Step 3 — small companion fix
In playlists (`isPlaylist`) the # column shows each song's ALBUM track number (Liked Songs reads 1,3,9,4,1…).
Playlists show position (index+1); real albums keep `track.trackNumber ?? index + 1`. Add a tiny test.

## DISCIPLINE
- Lane: only Sources/Timbre/Views/{AlbumDetailView,MissingLikesSection,Pointer,Theme}.swift + new test files.
  Never touch other repos (esp. ~/Projects/timbre-feed). Never write into `/Users/y/Music/Timbre Library`.
- Commits: atomic, on your builder branch, message what+why, end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. NEVER push, NEVER merge into main.
- Do NOT launch GUI Timbre, do NOT kill/signal Yahia's running copy (~/Applications/Timbre.app), no osascript.
- Swift 6: GeometryProxy closures -> nonisolated static funcs; NotificationCenter closures must not capture `note`.
- Gates in the FOREGROUND; no background shells or watch loops. 'done' = gate run + output pasted.
- If blocked: BLOCKED + one line why. No extra scope.

GATE: `swift build -c release` 0 warnings AND `swift test` all passing (baseline at b922155; report counts).
Report: which suspect was real (with the before/after numbers), files changed, commits, gate tails.
