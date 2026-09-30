# Integrations
Owner: integrations-engineer · Last verified: 2026-09-30

| Service | Purpose | Auth method | Key location (never value) | Limits | Failure mode | Owner |
|---|---|---|---|---|---|---|
| SwiftTerm | Terminal emulation | none (library) | n/a | ≥ 1.2.0 [source: Package.swift] | build break on API change | swift-engineer |
| Claude Code CLI | Agents run `claude --name … --settings … --resume` | user's own login | `~/.claude` config | resume only if transcript exists [source: SPEC.md Run 4] | pane shows shell error | integrations-engineer |
| Claude hooks → socket | Live agent status | local socket, no auth | `~/.true/agent-events.sock` | — | status stays stale/Asleep | integrations-engineer |
| `~/.claude/bin/builder` | Background helpers (`truectl spawn`) | local process | n/a | budget per builder default $5 [source: ~/.claude/CLAUDE.md] | spawn returns error text | integrations-engineer |
| Peer registry / builders dirs | Hub data (read-only) | filesystem | `~/.claude/sessions`, `~/.claude/builders` | never read `*.key` [source: SPEC.md Run 7] | row missing | integrations-engineer |
| TypeSafe Jev API | Typed judgments (cleaner, AI fill) | Bearer key | env `TYPESAFE_API_KEY`, else Keychain item `net.prismlens.jev-cli` / account `typesafe` [source: SPEC.md Run 6] | timeouts 3–8 s | nil → old behaviour | integrations-engineer |
| macOS signing | Stable app identity | self-signed cert | "Deck Signing" in login keychain [source: scripts/package.sh] | — | falls back to ad-hoc + WARNING | cto |
