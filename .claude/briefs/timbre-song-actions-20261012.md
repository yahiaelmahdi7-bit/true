# Timbre: every song is interactive (add to playlist / like / queue / go to album / go to artist)

Work in a NEW git worktree branched from `live/scroll-photos-20261012` (repo ~/Projects/timbre; base worktree ~/Projects/timbre.builders/combined-live-20261012). Do NOT touch the main checkout ~/Projects/timbre (another builder works there uncommitted). Another builder (cover art) is editing ArtworkViews.swift + album cards on a sibling branch: keep your changes out of ArtworkViews.swift where possible to avoid merge conflicts. Commit on your branch.

## Yahia's words
"the songs are not interactable make it so i can add them to playlist and liked songs and queue and so on and go to album n artist"

## Do
1. Audit every place a song appears (TrackRow, album detail, playlist, Liked Songs, search results, Home shelves, queue, Now Playing panel, full-screen ImmersiveView, mini player). List which have actions today.
2. One shared song-actions component (single source of truth) used everywhere:
   - Right-click context menu + a "…" button that appears on row hover (and is always visible on Now Playing / full screen).
   - Actions: Play next · Add to queue · Like / Remove from Liked Songs · Add to playlist ▸ (list of playlists + "New playlist…") · Go to album · Go to artist (submenu when several artists) · Remove from this playlist (only in a playlist) · Remove from queue (only in queue) · Show in Finder.
   - Clicking the artist name / album name text in rows and in Now Playing navigates there.
   - Multi-select (⌘/⇧-click) rows → the same menu applies to the selection.
   - Drag a row onto a playlist in the sidebar adds it.
3. Reuse existing models for likes/playlists/queue; if any action has no backing model (e.g. playlist write), implement it with persistence and a test.
4. Feedback: brief non-blocking toast ("Added to Late Night") with Undo where cheap.
5. Keyboard: ⌘L like, Return play, menu key/ctrl-click works.

## Gate
`swift build -c release` 0 warnings, `swift test` all pass (PerfTests.scrubberTicks is environmental if display asleep — rerun). Tests for queue insert (play next vs add), playlist add/remove persistence, like toggle, navigation targets. No scroll-perf regression on Liked Songs (hover affordance must not re-render whole rows; never blur large scaledToFill images). Report a table: surface × action → works. Package with ./scripts/package.sh assets/timbre-red.icns into dist/. Don't install, don't launch on screen.
