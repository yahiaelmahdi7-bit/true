# Edit Room — round 4: music bed + SFX policy (Yahia delegated the call: "music just sort it yourself out")

Your branch was MERGED into main (09b0107, incl. the lead's fix 86d7a9d: layout_square = longest p95-lit run). First
`git merge main` (fast-forward/no-op expected) so you build on what shipped. Same standing rules: temp home only, never
the real library or app, never yt-dlp, never push. Write result.md round-4 section EARLY and extend it.

## Policy (decided by the lead — implement exactly)
- **SFX:** off for PB Blake (refs measured: zero whooshes/hits). Per-campaign style key `sfx: false` default.
- **Music bed:** per-campaign style key `music_bed: "off" | "montage"` (default "off"). PB Blake = "montage": a bed under
  the text-free ending montage only (refs ex5 from 29.9 s, ex7 from 15.6 s). Never under talking for PB Blake.
- **Where the music comes from, in order:**
  1. **Campaign-source music** — music-only stretches inside the SAME campaign's sources (rights = the campaign grant;
     nothing third-party is added). Detect windows >= 8 s with NO transcript words, sustained energy (not silence /
     not room tone), and musical structure (steady onset rhythm / low spectral flatness). Store in an additive
     `music_beds` table (source_id, campaign_id, t0, t1, bpm, lufs, score). Index command `edit-music-index --campaign`.
  2. **Licensed folder** — `<app support>/ClipStudio/music/` where a track is usable ONLY if `licence.json` has an entry
     for it (title, licence, url, attribution). Empty by default; never download anything.
  3. Otherwise: no bed (montage keeps its own source audio as today).
  NEVER AI-generated music (PB Blake no-AI-tools rule), never commercial/copyrighted tracks, never ElevenLabs.
- **Choosing the bed:** Jev `choice` among the top candidates (energy/tempo vs the montage), with a no-match option ->
  fallback no bed. Keep the rule in code; Jev only picks.
- **Mix:** bed fades in 0.4 s at montage start, out with the last frame; montage cuts snap to the bed's beat onsets when
  within 120 ms (refs: 1.4-1.7 cuts/s); final loudness stays -14.2 +/- 0.5 LUFS; bed never overlaps speech.
- `allow_added_audio` keeps meaning THIRD-PARTY audio (licensed folder). Campaign-source beds don't need it; licensed
  folder tracks do. Record the bed's origin + licence in the EDL and in the edit's approval card so Yahia sees it.

## Done means
- pytest green (count). New tests: no-words window detection on a fixture, licence gate (track without licence.json
  entry is never used), PB Blake style => no SFX + bed only in montage, beat-snap within tolerance, bed never over speech.
- One proof render in temp home: a PB Blake-style edit with a montage ending + campaign-source bed. Measure and report:
  LUFS, bed start vs montage start, speech overlap = 0, cuts on beat (count). Sheet + waveform PNG under
  docs/proof/editroom/r4-*. Look at them before claiming.
- result.md checklist with PASS/FAIL per line. Anything unverified said plainly.
