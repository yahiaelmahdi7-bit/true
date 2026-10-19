# Edit Room — round 3 (review fixes from the lead, 2026-10-12)

Same worktree, same branch. All standing rules from round 1/2 briefs still apply: temp home only (never the real
library, never the ClipStudio app, never yt-dlp), never push, keep the approval gate + daily cap untouched.
Write result.md EARLY (a stub with the checklist below) and extend it as you go.

The lead re-ran pytest (358 passed) and reviewed the code + proof sheets. Fix these, in order:

## 1. Punch-ins / push-in must be OFF for PB Blake (hard fail today)
`editroom.py:190` hard-codes `push_in=True, punch_in=True`; nothing turns them off per campaign. BREAKDOWN.md rule 7
(~/Projects/clip-studio-refs/pb-blake/BREAKDOWN.md line 267): "Keep the talking head locked off. No punch-ins, zooms or
whip effects on the talking shot."
- Add a per-campaign edit style (cfg key like `edit_style:<campaign_id>` JSON, or a STYLE file per campaign — pick one,
  document it) with `punch_in`, `push_in` (and `allow_added_audio` can move there too).
- **Default for any campaign without a style: punch_in=False, push_in=False** (copy the refs; research moves are opt-in
  per campaign, e.g. Solved).
- Add `punch_in` to the critic patch whitelist only if the campaign style allows it — the critic must never be able to
  switch punch-ins/push-in ON for a campaign whose style says off.
- Tests: a PB Blake-style campaign EDL has `punches == []` and a constant zoom expr; the critic patch cannot enable them.

## 2. Critic calibration: refs are ground truth — fix the rubric, then calibrate the thresholds
Approved refs score 4-5. By definition that means the rubric is penalising the refs' own grammar.
- Dump per-criterion scores for the 7 refs. Any criterion where approved refs lose points is mis-specified vs the
  measured PB Blake grammar (BREAKDOWN.md "What our editor must copy", line 259+): small sentence-case captions,
  locked-off head, no SFX, sparse cuts are CORRECT here. Rewrite those criteria to the measured grammar
  (campaign-scoped rubric: the rubric is built from the campaign's style/breakdown, not generic viral taste).
- Then derive thresholds from data instead of a fixed 7: pass line = lowest approved-ref leave-one-out score,
  fail line = highest known-bad score; report the gap. Bar: every approved ref above every known-bad (already true)
  AND a gap of >= 2 points.
- Max 3 rubric iterations. Freeze the final rubric (store a hash/version in the calibration JSON).
  Refs 6-7 are contaminated — say so plainly; mark "true held-out: pending new refs" in result.md. Do not claim held-out.
- Show the critic score to the user as a band ("at ref level" / "below ref" / "known-bad level"), not a bare /10.

## 3. Text over footage, but never over the eyes/mouth
r2-forcedB sheet: red caps sit on the forehead/eye line. Text over footage is right; covering the eyes or mouth is not.
Restore a HARD check: caption box must not intersect the eye-mouth box of the tracked face (forehead/hair is fine).
Shift the text band above/below when it would. Keep `text_clear_of_faces` informational for the rest of the face.

## 4. Opening + b-roll quality
- Never open on b-roll: first 1.5 s is the speaker (E edit opened on a blurry b-roll frame).
- Reject b-roll shots whose sharpness (variance of Laplacian on the thumb or 3 sampled frames) is below a threshold
  set from the indexed catalog (e.g. bottom 20%); test it.

## 5. Re-render all three proof edits on the final code
edit_f3561f1093 was rendered before the fixes. Re-render the three (E Jev pick, forced B, forced E), new sheets as
`docs/proof/editroom/r3-*.png` next to `ref-sheet-loo.png`, one critic round each, and a table in result.md with the
banded score. Add one PB Blake-style edit using the DOMINANT ref grammar (small white sentence-case captions, centred,
~2% canvas height) — 5 of the 7 refs look like that; currently no proof uses it.

## Done means
pytest green (report the count), the checklist below in result.md with PASS/FAIL per line, nothing pushed:
- [ ] PB Blake EDL: no punch-ins, no push-in; critic cannot enable them
- [ ] default campaign style = locked-off
- [ ] rubric frozen; ref LOO scores, known-bad scores, gap >= 2; held-out stated as pending
- [ ] no caption over eyes/mouth in any r3 proof frame
- [ ] no edit opens on b-roll; blurry b-roll rejected
- [ ] 4 r3 proof sheets incl. the dominant-grammar edit
