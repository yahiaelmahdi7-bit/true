# Expert editing toolkit — adopt open-source tools into Clip Studio (AI-callable + manual)
Yahia: we want the tools pro editors have, usable by our AI editor AND manually in the studio, rebuilt into our system. Shortlist + licenses: /Users/y/Projects/true/.claude/briefs/cs-oss-adopt-notes.md (read first).

## Build (engine/clipengine/tools/, one module per tool, each with a uniform interface: run(clip/moment, params) -> result + features record; register in a TOOL REGISTRY with name, plain-English description, params schema, so the AI editor (agent/autopilot) can call them and the app can expose them as manual buttons later)
Priority order:
1. speech_map — silero-vad (MIT) speech/silence map; 2. tighten — silence + filler ("um/uh/like/you know" from word timings) removal producing a cut list, auto-editor ideas (Unlicense), configurable aggressiveness, never cut mid-word, keep breaths natural; 3. who_talks — mediapipe faces + Light-ASD (MIT; test on 3 Solved moments, fall back to mouth-motion if bad) [+ pyannote only if weights obtainable without Yahia login — else skip and note]; feed stack.py / crop aim; 4. audio_polish — loudness EBU R128 -14 LUFS (ffmpeg loudnorm two-pass; ffmpeg-normalize only if LICENSE ok) + DeepFilterNet denoise if license files ok; 5. shots — PySceneDetect (BSD) as alt shot detector.
GPL/AGPL/unlicensed (lossless-cut, ultralytics, whisper-timestamped, Wav2Lip): study ideas only, never import or bundle.
Install deps into engine .venv; Apple Silicon must work; pin versions.

## Wire
- autopilot/render path: tighten + audio_polish ON for podcast type behind a config flag (default on in sandbox, report before/after); who_talks feeds stack decisions.
- Don't change Swift UI (manual buttons later need Yahia's OK on stills).

## Proof (docs/proof/toolkit/)
Re-render mom_8f399fa883, mom_4dc7ab17af, mom_0185f2fcd1 in a SANDBOX library copy: before vs after duration, cuts removed, LUFS before/after, who_talks accuracy vs manual check on sampled frames, contact sheets + mp4s. Tests per tool. Full engine suite green.
Rules: branch only, no merge/push, real library DB + installed app untouched, no post.golive/autopilot changes. Mute playback in tests.
