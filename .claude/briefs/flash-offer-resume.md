New ask from Yahia (answering your open question): the 10s flash edit should be OFFERED AUTOMATICALLY on high-scoring clips,
alongside the normal edit, never posted without his approval.

Build:
- "High-scoring" = a deterministic rule on the score the app already shows for a moment/edit (find the existing scale; use the
  campaign's top band, e.g. >= its 80th percentile over the last 30 days, min sample guarded). Put the threshold in config.
- When a qualifying edit is created, queue ONE flash sibling (reuse edit-flash10 + Jev window pick) at low priority, labeled
  "Suggested flash" in Review/Inspector, status awaiting approval. Cap: max 3 suggested flashes per campaign per day (config).
- It must never be auto-approved, never enter the post queue or slot routine on its own, and never flip post.golive. Replace
  the old "never created" grep guard in test_flash10.py with tests that prove: suggestion created only above threshold, cap
  enforced, suggestions excluded from auto-post/slot paths until approved.
- One-click "Dismiss suggestion" that deletes the suggested render.
- Also fix from your last result: slam text hard to see in stills (contrast), and re-render the two proof clips now that the
  duplicate header fix is in; look at the contact sheets.

DISCIPLINE (non-negotiable):
- Lane: you work ONLY on [files/dir/branch]. Do not touch, checkout, or revert any file outside it —
  other agents have uncommitted work in this tree.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge,
  NEVER 'ship' — the user pushes, not you. Do not suggest pushing more than once.
- Gates: run lint/tsc/tests in the FOREGROUND and wait for them. NO background shells
  (run_in_background), NO watch modes, NO until-loops. Kill anything you started before finishing.
- Claims: 'done' means you ran the gate and pasted the passing output. Local commit ≠ 'pushed';
  code written ≠ 'working'. Never report a state you didn't verify this session.
- Decisions: if your change adds or touches a classify / route / gate / rank / verify step, make it a Jev
  call through the repo's vendored jev-kit (see the jev skill): code owns the flow, Jev answers narrow
  typed questions, route on confidence, log the decision. No LLM prompt-and-parse, no keyword lists.
- If blocked or idle: say BLOCKED/IDLE + one line why. Do not invent extra scope.

Lane: this worktree/branch only. result.md: what changed, gate output pasted (engine pytest + swift test), stills/contact sheets.
