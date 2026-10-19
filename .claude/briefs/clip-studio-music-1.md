# Clip Studio — music from the Navidrome/Timbre library: beat + section map, cut the edit to the track, sound added in-app (engine)

GOAL (one sentence): every edit can be cut to a track from Yahia's own library — the engine knows each track's beats, drops and
sections, picks a track + segment that fits the clip, snaps the cuts to the beat, renders a PREVIEW with the music, and posts a
music-free file plus a sound note ("add <artist – title> from 0:45") so the in-app licensed copy lines up.

Yahia (verbatim): "grab the music and audio libary from our navidrome libary to feed audio with segemtns and properly cuts".
His licensing pick (asked, answered): "Cut to it, sound in-app" — the standing rule stays: NO commercial track is ever mixed into
a POSTED file. Music appears only in preview renders and in the sound note.

## Names (one per thing)
music library = the Timbre/Navidrome folder. track map = a track's analysis (bpm, beats, downbeats, sections, energy, drops).
segment = a section span of a track (intro/verse/chorus/drop/outro). sound note = the "add this sound from m:ss" instruction.
preview = a render WITH music for review only. post file = the render that gets posted (never contains library music).

## Context (do not re-derive)
- Music library (READ-ONLY, never write/move/rename): /Users/y/Music/Timbre Library/Music/<Artist>/... — 110 .flac + 313 .webm
  (+ cover .jpg), 215 artist folders; playlists as .m3u8 in /Users/y/Music/Timbre Library/Playlists (55: "Afrobeats", "Chill R&B
  Night", "BANGERS⛽️🛻💨", ...) → use playlist names as vibe tags. Served by Navidrome (docker `navidrome`, :4533, mount /music
  ro) — you don't need its API; read files + playlists directly. ~/Projects/timbre-feed/src/libindex.js shows the folder layout.
- Engine ~/Projects/clip-studio/engine/clipengine (Python); you are in a git worktree of clip-studio. Tests from the worktree's
  engine/: `PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q` (slow files one at a time).
- Existing music code you MUST extend, not duplicate: music.py (licensed library + ducked mix + render QA gate), editmusic.py
  (Edit Room bed; licence gate: campaign-source or licence.json only — keep that gate for POST files), sounds.py /
  soundtasks.py / soundintel.py + table sound_plans (cols: clip_id suggestions energy business_only added_in_app created
  chosen_key timbre — read how `timbre`/`chosen_key` are used today and plug the chosen track + start offset into that flow).
  The "needs your sound" path (Yahia adds the sound by hand in TikTok/IG; such clips are not auto-posted) already exists —
  the sound note rides on it.
- librosa is NOT in the engine venv. Install it (and only what it needs) into ~/Projects/clip-studio/engine/.venv with pip;
  record the version. Decode .webm/.flac via ffmpeg to mono 22.05 kHz wav for analysis (temp files only).
- Other builders run in their own worktrees (layouts: editroom/templates; finder: finder.py/live.py; redesign: Sources/). Keep
  changes additive, new modules (musiclib.py, musiccut.py). No Sources/ changes.

## HARD SAFETY RULE (a sibling builder wiped the real library today)
Never open/write/migrate ~/Library/Application Support/ClipStudio/library.sqlite. Work with CLIPSTUDIO_HOME = a sandbox inside
your worktree made by `sqlite3 <real> ".backup <sbx>/library.sqlite"` (the one allowed touch) + media symlinked. The track maps
live in their OWN db: $CLIPSTUDIO_HOME/musiclib.sqlite (so indexing never touches the library db). Report the real library's
mtime before/after.

## Build
M1. musiclib.py — `music-index [--limit N] [--force]`: walk the music library; per track: artist, title, album (tags via
    ffprobe, else folder/file names), duration, playlists it's in (vibe tags), file hash (skip unchanged). Track map: bpm,
    beat times, downbeats (bar starts), onset strength, RMS energy curve (0.5 s), sections via librosa structure segmentation
    (recurrence/novelty boundaries) labelled by energy + repetition into intro/verse/chorus/drop/outro, drop times (sharp
    energy rise after a low), vocal-presence estimate per section (so music under speech can avoid busy vocals). Resumable,
    parallel (cpu-1 workers), progress events. Index ALL 423 tracks; report wall time + failures.
M2. Pick — `music-pick --edit <edit_id> | --moment <id>`: candidates filtered by energy/vibe vs the clip (speech pace, peak
    moment, campaign/style vibe, playlist tags; Jev `choice` picks among ≤ 8 candidates with a no-match option → no music);
    segment choice so the drop/chorus downbeat lands on the clip's peak (hook payoff / loudest laugh / reveal); start offset
    in the track = the sound note offset. Never the same track twice in a row per channel; record why.
M3. Cut to the beat — musiccut.py: given the edit's keep spans + word timings + the track map + start offset, snap every cut
    boundary to the nearest beat (prefer downbeats) within ±120 ms WITHOUT cutting inside a word (word timings win; if no
    beat fits, leave the cut and record it). Visual events (punch-ins, b-roll, layout switches, caption card swaps) snap to
    beats too where the layouts/editroom code exposes them. Report % of cuts on-beat and the mean offset.
M4. Renders: the PREVIEW = post file + the track segment mixed ducked under speech (reuse music.py's mix + loudnorm) → saved
    as preview-music.mp4 next to final.mp4, never posted (mark it in the EDL + make the publish path refuse any file whose
    EDL says preview). The POST file has no library music. Sound note in the EDL + sound_plans: {artist, title, start "m:ss",
    track_id, why} and a one-line human string "Add sound: Burna Boy – Last Last, start 0:45".
M5. Proof on the sandbox: index the full library; pick + cut + preview for Malik's clips src_863fe4f081/mom_c75439d1e6 and
    src_5cbf5b5f26/mom_d6cd6a485d (edit-run in the sandbox, campaign label "malik", --rounds 1) and one podcast moment. Report
    per clip: chosen track, segment, offset, why, beats-on-cut %, preview path, sound note. Contact sheet + a waveform/beat
    plot PNG showing cuts against beats for one clip → docs/proof/music/.
M6. Tests: index on 2 synthetic tracks (click track at known bpm → bpm ±1, beats ±20 ms), section labelling sanity, pick
    respects no-repeat + no-match, beat snap never cuts a word, post file never contains music (audio-diff test vs preview),
    publish refuses preview files. Full pytest green (per-file ok). No Sources/ diff. Commit; NO push/merge/launchctl.
State plainly anything not done or not proven.
