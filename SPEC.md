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
   a model tier shown as brightness (`AgentModel.tint`, monochrome; colour is reserved for the avatar — see Run 8), effort shown as a
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
Smart input → now Run 14 (Command bar); still later: next-command, commit/PR text · 3D/illustrated
character art (no Gemini) · Nova as a separate menu-bar app driving True over a control socket.

## Run 4 — Restore (exactly where he left off)
- **⌘O** opens the picked project as a split (axis horizontal) beside the focused pane of the selected tab;
  ↩ (or a click) starts Claude there in bypass mode (`claude --dangerously-skip-permissions`); ⌘↩ opens a plain shell.
- **Permission mode survives a restart:** the pane hook forwarder passes Claude's `permission_mode` on every event;
  True keeps the latest per pane and records it as `.claude(sessionID, cwd, mode)` (`mode` optional, old files decode).
  Resume replays it from an allowlist: `bypassPermissions` → `--dangerously-skip-permissions`, `default` → `--permission-mode manual`
  (the CLI rejects `default`), other modes the CLI accepts → `--permission-mode <m>`, unknown/nil → no flag (the user's settings default).
- **Records:** `TabState.resume: [UUID: PaneResume]?` in `~/.true/workspace.json` (`.claude(sessionID, cwd, mode?)` /
  `.agent(name)`). Optional, so v1 files still decode; `version` is NOT bumped.
- **Snapshot triggers (event-driven, no timers):** `applicationShouldTerminate`, main-window `willClose`,
  a one-shot ~2.5 s after Return in a pane, and any `.session` hook event. A gone view keeps its old record.
- **Claude discovery:** walk the shell's descendants (≤5 deep) for a `<claudeConfigDir>/sessions/<pid>.json`
  with `kind == "interactive"`; resume with `claude --resume <id>` if the transcript exists.
- **Agents** recorded as awake are re-woken in the same pane before first render.
- **Plain shells:** at quit/close the normal buffer (scrollback+screen, with colours) is saved to
  `~/.true/scrollback/<pane>.ans` + `.json` (mode 0600) and replayed before the shell starts, followed by a
  dim `── restored · … ──` marker line. Nothing is re-run.
- **Interrupted sessions continue (as built):** at the quit snapshot (`SessionSnapshot.atQuit`, after the
  records) a recorded pane is marked interrupted when its claude session file says `"status": "busy"`
  (`ClaudeSessions.Found.busy`) OR hook tracking says working / needs-you (`AgentRegistry.latest[pane]`
  folded through `AgentStatus.next`, or the seat's `statusOf`). A session file saying `"status": "idle"`
  overrides the hooks (Esc mid-turn fires no Stop, so a stale 'working' must not mark it; a missed mark only costs a quiet resume).
  Marks live in `TabState.interrupted: Set<UUID>?` (optional, old files decode). On the next launch `ResumePlan.apply` adds
  `ResumePlan.continuePrompt` as the final positional argument (`claude --resume <id> --settings <s> '<prompt>'`),
  seats get it as the last argv element (`AgentLaunch.argv(initialPrompt:)`, only when really resuming),
  idle sessions restore exactly as before, and every mark is cleared and saved at once (consumed once, so a
  crash cannot replay it). Logged: `quit snapshot: N interrupted (will continue)`, `restore: continuing N
  interrupted session(s)`. The restart confirm alert says sessions pick up where they left off.

## Run 6 — Jev in the backend (decisions only)
Jev (TypeSafe System One: typed judgments with probabilities, never prose) supplies judgments; code keeps
the workflow. Jev slow/down/keyless never breaks anything: every path falls through to the old behaviour.
- **JevClient** (`Agents/JevClient.swift`): `POST https://api.typesafe.ai/v1/systemone`, Bearer key, body
  `{model:"jev-latest", state, questions}`. Key order: env `TYPESAFE_API_KEY`, else once per process
  `/usr/bin/security find-generic-password -s net.prismlens.jev-cli -a typesafe -w` (result cached, including
  "missing"; never logged). `ask(state:questions:timeout:)` returns nil on no key / network / timeout / non-2xx /
  undecodable. Transport and key provider are injectable.
- **Cleaner fact check** (`Cleaner/CleanerFactCheck.swift`, additive only): blocks of the original (blank line or
  `#`, `- `, `* `, `+ `, `N. `, `>`, `|` starts one); a block is *vanished* if norm length >= 15, not a substring
  of the normalised output, and best word-Dice vs output blocks < 0.6. First 40 go to two parallel Jev calls
  (FILLER `f<i>`, KEPT `k<i>`, 8 s). Flag when `max(filler, kept) < 0.5`: orange "possible lost fact" chip
  (first ~80 chars, full text in tooltip), row unchecked. Jev never removes a regex chip. No reply: grey
  "fact check off". More than 40 vanished: grey "large rewrite — review by eye", row unchecked.
- **Ordering** (`Cleaner/CleanerOrdering.swift`): one `pad` score per unique content, 8 in flight, 5 s each and
  5 s overall; stable sort by score descending, unscored = 1.0. Nothing is skipped or shown.
- **AI fill** (`Agents/JevFill.swift`): Jev (3 s) picks model / effort / permission (and role when not editing)
  in parallel with Claude; each pick with confidence >= 0.6 is applied immediately. When Claude returns, the
  charter and symbol are always Claude's; other fields apply only if still equal to their pre-fill value. Claude
  failing keeps Jev's picks and shows the existing error. Needs-you stays the deterministic hook.
- **Tests:** all with injected transport/key provider (no network, no Keychain): JevClientTests,
  CleanerFactCheckTests, CleanerOrderingTests, JevFillTests. `JevLiveTests` (one noul, choice, score round
  trip) run only with `JEV_LIVE=1`; the builder never ran them.

## Run 7 — The Hub (every session, every project, live) + background helpers

**Goal:** one place in True showing every Claude session on this Mac, grouped by project, with live
status — and a lead can launch background helpers (detached `builder` runs) that appear there.
Pure code, no Jev: the hub is deterministic (code owns it — that IS the doctrine).

**Sources (read-only; never display or read `*.key` files):**
1. `AgentRegistry` — seats + hook-event status (existing).
2. Peer registry `~/.claude/sessions/*.json` — fields seen: pid, sessionId, cwd, startedAt, kind,
   entrypoint, name, status (busy|idle), updatedAt. Alive = `kill(pid, 0)` succeeds or EPERM.
3. Builders `~/.claude/builders/<id>/meta.json` — id, name, cwd, origin_cwd, worktree, branch, model,
   budget_usd, session_id, supervisor_pid, claude_pid, started, … Read `~/.claude/bin/builder` for the
   real status semantics (running / finished / failed / acked) and where the result lives. Show running,
   finished-not-acked, and anything finished < 24h ago.

**Project key:** `<X>.builders/<id>` → `<X>`; `<repo>/.claude/worktrees/<n>` → `<repo>`; builder →
`origin_cwd`; else nearest ancestor containing `.git`; else cwd. Display = folder name.
**Dedupe:** seat ↔ registry by sessionId or pid; builder ↔ registry by session_id / claude_pid. One row
per real session.

**UI — the ⌘E Agents panel becomes the Hub** (one name everywhere: "Hub"; rename menu item + title).
Project groups sorted by latest activity, header counts ("3 working · 1 needs you"). Inside each:
**Seats** (existing character cards, unchanged) · **Background** (builders: name, model tier colour,
elapsed, status pill, "from lead-x" when `parent` known) · **Other sessions** (live Claude sessions True
didn't launch: name, kind, status). Pills reuse the existing set + Failed. Clicks: seat → existing;
builder → read-only sheet (meta + result / recent tail from its files); other → reveal cwd in Finder. No
kill buttons in v1. Top toggle **All** (default) / **Seats**. Hide empty projects. HIG + Liquid Glass
consistent with the current panel.

**Live, within the idle-CPU rule:** DispatchSource watchers on both directories (event-driven); pid
liveness re-checked on each event and when the Hub becomes visible; any elapsed-time ticker runs ONLY
while the Hub is visible (justify in a comment). File IO off the main actor; diff updates so cards
don't flicker.

**Background helpers:**
- `truectl spawn --name <n> --prompt-file <F> [--repo <path>] [--worktree] [--model sonnet]` → control
  op `spawn` → True runs `~/.claude/bin/builder start --name <n> --cwd <repo> --prompt-file <F>
  [--worktree] --model <m> --parent <from>` (from = `$TRUE_AGENT`; repo defaults to the caller's repo).
  Validate: name regex as builder's, prompt file exists, repo under ~/Projects, ~/studio-builds or
  ~/Prism. Reply = builder id or the error text.
- `builder --parent` — ADDITIVE edit to live infra other sessions use right now: back up to
  `~/.claude/bin/builder.bak-20260930-parent` first; add optional `--parent NAME` on `start`, stored as
  `meta["parent"]`; default from env `TRUE_AGENT` when set, else omitted. Nothing else changes. Verify:
  `python3 -m py_compile`, `builder -h`, `builder start -h`, `builder status`.
- Lead role card gains: use `truectl spawn` for long/unattended work (survives resets, shows under
  Background in the Hub); `truectl summon` for interactive work with a helper seat; run `truectl status`
  first to avoid duplicate work. `truectl status` reply gains the hub snapshot (project → sessions) as JSON.

**Tests:** cwd normalisation table · dedupe · registry parsing (missing fields, dead pid) with sanitised
fixtures · builder meta per status · spawn parse/validate · builder command assembly (every flag) · role
card contains the spawn guidance · hub grouping / sort / counts.
**Done =** suite green (paste output), `scripts/package.sh` builds True.app in the worktree, commits on
the builder branch. App NOT launched/quit/killed (the orchestrating session runs inside True). No merge.

**Run 7 notes (as built):** `truectl status` text prints hub lines only for non-seat rows (seats are already
listed above); `truectl status --json` prints the raw reply including `hub`. Helpers are refused for
`spawn`. `ControlResponse` gained `hub` and `builderID`. `systemRunner` (real builder launch) is only
exercised through injected runners in tests; HubPanel is not visually verified (app not launched).

**Crew tab (as built, 2026-09-30):** the Hub picker is **All / Seats / Crew** (`HubFilter` replaces `seatsOnly`; `HubModel` still takes `seatsOnly: filter == .seats`). Crew = Claude Code sub-agent files (`*.md` + YAML frontmatter), never called seats. Sources: `<project root>/.claude/agents` (root via `HubProject.key`, only when a `.git` exists) and `~/.claude/agents`; a global with the same `name` as a project one is hidden. Project crew groups by job family (Lead, Engineering, Design, Security, Knowledge, Other) after stripping the repo prefix; global groups by name prefix when 3+ share it, else General, each a collapsed disclosure. Click stages `Use the <name> agent to ` (not submitted) via `PaneDelivery.write(.stage)` when the focused pane hosts Claude (awake seat, or `SessionSnapshot.probe(pane).found`), then re-focuses the pane; otherwise copies it and shows "Copied: no Claude pane focused" for 3 s (one-shot `Task.sleep`). Loading: one off-main scan via `.task(id:)` when the Crew tab is visible or the focused cwd changes; no watcher/timer; last result cached in `CrewStore`. Code: `Hub/CrewModel.swift`, `Hub/CrewDelivery.swift`, `Views/CrewView.swift`; tests `CrewTests.swift`. Not visually verified (app not launched).

**Results sheet (as built, 2026-09-30):** Hub menu > Show Results, ⇧⌘R (was free). Shows the final answer (**result**) of each of the last 20 turns of the focused pane's Claude session, newest first (newest expanded; others collapsed with relative time, prompt subtitle, first line; Copy = raw Markdown). Session id: awake seat's `lastSessionID` via `AgentRegistry`, else `SessionSnapshot.probe(pane).found`; transcript path from `AgentLaunch.transcriptURL` (the slug rule PaneResume uses). A turn = real user prompt to the next (skips `isMeta`, `tool_result` users, sidechain, compact/api-error entries); result = text after the turn's last `tool_use`, else the last text block; turns without text are skipped. `ResultsLoader` reads the file tail in doubling 1 MB windows off-main until 20 results, one load per sheet open, no watcher/timer. Markdown: own block renderer (`MarkdownBlock`), inline via `AttributedString(markdown:)`. **Show in Terminal**: probe = first ~40 chars of the answer, Markdown stripped; searched in `getBufferAsData(kind: .normal)` rows (scrollback + screen), rows joined so wrapped lines match, last occurrence wins; found = sheet closes, `scrollTo(row:)` puts it near the top, the matched rows are selected (selection = highlight), pane re-focused; not found = inline "Not in this pane's scrollback anymore". Nothing is written to the PTY. Code: `Results/*.swift`, `Views/ResultsSheet.swift`; tests `ResultsTests.swift`. Not visually verified (app not launched).

## Run 8 — Hub design pass (monochrome + one colour)
**Goal (Yahia, 2026-09-30):** Hub on par with Apple-level design, keeping the minimal black-and-white look, with a pop of vibrant colour for agent profile pictures.

**Doctrine:** True is black & white. Colour exists in exactly ONE place — agent avatars — and it means *identity*, never state. Model tier stays brightness (`AgentModel.tint`); status stays monochrome (the presence dot + word carry it).
**Amended 2026-10-06:** the doctrine governs True's own chrome. Terminal *output* keeps the colours programs paint (Terminal.app palette, no desaturation) — Yahia could not tell Claude working from done with the orange spinner greyed out. Settings ▸ "Colour in terminals" (`terminal.color`, default on) brings back the grey ladder + desaturation filter.

**As built**
- `Views/AgentAvatar.swift`: `AgentHue` (10 hue-adjacent gradients; FNV-1a 32-bit of the name mod 10 when unset, never `hashValue`), `AgentAvatar` (gradient disc + specular + glass edge + glyph; asleep = desaturated/dim, working = breathing glow (static under Reduce Motion), needsYou = glow + white ring; presence dot; optional parent ring). Other sessions get a grey disc.
- `Agent.hue: String?` (optional, old JSON decodes); Agent Builder gets a Colour row (10 swatches) and a 56 pt live preview.
- Hub: header without divider, seat card is the only container (radius 14), attention pill only for needsYou/failed, hover/context-menu/VoiceOver actions, iMessage-style message capsule, lighter 44 pt Background/Other rows, 340 pt wide. `HubPanel` (store-bound) → `HubPanelContent` (pure view) + `SeatActions` closures seam so it renders from fixtures.
- Snapshot harness `Tests/TrueTests/HubSnapshotTests.swift` (skipped unless `TRUE_SNAPSHOT_DIR`); PNGs in `docs/design/hub-v2/`.

**Deviations:** ringed avatars keep the same outer footprint (the disc shrinks 8 pt inside the ring) so a column of rows stays aligned; "New Agent" empty-state button is a custom white capsule (`.borderedProminent` dims in a non-key window); XCTest is unavailable with the CLT toolchain so the harness uses swift-testing with `.enabled(if:)`.

**Snapshots cannot show:** hover reveal, the breathing animation, row insert/remove transitions, real Liquid Glass; the message capsule shows faint edge ticks from the offscreen text field (not seen as a design issue, unverified live).

## Run 9 — work-gated KeepAwake
**Goal (Yahia, 2026-09-30):** the Mac may sleep when work is done; if agents are running they must also be idle to confirm idle. Replaces "screen stays on for as long as True is open" (Run 7 KeepAwake): the `PreventUserIdleDisplaySleep` assertion (reason "True: agents working") is now held only while work is happening.

**What counts as work** (`Model/IdleGate.swift`, pure; pids are RE-PROBED at evaluation time, never trusted from scan time):
- a peer session whose file says `busy` and whose pid is alive (seats in True's panes, interactive Claude sessions anywhere, helpers);
- a builder in state `running` whose claude pid is alive (pid 0 = launch in progress = busy);
- an awake seat with status `.working` whose last hook event is under 20 min old (older = stale, the stop hook never fired; a genuinely long tool call is still covered by the first rule because the Claude CLI keeps its session file busy).

**What does not:** `.needsYou` (waiting on the human), idle/done/failed/asleep, dead pids, and plain shell commands in panes — a `tail -f`, ssh or htop would pin the Mac awake forever, so they are deliberately excluded.

**Controller** (`Model/WorkAwake.swift`, backend behind `PowerAssertion`; `KeepAwake` is the real IOPM one): busy → hold immediately. Idle → release only after a 120 s grace of CONTINUOUS idle; any busy verdict inside it cancels (covers a lead finishing before its builder starts, and claude-burn's relaunch gap). Event-driven: `withObservationTracking` on `HubStore.peers/builders` and `AgentRegistry.status/latest/panes`. Only while held (or in grace) a repeating 60 s tick runs `HubStore.reload()` then re-evaluates, to catch processes that died with no file event; it is cancelled on release, so idle costs 0%. os.Logger `True`/`keepawake` logs each hold/release with reasons. Quitting True still drops the assertion (kernel).

**Verify live:** `pmset -g assertions | grep "True: agents working"` — present while something works, gone ~2 min after everything is idle.

**Asleep avatars:** fade to 10% saturation (in the gradient colours, not `.saturation()`, which ImageRenderer ignores) at 0.55 opacity — near grey, no brown.

## Run 10 — Hub pop-up (as built, 2026-10-01; approved by Yahia)
The Hub is a **centered pop-up over the terminal**, not a side panel: the terminal never resizes. `HubOverlay` = near-clear black scrim (takes the click that closes it) + a 600 pt card (`HubPanelContent.width`) at 80% of window height (`heightShare`, capped), radius 18, `.glassEffect(.regular.tint(.black.opacity(0.7)))` so text reads over busy output; the list scrolls inside. Closed, the overlay passes every click to the terminal.
- **Open/close:** ⌘E (menu item reads "Show Hub" / "Hide Hub"); scrim click or **Esc** closes. Esc is consumed in `TrueTerminalView`'s key monitor while the Hub is open, so it never reaches Claude Code (where it interrupts a turn). Waking/focusing a seat or a crew pick that typed its starter closes it; "Copied" keeps it open so the notice shows.
- **Header:** one row, "Hub" title + live one-line summary across every project; segmented filter **All / Agents / Crew** (UI says "Agents"; code keeps `HubFilter.seats`); New Agent and Close buttons.
- **Crew:** display names drop the repo prefix (`true-cto` -> "CTO"; `CrewDisplay.name`), the starter prompt keeps the real id (Claude routes by it); global crew sits under "All projects", collapsed teams; avatars use the name-derived hue, faded as asleep; nothing outside the avatar is coloured. Copy fallback reads "Copied. Paste it into a Claude pane."
- **Type/contrast:** `Theme.hubSecondary` 0.82 white (>=7:1 over the tinted glass); seat card avatar 44 pt, rows 52 pt with 32 pt avatars; sections are a quiet header + one soft card (`hubCardFill` 0.05 / `hubCardStroke` 0.08, radius 14).
- Snapshots: `HubSnapshotTests` (skipped unless `TRUE_SNAPSHOT_DIR`); approved PNGs in `docs/design/hub-v4/` (hub-glass, then hub-v3, are the earlier rounds, kept for the record).

## Run 11 — burn control in panes (2026-10-01)
- **Stable token per pane:** every pane's env gets `BURN_WRAPPER_TOKEN=true-<first 8 of pane UUID>` (`EmbeddedTerminal.burnToken`) and inherited `BURN_*` is dropped. Pane ids survive restore, so `claude-burn` in a restored pane keeps its `HANDOFF-<token>.md` instead of orphaning it under a fresh pid token.
- **Seats launch through claude-burn:** `AgentLaunch.shellCommand` execs `~/.claude/bin/claude-burn` when executable, else plain `claude` (claude-burn keeps --settings/--name/--model/--effort/--permission-mode/role file on relaunch; drops --resume and the prompt).
- **Sleep signals the process group** (`kill(-pid, …)`, pid fallback): the pane pid is the launcher and claude is its child in the same group.
- Hook side (outside this repo, `~/.claude/hooks`): handoff path = claude-burn's launch dir from `state/live-<token>`, not the session's drifting cwd; `lib/bg-pending.py` retires a background task stopped with TaskStop (no notification is ever sent for it).

## Panes and layout
- **Even tiling only.** Every add (split), close or drop re-evens the same-axis row/column it touched (1/2, then 1/3 each…); a stacked pair counts as one slot. Other rows keep their sizes; manual divider drags persist until the next add/close/drop in that row. No preset-layout menu.
- **Pick up:** hovering the top-centre of a pane (only when the tab has 2+ panes) shows a small grip. Only the grip's own rect takes the mouse — terminal clicks, selection and scrolling are never intercepted. Detach = within this window and tab only.
- **Drop:** onto another pane — its left/right/top/bottom zone moves the pane to that side; the middle zone swaps the two. A shaded preview shows the exact landing zone; Esc or dropping outside cancels. No animated reflow (terminals would be resized every frame).
- **Survival:** terminals are keyed by pane UUID in one flat list (`TerminalArea`), so a move only changes frames: process, scrollback and focus stay (the mover is focused). Ops: `SplitTree.insertingEvened / removingEvened / swapping / moving` (`Model/SplitTree.swift`), drop geometry in `Model/PaneDrop.swift`, grip UI in `Views/PaneDrag.swift`.

## Run 12 — The Overseer (Jev reads every finished turn)
**One sentence:** each time Claude in a True pane ends a turn, Jev reads what was asked, which tools ran and what
Claude answered, and True shows a **verdict** on the tab and in the Hub, listing the panes that need you first.
**Read-only:** the Overseer never types into a pane. Autopilot (Run 13, not built here) will act on
`asks to continue`; Run 12 already computes and logs the judgment Autopilot will need, so its thresholds can be
calibrated on real data first.

**Verdicts (one name each, UI labels in quotes):** `verified` "Verified" · `unverified` "Unverified" ·
`partial` "Partial" · `asksToContinue` "Asks to continue" · `asksYou` "Asks you" · `blocked` "Blocked".
No verdict = nothing shown (today's behaviour).

**Scope:** Claude sessions running in True panes (seats and plain ⌘O / ⌘↩ panes) — the only sessions whose
hooks report to True. Not background builders, not sessions in other terminals.

**Hard-rule check:** event-driven — one Jev call per Stop event, nothing on a timer. Jev slow / down / keyless →
no verdict, everything as before. Settings toggle off → no calls at all.

1. **Forwarder** (`Agents/AgentHooks.swift`): the Stop wire line adds `transcript` (payload `transcript_path`) and
   `session` (payload `session_id`) when they are non-empty strings; other events unchanged. `PaneEvent` gains
   optional `transcript` and `session` (old lines still parse). The forwarder file is rewritten when stale and read
   fresh on every hook call, so running sessions pick it up after True's next launch.
2. **TurnDigest** (`Overseer/TurnDigest.swift`, pure): read the transcript from its END (reuse the chunked
   approach in `Results/ResultsLoader.swift`; grow the window until the last real user prompt is inside, cap 8 MB)
   and build the LAST turn:
   - `asked`: the turn's prompt (same rules as `TranscriptParser.promptText`; skip isMeta / sidechain /
     compact-summary / API-error lines), first 1,500 chars.
   - `steps`: tool calls in order, each `{n, tool, what, result, failed}`. `tool`/`what` from
     `ToolSummary.summarize` on the tool_use input's string values; `result` = the matching tool_result
     (paired by `tool_use_id`) text, whitespace-collapsed, last 240 chars; `failed` = `is_error == true`.
     Keep the last 30 steps.
   - `edited` (code fact): any Edit / Write / MultiEdit / NotebookEdit step in the turn.
   - `answer`: the Stop event's message (else the digest's final text). Over 3,000 chars → first 800 + " … " +
     last 2,200.
   - `Redact.secrets` runs on asked / steps / answer before anything leaves the process: `sk-…` / `sk-ant-…`,
     `ghp_` / `gho_` / `github_pat_`, `AKIA…`, `xox[bp]-…`, `Bearer <token>`, PEM private-key blocks, and
     `NAME=value` where NAME contains KEY / TOKEN / SECRET / PASSWORD → `[redacted]`.
3. **Questions** (`Overseer/OverseerJudge.swift`, pure; ONE `JevClient.ask`, 8 s timeout, state =
   `{asked, steps, edited, answer}`):
   - `outcome` choice:
     `finished` — `answer` says the work asked for in `asked` is complete ·
     `partial` — some of the asked work is done and `answer` names work still left, or it stopped midway ·
     `asks_to_continue` — `answer` ends by offering or asking to carry on with the next step of the same task ·
     `asks_you` — `answer` needs something only the user can give: a choice between options, missing
     information, credentials, or approval for something outside the task ·
     `blocked` — `answer` reports an error or obstacle it could not get past ·
     `answered` — `asked` was a question or conversation, not work, and `answer` replies to it ·
     `none` — none of these fit.
   - `proof` noul: "Does `steps` show a check that ran successfully after the work it checks — tests or a build
     that passed, a command whose output confirms the result, an HTTP or live check — supporting what `answer`
     says was done?"
   - `contradiction` noul: "Does any `result` in `steps` show a failure — a failing test, an error, a non-zero
     exit — that `answer` does not mention?"
   - `next_safe` noul (shadow: logged, never acted on in Run 12): "Would the next step that `answer` proposes stay
     inside the task in `asked` and be easy to undo, touching only local files and local commands?"
4. **Verdict mapping** (code; policy next to the numbers, all constants in one place):
   - outcome confidence < 0.5 → no verdict.
   - `finished`: contradiction ≥ 0.7 → `unverified` (reason names the last failed step's `what`); else no steps and
     not `edited` → no verdict; else proof ≥ 0.7 → `verified`; proof ≤ 0.35 → `unverified`; between → no verdict.
   - `partial` / `asks_to_continue` / `asks_you` / `blocked` → that verdict. `answered` / `none` → no verdict.
   - Reason lines are code-composed, never Jev text (e.g. "Says done; no check ran", "A step failed that the
     answer doesn't mention: <what>", "Stopped with work left", "Wants to carry on", "Waiting on your answer",
     "Hit an error").
   - Urgency (code): blocked 0 · asksYou 1 · unverified 2 · asksToContinue 3 · partial 4 · verified 5; ties newest first.
5. **OverseerStore** (`Overseer/OverseerStore.swift`, `@Observable @MainActor`, fed from the same event tap as
   `AgentRegistry.shared.handle` in `TrueApp.swift`): `verdicts: [UUID: OverseerVerdict]` (pane → verdict, reason,
   at, sessionID, cwd). On `.stop` with a transcript: bump that pane's turn token, digest off-main, ask Jev, store
   only if the token still matches. A pane's next `.progress` "prompt" event, or pane close, clears its verdict.
   `.error` events are not judged. At most one call per pane in flight; at most 6 overall (over that: skip + log).
   Settings: "Overseer" toggle (default on; key in `Settings/TerminalSettings.swift` style); off clears verdicts.
6. **UI** (HIG, monochrome + one colour as in Run 8; Unverified uses one warm orange token, Blocked / Asks you reuse
   the existing needs-you colour, the rest are neutral):
   - **Hub "Your move"** section at the top of the card (All filter only), shown when any non-Verified verdict
     exists: one row per pane ordered by urgency — name (seat name, else the tab title), project title, verdict
     label + reason, age. Click → focus that pane and close the Hub (same path as waking a seat).
   - **Badges:** seat cards and Other-session rows (matched by session id) show a small verdict capsule beside the
     status pill.
   - **Tab dot:** a pane verdict of Unverified tints the tab's dot orange; Blocked / Asks you use the needs-you
     colour; the dot's tooltip reads the verdict label + reason.
   - Extend `HubSnapshotTests` with a fixture that has one of each verdict; save PNGs to `docs/design/overseer/`.
7. **truectl status:** `HubRow` gains optional `verdict` (raw value) for seat and other rows.
8. **Logging:** os.Logger subsystem `net.prismlens.true`, category `overseer`, one line per judgment (pane prefix,
   outcome + confidence, proof, contradiction, next_safe, verdict, ms, state chars). File
   `~/.true/overseer/verdicts.jsonl` (dir 0700, file 0600): at, pane, session, cwd, verdict, every answer with its
   probabilities, latencyMs, and the redacted state — the calibration set for these thresholds and for Run 13.
   Over 5 MB → rename to `verdicts.1.jsonl` (keep one).
9. **Tests** (injected transport / key provider, no network, no Keychain): TurnDigest on synthetic JSONL (tail
   starting mid-turn, tool_use ↔ tool_result pairing, is_error, sidechain lines ignored, empty answer, 30-step cap);
   redaction; question JSON shape; the full mapping table (every outcome, the 0.5 floor, the 0.7 / 0.35 edges,
   contradiction override, no-steps rule); store (stop → verdict, new prompt clears, late reply dropped, toggle off
   makes no call, Jev nil → no verdict, per-pane in-flight guard); urgency ordering; HubRow encoding; forwarder
   adds `transcript` / `session` on Stop only. `OverseerLiveTests` gated by `JEV_LIVE=1`: at least 3 hand-labelled
   synthetic turns per category (verified, unverified-no-check, unverified-contradiction, partial,
   asks_to_continue, asks_you, blocked, answered), labels written BEFORE any run, printing a table of label vs
   verdict + probabilities.

**Run 12 done =** `swift build` clean with no new warnings, all tests green (paste the output), `scripts/package.sh`
produced `True.app`, commits on the branch. App NOT launched; JEV_LIVE suite NOT run.

## Run 14 — The Command bar (⌘K: one box, Jev routes it)
(Run 13 is reserved for Autopilot. This run moves "Smart input" out of "Later (not v1)"; Yahia approved 2026-10-06.)

**One sentence:** press ⌘K, type what you want in plain words or as a command; True shows where it will go
(shell / Claude / a True action, which project, which agent, which model + effort) and Return sends it there.

**Doctrine:** Jev decides, code acts, Claude writes. Jev only SELECTS from candidates code built (projects,
seats, verbs); code lifts names and values. Nothing ever runs on a keystroke: the user always sees the route and
presses Return. Jev slow/down/keyless = the bar still works with deterministic rules and a manual route picker.
Idle ≈ 0%: no work at all while the bar is closed.

1. **UI** (`Views/CommandBar.swift`): a centered glass card like `HubOverlay` (same scrim, Esc consumed in
   `TrueTerminalView`'s key monitor so it never reaches Claude), ~640 pt wide, near the top third. One text field,
   below it ONE **route line**: `→ Claude · prism · new pane · sonnet · medium` (chips; clicking a chip cycles or
   opens a small picker for that slot). Return = run. ⌘Return = run in the background (builder) when the kind is
   agent work. Tab = swap to the runner-up route. ↑/↓ = history (last 50, `~/.true/commandbar/history.json`, 0600).
   Under the route line, up to 3 alternative routes when confidence is below the floor.
2. **Deterministic first** (`CommandBar/CommandRules.swift`, pure; when a rule matches, Jev is asked ONLY the
   `destructive` noul — a `!`/`$` prefix picks the door, it never skips the danger gate, e.g.
   `! cd ~/Prism && supabase db push --include-all`):
   `$ <cmd>` or `! <cmd>` = shell · `> <text>` = Claude in the focused/obvious pane · `@<name> <text>` = that seat
   (`CrewDisplay`-style lookup) · `/<project> <text>` = Claude in that project (ProjectMatcher top hit) ·
   the first word being an executable on `$PATH` or a shell builtin with no natural-language tail = shell
   (Jev still asked, rule wins only when the bar is offline). Exact action names ("new tab", "split right", "show
   hub", "results", "fill all displays") = that action.
3. **Jev read** (`CommandBar/CommandRouter.swift`; one `JevClient.ask`, 3 s timeout, fired 300 ms after typing
   pauses while open, previous call cancelled; state = `{ text, focused: {kind: shell|claude|seat|empty, project,
   seat}, projects: [top 8 from ProjectMatcher.rank(query: text) + recents], seats: [name, project, awake] }`):
   - `kind` choice: shell_command / agent_task / question_for_claude / true_action / none.
   - `project` choice: each candidate id + `current` + `none` (criteria = name + path; code maps the id back).
   - `target` choice: focused_pane / new_claude_pane / seat_<name> (only seats in the picked or current project) /
     background_builder.
   - `action` choice over a fixed verb list (open_project, new_tab, split_right, split_down, show_hub, show_results,
     wake_seat, sleep_seat, fill_displays, none). Verbs needing an argument get it lifted by code (seat via name
     lookup, project via ProjectMatcher), never written by Jev.
   - `model` choice and `effort` score: reuse `JevFill`'s exact questions and floors (one source; extract them).
   - `destructive` noul: "Does `text` delete data, force-push, deploy, publish, send messages or write to a live
     third-party service?"
   Confidence floor 0.6 per slot (`CommandRouter.floor`); a slot below it shows the deterministic default with a
   dim "?" chip. `kind` below 0.5 → show two big choices "Run in shell" / "Send to Claude", no default.
4. **Execution doors** (`CommandBar/CommandExecutor.swift`, only existing doors):
   - shell → typed into the focused pane if it is a plain shell, else a new split beside it in that project's cwd;
     typed, NOT auto-submitted when `destructive` ≥ 0.5 or a rule-matched dangerous pattern (`rm -rf`,
     `git push --force`, `sudo`, `DROP`) — the user presses Return in the pane.
   - agent / question → focused Claude pane or awake seat via `PaneDelivery.write`; asleep seat → wake then
     deliver (existing summon path); new pane → the ⌘O path (`claude --dangerously-skip-permissions --model m
     --effort e '<text>'`, through claude-burn as seats do); background → `BuilderSpawn` with model, name derived
     from the text (slug, validated by `isValidName`). Model/effort only apply where a NEW process starts; for an
     existing pane the chips show "current" and are disabled.
   - `destructive` ≥ 0.5 on agent work: route line turns orange "will ask first" and Return needs a second Return.
   - true_action → the same functions the menu items call (no duplicated logic).
5. **Learning log** (`~/.true/commandbar/routes.jsonl`, dir 0700, file 0600, rotate at 5 MB keep one): text
   (redacted with the Overseer redactor), Jev answers + probabilities + latency, the route shown, the route
   actually RUN (after chip edits / Tab), and whether the user cancelled. Chip edits are free labels: this is the
   calibration set for the floors. os.Logger category `commandbar`, one line per read and per run.
6. **Menu + settings:** Window/Terminal menu "Command Bar…" ⌘K (check ⌘K is free; Terminal "clear" users can still
   use ⌘⇧K if we add it, don't). Settings toggle "Jev routing" (off = rules + manual picker only).
7. **Tests** (injected transport, no network): every rule; question JSON shape; slot mapping incl. floors and
   unknown ids; project/seat id ↔ candidate round trip; executor decisions as a pure `Plan` value (door, argv,
   autoSubmit) for each kind × focused-pane kind, destructive gating, model flags only for new processes;
   history + log encoding; bar closed = zero Jev calls; cancelled in-flight read never applies.
   `CommandBarLiveTests` (`JEV_LIVE=1`) reads `Tests/TrueTests/Fixtures/commandbar-labelled.json`: 39 utterances
   hand-labelled BEFORE any run (31 verbatim from Yahia's `~/.claude/history.jsonl`, 8 spec phrasings), each with
   the focused pane it was typed in, fixed project/seat candidates, and scoring rules in its `_readme`. The file is
   FIXED: never edit a label; report disagreements. Prints label vs route + probabilities and per-slot accuracy;
   no accuracy assertion until the floors are calibrated from `routes.jsonl`. The offline tests reuse the same
   file for the rule cases (`!`/`$` lines, exact action names) and the fixture-decoding test.
   Snapshot fixtures in `docs/design/commandbar/` (confident route, low-confidence choices, destructive state);
   v1 passes /taste.

**Run 14 done =** `swift build` clean with no new warnings, all tests green (paste the output), `scripts/package.sh`
produced `True.app`, commits on the branch. App NOT launched; JEV_LIVE suite NOT run.
