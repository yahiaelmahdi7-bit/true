# Brief: Clip Studio quality HIT LIST (overnight, Yahia asleep)

Repo ~/Projects/clip-studio. You're in a worktree branched from main @ 22d7fa9, which has every quality builder merged: styles, capcut presets, toolkit, layers + planner (CLIP_PIPELINE=v2), tools r3, ecosystem spine, Jev verify. Python: ~/Projects/clip-studio/engine/.venv/bin/python. Tests: `cd engine && env -u CLIP_PIPELINE <venv python> -m pytest -q -p no:cacheprovider` (1230 passed / 3 skipped at start; run from YOUR worktree's engine dir).
Goal: close the visible quality gaps so clips look like pro clippers made them. Each fix lands default-ON in the v2 path and works on the LIVE path. Proof means measured numbers on real Solved renders, not "it ran".

DISCIPLINE (non-negotiable):
- Lane: you work ONLY in this worktree/branch. Don't touch ~/Projects/clip-studio (main) or other builders' worktrees (cs-ab-video, cs-system run alongside you).
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge, NEVER 'ship'.
- Gates: run tests in the FOREGROUND and wait. NO background shells, NO watch modes, NO until-loops. Kill anything you started.
- Claims: 'done' means you ran the gate and pasted the passing output. Never report a state you didn't verify.
- Decisions: any new classify/route/gate/rank/verify step = a Jev call via the repo's vendored jev-kit (code owns flow, route on confidence, log it). No LLM prompt-and-parse, no keyword lists.
- If blocked: say BLOCKED + one line why. Don't invent scope.

## Measuring kit (reuse, don't rebuild)
- Refs and bar: docs/proof/studio-tune/bar.md (14 refs). Style-pack measurements live under the styles code and docs/proof/capcut-presets/clipping/measured.json.
- Sandbox render flow: scripts/toolkit_proof.py / scripts/tools3_proof.py with CLIPSTUDIO_HOME pointing at a FRESH copy of /tmp/cs-tune-home. NEVER the real home or the real library.
- Moments: Solved mom_0185f2fcd1 mom_16461a68dc mom_4c84b47f2b mom_4dc7ab17af mom_6ef3c64af7 mom_72e6616de2 mom_8080afc6d2 mom_8f399fa883 mom_eae11f677a, plus the held-out set bar.md used.
- LIVE path: memory says there were twin render paths (render_moment/_render_locked/agent.py vs autopilot.cut_one). Find the path the autopilot conductor ACTUALLY uses on main now. Every fix must take effect there; prove it by rendering through that entry point, not only through render_clip.

## The list, in order (biggest visible gap first). Before/after numbers for each.
1. PACING. Now 1.0-1.2 cuts/10s vs refs 2.04; held-out longest static shot got worse (12.6 -> 24.0 s). Target: cuts/10s within ±20% of the refs, longest static shot no worse than the refs' p90 (measure it). pacing_check and reaction_detector currently SKIP stack/card shots because zooming would crop a face. Give those shots a face-safe cut instead: alternate stack <-> full-frame single speaker (only when who_talks is confident; otherwise alternate on sentence boundaries between stack and a face-safe wide), or a gentle face-safe push-in. Never crop a face; the check that enforces that must stay green.
2. BLEEP not firing on real renders. In the studio-tune blind sheet, moment 4 shows "fuck" uncensored in BOTH A and B (find which mom that is from docs/proof/studio-tune/.key/key.json; you may read the key, Yahia already judged). Find why it doesn't fire on the live path, fix it, and prove it: a tone over the word plus masked captions, on that moment, through the live entry point.
3. CAPTIONS: too small and thin (calm style), and the stack-seam captions are faint. Measure caption height, stroke and weight vs the doac (main style) and flagrant refs, then match them. Seam captions need contrast >= 4.5. Add active-word highlight (karaoke) ONLY if the refs measurably use it; emphasis colour must match the style pack.
4. REFRAME pan p99 rose from 5.9 to 8.9 (refs 6.95). Bring it to <= the refs WITHOUT losing the dead-centre win (0.28, bar 0.31).
5. AUDIO differs between old and v2 OUTSIDE the bleep spans (never investigated). Find the cause (loudness norm? tighten? resample?). Fix it if it's a bug; if it's intended, document it.
6. TITLES are raw transcript clauses. Make title_writer produce a short hook title (pick/trim the best line; select-not-generate via Jev is fine). Use only what the engine already has: NO new paid API (monthly paid-API ceiling is $25).
7. Edit room shows a SQUARE picture on black inside 9:16, not full-bleed. If it's an engine render/preview bug, fix it. If it's in the Swift view, fix it on this branch, `swift test` green, and save before/after stills to docs/proof/hitlist/. Do NOT install or launch the app over Yahia's installed copy.
Skip: the who_talks rebuild (keep the CLIP_VERIFY safe layout), loop_end, head-fix, viral ranker.

## Done =
- One commit per item (or a BLOCKED note in the report).
- Full engine tests green (paste the tail). `swift test` green if any Swift changed.
- docs/proof/hitlist/REPORT.md: a before -> after table per item vs the refs on the Solved moments, which path you proved it on, and what's still open. Lead line: "N/7 fixed". Commit the jpg/png/json proof (mp4s gitignored).
Hard rules: never post, flip post.golive, unpause autopilot, push, or touch the real library/home. macOS has no `timeout` (use a python subprocess timeout). Kill any render after 10 min.
