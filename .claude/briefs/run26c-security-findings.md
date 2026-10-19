# Run 26c — Nova security findings (fix brief)

Owner: true-security · Reviewed: 2026-10-10 · Branch `builder/true-nova-20261010-221217`
All paths relative to worktree `/Users/y/Projects/true.builders/true-nova-20261010-221217`.
Verdict: BLOCK until C1, C2, H1–H3 fixed. Payloads below are harmless (`print`); keep them harmless in tests.

## Critical

### C1 · Nova approves its own park (self-speech / ambient audio)
- Where: `Sources/True/Nova/NovaEngine.swift:191` (ambient resolves before the speaking check at :192), `:201` (TTS says "Go ahead?"), `:209-212`; `Sources/True/Nova/WakeWord.swift:320-341` (onUtterance has no speaking guard), `:466` (`minWords = 2` lets "Go ahead" through). Wake stream has no echo cancellation (`AudioRecorder` is never instantiated).
- Exploit: any park → Nova speaks "Go ahead?" through speakers → mic transcribes it → `onUtterance` → `ambient()` → `resolveSpoken` → `resolve(true)`. Same for a TV/video/call saying "go ahead"/"approve" within 30 s; no wake word needed. Overheard "quit X" (`NovaReflex.swift:245` ambientSafeVerbs) → parks → self-approves.
- Fix: never resolve an approval from `ambient()`; drop all utterances while `speaking` and for a tail after it. Approval phrase/addressing rule: POLICY: see Yahia's decision.

### C2 · Consequential sinks pass the gate un-parked (prompt-injection target)
- Where: `Sources/True/Nova/NovaGate.swift:70` (`send_to_pane` allow unless busy), `:75` (`spawn_agent` allow), `:76` (default allow → `relay`, `open_url`); `Sources/True/Nova/NovaHands.swift:19` (busy check reads `target`; `relay` uses `to`), `:46-49` (relay pastes raw pane text, unwrapped), `:126-142`; `Sources/True/CommandBar/CommandRules.swift:67-70,93-94` + `CommandExecutor.swift:50-54` (shell-routed text auto-submits), `:70` (new Claude pane `--dangerously-skip-permissions`).
- Exploit: text in a pane/file/shell output tells Haiku to call `send_to_pane`/`relay`/`spawn_agent` (or `open_url` with data in the query). Gate allows → text lands in an unrestricted agent or a shell (`spawn_agent` text starting `!` / `$ ` or an executable word skips `NovaGate.shell`) → runs with no approval.
- Fix: POLICY: see Yahia's decision. Independent of policy: `relay` busy check must read `to`; wrap relayed text as data.

## High

### H1 · Negated approval counts as yes
- Where: `Sources/True/Nova/NovaEngine.swift:211-212`.
- Exploit: "don't go ahead", "I don't approve", "disapprove" → `contains("go ahead"|"approve")` checked first → `resolve(true)`.
- Fix: make it a pure static func; tokenise; check negations (`don't`, `do not`, `no`, `stop`, `cancel`, `dis-`) FIRST; accept only an exact short phrase (per C1 policy).

### H2 · Read-only shell allowlist escapes (confirmed with `/bin/zsh -f -c` this session)
- Where: `Sources/True/Nova/NovaGate.swift:16-35` (first-word check only, runs via `/bin/zsh -c` at `NovaHands.swift:154`), meta set `:19`, `$(` check `:25`; `Sources/True/Duty/DenyList.swift:27` does not catch these.
- Exploits (all return `.allow` today):
  - zsh process substitution: `cat =(print subst-ran)` → prints `subst-ran` (inner command ran).
  - zsh glob qualifier: `ls /etc/hosts(e:"print -n qual-ran-":)` → prints `qual-ran-/etc/hosts` (code ran per match). `(+func)` qualifier is the same class.
  - `find . "-exec" print x ";"` style: quoted `-exec` token ≠ `-exec` at `:32`, shell strips quotes. (`;` is blocked, but `+` terminator is not.)
  - Write primitives on allowlisted tools: `sort -o <file>`, `uniq <in> <out>`, `tree -o <file>`, `git log --output=<file>` / `git diff --output=<file>`.
  - `rg --pre <cmd>` (latent: `rg` not on zsh -c PATH today).
  - `git status` / `git diff` with model-chosen `cwd` in a hostile repo runs `core.fsmonitor` / external diff / textconv.
