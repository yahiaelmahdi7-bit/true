# Brief: study the Clip Farm course with VISION, not just transcripts

Yahia: "actually use AI vision and watch them rather than just transcripts so you can really see what's going on, on all of them."

## Inputs (already downloaded, do not re-fetch)
~/Projects/clip-studio-research/clipfarm-course/
- lesson-01-intro-to-whop-clipping.mp4 (3:40), lesson-02-what-is-clipping.mp4 (3:54), lesson-03-find-viral-clips.mp4 (9:54), lesson-04-how-to-edit.mp4 (16:29), lesson-05-proxy-setup.mp4 (4:17). 1080p screen recordings + facecam.
- clipfarm-how-to-submit-clips.txt, clipfarm-global-campaign-rules.txt (read both first).

## Do
1. Transcribe each lesson with the clip engine's own whisper (find it in ~/Projects/clip-studio/engine/clipengine/ingest.py; venv ~/Projects/clip-studio/engine/.venv). Keep word timestamps.
2. Extract frames: scene changes (ffmpeg select='gt(scene,0.08)') PLUS one every 4 s, 1280 px wide, into frames/<lesson>/. Dedupe near-identical frames.
3. WATCH: Read (view) the frames in order alongside the transcript. Lesson 04 (editing) gets the most care: view enough frames to see every tool, panel, setting, effect, caption style, timeline action and on-screen example. Zoom (ffmpeg crop) on UI text you can't read.
4. Write ~/Projects/clip-studio-research/clipfarm-course/NOTES.md:
   - Per lesson: what is SHOWN (apps, sites, settings, values, clicks, example clips) vs what is SAID, with timestamps; quote on-screen numbers exactly.
   - "Rules that get clips rejected" checklist merged from the lessons + the two .txt files.
   - Editing recipe from lesson 04 as concrete parameters (caption font/size/position/colour, hook text, zooms, cuts, music, length, aspect, export settings).
   - Viral-clip finding method from lesson 03 as steps.
   - Lesson 05 (proxy / USA audience): describe exactly what it teaches and any platform-ToS risk. Describe only; do not set anything up.
5. Gap list GAPS.md: each course rule/technique vs what Clip Studio does today (read code in ~/Projects/clip-studio/engine/clipengine read-only: render.py, captions, finder/moments.py, campaign_run.py, publish.py, slot.py, submit.py). For each: matches / differs (how) / missing, and a recommended change. Don't change engine code.
6. Pick 6-10 frames that best show the editing style; copy to clipfarm-course/key-frames/ and list them in NOTES.md.

## Phase 2 (REVISED 2026-10-14: OpenChatCut becomes the editor — Yahia's decision)
You are in a builder worktree of ~/Projects/clip-studio. If frames/ or transcripts already exist in the research dir from an earlier run, reuse them.
7. EDITING recipe (lesson 04 etc.) does NOT go into engine render.py any more. Write it as ~/Projects/clip-studio-research/clipfarm-course/EDIT-SPEC.md: an instruction set for an AI editor (OpenChatCut) — exact cut rules, hook, caption look/position/timing, framing, pacing targets, what to never do — plus the list of tools the editor needs from us (face track, reframe, who-talks, captions, bleep, hook finder...). Another builder (cs-openchatcut-editor) turns it into OpenChatCut's teaching prompt. Respect settled rules: NO word punch-in zooms, NO pop/boop SFX, captions spoken-only and on time, no music on Solved, HD masters; list any course advice that contradicts them for Yahia instead of including it.
8. FINDING method (lesson 03) DOES go into the engine: implement the gaps in moment finding/scoring (engine/clipengine finder/moments.py/campaign_run.py), with tests. Don't touch render.py, slot.py, submit.py, publish.py.
9. Proof for 8: run the finder before/after on 2 real sources in a sandbox CLIPSTUDIO_HOME (copy /tmp/cs-tune-home library.sqlite + playbook, symlink models + media; never ~/Library/Application Support/ClipStudio); FINDER-REPORT.md: which moments each picks and why, in plain words.
10. Full test suite passes (`cd engine && env -u CLIP_PIPELINE .venv/bin/python -m pytest -q -p no:cacheprovider`, baseline 1255 passed / 2 skipped). Commit on your branch; don't merge or push.

## Rules
- Phase 1 is read-only on code; phase 2 edits code on your branch only.
- Don't post, submit, message, or log into anything.
- Plain English in NOTES.md; one name per thing.
- Done = NOTES.md + GAPS.md + EDIT-SPEC.md + key-frames, every lesson section cites frame files you actually viewed, finder gaps implemented with tests + FINDER-REPORT.md.
