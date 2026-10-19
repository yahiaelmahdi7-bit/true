# CapCut / TikTok preset school — reverse-engineer the edit grammar (Clip Studio)

Goal: Clip Studio's renderer lacks pro "finish + pace" (caption pop animations, punch-in zooms, shakes, transitions, cut timing). Learn these PARAMETERS from the most-used CapCut/TikTok presets and rebuild them as our own Clip Studio preset library. Yahia authorised installing CapCut and doing it all.

## Steps
1. Try `brew install --cask capcut` (Yahia authorised). If it needs sign-in to fetch templates, do NOT log in — fall back to step 2 and note it.
2. Capture online too: public capcut.com template/effects pages and TikTok template listings (playwright/headless). Rank by popularity (uses/likes shown). Save raw captures read-only under ~/Projects/clip-studio-refs/capcut/raw/ (immutable, outside git). Respect rate limits; no auth bypass, no DRM circumvention.
3. Reverse-engineer (REA discipline: evidence for every claim): for local CapCut, inspect its cache/resource dirs (~/Library/..., ~/Movies/CapCut) — JSON specs for text animations, keyframes, easing curves, durations. For online-only, measure from preview videos (framescan per-frame: text scale/opacity over time, zoom factor curves, cut intervals).
4. Scope (priority order): caption/text presets (word pop, highlight, karaoke, bounce) → punch-in/zoom/shake effects → transitions → cut-timing rules. Skip music-beat templates.
5. Rebuild as OUR presets in engine (new module e.g. clipengine/presets/ + JSON library), pluggable into edit_style packs (doac/flagrant packs at ~/Projects/clip-studio-refs/style-packs). Own fonts/sounds only — NEVER ship CapCut fonts, stickers, SFX or template files in renders.
6. Proof: docs/proof/capcut-presets/ — for top ~8 presets: side-by-side frames (reference preview vs our rebuild) on a Solved moment (mom_8f399fa883), plus a README table: preset, source rank, measured params, our param match. Tests for the preset module.

## Rules
Builder branch only, no merge/push. Don't touch the real library DB or installed app; render in a sandbox copy. Don't flip post.golive or unpause autopilot. Keep the "Solved." logo whole in crops.
