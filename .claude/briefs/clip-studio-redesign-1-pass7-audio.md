PASS 7 — AUDIO STUDIO + SONG LIBRARY (same worktree/branch). Real playback, audio clipping and editing inside the app.

Yahia (verbatim): "what happend with the music and sounds we need this done with real playback and audio clipping and editing
skills in the studio" and "we need a better sound page with liabry of songs based on views n listents to add to our clips"

## Step 0 — bring in the music engine
Merge branch `builder/clip-studio-music-1-20261012-142616` into this branch (engine-only: musiclib.py track maps — beats,
sections, drops — musiccut.py pick / beat snap / preview / sound note, publish refuses preview files, edit-run --music-cut).
Read its docs + result first; use ITS CLI (`--json`) for everything — no Python logic re-implemented in Swift.
Library = /Users/y/Music/Timbre Library (local files, COMMERCIAL music). Licence rule is fixed: music lives in PREVIEW
renders only; the POSTED file never contains library music; the sound note tells Yahia what to add in-app.

Songpop (engine: `music-popular --json` = real popularity per library track: YouTube views, Last.fm listeners/plays,
TikTok uses/rank/trend, score 0–1, per-signal status) is STILL BEING BUILT on branch
`builder/clip-studio-songpop-1-20261012-152408` while you work. ORDER: build items 2, 3 and 4 FIRST. Then, before item 1, check
`git -C ~/Projects/clip-studio log --oneline builder/clip-studio-songpop-1-20261012-152408 -- engine/docs/songpop.md`: once
that commit exists AND `~/.claude/bin/builder status 2>&1 | grep songpop` says done, merge the branch, read docs/songpop.md +
docs/proof/songpop, and build item 1 on it. Not done yet → re-check every 5 min for up to 40 min; still not done → build item 1
against the contract in this brief with "—" for every signal (never placeholder numbers) and say so in your result.

## Also (from pass 6 review)
- Home "Needs you" with 1 card leaves its column mostly empty: when one side has ≤2 items, give the other side the width.
- Screens must never ship sample numbers in the app itself (render.sh snapshots may, but label the render "sample data").

## Build
1. Sounds page = a SONG LIBRARY ranked by real popularity, two segments: "Song library" (default; music-popular rows) and
   "Trending sounds" (pass-5 tiles). Song library = a ranked list/grid, rank number on the left; each row/tile: title · artist ·
   length · YouTube views · listeners · TikTok uses (+ up/down trend arrow) · ActivityRing = score · ▶ real preview of the
   local file (AVPlayer, 15 s from the track map's drop) · "Add to clip…" (picks a moment → opens its review player with this
   track loaded in the music lane, item 3). Sort chips: Top (score) · Most viewed · Most listened · Trending on TikTok.
   Search + BPM/mood chips. Numbers compact (1.2M); null = "—" with the status as a tooltip ("no match on YouTube").
   Licence line under the header, plain: "Songs play in previews only. The posted video stays clean — add the sound in TikTok."
2. Track view (click a tile): REAL playback of the local file (AVPlayer), waveform drawn from the audio itself
   (AVAssetReader → downsampled peaks, cached to disk per track), beat grid + section/drop markers from the track map,
   playhead, click-to-seek, scrub. Drag on the waveform = select a region (the "audio clip"); edges snap to beats (hold ⌥ for
   free); region shows its length; Space plays, L loops the region, I / O set in/out at the playhead. "Use on clip…" sends
   the region to a moment's review player.
3. Sound timeline in the pass-5 full-screen review player (under the 9:16 video):
   - Lane 1 = the clip's own audio waveform (speech). Drag a range → mute it. Slur ranges from the EDL show red and stay
     muted (locked). Speech level slider.
   - Lane 2 = music: the chosen segment as a block; drag to offset, trim edges (beat-snapped), bed volume (dB), fade in /
     fade out, "duck under speech" toggle. "Suggested" fills it with musiccut's pick + why + beats-on-cut %.
   - LIVE preview: playback mixes clip audio + music segment in real time (AVMutableComposition + AVAudioMix volume ramps,
     fades, ducking) — no render needed to hear an edit. Video stays in sync.
   - Save → engine renders preview-music.mp4 via the music branch CLI with the chosen track / offset / segment / levels;
     the post file stays music-free. The sound note is shown as "Add in TikTok: Artist – Title, from 0:45" + Copy.
   - ⌘Z / ⇧⌘Z undo/redo for every sound edit. J/K/L shuttle.
4. Taste: ~/.claude/skills/taste/SKILL.md. Waveforms in text2/text3, the selected region and the music block in money green
   at low alpha, playhead white/ink. Light + dark.

## Gates
swift build, swift build --build-tests, swift test (grep "Executed") + new tests: peak extraction on a generated sine file,
region beat-snap math, composition duration + volume ramps match the edit model, save builds the right CLI args,
music-popular JSON decode (fixture from docs/songpop.md) + each sort order + null signals render "—".
Engine pytest for the merged music files. Renders into docs/screens/redesign/: sounds-library-light/dark, track-view-light/dark
(region selected, beat grid visible), review-sound-light/dark (both lanes, a muted range, a music block). Read your renders.
Also prove playback for real: a test that plays 2 s of a library track through the AVPlayer path and asserts currentTime
advanced. Commit; no push/merge to main; do NOT quit or relaunch any running ClipStudio.app; CLIPSTUDIO_HOME sandbox only.
