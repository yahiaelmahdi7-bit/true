# Conventions
Owner: cto · Last verified: 2026-09-30

## Gates (exact commands)
```
swift build
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
nice -n 10 swift test -j 4 -Xswiftc -F$FW -Xlinker -F$FW -Xlinker -rpath -Xlinker $FW -Xlinker -rpath -Xlinker $LIB
scripts/package.sh [debug|release]
```
[source: SPEC.md:33-38; scripts/package.sh]. "Done" = build clean, tests green with output pasted, package.sh produced True.app, app NOT launched.

## Branch, commit & deploy rules
No deploy (local app). Builders work on `builder/<name>-<ts>` worktree branches; never push/merge from a builder. Commits are atomic, imperative-style subjects, Co-Authored-By trailer. [source: git log; dispatch brief]

## Code style
Swift 6 strict concurrency; keep the actor-isolation flag on both targets. Lifted Axon code keeps its incident comments; any launch-time side effect carries a justifying comment. [source: SPEC.md Hard rules]

## Testing
XCTest in `Tests/TrueTests` (pure logic; injected transports/runners; fixtures in `Fixtures/`). `JevLiveTests` only run with `JEV_LIVE=1`. [source: SPEC.md Run 6]

## Concurrency (worktrees)
Other sessions edit the main checkout live: work in a worktree, never touch the main checkout. Don't touch `.claude/HANDOFF*.md` (gitignored). [source: task brief; .gitignore]
