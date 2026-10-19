# Clip Studio: playbook Jev gates #1-2 — hook-text faith gate + one_problem/short_cut short variants

First read and follow ~/.claude/skills/dispatch-brief/SKILL.md. Repo: ~/Projects/clip-studio (worktree off main at or after
9461932 "Merge caption flow r3.1"). No push, no merge, never relaunch the ClipStudio app, never write to the real library
(`?mode=ro` only; tests use fixtures / a tmp CLIPSTUDIO_HOME copy). Never post or queue anything for real. Write result.md
EARLY and extend it as you go. Worktrees have no venv: run tests as
`PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q` from the worktree's engine/.

Spec + exact Jev statement text + smoke-test numbers: ~/Projects/clip-studio-refs/research/clipping-playbook-jev.md
(sections "New Jev statements" #4, #5, #6 and "Build order" 1-2). Use those statements VERBATIM. Build ONLY build-order
items 1 and 2 — cold open, script shape, quotable end card, outcome logging are later builds.

## Lane discipline (other builders are editing editroom.py, render.py, overlays.py, campaigns/onboarding right now)
Put the logic in a NEW module `engine/clipengine/playbook.py`. Touch existing files only with small, additive call sites
(a few lines each). Use the existing Jev helper `clipengine/jev.py` (`noul`, `ask`, `route`) — no new HTTP client.

## 1. `faith` gate on on-screen hook text (do this first; smallest, prevents the worst failure)
- Find EVERY place on-screen hook / overlay / cover text is produced from a moment (grep says: covers.py, overlays.py,
  editroom.py, moments.py, render.py, series.py, seriesscale.py, common.py — confirm each). Route all of them through ONE
  function `playbook.faith_gate(clip_text, candidates) -> [{text, faith, verdict: keep|review|drop}]`.
- Statement (verbatim): "Is every claim in the on-screen hook text `hook_text_candidates.hN` directly supported by what is
  said in `clip_text`, with no added facts, numbers or promises?" — state = {clip_text, hook_text_candidates: {h1..hN}}, all
  candidates in ONE Jev call.
- Rule in code: >= keep floor → keep; < drop floor → drop; between → `review` (surfaces in the approval queue with the
  faith score; never auto-approved). Survivors ranked by the existing hookscore `stop` noul.
- Fail-closed: Jev unreachable/timeout → every candidate is `review`, never `keep`. A render whose only hook text is
  `drop` falls back to no hook text (or the speaker's verbatim first line), never the dropped text. Log every verdict in
  the run record.
- Floors: placeholders 0.8 / 0.5 from the doc until calibrated. CALIBRATE: build a labelled set of >= 40 (hook, clip_text)
  pairs from real PB Blake moments read `?mode=ro` — roughly half faithful paraphrases/verbatim quotes, half with an added
  number, claim, promise or exaggeration (write them by hand from the transcript, label each). Split it: choose floors on
  one half, REPORT precision/recall of `keep` and of `drop` on the held-out half. Save the set as a fixture (labels + text
  only, no media). If held-out precision of `keep` < 0.9, raise the keep floor and say so.

## 2. `one_problem` + `short_cut` → short-variant proposals in moments.py
- Statements (verbatim): `one_problem` "Is `clip_text` about exactly one specific problem, rather than several problems or a
  general topic?" and `short_cut` "Could `clip_text` be cut to a 15-25 second excerpt of consecutive sentences that still
  delivers a complete point by its end?"
- Rule: short_cut yes → propose consecutive-sentence windows of 15-25 s (sentence boundaries from word timings, never
  mid-word), score each with the existing `payoff` + `one_problem`; best window above floor becomes a SHORT VARIANT: a
  second edit linked to the parent moment (`variant_of`, `variant_kind: "short"`), same approval gate, same 3/day cap
  (a variant counts toward the cap; parent + variant of one moment must not both post the same day unless a human
  approves both).
- Speaker words stay verbatim; a variant is a cut, never a re-script.
- Per-campaign switch `playbook.short_variants` (config key `playbook:<campaign_id>` JSON), DEFAULT OFF, onboarding/critic
  cannot enable it.
- CLI: `playbook-check --moment <id>` prints faith verdicts for current hook text + one_problem/short_cut + proposed
  windows (read-only).

## Proof (local only, never posted)
- PB Blake moment mom_bab1b6992f: reproduce the doc's smoke test shape (one_problem low, short_cut high, the ~18 s s1-s6
  window proposed, h2 "Prop firms made me a millionaire" dropped). Render the short variant in a tmp library copy with
  PB Blake's real edit_style (frame=wide) → docs/proof/playbook/ + 3 stills (first frame, mid, last frame) pulled with
  ffmpeg select. ffmpeg has NO drawtext — proof labels via Pillow.
- Calibration table (held-out precision/recall per floor) in result.md.

## Done =
- Whole engine pytest green; new tests: every hook-text producer goes through faith_gate (a test that fails if a new
  producer bypasses it), fail-closed on Jev error, drop never reaches the render, variant window boundaries on sentence
  ends, variant respects approval gate + cap, switch default off and not enable-able by critic/onboarding.
- You LOOKED at the short variant stills: starts and ends on sentence boundaries, no orphan word, captions intact.
