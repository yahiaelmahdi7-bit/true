TYPES PASS 2 — make the classifier trustworthy enough for the AI feed (same worktree/branch as your types pass).

Why: pass 8 (redesign branch) is building an AI-native feed where the agent sorts every moment by type and renders its recipe
with no human in the loop until Approve. Your result: podcast 0/15 (no speaker labels → Solved interviews land as yt_talking),
21/49 overall, numbers tuned on the test set. Solved is Yahia's main paid campaign, so podcast must work.

## 1. Honest evaluation FIRST (before any tuning)
- Freeze a held-out split BY SOURCE (never split moments of one source across sets). Write docs/proof/types/split.json with the
  labels and the date; commit it before touching the classifier. Report every number twice: tuning set and held-out.
- Grow the labelled set only from sources already in the sandbox library + channels with a rights choice (Malik, N3on campaign,
  spitzz). No new downloads of unlicensed footage; downloads only for channels with rights. Label by eye from contact sheets.

## 2. Podcast detection
- Add speaker evidence: pick the simplest method that works on held-out — (a) distinct-face clustering across sampled frames
  (face embeddings, alternating single-face shots = multi-cam podcast), and/or (b) audio speaker-change detection with a light
  local model (no paid API, no HF-token-gated model unless already installed). Cache per source.
- Target: podcast ≥ 12/15 on the Solved moments, AND no regression on gaming_cam 7/7 + facecam 18/18. If the target is missed,
  say so and report the confusion matrix; never relabel ground truth to hit it.

## 3. Reaction / just_chatting signals (should)
- Video-player-region detection (a large inset that is not a face cam) so `reaction` stops relying on title words.
- Report per-type coverage honestly: types with < 5 labelled examples are marked "untested" in `clip-types --json`, and the
  agent (pass 8) must treat "untested" types as needs-review (add a `confidence` + `tested` field to the classifier output;
  document the field in docs/clip-types.md so the Swift side can show it).

## Gates
pytest (each test file you touch + test_cliptype + test_facecam_regress), new tests for the speaker signal on fixtures.
docs/proof/types/README.md: before/after table (tuning vs held-out), confusion matrix, misses list, runtime per source.
Commit; no push; no merge to main; sandbox CLIPSTUDIO_HOME only; never write the real library; `--apply` stays refused.
