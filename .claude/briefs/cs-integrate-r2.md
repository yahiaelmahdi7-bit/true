# cs-integrate-r2 — merge four finished builder branches into one branch, tests after each
You are in a builder worktree of ~/Projects/clip-studio (from main 2ed2b39). Merge with `git merge --no-ff`, in this order:
1. builder/cs-wideshot-faces-20261014-161925 (wide/profile face detection, graphic-opening trim, QA reason logging, boxed_share)
2. builder/cs-solved-golive-polish-20261014-163738 (Solved logo + end line brand.py, hook+CTA post text per platform, NY-tz slots, caffeinate agent)
3. builder/cs-storage-keeper-20261014-170707 (clip storage plan/apply, floor gating, temp root, disk-keeper)
4. builder/cs-openchatcut-editor-20261014-152310 (mcp_tools.py + CLIP_EDITOR flag, OFF by default)
Conflicts: keep BOTH behaviours (render.py / autopilot.py / agent.py / slot.py overlap likely; 1 and 3 both touch temp/render paths). Flags/defaults unchanged (CLIP_EDITOR off, CLIP_BRIDGE off).
After EACH merge run: `cd engine && env -u CLIP_PIPELINE ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q -p no:cacheprovider` (baseline 1296 passed / 3 skipped). Known flake: test_cut_approved_only_when_all_pass "database is locked" — if it fails, re-run that file alone and report; if it fails in the full suite twice, find and fix the lock cause.
Swift changed? then also `swift build`.
Rules: don't touch main, push, post, submit, flip post.golive/autopilot.pause, install agents, or apply storage on real data. Done = 4 merge commits (+ fix commits) and a report: per-merge test counts, each conflict + resolution, anything unsure.
