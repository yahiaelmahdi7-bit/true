# Run 26f — security review fixes for 26d/26e (same branch, before merge)

A fresh security review of `0b3c9bc..cf71964` confirmed: no model/Haiku/reflex path reaches `.user` or `runUser`;
control characters are refused in tells; only exact, unique roster names match. Fix the items below. **No fix may add
latency to the instant lane or the tell lane** (Yahia: instant is the product).

**Do NOT change:** a tell still sends at the existing end of turn, with the current silence timing. Yahia chose
2026-10-10 to keep tells instant and accept that a mid-sentence pause can send half a sentence. Don't add a longer
pause, a countdown or a confirm step for tells.

## Fix
1. **MEDIUM: own-voice residue across stream revisions** (`NovaLiveTurn.swift:26-42`, `NovaApproval.swift:10`).
   - The `toks.count < floor → floor = 0` restart test brings Nova's already-dropped words back to life when a later
     revision merges tokens (for example "no va" → "nova").
   - Replace it with a stream-generation number that `WakeListener.begin()` increments. Reset the floor only when the
     generation changes.
   - Also drop words whose recognizer segment timestamps fall inside the time Nova was speaking (+ the 400 ms tail),
     even if they arrive late. Keep `micTail` at 400 ms.
2. **MEDIUM: a tell sentence also fires instant clauses** (`NovaInstant.swift:122`).
   - Example: "Nova, tell the CTO to check the build and quit Music" quits Music locally AND sends the whole sentence.
   - Fix: once `NovaTell.parse(...)` matches the addressed command, stop feeding that turn to the instant session. If
     instant clauses already ran before the tell matched, undo them the same way "no" does.
3. **LOW: strip control characters at the one door** (`PaneDelivery.write(.prompt)`).
   - The model path (`NovaGate.swift:74`) checks only NUL, so ESC sequences can reach a pane (`ESC[201~` ends the
     bracketed paste early, then `ESC[Z` toggles the agent's permission mode).
   - Refuse or strip U+0000–001F (except where the paste framing itself needs them), U+007F and U+0080–009F inside
     `PaneDelivery` for EVERY origin. Keep the existing tell-lane refusal.
4. **LOW: Claude Code prefixes.** A tell whose text starts with `/`, `!` or `#` (after trimming) parks with a card,
   because it would run a slash command, a shell command or a memory note. Mention this in docs/kb/security.md.
5. **LOW: tell only to a live agent session.** If the target pane fell back to a plain login shell
   (`AgentLaunch.swift:32`, `claude` missing on PATH) or its agent status is unknown, don't type the tell. Speak
   "<agent> isn't running" and send nothing.

## Tests (write first, paste the failing run, then fix)
- A stream revision that lowers the token count within the same generation does NOT resurrect Nova's dropped words, and
  a stale "Nova, go ahead" from Nova's speech never approves. A new generation does reset the floor.
- Words whose timestamps fall inside Nova's speech window are dropped even when delivered 1 s after she stops.
- "Nova, tell <agent> to X and quit Music" → exactly one send, no local quit.
- An ESC / C1 / DEL in a `.model` prompt never reaches the pane bytes (test at `PaneDelivery`).
- Tells starting with `/`, `!` or `#` park; normal tells still send unparked.
- A tell to a shell-fallback pane, or to an agent with unknown status, sends nothing.
- Timing: the in-process final→gate p50/p95 for a tell stays within 10% of 26e (0.89 ms / 1.37 ms). Assert it numerically.

## Gate (paste the output)
`swift build`; `nice -n 10 swift test -j 4` with the FW/LIB flags from `docs/kb/conventions.md`; `scripts/package.sh debug`.
Don't launch True. Commit on the branch only, with no merge and no push. In the result, report test counts and the
fail-first evidence.
