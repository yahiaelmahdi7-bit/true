Build True "Run 30 — Drive" exactly as specified in SPEC.md (section "## Run 30 — Drive", at the end of the file). SPEC.md is the source of truth; read that section first, then Run 29 (lines ~759-788) and the files it names under Sources/True/Peers/ and Tests/ (PeerCryptoTests, PeerEngineTests, PeerEndToEndTests, PeerLogicTests). Also read CLAUDE.md and docs/kb/index.md for conventions.

Scope: Sources/True/Peers/*.swift, Sources/True/Hub/* only where the Sent-to-peers row needs the activity view, the Peers sheet in PeerViews.swift, the true-peer CLI in PeerCLI.swift, and the four Peer* test files. Do not touch the relay (relay/) — no protocol change is needed; the new payloads ride inside the existing sealed envelope. Do not touch Remote/, Nova, Capture or anything outside the peer feature.

Order: 1) models + logic + tests (PeerLogic/PeerModels), 2) engine (sender + receiver paths) with FakeRelay tests, 3) launcher + hook subscription, 4) CLI ops, 5) views. Commit after each step. Gate = `swift build` then `swift test --filter Peer` in the foreground; the last commit must paste both passing. If a SPEC line is unbuildable as written, implement the nearest behaviour that keeps the security doctrine and write the deviation into a short "### Deviations (builder)" block under the Run 30 section of SPEC.md.

Memory rules that apply: SourceKit "cannot find X in scope" diagnostics on this SwiftPM package are false positives, trust `swift build`. Never launch or quit True.app. Never pkill by name.

DISCIPLINE (non-negotiable):
- Lane: you work ONLY on the files above, on your own worktree branch. Do not touch, checkout, or revert any file outside it — other agents have uncommitted work in this tree.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge, NEVER 'ship' — the user pushes, not you. Do not suggest pushing more than once.
- Gates: run build/tests in the FOREGROUND and wait for them. NO background shells, NO watch modes, NO until-loops. Kill anything you started before finishing.
- Claims: 'done' means you ran the gate and pasted the passing output. Local commit ≠ 'pushed'; code written ≠ 'working'. Never report a state you didn't verify this session.
- Decisions: if your change adds or touches a classify / route / gate / rank / verify step, make it a Jev call through the repo's vendored jev-kit (see the jev skill): code owns the flow, Jev answers narrow typed questions, route on confidence, log the decision. No LLM prompt-and-parse, no keyword lists.
- If blocked or idle: say BLOCKED/IDLE + one line why. Do not invent extra scope.
