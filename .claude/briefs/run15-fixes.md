# Brief: True Run 15 — fix round (security + spec conformance)

You built the Watcher on this branch. Two read-only reviews found holes. The full findings, with file:line, inputs and
suggested fixes, are in /Users/y/Projects/true/.claude/briefs/run15-review-findings.md — read it first, whole.
Spec = SPEC.md lines 481-650 (source of truth). One extra commit already on the branch: dcfd030 (hook runs under `node`).

## Order (security first — the merge is BLOCKED until S1-S4 are fixed; if budget runs short, stop after a group, commit)
1. S1-S6 (P1). S1: the deny-list must run on the EXACT brief string written to `fix.md` (fix + evidence + files) right
   before `builder start`; refuse on any hit. Also screen investigate's text with evidence quote/path/what/cause/title.
2. S7, S8, S12. Normalise before matching: join backslash-newlines, strip invisible chars (extend the set per S7), NFKC,
   then match case-insensitively. Keep the deny-list a pure function with one entry point used by investigate AND approve.
3. S11: run `~/.local/bin/claude --help` and drop any argv flag it does not list (an unknown flag would make every
   investigation fail). Add Read(**/credentials*) and Read(~/.aws/**) to the settings deny. For ask_file's path reach:
   check whether /Users/y/Projects/jev-tools (bin/jev-files-mcp, files/) supports a root limit; use it if so. Do NOT edit
   jev-tools; if no limit exists, say so in the report.
4. D1-D10 (spec gaps), D12 memory.md heading "Yahia told me" + the missing triggers (HubStore builder change, wake).
   D1 card must render with the inbox empty. D2 digest must be visible in the Hub, pinned until opened.
5. Tests: one per S-finding using the exact bypass input from the findings (each must fail on the old code), plus tests
   for D3 throttle, D5 done-in-code, D8 fixUSD ledger, D9 reject decision, D10 Jev-nil no investigation.
Skip S9 and S10 (spec decisions; leave as is).

## Gate (exact; plain `swift test` fails with "no such module Testing")
```
swift build
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
nice -n 10 swift test -j 4 -Xswiftc -F$FW -Xlinker -F$FW -Xlinker -rpath -Xlinker $FW -Xlinker -rpath -Xlinker $LIB
scripts/package.sh
```

## Rules
- Commit on this branch only. Never push, merge, launch True.app, or touch real ~/.true / ~/.claude files (temp dirs in tests).
- Do not edit SPEC.md or Tests/TrueTests/Fixtures/watcher-labelled.json. Where the spec is ambiguous, pick the strictest
  reading and list it in the report.
- Do not run WatcherLiveTests with JEV_LIVE=1.

## Final report
A table: finding id -> fixed? -> how (file:line) -> test name. Then gate output (test count, pass/fail), commits, and a
"Not verified" list. Plain English, no preamble.
