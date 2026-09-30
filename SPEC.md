# True — a lean Warp-style terminal with an agents mode

**One sentence:** a fast, quiet macOS terminal (tabs + splits, native window feel) with an **Agents
mode** where you build Claude agents like game characters, wake them into tabs, see who is working
or waiting on you, and talk to your lead agent, who hands work to its helpers.

**Why it exists:** Axon (`~/Projects/axon`, frozen at tag `axon-parked-2026-09-29`) was meant to
replace Warp and didn't: 68k lines, 20+ subsystems, fans spinning. True keeps only Axon's proven
terminal + agent plumbing. Everything else stays behind.

## Hard rules
- **Idle ≈ 0% CPU.** No timers, polling loops or `repeatForever` animations at launch. Everything is
  event-driven (PTY output, the agent-events socket, user input). Every launch-time side effect must
  justify itself in a code comment.
- **No Nova, voice, canvas/desk, player, blocks, brain lens, Keychain, mic/TCC, smart input** in v1.
- **Own identity, zero collision with Axon:** bundle id `net.prismlens.true`, state in `~/.true/`,
  socket `~/.true/agent-events.sock`, hook scripts in `~/.true/hooks/`. Never read/write `~/.axon/`,
  never edit `~/.claude/settings.json` (per-agent `--settings <file>` only).
- **Apple HIG look:** SF Symbols, system materials / Liquid Glass (`.glassEffect`) on bars and the
  agents panel, system fonts for UI, a monospaced terminal font, dark + light following the system.
  Reference: the `apple-hig` skill at `~/.claude/skills/apple-hig/`.
- **Copy + trim from Axon, never import it.** Axon is read-only reference. Lifted code keeps its
  hard-won comments (they explain real incidents).

## Stack
SwiftPM, `swift-tools-version: 6.0`, `platforms: [.macOS("26.0")]`, one executable target `True`
+ test target `TrueTests`, one dependency: SwiftTerm (`from: "1.2.0"`). Keep Axon's
`.unsafeFlags(["-Xfrontend", "-disable-dynamic-actor-isolation"])` on both targets (macOS 26 runtime
crash in SwiftUI/AppKit event dispatch; see Axon `Package.swift` comment).
`scripts/package.sh` builds `True.app` (adapt Axon's `scripts/package.sh`; drop ONNX/resources,
Keykeeper and fonts unless needed). It must never launch the app.

Tests need the CommandLineTools flags:
```
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
nice -n 10 swift test -j 4 -Xswiftc -F$FW -Xlinker -F$FW -Xlinker -rpath -Xlinker $FW -Xlinker -rpath -Xlinker $LIB
```

## Run 1 — Terminal core
1. **App shell:** one main window, `.windowStyle(.hiddenTitleBar)`, `.windowResizability(.contentMinSize)`,
   default ~1280×820. A tab bar at the top (Liquid Glass), terminal content below. Nothing else.
2. **Terminal panes:** SwiftTerm local-process panes running the user's login shell in a chosen cwd.
   Lift from Axon `Sources/Axon/Terminal/`: `EmbeddedTerminal.swift`, `TerminalSession.swift`,
   `TerminalRedraw.swift`, `MemoryGuard.swift` (SIGSTOP flow control, the 80 GB incident), and the
   **scroll fix** — a local NSEvent monitor for precise deltas + alt-screen (in Axon it lives in
   `Sources/Axon/Desk/AgentActivity.swift`, `MonitoredTerminalView` / `addLocalMonitorForEvents`).
3. **Tabs:** ⌘T new, ⌘W close pane (tab when last), ⌘1–9 jump, ⌃Tab / ⌃⇧Tab cycle, ⌘⇧[ / ⌘⇧],
   double-click a tab to rename, drag to reorder. Tab title = custom name, else cwd basename.
4. **Splits:** a binary split tree per tab. ⌘D split right, ⌘⇧D split down, ⌥⌘←↑→↓ move focus,
   drag the divider to resize. The layout is ALWAYS computed from the live window size (GeometryReader
   / proportional fractions), so resizing the window resizes every pane — nothing is ever clipped.
   This is one of the two bugs Yahia hit in Axon; test it.
5. **Native window feel:** empty tab-bar space drags the window on single click and runs the Mac's
   title-bar double-click action (Fill/Zoom/Minimize per `AppleActionOnDoubleClick`). Lift
   `Sources/Axon/Chrome/WindowChromeArea.swift` (apply it BEHIND the bar's controls, before the bar
   background) and the tab-bar usage in `Sources/Axon/Terminal/WorkspaceTabBar.swift`.
6. **Workspace autosave:** tabs, split tree, fractions, cwd and custom names saved to
   `~/.true/workspace.json` (debounced on change, not on a timer) and restored at launch. See Axon
   `WorkspaceLibrary.swift` and memory note: an empty session id must never be resumed.
7. **Settings (⌘,):** terminal font + size, cursor style, scrollback lines. Small.
8. **Tests (pure logic):** split-tree insert/remove/focus-move, fraction math under window resize
   (no pane ever exceeds the container), workspace encode/decode round-trip + a corrupt-file fallback,
   tab ordering.

**Run 1 done =** `swift build` clean with no warnings you introduced, all tests green (paste the
output), `scripts/package.sh` produced `True.app`, commits made. App NOT launched.

