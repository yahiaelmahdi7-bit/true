# Clip Studio ecosystem retrofit — rebuild the clip pipeline around tools + layers + planner
Runs AFTER the 4 builders merge (styles, clipping presets, toolkit r1 tools/, layers+tools2 r2). Yahia 2026-10-14: "current editing and clip creation pipeline sucks — retrofit into an ecosystem using our tools".

## Target pipeline (one path for autopilot AND edit room; kill the twin paths render_moment/_render_locked/agent.py vs autopilot.cut_one — see memory verify-builder-on-live-path)
1. Ingest -> transcript (word timings; parakeet-mlx/whisperX alignment if better, measured) -> speech_map, shots, who_talks, text_guard computed ONCE per source and cached as source analysis.
2. Moment finder -> candidates; hook_finder + completeness check (one full idea, payoff, no mid-thought end, 15-45s) -> rank.
3. Planner (backend AI editor) builds a LAYER DOCUMENT per clip: chooses style (rotation), tools + params from the registry, logs every choice + reason.
4. Tools edit the layer doc: tighten -> smooth_reframe/stack/card -> jump_zoom -> captions preset + emphasis -> depth layering -> grade -> audio_polish -> bleep(campaign) -> logo/text safety.
5. Renderer compiles layer doc -> mp4 (cached per layer, re-render only changed layers).
6. QUALITY GATE: qc_score + checks (face never cut, captions readable contrast, no sliced text, pace, loudness, hook in first 2s). Below bar -> planner retries with different params (max N) -> else discard. Only passing clips enter the queue. Volume = passing clips only.
7. Learn loop: Yahia keep/reject labels + post analytics feed the grader weights and style rotation weights; nothing auto-tunes without held-out validation.
Manual edit (only when Yahia opens a clip): same layer doc + same tools.

## Delivery
- Migrate in slices behind a flag (CLIP_PIPELINE=v2), v1 stays until v2 beats it on blind comparison.
- Proof: same 9 Solved moments v1 vs v2, blind A/B sheets + mp4s; gate pass rate; time per clip.
- Full engine + swift tests green. No UI changes without stills OK. No golive/autopilot unpause. Branch only.

## END-TO-END ACCEPTANCE (Yahia 2026-10-14: "source through all this to a final high quality product")
Final integration run must prove: one NEW Solved episode URL -> ingest -> analysis -> moments -> planner+tools+layers -> render -> quality gate -> post-ready queue (final caption text with campaign tags) with ZERO hand edits. Report: clips produced, gate pass rate, rejects + reasons, time per clip, blind A/B vs v1. Every stage logs into one per-clip trace Yahia's crew can read.
