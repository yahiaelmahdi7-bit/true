# True lag fix — main-thread blocking + disk-write storm

Yahia: "True is very laggy." Measured 2026-10-10 on the running app (pid 48037, `sample` 3 s, macOS diag report):

## Evidence
- **Main thread blocked by the Watcher.** In a 3 s sample the main thread spent 911 of 2226 samples (~41%) inside
  `WatcherStore.checkStuck()`. Of those, 463 were in `WatcherStore.checkDone(builders:)` and 392 in
  `GitSignals.systemRunner`, which launches `git` and WAITS on the main thread. It's triggered from
  `TrueApp.swift:151` (`Task { @MainActor in WatcherStore.shared.checkStuck() }`) and `Model/WorkAwake.swift:52`.
  `WatcherStore.swift:29-31` injects `Investigation.systemRunner`, `BuilderSpawn.systemRunner` and
  `GitSignals.systemRunner`.
- **Disk-write storm.** macOS diag `/Library/Logs/DiagnosticReports/True_2026-10-10-200239_*.diag`: 2.15 GB of file
  writes in 3570 s (602 KB/s; limit 24.86 KB/s). Files written in the last 10 min: `~/.true/overseer/verdicts.jsonl`
  (3.2 MB), `~/.true/agents/watcher/decisions.jsonl` (3.1 MB), `~/.true/agents/watcher/inbox.jsonl` (1.8 MB).
  `Duty/Inbox.swift:192` rewrites the whole inbox atomically on every change. Check `OverseerLog.swift` and
  `WatcherStore.swift:76/412` for the same whole-file rewrite pattern. AppKit `NSPersistentUIManager flushAllChanges`
  (state restoration) also writes repeatedly; find what dirties window state so often.
- **Memory:** physical footprint 1.0 GB, peak 2.1 GB. Swap on this Mac is 5.4 of 6 GB used, so any bloat hurts everything.
- Also seen: `TerminalView.draw` at ~390 samples. That's normal rendering; only touch it if you find waste.

## Fix (in this order, measuring each)
1. **Nothing slow runs on the main thread.** Move `checkStuck` / `checkDone` / every `Process`, git and file scan they
   reach onto a background actor or `Task.detached`, and publish only results to the main actor. Audit every periodic
   timer and `Task { @MainActor … }` in `TrueApp.swift`, `WorkAwake`, the Hub, `GitSignals`, `Investigation`,
   `BuilderSpawn` and the Overseer for synchronous `Process`/`waitUntilExit`/large file reads on main. Add
   `dispatchPrecondition(condition: .notOnQueue(.main))` (DEBUG) inside each `systemRunner` so a regression fails loudly
   in tests. Don't run overlapping checks: if one is still running, skip that tick.
2. **Append, don't rewrite.** JSONL logs append with a `FileHandle` (seekToEnd + write). Whole-file rewrites happen only
   on compaction. Cap and rotate each JSONL (e.g. 1 MB → `.1`, keep 2). Inbox state changes go to an append-only log or
   a small index, not a full rewrite per change. Keep 0600 perms. Keep reads compatible with existing files.
3. **State restoration churn:** find what invalidates restorable state every few seconds (window title, frame,
   `@SceneStorage`, `invalidateRestorableState`) and stop updating it when nothing changed.
4. **Memory:** measure what holds the 1 GB (scrollback limits, Shots/thumbnail caches, web server buffers, Overseer
   history in memory). Bound any unbounded cache. Report before/after numbers from a test or a heap count, not guesses.

## Tests (write first, paste the failing run, then fix)
- With a fake git runner that sleeps 300 ms, `checkStuck()` returns to the main actor in < 10 ms, and the main actor
  stays responsive (a main-actor ping completes in < 20 ms while the check runs).
- Calling a `systemRunner` from main trips the DEBUG precondition. Run it via a helper, without crashing the suite.
- Appending N=1000 records to each JSONL writes O(record) bytes per append (measure the file-size delta and the
  write count), and rotation triggers at the cap.
- Inbox changes don't rewrite the whole file.

## Rules
- Branch/worktree only; never commit to main; never launch or quit True.app (Yahia's running copy stays untouched).
- Never weaken an existing test.
- Another builder (Nova) is editing `Sources/True/Nova/*`, `TrueApp.swift` (2 lines), `Views/SettingsView.swift` and
  `Views/TabBar.swift` on another branch. Keep your edits to `TrueApp.swift` minimal to avoid merge conflicts.
- Gate (docs/kb/conventions.md): `swift build` · `nice -n 10 swift test -j 4` with the FW/LIB flags ·
  `scripts/package.sh debug`. Paste the tails.
- Report: each cause with its fix, test names, fail-before/pass-after, before/after numbers (main-thread time per
  check, bytes written per append, memory), and what is unverified live.
