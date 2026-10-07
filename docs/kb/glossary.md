# Glossary
Owner: knowledge-keeper · Last verified: 2026-09-30

| Term | Meaning | Not to be confused with |
|---|---|---|
| Agent | A saved Claude config (name, role, model, effort, permissions, charter) | a running process |
| Awake / Asleep | Agent running in a pane / not | Idle (a status pill) |
| Lead / Helper | `lead-<repo>`; up to four `helper-N-<repo>` per repo | builder |
| Seat | An agent's card in the Hub | a tab |
| Hub | The ⌘E panel of all sessions by project (was "Agents panel") | Axon's desk |
| Builder | Detached `~/.claude/bin/builder` background run shown under Background | in-process sub-agent |
| truectl | CLI agents use to talk to True (summon, status, spawn) | `claude` |
| Needs you | Agent waiting on a permission/question; badge + ⇧⌘U tray | Idle |
| Jev | TypeSafe System One typed-judgment model | a chat LLM |
| Context Cleaner | Sheet that rewrites bloated Claude context/memory with backup+undo | terminal clear |
| PaneDelivery | Single door for writing into a pane | paste |
| Axon | Older parked cockpit (tag `axon-parked-2026-09-29`) | True |
| Overseer | Jev reads each finished Claude turn in a True pane and posts a verdict; read-only (SPEC Run 12) | autopilot |
| Command bar | ⌘K line that routes one typed sentence to a shell, a Claude pane, a seat or a True action (SPEC Run 14) | command-bar |
| Route | What the Command bar decided for a line: kind, project, target, destructive flag; Jev picks among code-built candidates, code owns the floors | command-bar |
| Verdict | The Overseer's one-word read of a turn: verified, unverified, partial, asksToContinue, asksYou, blocked | status |
| Watcher | Standing agent (eye avatar) that turns builder/git/Overseer signals into Inbox items you approve, reject or hand off (SPEC Run 15) | architecture |
| Inbox | Append-only event log of Watcher items; state is `Inbox.fold` over it | architecture |
