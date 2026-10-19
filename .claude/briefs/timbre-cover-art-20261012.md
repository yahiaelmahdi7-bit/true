# Timbre: real cover art for albums that show a flat colour square

Work in a NEW git worktree branched from `live/scroll-photos-20261012` (repo ~/Projects/timbre, existing worktree ~/Projects/timbre.builders/combined-live-20261012 is the base). Do NOT touch the main checkout ~/Projects/timbre (another builder is working there uncommitted). Commit on your branch.

## Problem
Many albums (e.g. A.O.A "يمه ما تبكي" 2021, lots of Arabic + single releases) have no embedded art, so cards render as a flat colour square (see ArtworkViews.swift fallback). Yahia: "the cover art is ass we need better ones".

## Do
1. Audit: count albums with no usable art (no embedded, no folder.jpg/cover.*, or art < 300px). Print the list.
2. Fetch missing art, in order, first good hit wins: iTunes Search API (entity=album, artist+album, upscale artworkUrl100 → 1200x1200), then MusicBrainz release search → Cover Art Archive front-500/1200, then Deezer album search (cover_xl). Match must be confident: normalised artist equals AND album title fuzzy ≥0.85 (handle Arabic script, strip "- Single", "(Deluxe)", feat.). Singles: also try the track title as album name. Reuse whatever fetch/cache/rate-limit code the artist-photo work (commit b699576) added.
3. Cache fetched art in App Support (NOT inside the music library), keyed by album id; record source+confidence. Never overwrite embedded art. Background, rate-limited, off main thread; no scroll regression.
4. Still-missing albums: better fallback than a flat square — generated cover (artist/album initial typography over a gradient from the palette), tasteful, House grammar.
5. Fix "1 tracks" → "1 track" pluralisation.
6. A way to pick a different cover if a match is wrong (context menu "Find other cover…" showing the top candidates) — small, optional if time.

## Gate
`swift build -c release` 0 warnings, `swift test` all pass (PerfTests.scrubberTicks is environmental if display asleep — rerun). Add tests for the matcher (exact, fuzzy, Arabic, Single suffix, wrong-artist rejection). Report: before/after missing count, per-source hit counts, 10 sample matches with source, any suspected wrong matches. Package with ./scripts/package.sh assets/timbre-red.icns into dist/. Don't install; don't launch on screen.
