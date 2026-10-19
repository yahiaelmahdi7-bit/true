# Jev-verified analysis + viral-moment learning (Yahia 2026-10-14)
Base: branch builder/cs-ecosystem-20261014-022356 (pipeline2/ spine: analysis.py, finder.py, planner.py, gate.py, learn.py). Build on it; don't touch tools/, tools2/, layers/ folders (other builders).

## A. Jev confirms analysis (accuracy)
Jev = TypeSafe System One via MCP `typesafe-jev` / skill ~/.claude/skills/jev/SKILL.md (read it; key in Keychain via ~/.claude/bin/jev-mcp — use the same client the engine already uses if any: grep for typesafe/jev in engine first).
- For each analysis output (who_talks per segment, shot boundaries, speech/silence edges, burned-in text/logo boxes, moment completeness), add a verify step: Jev noul/choice over a compact state (transcript window, face/mouth-motion numbers, detector scores, neighbouring frames' features). Store {value, detector_conf, jev_p, verdict} per item.
- Disagreement or jev_p below floor -> mark low-confidence; planner/gate treat as unknown (safe fallback layout, no stack, etc.).
- CALIBRATE: hand-label a held-out set (≥40 items per check from the Solved moments; label from frames/audio yourself, record evidence) -> pick floors on a train split, report accuracy on unseen split. No floor without held-out numbers. Batch Jev questions; cache results per source.

## B. Viral-moment learning loop
1. Harvest: (a) our own posted clips' analytics (engine analytics module; 0 posts now -> build it, test with fixtures); (b) EXTERNAL proof: top-viewed clips of the same podcasts from big clipper/official accounts (Solved/Mark Manson, DOAC…) via yt-dlp metadata + auto-subs (views, likes, duration, posted date) into ~/Projects/clip-studio-refs/viral/ (refs only).
2. Map each viral clip back to its source episode timestamp (transcript fuzzy match on our ingested sources; fetch source if needed) -> labelled "viral moment" spans with view-normalised score (views vs account median).
3. Cross-reference with our finder: for the same episodes, did finder pick those spans? recall@k, rank, what features differ (hook type, topic, emotion, length, payoff, speaker).
4. Improve finder: feature weights / Jev scoring questions learned from (viral vs non-viral spans of same episodes); validate on HELD-OUT episodes only; adopt only if recall@k beats current. Log in docs/proof/viral/.
Proof: docs/proof/jev-analysis/ (accuracy tables before/after Jev, floors) + docs/proof/viral/ (harvest table, mapping, recall before/after on held-out). Tests. Branch only, no merge/push, real library untouched.
