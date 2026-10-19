# Brief: Clip Studio SYSTEM WORKING end-to-end + one-command campaign run (overnight, Yahia asleep)

Repo ~/Projects/clip-studio. You're in a worktree branched from main @ 22d7fa9 (all quality builders merged, incl. the ecosystem spine: post-ready queue + quality gate). Python: ~/Projects/clip-studio/engine/.venv/bin/python. Tests: `cd engine && env -u CLIP_PIPELINE <venv python> -m pytest -q -p no:cacheprovider` (1230 passed / 3 skipped at start). Spec: /Users/y/Projects/true/.claude/briefs/cs-ecosystem-retrofit.md (read it first; its "Final integration run" is your acceptance).
Yahia, before bed: "get the system working then run the campaign so we post later". Clips get QUEUED post-ready tonight; posting happens later, by him. A sibling builder (cs-hitlist) is fixing render quality in parallel, so you own the PLUMBING, not the look.

DISCIPLINE (non-negotiable):
- Lane: you work ONLY in this worktree/branch. Don't touch ~/Projects/clip-studio (main) or other builders' worktrees. Stay out of render look (captions/pacing/reframe/bleep/titles = cs-hitlist's lane) unless a crash forces a minimal fix; name it in the report if so.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge, NEVER 'ship'.
- Gates: tests in the FOREGROUND. NO background shells, NO watch modes, NO until-loops. Kill anything you started.
- Claims: 'done' means you ran it and pasted the output. Never report a state you didn't verify.
- Decisions: any new classify/route/gate/rank/verify step = a Jev call via the vendored jev-kit, route on confidence, log it. No LLM prompt-and-parse, no keyword lists.
- If blocked: say BLOCKED + one line why.

## Part 1: prove the chain in a SANDBOX (CLIPSTUDIO_HOME = a fresh copy of the real home's campaign config + library index; never write to the real one in Part 1)
One NEW official Solved episode (from the Solved campaign's source allowlist; one NOT already in the library) -> ingest -> analysis -> moments -> planner + tools + layers (CLIP_PIPELINE=v2, CLIP_VERIFY=1) -> render -> quality gate -> post-ready queue, with ZERO hand edits. Each queued item carries its final caption text with the campaign's required tags (Solved: @solvedpodcast + Mark: IG @markmanson, YT @iammarkmanson, per platform). Campaign rules (memory): official Solved episodes only, Mark's face in the first 5 s, no ad reads/sponsor segments, no mid-thought cuts. Check the rules gate enforces them.
Drive it through the SAME conductor entry point the autopilot uses (find it; there used to be twin paths: render_moment/_render_locked/agent.py vs autopilot.cut_one). Don't write a parallel path. If it breaks, fix the plumbing on this branch, one commit per fix, with a test.
Every stage must log into the one per-clip trace (events + campaign_id), so it's readable afterwards.

## Part 2: one command to run the campaign, cut-only
Ship `scripts/run_campaign.py` (or wire an existing CLI if one already does this):
`--campaign <id|name> --target-clips N [--episodes K] [--home PATH] --dry-run`
It sources new allowlisted episodes, runs the conductor's cut path, and stops when N clips have PASSED the gate or the sources run out. It NEVER posts, NEVER submits, NEVER flips post.golive, NEVER unpauses autopilot. Assert all four in code: refuse to run if any post path would be reached. It's idempotent: re-runs skip episodes and moments already done. It prints a summary: clips passed / rejected (with reasons) / time per clip / paid-API calls made (monthly paid-API ceiling is $25; estimate the cost per clip). Test it in the sandbox with N=3.

## Done =
- Part 1 chain proven in the sandbox with the real output: clips in the post-ready queue, gate pass rate, rejects + reasons, time per clip.
- run_campaign.py --dry-run and N=3 sandbox runs pasted.
- Full engine tests green (tail pasted).
- docs/proof/system/REPORT.md with all of that, plus the EXACT command the orchestrator should run tonight on the real home for Solved (target 10 passing clips), and anything that needs Yahia (e.g. accounts not created yet: the Solved IG/YT may not exist; queueing must still work without them).
Hard rules: never post, submit, flip post.golive, unpause autopilot, push, or write to the real library/home in this brief (the orchestrator does the real run after merging). macOS has no `timeout` (use a python subprocess timeout). Kill any render after 10 min.
