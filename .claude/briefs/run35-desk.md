Build True "Run 35 — One desk per peer project" exactly as specified in SPEC.md (section "## Run 35", the last section). SPEC.md is the source of truth; read Run 29, 30, 34 and 35, then Sources/True/Peers/* (PeerEngine run()/end()/paneEvent, PeerLogic PeerNaming/PeerText/PeerSettings, PeerModels InboundJob + PeerLauncher protocol, PeerLauncherLive deliverToPane/atPermissionPrompt, PeerViews Peers sheet), Hub/* for the job card, and the Peer* tests (FakeRelay + fake launcher rig). Also CLAUDE.md and docs/kb/index.md.

Scope: desk keying + in-line queue + pane reuse in PeerEngine, `desk` field on InboundJob, `deskWorktree`/`deskAgentName` + `roleCardDesk` + the envelope's checkout-first step in PeerLogic, `paneAlive` on the PeerLauncher protocol (live impl via TerminalRegistry, fake default true), `PeerSettings.desk` + the Peers sheet toggle and live-desks list, the job card's desk line, and new tests. Do not touch the relay, Nova, Remote, Capture, the Updater, ChatBus/ChatCLI/Oracle, or the sender side.

Order: 1) desk key + in-line queue + reuse over the fake launcher + tests (the core: one launchPane, then deliverToPane), 2) envelope/role-card text + naming + tests, 3) settings toggle + Peers sheet + job card line, 4) paneAlive live impl. Commit after each step. Gate = `swift build` then `swift test --filter Peer` in the foreground; the last commit must paste all passing. Unbuildable SPEC line → nearest safe behaviour + a "### Deviations (builder)" block under Run 35 in SPEC.md.

Memory rules: SourceKit "cannot find X in scope" diagnostics are false positives, trust `swift build`. Never launch or quit True.app. Never pkill by name. Never run real git or open real panes in tests.

DISCIPLINE (non-negotiable):
- Lane: you work ONLY on the files above, on your own worktree branch. Do not touch, checkout, or revert any file outside it.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge, NEVER 'ship'.
- Gates: run build/tests in the FOREGROUND and wait for them. NO background shells, NO watch modes, NO until-loops. Kill anything you started before finishing.
- Claims: 'done' means you ran the gate and pasted the passing output. Local commit ≠ 'pushed'; code written ≠ 'working'. Never report a state you didn't verify this session.
- Decisions: plain code; this run has no classify/route/rank step that needs Jev.
- If blocked or idle: say BLOCKED/IDLE + one line why. Do not invent extra scope.