## Run 2 — Agents mode
Terminology (one name per thing): an **agent** is a saved Claude config; an agent that is running in
a pane is **awake**, otherwise **asleep**. Every repo has at most one **lead** (`lead-<repo>`) and up
to four **helpers** (`helper-1-<repo>` … `helper-4-<repo>`), the naming Axon's crew already uses.

1. **Agent model** (`~/.true/agents.json`, Codable, `version` field): name, role (lead|helper), repo
   path, model (`haiku|sonnet|opus|fable`), effort (`low|medium|high|xhigh|max`), permission mode
   (`default|acceptEdits|plan|auto`), charter (extra instructions), team (a lead lists its helpers),
   last session id (resume only if non-empty and its transcript exists), symbol (SF Symbol name).
   Lift the ideas + role cards from Axon `Sources/Axon/Crew/SeatRoles.swift` and `CrewModels.swift`.
2. **Agents panel** (⌘E toggles; trailing sidebar, Liquid Glass). Grouped by repo, lead first.
   Each agent is a **character card**: SF Symbol avatar (lead `crown`, helper `hammer` by default),
   a tier colour by model (haiku teal · sonnet blue · opus purple · fable gold), effort shown as a
   5-step meter, a permission badge, and a status pill: Asleep / Working / Needs you / Done / Idle.
3. **Character builder** (sheet from "+" or Edit): a live card preview on the left that updates as you
   change fields on the right. Fields: repo (folder picker; name auto-fills `lead-<repo>` or the next
   free `helper-N-<repo>`), role, model (segmented), effort (5-stop slider), permission mode, symbol
   picker (curated list of ~24 SF Symbols), charter text, and for a lead, which helpers it manages.
   Should feel like a game character creator, but made from native HIG controls.
4. **Wake / sleep:** clicking an asleep card opens a tab in the agent's repo and runs
   `claude --name <name> --model <m> --effort <e> --permission-mode <p>
   --append-system-prompt-file ~/.true/roles/<name>.md --settings ~/.true/hooks/<name>.settings.json
   [--resume <id>]`. Write the role file from charter + role card (a lead's card must tell it to
   hand work to its helpers by name with SendMessage). Sleeping ends the process cleanly (Axon memory:
   SIGTERM-proof teardown) and keeps the session id. Agents that were awake when True quit are re-woken on
   launch into the same pane with `--resume`; nothing else wakes by itself.
5. **Live status:** per-agent hook settings post Claude Code hook events (SessionStart, UserPromptSubmit,
   PreToolUse, Notification, PermissionRequest, Stop) to `~/.true/agent-events.sock`. Lift Axon
   `Sources/Axon/Desk/AgentEvents.swift` (socket) and `AgentHooks.swift` (hook script + settings),
   repointed at `~/.true`. Status drives the card pill and a dot on the agent's tab.
6. **Needs you:** a count badge in the tab bar; ⇧⌘U opens a tray listing waiting agents with the
   question and Allow / Deny (or the dialog's own options). Lift `NeedsYou.swift`, `NeedsYouTray.swift`
   and `PaneDelivery.swift` (the ONE door for writing into a pane; verification reads the rendered
   screen). Replace their DeskModel/SleepCenter dependencies with a small `AgentRegistry`
   (name → agent config + pane + status).
7. **Talk to the lead:** the lead's card has a message field; Return delivers the text into the
   lead's pane through PaneDelivery (waking it first if asleep).
8. **Tests:** agents.json round-trip + migration from a missing `version`, launch-command builder
   (every flag, resume only when valid), name auto-assignment, hook-event parsing, needs-you detector
   on Axon's recorded fixtures (`~/Projects/axon/Tests/AxonTests/Fixtures/permission-dialog` — copy
   them in), registry state transitions.

**Run 2 done =** same bar as Run 1.

## Later (not v1)
Smart input (one box: shell command vs agent request, next-command, commit/PR text) · 3D/illustrated
character art (no Gemini) · Nova as a separate menu-bar app driving True over a control socket.

## Run 4 — Restore (exactly where he left off)
- **⌘O** opens the picked project as a split (axis horizontal) beside the focused pane of the selected tab;
  ⌘↩ starts Claude in that new pane only.
- **Records:** `TabState.resume: [UUID: PaneResume]?` in `~/.true/workspace.json` (`.claude(sessionID, cwd)` /
  `.agent(name)`). Optional, so v1 files still decode; `version` is NOT bumped.
- **Snapshot triggers (event-driven, no timers):** `applicationShouldTerminate`, main-window `willClose`,
  a one-shot ~2.5 s after Return in a pane, and any `.session` hook event. A gone view keeps its old record.
- **Claude discovery:** walk the shell's descendants (≤5 deep) for a `<claudeConfigDir>/sessions/<pid>.json`
  with `kind == "interactive"`; resume with `claude --resume <id>` if the transcript exists.
- **Agents** recorded as awake are re-woken in the same pane before first render.
- **Plain shells:** at quit/close the normal buffer (scrollback+screen, with colours) is saved to
  `~/.true/scrollback/<pane>.ans` + `.json` (mode 0600) and replayed before the shell starts, followed by a
  dim `── restored · … ──` marker line. Nothing is re-run.
