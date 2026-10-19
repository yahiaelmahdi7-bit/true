# Studio tune — learn from rounds 1-2 and finish (Yahia 2026-10-14: "learn from these rounds and fine-tune the studio")
## Lessons (apply to everything)
1. BUILT ≠ USED. Round 2 tools decide things the video never shows (emphasis, hook cold-open, planner not in render). Every tool must change the actual output mp4 or it doesn't count.
2. PROVEN ON REAL CLIPS, not unit/synthetic. Bleep, head-fix, text_guard were only unit-tested. Each change: before/after on real Solved moments that actually exercise it (find them).
3. PARITY IS NOT A WIN. smooth_reframe matched the old crop. Measure against the BAR (top clipper refs in ~/Projects/clip-studio-refs/), not against our old self.
4. qc_score 51-58 on Solved = the honest gap. Target: raise it on held-out moments AND confirm by Yahia's blind eye (score ≠ taste; style school showed self-score disagreed with him).
## Finish (branch builder/cs-layers-toolkit-20261014-020537)
- Wire planner into the real render path (render_moment/_render_locked AND autopilot.cut_one — twins!), behind CLIP_PIPELINE=v2.
- Caption renderer reads emph_words (highlight colour + pop); hook_finder cold open applied to the timeline when score says so.
- Install torch + sam2 in engine .venv (Apple Silicon MPS), run real per-person mattes on 3 Solved moments, measure edge quality + speed; use for depth captions/background ops.
- Bleep on a real profane Solved clip (mom_6ef3c64af7 has "fucking bullshit"); head-fix on a moment that triggers it; text_guard with framescan on real logo frames.
- smooth_reframe: beat the bar — lead room, ease-in on speaker switch, no dead-centre; compare vs reference clipper framing.
## New tools I (the director) want in the pipeline
- caption_readability: auto contrast per frame (measure luminance behind text; add backing/outline/position move until WCAG-ish contrast ≥4.5) — fixes the white-wall problem for good.
- reaction_detector: laughter/applause/gasps (audio) + big facial expression (mediapipe blendshapes) -> boost moment score + punch-in on reaction.
- pacing_check: words/sec, longest static shot, cut interval vs reference clippers; planner adds jump_zoom/b-roll where a shot sits >3s static.
- variant_maker: 2 hook/opening variants per clip (different first line/hook card) for A/B posting; logged for analytics.
- title_writer: post title/description from the moment + campaign tags (plain, no AI voice; humanizer rules).
- topic_segmenter: chapter the episode so moments never straddle two topics.
- loop_end: ending that cuts on a line that loops back to the hook (retention trick) when available.
Each = registry tool, default off until proven, proof row with metric + real before/after.
## Proof
docs/proof/studio-tune/: per item before/after on real moments + qc_score before/after on held-out moments + blind sheet for Yahia (KEY hidden). Full engine suite green. Commit the proof mp4s (or note path). Branch only, no merge/push, real library untouched.
