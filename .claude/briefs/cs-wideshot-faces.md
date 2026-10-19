# cs-wideshot-faces — 4 of 9 Solved clips died on a face-detector miss

You are in a builder worktree of ~/Projects/clip-studio (from main 3cadca8). Code: engine/clipengine (render.py, qa.py, autopilot.py, agent.py, liverender.py, layers/, pipeline2/).

## What happened (verified 2026-10-14)
Campaign run (log ~/Library/Logs/ClipStudio/campaign-solved-20261014-1402.log) attempted 9 moments; 4 came back `render_failed`. All 4 rendered to 99% then failed QA with the same reason, stored in `moments.qa`: **"no face in the opening"** (Solved rule `face_first_seconds: 5`; `qa.face_in_opening` needs a face at conf>=0.8 in the first 5 s; samples come from `feats["face_times"]` built in render.py ~l.513).
Frames from each opening (source time = moment start + 0.5/2.5/4.5 s):
- mom_c8cfd58215 (src e4EE71qghZ8.mp4 @1869.3), mom_157afd042a (gZsE5nsbuao.mp4 @920.17), mom_e8ac7c07d7 (gZsE5nsbuao.mp4 @1531.66): Solved's WIDE studio shot — two people in side profile at opposite ends of a long table, faces small. Real faces, detector missed them.
- mom_0c34984315 (1A1c-QIh31Y.mp4 @2220.36): a full-screen QUOTE CARD graphic ("Inspiration is for amateurs…", Chuck Close photo). Genuinely no host face.
Passing clips also show patchy detection: mom_ffa47f1f2a has a face at 0.0 then none until 17.3 s; mom_ef4e4c8889's first face is at 4.59 s.
Also: autopilot only logged `RuntimeError` (the type); the QA reason was lost. And clip mom_ef4e4c8889 looks boxed (small 16:9 picture on blurred fill) at 1/8/15 s but `fit_share`=0.1 because `card` layout is excluded from that metric.

## Do
1. Face detection on wide / side-profile shots: make the face samples find these faces (e.g. detect on full-res crops/tiles of the wide frame, add a profile detector, or a head/person detector — pick the simplest that works; local, free). Measure on UNSEEN data: label >=60 frames from the Solved sources above + 2 other Solved sources (wide shot / close-up / graphic insert), split half tune / half held-out; report hit rate and false positives before vs after on the held-out half only.
2. Graphic-insert openings: a clip must not open on a full-screen graphic with no person; trim the start to the first person frame (keep word boundaries) or let the finder skip it. Say which and why.
3. autopilot.cut_one AND its twin in agent.py: log the exception message (e.g. "QA failed: no face in the opening"), not just the type, in the event text and the campaign_run summary `reasons`.
4. Add an honest `boxed_share` feature (fit + card time / duration) next to `fit_share`. Do not change any gate or layout choice with it — report only.
5. Proof: in a sandbox CLIPSTUDIO_HOME (copy /tmp/cs-tune-home library.sqlite + playbook if present, symlink models + media; NEVER write ~/Library/Application Support/ClipStudio), re-render the 4 failed moments + mom_40150a1507 + mom_ef4e4c8889 with CLIP_PIPELINE=v2 CLIP_VERIFY=1 CLIP_TOOLS_EXTRA=caption_readability. Report QA before/after per moment. Make docs/proof/wideshot/ab.mp4 = synced side-by-side VIDEO of the first 6 s of each re-render vs the source opening (no still grids). View frames yourself before calling it done.
6. Full suite: `cd engine && env -u CLIP_PIPELINE ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q -p no:cacheprovider` (baseline 1255 passed / 2 skipped) + new tests for 1-4. Commit on your branch.

## Rules
- Settled, don't reintroduce: no word punch-in zooms, no pop/boop SFX, no scrim box, captions spoken-only.
- Don't change the CLIP_VERIFY safe-layout policy or the card layout look (that's Yahia's call) — report what you see.
- Don't touch main, push, post, submit, or flip post.golive / autopilot.pause.
- Done = items 1-6 with numbers, ab.mp4 watched, plain-English REPORT in docs/proof/wideshot/REPORT.md.
