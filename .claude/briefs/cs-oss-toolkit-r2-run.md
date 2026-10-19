NOTE: runs IN PARALLEL with cs-oss-toolkit round 1 (branch builder/cs-oss-toolkit-20261014-015036, building engine/clipengine/tools/ registry + speech_map/tighten/who_talks/audio_polish/shots). Do NOT build those 5. Put layer system in engine/clipengine/layers/ and new tools in engine/clipengine/tools2/ with the same registry shape (name, description, params schema, run(...)->result+features) so they merge cleanly later. Start with section 0 (layers).

# Toolkit round 2 (Yahia 2026-10-14) — resume after round 1
1. AI editor is BACKEND ONLY. It runs automatically inside autopilot/render; no user-facing AI editor UI. Manual tool access only appears if Yahia opens a clip to edit himself. Do not add UI.
2. REA discipline for solidity: for each tool, before adopting, reverse-engineer how the reference does it (read the OSS source; for closed apps like CapCut desktop / Descript / OpusClip, inspect locally installed bundles and public behaviour only, no auth bypass/DRM) and record evidence (file:line or measured output) in docs/proof/toolkit/REA.md: algorithm, params, edge cases, failure modes. Our rebuild must match or beat it on the 3 Solved moments, measured.
3. MORE TOOLS (registry, same interface), priority order:
   - smooth_reframe: face-follow crop with critical-damped smoothing, no jitter, lead room, head never cut (fix bottom-panel head crop)
   - jump_zoom: alternate 100%/112% scale across tightened jump cuts so cuts feel intentional (pro clipper trick)
   - emphasis: pick key words (LLM/score) -> caption highlight + optional punch + SFX hit
   - hook_finder: best 1-2s opening line within the moment; reorder/cold-open if it lands
   - text_guard: burned-in text/logo detection -> keep whole or exclude (crop safety)
   - grade: light consistent colour/contrast + sharpen for soft upscales
   - bleep/profanity filter (campaign rule switch)
   - broll_hook: optional still/zoom-on-object insert slot (stub + registry entry if heavy)
   - qc_score: per-clip quality score from all tool features (feeds the future quality grader)
4. Planner: a backend 'editor' that reads the registry descriptions + clip features and chooses tools/params per clip (deterministic rules first, Jev/LLM for judgment calls), logs its choices in clip features.
Proof + rules as round 1.

## 0. LAYER SYSTEM — FIRST, foundation for everything above (Yahia 2026-10-14)
Every clip becomes a stack of named layers instead of one flat ffmpeg graph:
- Layer model (engine/clipengine/layers/): Clip = ordered layers, each {id, kind (video|matte|text|image|sfx-marker|adjustment), source, z, t0/t1, transform keyframes (pos/scale/rot/opacity), mask ref, effects list, blend mode, locked/visible}. Serialised as JSON per clip (stored in clip features / sidecar), so AI planner and a future manual editor edit the SAME document; renderer compiles layers -> ffmpeg (deterministic, cached per layer).
- Element separation ("mark out each element as a layer"): person/speaker mattes (existing personmask + SAM 2 [Apache-2.0] for per-person/object masks with click-free prompts from face boxes), background plate, burned-in source text/logo regions (text_guard), mic/desk/hands as optional object layers. Each gets its own layer so tools can modify/clean one element (e.g. blur/replace background, remove burned-in source caption, grade person only, captions BEHIND person but in FRONT of background = true depth).
- Migrate existing pieces onto it: crop/stack panels, depth captions (behind/front), hook card, captions, logo overlay, zooms -> all layers. Output must be pixel-equivalent to today's render for an unchanged clip (regression test on 3 moments).
- Cleanup ops on layers: background blur/replace, remove/inpaint burned-in source text (ProPainter/LaMa only if license OK; else blur/cover), per-layer grade, edge feather/refine on mattes.
- REA: study how CapCut/After Effects/DaVinci-style layer stacks and OSS (MLT framework, Olive editor — check licences, ideas only if GPL) model layers; evidence in REA.md.
Tools in sections 1-4 must read/write layers, not raw ffmpeg.

## REA tooling (enhanced 2026-10-14)
Read ~/.claude/skills/rea-mode/SKILL.md first and follow it. Engines installed: radare2 (/opt/homebrew/bin/r2), Ghidra (ghidraRun; GhidraMCP). CapCut desktop is installed (/Applications) — inspect its app bundle, frameworks, resource/effect packs and JS/JSON configs for how layers, mattes, caption animations, smart reframe and auto-cut are implemented; record evidence in REA.md. Scope: understanding + rebuilding our own implementation. No auth bypass, no DRM/licence circumvention, no copying their code/assets into ours.
