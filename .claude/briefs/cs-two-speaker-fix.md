# Two-speaker fix pass — listener reactions, readable captions, no cut-off source text

Continue on your branch (builder/cs-two-speaker-20261013-233615). Same rules: no merge, no push, no package.sh, sandbox library copy only, gates in the FOREGROUND, never change post.golive / autopilot.pause in the real library.

Yahia reviewed your proof sheets and decided:

1. **Stack also for listener reactions.** Fire `stack` when a two-shot shows both faces side by side at similar size, even if only one person speaks (the other is listening/reacting). Keep panel positions FIXED for the whole clip (no swapping when the speaker changes); a subtle active-speaker emphasis is fine. Don't flick: no stack segment shorter than ~1.5 s, merge/absorb tiny gaps. Single-speaker close-ups stay `crop`. Never cover a face. Record decision + reason per shot as before.
2. **Captions readable on bright walls.** Solved's set is near-white, and white captions vanished in your sheets ("I realize I'm in", "If I just sat" in mom_4dc7ab17af). Add a soft shadow (subtle, not a thick black stroke) to caption cards on BOTH the front and depth paths, so they read on white without looking heavy. Keep captions v3 look (spoken-only, on-time, one spot, money green). Show before/after stills of the same frames.
3. **No cut-off source text.** In the forced stack sheet the top panel shows the show's own burned-in title cut to "VEN LUCK". When a crop/panel would slice burned-in source text, move/zoom the crop to exclude it (or include it whole). Reuse the existing off-crop source text detection (reveal-zoom) if it exists — don't add new deps.

## Proof (required)
- Re-render mom_8f399fa883, mom_6ef3c64af7, mom_9358c25556, mom_4dc7ab17af, mom_0185f2fcd1 through the AUTOPILOT path with NO force flag. README verdict first: per clip, which shots use stack now and why, depth share %, caption readability before/after.
- Contact sheets in docs/proof/two-speaker/ (replace old ones, keep the before frames for the caption comparison). Look at every sheet yourself; flag any frame where a caption is hard to read, a face is covered, or text is cut off.

Done = engine pytest green (paste counts), proof README + sheets, commit on your branch.

DISCIPLINE (non-negotiable):
- Lane: only your worktree branch; render.py / captions.py / stack.py + tests + docs/proof/two-speaker. Other builders work in their own worktrees.
- Commits atomic, never push/merge/package. Gates in the foreground, no background shells or until-loops.
- 'Done' = you ran the gate and pasted the output. If blocked: BLOCKED + one line why.
