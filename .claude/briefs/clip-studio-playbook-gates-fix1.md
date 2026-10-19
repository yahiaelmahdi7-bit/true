# Playbook gates — fix round 1 (review of your result; keep everything you built)

Same rules as the original brief (no push/merge, real library `?mode=ro` only, tmp copy for renders, never post/queue).

## 1. Close the render-time bypass (blocking — this is the failure the gate exists for)
Your own risk list: legacy moments with stored hooks are not re-gated. render.py burns `m["hook"]` (render_clip call ~l.454,
hook card ~l.294) and series `hook_text` (~l.398 via overlays.hook_line) with no gate check, so every hook already in the real
library reaches the screen unchecked.
- At render time, any hook / series hook_text about to be burned must have a gate record with verdict `keep` FOR THAT EXACT TEXT
  (hash the text). No record → run `gate_one` there (fail-closed). Not `keep` → do NOT burn it: render without hook text (or the
  speaker's verbatim first line if that passes), set the clip's review flag with reason `faith:<verdict>`, log it in the run record.
- Persist the record so a re-render does not re-call Jev.
- Strengthen the no-bypass test: it must fail if ANY call to `overlays.hook_line` / any hook-card construction in render.py,
  editroom.py, covers.py or anywhere else is reachable without a gate record for that text. Cover covers.py (thumbnail/cover text)
  explicitly — say in result.md whether covers burn hook text and how it is gated.

## 2. Deterministic window pick
Equal-scoring windows (within 0.02) must not be decided by Jev noise: tie-break by closeness to 16.5 s, then earlier start.
Same input → same variant on every run (test it with a stubbed Jev returning tied scores).

## 3. Calibrate on SUBTLE fakes
Your unfaithful half was blatant (all <= 0.09), so `keep` precision on realistic embellishment is unknown. Add >= 24 subtle
unfaithful pairs written from real PB Blake transcripts (`?mode=ro`): a number changed or inflated ($2,000 → $20,000), a hedge
removed ("might" → "will"), an added time frame or promise ("in 30 days"), a superlative/universal added ("every", "always",
"best"), wrong subject ("I" → "you"/"everyone"), a cause the speaker did not state. Keep the 56 existing pairs. Re-split
held-out, report precision/recall of `keep` and `drop` overall AND on the subtle subset alone. If subtle-subset `keep` precision
< 0.9, raise the keep floor until it is >= 0.9 and report the recall you lose. Update calibration.md and the fixture.

## 4. Variant opens with no hook on frame 0
still-first.png (t=0) shows no hook text, yet the variant's hook is the speaker's verbatim first line. Check the EDL/run record:
is the hook card late, dropped by a gate, or deliberately absent? If dropped/late by mistake, fix it; either way say which in
result.md and pull a still at t=0.3 s.

## Done =
Whole suite green; new tests for 1-2; calibration.md updated with the subtle-subset table; re-rendered proof + stills; result.md
"fix1" section with what changed.
