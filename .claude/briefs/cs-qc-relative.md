# Clip Studio — quality check false positive (relative sharpness) + hook/caption overlap check

Repo: ~/Projects/clip-studio (you are in a worktree off main @5ad6e76; gates green: engine 1028 pass, swift 115/0).
Read first: engine/clipengine/quality.py, where qc_video is called (grep), docs/proof/kumar/result.md (how SHARP_MIN=40 was set),
/Users/y/Projects/true/.claude/briefs/clip-studio-captions-v3.md (caption rules).

## Evidence (observed 2026-10-13, real library)
A conductor tick on the joined campaign "ClipFarm x Solved w/ Mark Manson" rendered 4 clips (moments mom_9358c25556,
mom_72e6616de2, mom_4dc7ab17af, mom_f900bcaca4; files in ~/Library/Application Support/ClipStudio/media/clips/) and held ALL
four: "soft: sharpness 6-7 < 40". By eye the frames are acceptably sharp: soft-lit studio podcast, smooth skin, ~1.78x zoom
from the 16:9 → 9:16 face crop. The absolute Laplacian threshold was calibrated on stream renders, so it measures the CONTENT,
not whether our render lost quality. Result: no clip of this campaign can ever reach Review; the pipeline is stuck here.

## Fix 1 — relative sharpness
- Measure the SOURCE at the same timestamps and the same face region (map the output face box back through the crop, then
  scale to the output box size) and compare: fail when out/src falls below a ratio R (the render lost sharpness), or when the
  absolute value is near zero (truly broken frame). Keep blockiness and the upscale guard as they are.
- Calibrate R on labelled data, honestly: positives = existing good renders (kumar proof set, the 4 ClipFarm clips above),
  negatives = degraded copies of the same renders you make (box blur, downscale→upscale, heavy CRF). Split by SOURCE video into
  calibration and held-out halves; pick R on calibration only; report the confusion table on the held-out half in the lane
  report. Code the threshold, don't eyeball it.
- Re-run QC on the 4 ClipFarm clips in a SANDBOX copy of the library (never the live DB): backup with
  `sqlite3 "<live db>" ".backup <tmp>/library.sqlite"`, CLIPSTUDIO_HOME=<tmp>. Paste before/after verdicts.

## Check 2 — hook card duplicates the spoken words
In the first 3 s of mom_9358c25556 a white hook card reads "poker player before it was ever on television. You" while the yellow
word captions show "POKER PLAYER BEFORE" — the same words twice, in two places. Check this against the captions v3 rules
("spoken-only, on-time, one spot, in-picture"). If it breaks them, fix it so only one text block of the spoken words is ever on
screen (the hook must be a distinct headline or not overlap captions, per the spec). If the spec allows it, say so and leave it.
Extract a frame at t=1.0 s before/after and LOOK at it.

## Tests + gates
Unit tests for the relative measure (synthetic sharp/blurred frames, face-box mapping), a regression test that a soft-lit but
undamaged frame passes and a blurred copy fails, and a test for the hook/caption rule if you change it. No network in tests.
Gates (foreground): `cd engine && PYTHONPATH=$PWD ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q` and `swift test`
AT REPO ROOT. Before every commit: `git checkout -- docs/proof/submit/happy.png; rm -f docs/proof/submit/happy-watched-run.png`.
Report in docs/lanes/qc-relative.md: what changed, held-out confusion table, before/after verdicts, stills, verified vs NOT.

Rules: never flip post.golive; never write the live DB or touch ~/Projects/clip-studio.live or the main checkout (only run
its venv python); no posting.

```
DISCIPLINE (non-negotiable):
- Commits: atomic, message says what+why. NEVER push, NEVER merge. The user pushes, not you.
- Gates: run in the FOREGROUND and wait. NO background shells, NO watch modes, NO until-loops.
- Claims: 'done' means you ran the gate and pasted the passing output. Code written ≠ working; a threshold is validated
  only on held-out data.
- If blocked: say BLOCKED + one line why. Do not invent extra scope.
```
