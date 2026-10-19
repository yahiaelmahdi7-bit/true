# Run 26e — instant verbatim agent sends (same branch, before merge)

Yahia, 2026-10-10: voice must beat the mouse, or it is useless. Today "Nova, tell the CTO to review the PR" goes Haiku →
park → "Nova, go ahead" → send, which takes 3–5 s and fails that bar. Decided: **when the message is his own words, it
goes straight to the agent with no approval. Approval still applies whenever the model writes or routes the message.**

## Build
- **New instant-lane verb `tell`:** "tell / ask / message `<agent or pane>` [to] `<rest>`" → `send_to_pane(target, text)`.
  `text` is the rest of HIS utterance, verbatim from the live stream's final. It never passes through Haiku or Jev.
- **When it fires:** at the FINAL end of turn only (hotkey release, or `DynamicEndpointing`), never on the eager
  250 ms start. The payload is the rest of the sentence, so a pause mustn't send half of it. Hotkey release = send
  immediately.
- **Target:** the agent or pane name must match the roster uniquely (full name or alias). No match, or more than one →
  fall through to the normal reflex/brain path, where C2 still parks.
- **Origin tag, enforced in code:** the lane calls the hand with `origin: .user`. The model's tool path hard-codes
  `origin: .model` and can never set `.user`. `NovaGate` skips the C2 park ONLY for `origin == .user` sends from the lane.
  `relay`, `spawn_agent`, `open_url` and every model send stay parked exactly as now.
- **Still enforced for `.user` sends:**
  - addressed only (wake word in the same utterance, or hotkey held); ambient never sends
  - Nova-speaking gate + tail (P1 rules)
  - the existing "target pane mid-turn → park" rule
  - a `Duty/DenyList` hit anywhere in the text → refused with the reason spoken
  - control-character validation (P2a)
  - sent at most once per turn
- **Feedback:** act earcon + HUD line "→ <agent>: <first ~6 words>" ticked when delivered. No spoken confirmation.
- **Measure:** `clause_to_act_ms` from the final transcript to the send starting. Show it under Show timings.

## Tests (write first, paste the failing run, then fix)
- A `.user` verbatim send runs unparked, and the delivered text equals the spoken rest byte for byte.
- A `.model` send with the same target and text still parks.
- Ambient speech never sends.
- An ambiguous or unknown target falls through to the brain.
- The eager start never sends; only the final end of turn does.
- At most one send per turn.
- Words heard while Nova is speaking are ignored.
- A DenyList text is refused.
- In-process latency from the final transcript to the send starting is ≤ 30 ms; paste p50/p95.

Update SPEC Run 26, glossary ("verbatim send", "origin"), and `docs/kb/security.md` (residual risk: audio that says
"Nova, tell <exact agent name> …" can send a message to an agent that runs without permission prompts; accepted by
Yahia 2026-10-10). Gate: the three commands, with the tails pasted. Commit on this branch only; never main; never launch
True.app; never weaken an existing test.
