# Tools must REALLY work — multi-speaker who_talks + real-media acceptance for every tool (Yahia 2026-10-14)
Your round-1 who_talks was only checked on frames where the RIGHT speaker talked. Not acceptable.
## 1. who_talks multi-speaker validation
- Build a labelled set from REAL footage in the library (read-only; sandbox copy): ≥150 frames across ≥6 sources/episodes covering: left speaker talking, right talking, rapid back-and-forth (<2s turns), overlap/interruptions, listener laughing/nodding (not talking), single-speaker close-ups, 3+ people if any source has them, side profiles, hand over mouth/mic occluding mouth. Label from audio+video with evidence (timestamp, transcript words, why). Keep 50% held out.
- Measure Light-ASD, mouth-motion, and combined on held-out: accuracy per category, turn-switch latency (how fast it flips after the speaker changes), flicker rate. Fix what fails (temporal smoothing, audio-energy per-side, re-detect faces within shot instead of once per shot). Target: ≥95% held-out overall, ≥90% in every category, switch latency ≤0.5s, zero flicker <1.5s. If a target is missed, say so with numbers — do not hide it.
- Re-render the stack proof on the back-and-forth moments and check panels/dimming follow the real speaker.
## 2. Every tool: real-media acceptance (not unit tests only)
speech_map, tighten, audio_polish, shots: run on ≥10 real moments across ≥4 sources; per tool report a measured metric vs ground truth you label (speech edges ±80ms, shot cuts F1, LUFS within ±1 of -14 and true-peak ≤-1.5, tighten: no clipped words — check word boundaries vs transcript, pace before/after). Find a moment where tighten SHOULD cut (long pauses/fillers with retention off) and prove it.
- Speed: who_talks currently ~2x realtime; cache per source and parallelise; report.
Proof: docs/proof/toolkit/acceptance/ (tables, failure examples with frames, before/after mp4s). Tests added for every fixed failure. Branch only, no merge/push, real library untouched.
