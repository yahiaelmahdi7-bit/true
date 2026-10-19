# cs-integrate-clipfarm — merge three finished builder branches, tests after each

You are in a builder worktree of ~/Projects/clip-studio (branched from main 3cadca8). Make ONE integration branch that contains these three branches, merged in this order:
1. `builder/cs-clipfarm-submit-20261014-150916` (per-platform clips/lanes, Content Rewards submit, spam + dedicated gates)
2. `builder/cs-clipfarm-course-20261014-152303` (finder: dead-air share + Jev share question)
3. `builder/cs-bridgeclip-rea-20261014-152904` (CLIP_BRIDGE completeness gate + edge repair, off by default)

## Do
- `git merge --no-ff <branch>` each in order. On conflicts: keep BOTH behaviours; the finder overlaps between 2 and 3 are expected (moments.py / retention.py / campaign_run.py) — combine them so each change still works and its flag/default is unchanged (CLIP_BRIDGE stays off by default).
- After EACH merge run the full suite: `cd engine && env -u CLIP_PIPELINE ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q -p no:cacheprovider` (~11 min; baseline on main 1255 passed / 2 skipped). Record pass/skip/fail counts per step. Fix failures caused by the merge; if a failure is a real bug in one branch, fix it in a separate commit and say so.
- Builder 2 never re-ran the full suite after its last fixture fix — step 2's run is the first full confirmation; report it.
- If any Swift file changed, also run `swift build` in the app folder; otherwise say none changed.

## Rules
- Do NOT touch main, do NOT push, do NOT flip post.golive / autopilot.pause, do NOT post or submit anything.
- Never use ~/Library/Application Support/ClipStudio for tests (tests use their own temp homes).
- Done = integration branch with 3 merge commits (+ any fix commits), and a report: per-merge test counts, every conflict and how you resolved it, anything you were unsure about.
