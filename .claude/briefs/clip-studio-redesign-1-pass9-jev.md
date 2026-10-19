# Pass 9 — Jev runs the brain (no paid LLM needed)

Yahia's call (2026-10-12): every AI step that is a CHOICE goes to Jev (TypeSafe System One, `typesafe-jev`,
already wired in engine/clipengine via cliptype/ask/agent — reuse that client + key lookup). Claude stays only as an
OPTIONAL fallback behind a config flag (`llm.fallback: off` by default); the Anthropic key has no credit, so the
whole pipeline must work end to end with Claude OFF. Principle: code generates candidates, Jev picks/scores.
Jev cannot write text — it can only choose among options you give it (≤255) and return probabilities.

Proven live in chat: one Jev call (state = transcript sentences) picked the title line (0.74), the watch reason
(bold_claim 0.80) and a worth score, ~650 input tokens.

## Move these steps (each: Jev path default, Claude path kept behind the flag)
1. **Moments** (moments.py, Sonnet today): code slides windows over the transcript (sentence-aligned, 15–60 s,
   respect existing boundary/bounds logic), Jev scores each window in batches (score levels = concrete descriptions),
   keep top-N with non-overlap. Reuse existing heuristic signals as state fields, not as verdicts.
2. **Title**: Jev choice over spoken sentences in the clip (cleaned). Never invented text.
3. **Why-line**: Jev choice of reason (bold_claim/how_to/story/funny/reaction/none) + score → code template
   ("Bold claim · strong hook"). Show the confidence in data; low confidence → "needs your eye".
4. **Ask / Change…**: Jev only (already first); remove the Claude tool-use hop when fallback off.
5. **Edit critique / draft / voiceover-script / trendedits gate / finder_chat**: where it is a decision, route to Jev
   over the existing code checks + a text summary; where it truly needs generated prose (voiceover script),
   disable cleanly with a clear "needs a writing model" state rather than fail.
6. Agent budget: count Jev spend at real Jev prices (input $0.042/M, output free); keep the 12 renders/day cap.

## Validation (the gate — Virgilio: unseen data, honest numbers)
- Build a held-out set from the REAL library READ-ONLY (`sqlite3 "file:...?mode=ro"`): moments Yahia approved vs
  rejected/discarded, posted-clip outcomes if present. Freeze the split BEFORE tuning any threshold.
- Report: Jev window-ranking vs his verdicts (precision@k, how many approved moments land in top-N), title pick vs
  the title he kept/edited, and old Sonnet moments vs Jev overlap where history exists. Say plainly if it is worse.
- `agent tick` in a CLIPSTUDIO_HOME sandbox copy with Claude OFF must find moments organically (pass 8 found 0) and
  produce feed cards with Jev titles + why-lines. Proof in docs/proof/jev/README.md with screenshots of the feed.

## Rules
- Real library read-only; sandbox writes only. Don't quit/relaunch ClipStudio, don't run package.sh, don't load the
  LaunchAgent, never push, never merge to main. Commit on this branch.
- Never fake numbers. Name stays "Clip score". Gates: swift build, swift build --build-tests, swift test, engine pytest.
- Final report: plain English, verdict first, then numbers vs held-out, then risks.
