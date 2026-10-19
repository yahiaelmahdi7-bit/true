Rebuild the Accounts + Mail UI/UX to the spec at /Users/y/Projects/true/.claude/briefs/clip-studio-accounts-ux-20261013.md.
Read it fully first; it lists every v1 flaw to fix, the IA, both screens, the create flow, states, engine changes and the proof you owe.

Context since your last run:
- The direct-posting branch is now MERGED into this branch (merge commit at HEAD). 'clipengine auth <platform> --status' and the
  platform_auth table exist here, so "Connect for posting" and the "connected" status must work for both providers for real.
- Yahia decided: when a code lands during sign-up, AUTO-COPY it + play the system "Glass" sound once + post a notification if the
  app is not frontmost (spec step 3 already says so).
- The Resend inbound key is not in the Keychain yet; the domain may still be pending. Everything must work against mocks and show
  the no-key state cleanly. Do not call Resend or any platform from tests.
- docs/proof/submit/happy.png (modified) and happy-watched-run.png (untracked) are NOT yours: leave them alone, never commit them.

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

Lane: this worktree/branch only (Sources/ClipStudio*, Tests/, engine/clipengine/{inbox,accounts,authcli}.py + their tests, docs/).
Finish with result.md: what changed, gate output pasted (full engine pytest + swift test), the stills list, and anything you
could not verify. Look at every still yourself and fix what fails /taste before you finish.
