PASS 7b — real song numbers + Save the full mix (same worktree/branch as pass 7).

## 1. Merge songpop (now DONE)
Merge branch `builder/clip-studio-songpop-1-20261012-152408` (engine: songpop.py, `music-popular`, cache table track_pop in
musiclib.sqlite; 692 pytest). Read engine/docs/songpop.md + docs/proof/songpop/README.md FIRST and make the Swift decoder match
the REAL contract (your pass-7 decoder was a guess) + add the missing fixture test from docs/songpop.md. Real coverage on 443
tracks: YouTube views 388 ok / 55 no_match, Last.fm listeners 440 ok, your plays (Navidrome) 110, TikTok 0 = `no_source`
(Creative Center is login-gated). UI: TikTok column shows "—" with tooltip "TikTok data needs a browser export" and the
"Trending on TikTok" sort chip is hidden while every row is no_source. "Your plays" shows as its own small label, never mixed
into views. Sandbox only: point CLIPSTUDIO_HOME at a sandbox with the songpop builder's sandbox musiclib.sqlite copied in
(~/Projects/clip-studio.builders/clip-studio-songpop-1-20261012-152408/ — find its .sandbox) so renders show REAL numbers;
remove the "SAMPLE DATA" rows from the song-library render.

## 2. Save carries the whole mix
Save must render exactly what you hear: mutes (speech ranges), speech level, music offset/segment, bed dB, fade in/out, duck
under speech — extend the engine CLI (`music-preview` or edit-run flags, additive, tests) and pass all of it. Test: CLI args built
from an edit model with every control set; engine test that the rendered preview's loudness in a muted range is ≥30 dB below
neighbours and the music bed ducks under speech.

## 3. Small fixes from your pass-7 result
Music block drag beat-snaps (⌥ = free); ⌘Z scoped so it never fights the hook text field; Save/Suggested on a plain clip:
create the edit record via the existing engine path instead of disabling; "SAMPLE DATA" label readable in dark.

## Gates
swift build, swift build --build-tests, swift test (grep Executed) + engine pytest for merged files. Renders: sounds-library
light/dark with REAL numbers, review-sound light/dark. Read them. Commit; no push/merge to main; never quit/relaunch
ClipStudio.app; never write the real library or the real musiclib.sqlite.
