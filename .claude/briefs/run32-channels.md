Continue on THIS branch (Run 30 Drive is already built here; keep it green). FIRST run `git merge --no-edit main` in this worktree so SPEC.md carries the Run 31 and Run 32 sections (main only adds spec text and briefs; resolve nothing else). Build True "Run 32 — Channels" exactly as specified in SPEC.md (section "## Run 32", the last section). SPEC.md is the source of truth; read Run 29, 30 and 32, then Sources/True/Peers/* (your previous work), Model/PaneDelivery.swift, Model/InjectionScreen.swift, Hub/* and the Peer*/Chat* tests. Also CLAUDE.md and docs/kb/index.md.

Scope: new Sources/True/Peers/ChatBus.swift + ChatCLI.swift, PeerEngine/PeerModels/PeerLogic for the `chat` payload, PeerViews/Hub for the Chat tab, the socket ops in PeerCLI.swift, and new tests. Do not touch the relay, Nova (except the one `tell` fallback line in the Nova→bus seam, guarded by a unit test), Remote, Capture, the Updater.

Order: 1) ChatBus store + membership + delivery + tests, 2) `chat` payload over FakeRelay + tests, 3) CLI ops + tests, 4) Chat tab. Commit after each step. Gate = `swift build` then `swift test --filter Peer` and `swift test --filter Chat` in the foreground; the last commit must paste all passing. Unbuildable SPEC line → nearest safe behaviour + a "### Deviations (builder)" block under Run 32 in SPEC.md.

Memory rules: SourceKit "cannot find X in scope" diagnostics are false positives, trust `swift build`. Never launch or quit True.app. Never pkill by name.

DISCIPLINE (non-negotiable):
- Lane: you work ONLY on the files above, on your own worktree branch. Do not touch, checkout, or revert any file outside it — other agents have uncommitted work in this tree.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge, NEVER 'ship' — the user pushes, not you. Do not suggest pushing more than once.
- Gates: run build/tests in the FOREGROUND and wait for them. NO background shells, NO watch modes, NO until-loops. Kill anything you started before finishing.
- Claims: 'done' means you ran the gate and pasted the passing output. Local commit ≠ 'pushed'; code written ≠ 'working'. Never report a state you didn't verify this session.
- Decisions: if your change adds or touches a classify / route / gate / rank / verify step, make it a Jev call through the repo's vendored jev-kit (see the jev skill): code owns the flow, Jev answers narrow typed questions, route on confidence, log the decision. No LLM prompt-and-parse, no keyword lists.
- If blocked or idle: say BLOCKED/IDLE + one line why. Do not invent extra scope.