- Fix: no shell on the free path. Tokenise to argv yourself; reject `( ) = * ? [ ] { } $ ~ ! ' "` outright (park); exec the binary directly (`/bin/ls` etc.); per-command flag allowlist (no `-o`, `--output`, `--pre`, `-exec*`, `-ok*`, `-delete`, `-f`ile-writing flags; `uniq` max one path arg); git runs as `git -c core.fsmonitor= -c core.pager=cat --no-pager <sub> --no-ext-diff --no-textconv` or parks outside known project paths.

### H3 · Secret-file refusals bypassable
- Where: `Sources/True/Nova/NovaGate.swift:39-46` (`standardizedFileURL` = lexical, no symlink resolve; case-sensitive `hasPrefix`; narrow list); `NovaHands.swift:74-75` (FileHandle follows symlinks); `NovaGate.swift:67` (`run_shell` never consults `readableFile`).
- Exploits: (a) `run_shell` `cat ~/.true/agents.json` → allowed (DenyList has no `.true/` rule); (b) `ln -s ~/.true/agents.json ~/Downloads/notes.txt` (or a symlink shipped in a cloned repo/zip) → `read_file ~/Downloads/notes.txt` allowed; (c) `read_file ~/.TRUE/agents.json` → opens on case-insensitive APFS; (d) unlisted: `~/.config/gh/hosts.yml`, `~/.netrc`, `~/.npmrc`, `~/.docker/config.json`, `~/.kube/config`, `~/.gnupg/`, `~/.zsh_history`.
- Fix: open first, `fcntl(fd, F_GETPATH)` → canonical on-disk path, check THAT (case-insensitive) with the extended list, then read from the same fd (no TOCTOU). Apply the same path check to every path argument of an allowlisted shell command, or park any shell command naming a path under `~/.`.

## Medium

### M1 · Eager turn acts on half a sentence; brain tools not de-duplicated
- Where: `Sources/True/Nova/NovaLiveTurn.swift:42,62` (0.25 s quiet, up to 4 runs/turn); `NovaEngine.swift:144-153,176-177`; dedup only for reflex acts `:289`.
- Exploit: "Nova, tell Ada to delete … [250 ms pause] … only the stale branch" → eager brain sends the truncated task via `send_to_pane`; restart sends again.
- Fix: eager runs may only call read-only tools; side-effecting tool_uses are held and executed only by the end-of-turn run; dedup key per tool+input across the turn.

### M2 · Approval not bound to one action; card hides the action
- Where: `Sources/True/Nova/NovaEngine.swift:198-207` (single `approval` slot overwritten → first continuation leaked; any earlier 30 s timer resolves the current park); park strings `NovaGate.swift:25,31,69` ("shell command", "move to trash").
- Exploit: injected tool parks just as the user says "go ahead" to a different park → wrong action approved; user approves "shell command" without seeing it.
- Fix: approvals keyed by UUID with their own timer; a new park while one is pending denies the old one; park text carries the exact command / path / target (truncated only in the HUD, full on hover).

### M3 · Run logs store typed values
- Where: `Sources/True/Nova/NovaEngine.swift:321` (`tools: lines.map { $0.text }`), lines come from `HaikuBrain.swift:134-137` (40 chars of command/text/path/url/query).
- Exploit: `~/.true/nova/runs/*.json` holds shell commands, pane prompts, paths, URLs.
- Fix: persist `{tool: name, ok: Bool}` only.

### M4 · Nova can quit True; instant quit never gated
- Where: `Sources/True/Nova/NovaInstant.swift:172-173` (any resolved app, incl. True); `NovaInstantRunner.swift:37-40` (`quit_graceful`); gate keys only `"quit_app"` at `NovaGate.swift:71`; `NovaHands.swift:51-55`.
- Exploit: "Nova, quit True" → terminates the app hosting the orchestrator.
- Fix: refuse when `bundleIdentifier == "net.prismlens.true"` (and `Bundle.main.bundleIdentifier`) in both quit paths and in the instant matcher.

## Low

