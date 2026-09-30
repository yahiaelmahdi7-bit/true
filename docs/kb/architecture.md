# Architecture
Owner: cto · Last verified: 2026-09-30

## System map
Single macOS app process. SwiftUI shell + AppKit/SwiftTerm terminal panes. Local Unix sockets in `~/.true/`: `agent-events.sock` (Claude hook events in) and a control socket used by the `truectl` helper (written at launch). File watchers feed the Hub from `~/.claude/sessions` and `~/.claude/builders`. [source: SPEC.md Run 2, Run 7; git log "Write truectl at launch"]

## Components
Sources/True/ (~11k lines incl. tests dir count separate) [source: `find Sources -name '*.swift'`]:
- `Terminal/` SwiftTerm bridge, redraw coalescer, MemoryGuard (SIGSTOP flow control), scrollback snapshot, shell integration, drop handling
- `Model/` SplitTree, workspace model/store, pane resume, session snapshot, KeepAwake + IdleGate + WorkAwake (work-gated), screenshot watcher
- `Agents/` agent model + store, launch builder, hooks, events socket, registry, PaneDelivery, needs-you detector, control socket, JevClient/JevFill
- `Hub/` HubModel (records, project key, dedupe, grouping), HubStore (DispatchSource watchers), BuilderSpawn
- `Cleaner/` Context Cleaner (scan, rewrite via claude, apply/undo, Jev fact check/ordering)
- `Projects/` ⌘O palette, fuzzy matcher, recents
- `Views/`, `Chrome/`, `Settings/` UI
Tests: `Tests/TrueTests` (28 files) [source: ls].

## Data flow
Pane → PTY → SwiftTerm view. Agent wake → tab runs `claude --name … --settings ~/.true/hooks/<name>.settings.json`; hooks post events to the socket → AgentRegistry → card pill / tab dot / needs-you tray. Writing into panes only via PaneDelivery. Workspace saved to `~/.true/workspace.json` on events (no timers). [source: SPEC.md Runs 1, 2, 4]

## Stack & versions
Swift, swift-tools-version 6.0, macOS 26.0 minimum, SwiftTerm ≥ 1.2.0 (only dependency), no Xcode (CLT + SwiftPM). [source: Package.swift]

## Constraints & invariants
Idle ≈ 0% CPU; no Axon coupling; layout always computed from live window size; empty session id never resumed; Jev failure never breaks a path. [source: SPEC.md Hard rules, Run 1 §4, §6, Run 6]

## Known debt
- `-disable-dynamic-actor-isolation` workaround for a macOS 26 runtime trap (swift#88993/#89214); drop when fixed. [source: Package.swift]
- HubPanel and real `systemRunner` builder launch untested end to end. [source: SPEC.md Run 7 notes]
