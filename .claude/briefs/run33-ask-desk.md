Build True "Run 33 — Ask desk" exactly as specified in SPEC.md (section "## Run 33", the last section). SPEC.md is the source of truth; read Run 29, 30, 32 and 33, then Sources/True/Peers/* (ChatBus, ChatCLI, PeerEngine, PeerRelay, PeerLogic, PeerViews), Model/PaneDelivery.swift, Model/InjectionScreen.swift, and the Peer*/Chat* tests (FakeRelay rig). Also CLAUDE.md and docs/kb/index.md.

Scope: new Sources/True/Peers/Oracle.swift (+ BrainTransport), the `re` field in ChatBus/ChatMessage and the `chat` payload in PeerEngine, `chat.ask` + `--re` in ChatCLI.swift, the per-peer `peer.ask.projects` + `peer.ask` settings in PeerLogic/PeerViews, the `↩` rendering in ChatView.swift, and new tests. Do not touch the relay, Nova, Remote, Capture, the Updater, Hub files other than ChatView.

Order: 1) `re` field end-to-end (bus, payload, CLI) + tests, 2) Oracle + FakeBrain + OracleTests, 3) `chat.ask` / true-ask + tests, 4) settings + Chat tab. Commit after each step. Gate = `swift build` then `swift test --filter Peer`, `swift test --filter Chat`, `swift test --filter Oracle` in the foreground; the last commit must paste all passing. Unbuildable SPEC line → nearest safe behaviour + a "### Deviations (builder)" block under Run 33 in SPEC.md.

Memory rules: SourceKit "cannot find X in scope" diagnostics are false positives, trust `swift build`. Never launch or quit True.app. Never pkill by name. The brain server (127.0.0.1:8800) may or may not be running on this Mac: tests use FakeBrain only, never the live server.

DISCIPLINE (non-negotiable):
- Lane: you work ONLY on the files above, on your own worktree branch. Do not touch, checkout, or revert any file outside it — other agents have uncommitted work in this tree.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge, NEVER 'ship' — the user pushes, not you. Do not suggest pushing more than once.
- Gates: run build/tests in the FOREGROUND and wait for them. NO background shells, NO watch modes, NO until-loops. Kill anything you started before finishing.
- Claims: 'done' means you ran the gate and pasted the passing output. Local commit ≠ 'pushed'; code written ≠ 'working'. Never report a state you didn't verify this session.
- Decisions: if your change adds or touches a classify / route / gate / rank / verify step, make it a Jev call through the repo's vendored jev-kit (see the jev skill): code owns the flow, Jev answers narrow typed questions, route on confidence, log the decision. No LLM prompt-and-parse, no keyword lists.
- If blocked or idle: say BLOCKED/IDLE + one line why. Do not invent extra scope.
