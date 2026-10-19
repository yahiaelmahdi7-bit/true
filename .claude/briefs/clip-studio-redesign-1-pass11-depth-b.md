# Pass 11 — depth captions, option B (Yahia's pick 2026-10-13)

First: `git merge main` (main = a5d3c16, includes post-tracker + real-library guard). Gates green.

Problem: pass 10's per-shot rule turns depth OFF for whole shots whenever ONE card fails the gate → all 4 samples
ended with depth off entirely. Yahia chose **B: fix the problem caption, not the shot.**
- When a card would fail depth (occluded / glyph or word visibility too low / top_min etc. in depth_record.json),
  RELOCATE or RE-SIZE that card within the type's caption home so it passes (try: nudge vertically within safe zone,
  re-break lines / fewer words per card, smaller size within readability floor). Only if no placement passes does that
  card fall back — and the fallback must look identical in position/style so the eye sees no switch (same spot rule).
- Depth stays on for the shot. Target per clip: depth on for ≥80% of caption time, visible switches ≤1 per shot.
- Keep settled rules: spoken-only, on-time, one spot, in-picture, money green, never cover faces/gameplay focus.

## Proof (real renders this time — pass 10 had none)
- Render the 4 depth samples (close_talking, hands_near_face, wider_two_person, pbblake) in a CLIPSTUDIO_HOME sandbox.
  If a render is slow, profile and fix the slowness first (pass 10's sandbox render ran >20 min — find out why);
  use a 20-s excerpt only if a full render is still impractical, and say so.
- Report per clip: % caption time with depth, switches, cards relocated/resized/fallback. Stills + contact sheets in
  docs/proof/pass11/, mp4s alongside. Read your own stills before claiming success.

## Rules
Real library read-only. Don't quit/relaunch ClipStudio (Yahia's app now runs from ~/Projects/clip-studio main),
no package.sh, never push, never merge to main. Commit on this branch. Gates: swift build, --build-tests, swift test,
engine pytest. Report plain English, verdict first, honest numbers.