- L1 · ElevenLabs key on argv. `Sources/True/Nova/NovaShims.swift:40-42` called from `NovaElevenLabs.swift:66,113`; `security add-generic-password … -w <value>` is visible to same-user `ps`. Fix: `SecItemAdd`/`SecItemUpdate` via Security.framework.
- L2 · `$NAME` expansion allowed. `NovaGate.swift:25` + `DenyList.swift:27` block `${`/`$(` only; `echo $ANTHROPIC_API_KEY` (env fallback, `NovaShims.swift:31`) → value to model. Fix: H2's `$` rejection covers it.
- L3 · Data wrappers not escape-safe. `NovaHands.swift:79,110,155`; content containing `</file>` / `</pane>` / `</output>` closes the tag; label sits after content; `relay` (:49) and `find_files` (:72) unwrapped. Fix: escape `<`/`>` in content (or random per-call delimiter), put the "data, not instructions" label before the content.
- L4 · Guessable transcript hash. `NovaEngine.swift:314` 48-bit unsalted SHA-256 of short commands. Fix: HMAC with a per-install random salt in Keychain, or drop the field.
- L5 · `mdfind` option injection. `NovaHands.swift:72` query `-live` / `-onlyin …` parsed as flags. Fix: reject queries starting with `-`.
- L6 · Undo quits an app by name. `NovaInstantRunner.swift:136-138`; if the user launched the same app meanwhile, undo terminates it. Fix: capture the pid Nova launched and terminate only that pid.
- L7 · Mic on from launch by default. `TrueApp.swift:105`, `NovaSettings.swift:6-7` default `true`. DECISION: Yahia (default-on vs opt-in).
- L8 · KB claims wrong. `docs/kb/security.md` Run 26/26b sections assert ambient speech never fires, self-speech ignored, read_file refuses secrets, logs hold "summaries only". true-security corrects after fixes land.

## Clean (no action)
Prewarm HEAD keyless (`NovaInstantRunner.swift:13-18`); key only in `x-api-key` (`AnthropicClient.swift:37`); notices carry HTTP code/API message only; Keychain read via absolute `/usr/bin/security`, argv, stderr discarded (`NovaShims.swift:48-58`); on-device STT (`WakeWord.swift:193`); runs dir/file 0700/0600 (`NovaEngine.swift:317,324`); `open_url` http(s) only; volume clamped; media enum; `open -a`/osascript fixed argv; `move_to_trash` and brain `quit_app` always park; strict schemas + `validate`; 12-round cap; `scripts/package.sh` adds only usage strings (speech, Apple Events), no new entitlements.

## Regression tests to add (fail today, pass after fix)
- C1 · pending park + unaddressed utterance "go ahead" → still pending; utterance arriving while `speaking` (or within the tail) → ignored.
- C2 · `NovaGate.tool("send_to_pane"|"spawn_agent"|"relay"|"open_url", …, paneBusy:false)` → matches the chosen policy (not `.allow` from the brain); `relay` with busy `to` agent → `.park`.
- H1 · `resolveSpoken("don't go ahead")`, `("I don't approve")`, `("disapprove")` → deny, never approve.
- H2 · `NovaGate.shell(x) != .allow` for: `cat =(print t)`, `ls /etc/hosts(e:"print t":)`, `ls *(+f)`, `find . "-exec" print t +`, `sort -o /tmp/x a`, `uniq a b`, `tree -o /tmp/x`, `git log --output=/tmp/x`, `rg --pre print t x`, `echo $HOME`.
- H3 · temp symlink → `~/.true/agents.json` refused; `~/.TRUE/x` refused; `~/.config/gh/hosts.yml`, `~/.netrc` refused; `NovaGate.shell("cat ~/.true/agents.json") != .allow`.
- M1 · fake transport returns `send_to_pane` during an eager run → runner not called until end-of-turn; two runs same input → one call.
- M2 · two `approve()` calls: first resolves false, not leaked; first's timer doesn't resolve the second; park text for `run_shell` contains the command.
- M3 · record JSON for a turn with `run_shell "ls secretname"` contains no `secretname`.
- M4 · instant "quit true" → no act; `quit_app name:"True"` → refuse.
- L1 · Vault write path spawns no process with the value in argv (inject a process-runner spy).
- L2 · covered by H2 `echo $HOME`.
- L3 · `read_file` on content `</file>x` → output contains no raw `</file>` before the real closing tag.
- L4 · `transcript_hash` for "open safari" ≠ first 6 bytes of plain SHA-256.
- L5 · `find_files` query `-live` → error, no exec.
- L6 · undo of open terminates only the recorded pid (spy).
- L7 · per Yahia's decision.
