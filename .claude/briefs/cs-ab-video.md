# Brief: Clip Studio side-by-side A/B VIDEOS (before vs after the quality round)

Repo: ~/Projects/clip-studio (you are in a worktree branched from main @ 22d7fa9). Python venv: ~/Projects/clip-studio/engine/.venv/bin/python.
Goal: Yahia judges the quality round by WATCHING it. Output = synced side-by-side MP4s of clips that actually differ, blind (which side is new is hidden). Speed matters: target done in ~1h. No new features, no engine refactors.

## A and B
- OLD = main BEFORE the quality round: commit aa0ec9d. `git worktree add --detach <scratch>/old aa0ec9d`; render from `<scratch>/old/engine` (run python from that engine dir so it imports that tree's code; verify with `python -c "import clipengine,sys;print(clipengine.__file__)"`). Remove that worktree at the end.
- NEW = this worktree (main 22d7fa9) with the full new stack ON: CLIP_PIPELINE=v2, CLIP_VERIFY=1, and every opt-in tool that improves the render (grep `CLIP_` in engine/clipengine and the studio-tune README docs/proof/studio-tune/README.md to see which flags gate bleep / cold open / caption_readability / reaction_detector / pacing_check / tighten / reframe). Do NOT set CLIP_VIRAL_RANK or CLIP_VARIANT=B. Write the exact env used for each side into the report.
- Same moments, same source, same style pack on both sides. Moments (Solved episode, used in the studio-tune proof): mom_0185f2fcd1 mom_16461a68dc mom_4c84b47f2b mom_4dc7ab17af mom_6ef3c64af7 mom_72e6616de2 mom_8080afc6d2 mom_8f399fa883 mom_eae11f677a.
- How to render a single moment in a sandbox: reuse the studio-tune flow (scripts/toolkit_proof.py, scripts/tools3_proof.py, sandbox CLIPSTUDIO_HOME=/tmp/cs-tune-home, which already exists). Make a FRESH sandbox copy per side (e.g. <scratch>/home-old, <scratch>/home-new) so neither side's cache leaks into the other. The real library must stay untouched: never point CLIPSTUDIO_HOME at the real home.
- Parallel: render old and new concurrently if the machine copes (use CLIP_WORKERS if it helps). Don't let any single render hang: kill it after 10 min and report it.

## Measure first, then drop identical pairs
Per moment: duration A/B, mean abs pixel diff on frames sampled every 0.5 s (aligned from t=0, the shorter padded with its last frame), % of samples with diff > a small threshold, and whether the audio differs (e.g. compare PCM RMS per 0.5 s window). If video diff is ~0 AND audio is identical, mark the pair IDENTICAL and DROP it from the videos (still list it in the report). Earlier still-image A/Bs were useless because 4 of 6 pairs looked identical, so this filter is mandatory.

## Label each pair by WHAT changed (without saying which side)
Derive a short plain-English label per pair from the measured diffs plus the layers/features JSON the v2 render writes (e.g. "cold open added", "swears bleeped", "captions restyled", "tighter cuts", "smoother reframe", "punch-in zooms"). Plain words only: no flag names, IDs or numbers in the on-screen label (Yahia's rule: no engine text in UI). Do not guess. If you can't tell what changed, say "framing differs".

## The videos
- Per kept pair: hstack, each side scaled to 720x1280 (output 1440x1280, plus a top band about 90 px for the label), L/R randomised with a seeded RNG, small "A" and "B" tags over each side. Sync both sides from t=0; pad the shorter with its last frame.
- Audio: if the audio is identical, use L. If it differs, render the pair TWICE in a row inside the same file: first pass with A's audio (band reads "listening: A"), then pass two with B's audio ("listening: B"). Both passes must be visibly marked.
- Reel: concat all kept pairs into one `ab_reel.mp4` with a 1.5 s title card before each ("Pair 3 — swears bleeped"). H.264 yuv420p, AAC, faststart.
- Key: `.key/key.json` (which side is OLD/NEW per pair) in a dotfolder. Never print it in the report or log.

## Output
- Folder: ~/Projects/clip-studio/docs/proof/ab-video/ (mp4s gitignored via a .gitignore there; commit only report + label json + .gitignore on YOUR branch, never main).
- `REPORT.md`: table per moment (kept/dropped, durations, video diff %, audio differs y/n, label), env used for each side, the render commands, failures. Lead with one line: "N of 9 pairs differ; reel = ab_reel.mp4 (Xm Ys)".
- Before finishing, do the done check yourself: ffprobe every output (streams, duration > 0), and pull 3 frames from the reel to confirm labels render and both sides show different content.

## Hard rules
Never post, flip post.golive, unpause autopilot, push, install/restyle any UI, or touch the real library or real CLIPSTUDIO_HOME. Don't edit engine code. If a render crashes on one side, report it and move on (don't fix engine bugs in this brief). zsh/macOS: there's no `timeout` command (use a python subprocess timeout); don't `echo =====`.
