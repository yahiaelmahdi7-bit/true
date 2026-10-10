# Security
Owner: security · Last verified: 2026-09-30

## Data classification
Local personal state, no server, no cloud. Sensitive: terminal scrollback (`~/.true/scrollback/*.ans`, mode 0600), workspace/agents JSON, Jev API key, Overseer log `~/.true/overseer/verdicts.jsonl` (dir 0700, file 0600, secrets redacted before write, rotated at 5 MB keeping one old file). [source: SPEC.md Run 4, Run 6, Run 12]

## Threat model (assets, actors, entry points, top risks)
- Assets: Yahia's shell sessions, agent transcripts/permissions, API key.
- Actors: other local processes/users; malicious content reaching a pane. Remote actors: none identified. [assumption]
- Entry points: `agent-events.sock`, control socket (`truectl`), hook scripts in `~/.true/hooks`, drag-and-drop paths, Cleaner rewriting Claude memory files.
- Top risks: another local process writing to the sockets to spoof "needs you" or spawn builders; secrets in scrollback files; Cleaner rewriting memory (mitigated by backup + manifest + changed-since-read refusal [source: git log]).

## Secrets map
Jev key: env `TYPESAFE_API_KEY` or Keychain `net.prismlens.jev-cli`; never logged; cached in-process. Builder `*.key` files must never be read. No secrets in repo. [source: SPEC.md Run 6, Run 7]

## AuthN/AuthZ
None (local). `truectl spawn` validates name regex, prompt file existence, and repo under ~/Projects, ~/studio-builds or ~/Prism; helpers are refused `spawn`. [source: SPEC.md Run 7 + notes]. Socket permissions: Unknown — see index Open questions #8.

## Dependencies & supply chain
One dependency, SwiftTerm, pinned in Package.resolved. [source: Package.swift]. Unsafe flags in Package.swift (actor isolation).

## Open risks (ranked)
1. Socket access control unverified. 2. Scrollback at rest is plaintext (0600 only). 3. Signing cert is self-signed, not notarized. 4. Builder `--parent` edit touches shared live infra (backup exists at `~/.claude/bin/builder.bak-20260930-parent`). [source: SPEC.md]

- Command bar: `~/.true/commandbar/routes.jsonl`, `history.json` and `prompts/` hold what was typed: directory 0700, files 0600, text redacted before write, routes.jsonl rotated at 5 MB, history capped at 50. Shell text that is destructive or unjudged is typed, never submitted (SPEC Run 14).

## Incident steps
If a key leaks: rotate at TypeSafe, update Keychain item. If a runaway agent: `truectl status`, sleep the agent from the Hub/tab; never kill True.app from an agent. [assumption]

## Nova security (Run 26d) — fixes from the re-review of 0b3c9bc
Tests: `Tests/TrueTests/NovaSecurity26dTests.swift`, written first and run against the old code (23 failures) before the fixes.
- **P1 self-approval:** while the mic is gated (Nova speaking + 400 ms tail) the words heard are *consumed* (`NovaLiveTurn.ingest` moves the turn floor past them), so a "Nova" Nova said itself can never address a later command. The same applies to hotkey turns.
- **P2a control characters:** NUL and all U+0000–U+001F/U+007F are in the shell `forbidden` set (NUL refuses, other control characters park); the gate refuses any tool argument containing NUL; `NovaHands.exec` returns an error instead of calling `Process` with a NUL argument; `NovaPaths.check` refuses a NUL path.
- **P2b card shows cwd:** a parked shell card reads `run: <exact command>` and `in: <absolute resolved cwd>`; the approved run uses that same resolved folder.
- **P2c git:** free only when the resolved cwd is inside a known True project folder (roster repos, refreshed before each shell/file call); elsewhere it parks. In known folders git runs with `-c core.fsmonitor= -c log.showSignature=false -c diff.external= -c core.pager=cat -c core.hooksPath=/dev/null` and `--no-ext-diff --no-textconv`.
- **P3 git content:** free git is `status`, `branch`, `log` (no patch), `diff`/`show` only with `--stat`/`--name-only`/`--name-status`/`--shortstat`. `-p`/`--patch`, any argument containing `:` (`rev:path`) and bare `diff`/`show` park. Pathspecs go through `NovaPaths`.
- **P3 recursive search:** `rg` runs with `-g '!…'` globs for `.env*`, keys, `id_*`, `.ssh`, `.aws`, `.gnupg`. (`grep -r` is not in the allowlist.)
- **P3 hard links and hidden files:** `read_file` and shell path arguments park when the file has more than one hard link, or when any path component under home starts with "." (except `.claude` inside a known project). The explicit secret set (`~/.ssh`, keychains, `.env*`, `~/.true`…) stays a hard refuse and is checked first. `find_files` leaves hidden, hard-linked and protected results out and says how many.
- **P3 spoken yes:** approval needs the FINAL utterance (end of turn counts) and the card id that was showing when the utterance started; a yes after the card changed, or mid-sentence, is ignored. A no still works from any partial ("go ahead… no, wait" is no).
- **P3 de-dup:** a repeated action reports the stored outcome; a refusal or denial is never "already done".
- **Not done (by design):** the "nova token must come after the gate opened" check is carried by the consume-on-gate floor, not by segment timestamps.
- **Unverified live:** hidden/hard-link rules on the real filesystem and real home; the floor (word count) behaviour against the real recognizer when it restarts mid-turn; `find_files` omits rather than parks hidden results; git `-c` overrides are not exercised against a hostile repo.

## Nova security (Run 26c) — only what the code enforces
Tests: `Tests/TrueTests/NovaSecurityTests.swift`, one per finding ID.
- **Approval (C1/H1/M2):** a parked action is approved only by an *addressed* yes ("Nova, go ahead"/"Nova, approve"), a yes while the hotkey is held, or the HUD Approve button. A bare "go ahead" never approves; ambient speech can only say NO. Any negation ("don't", "no", "cancel", "stop", "disapprove"…) anywhere means NO. Each approval is bound to one parked action id; a new park denies the old one, a stale id or click is a no-op. The card shows the exact command, text or URL.
- **Mic during Nova's speech (C1):** all input is dropped while Nova speaks and for 400 ms after (only "stop" barges in). Voice processing (echo cancellation) is requested on the input node best-effort (`try?`); whether the OS grants it is NOT verified here.
- **Agent sends (C2):** every model-initiated `send_to_pane`, `relay`, `spawn_agent` and `open_url` parks (the only unparked send is the user-verbatim `tell` lane, Run 26e below) with the exact target and full text/URL. Only the instant lane's fixed known-site table opens URLs unparked (the user's own words, matched locally).
- **Shell (H2):** `run_shell` never goes through a shell on the free path. A strict tokenizer rejects any metacharacter (`$`, backtick, `;`, `&`, `|`, redirects, globs/qualifiers, `=(`, newline); allowlisted binaries run via `Process` with an argv array and an absolute path from a fixed table; per-command flag denylist; anything not provably read-only parks (git: see Run 26d), and an approved park runs `zsh -f -c` on the exact card text. `DenyList` is checked first.
- **Paths (H3):** one guard (`NovaPaths`) for `read_file`, `find_files` results and every path argument the shell allowlist passes: `realpath`, case-insensitive match against the refused set, refuse on doubt; `read_file` opens first then checks the descriptor's real path.
- **Eager end-of-turn (M1):** eager runs may start reflex+brain; read-only tools may run early; any tool that changes something is held until the end of the turn is final and the transcript still matches, otherwise the eager run is discarded and the final run redone. A same-input model action runs once per turn.
- **Run logs (M3/L4):** `~/.true/nova/runs/` 0600 holds tool names, ok flags and timings only — no command text, no transcript hash; os_log carries no words.
- **Self-quit (M4):** Nova refuses to quit, hide or terminate True itself (bundle id `net.prismlens.true`), in the gate, the hands and the instant matcher.
- **Low:** Keychain writes use Security.framework, so a secret never appears in a process argv (L1); `$NAME` is rejected by the shell tokenizer (L2); tool output is wrapped as escaped, labelled DATA (L3); `find_files` rejects queries starting with `-` (L5); undo of an open terminates only the pid Nova's open created (L6). Mic-on-from-launch stays the default (L7, Yahia's decision).
- **Still unverified live:** echo cancellation actually engaged; the HUD Approve click; end-to-end spoken approval in a real room; behaviour with real microphone hardware. Residual risk: an approved park is trusted, and the model can still *propose* anything — the card is the control.

## Nova threat model (Run 26, earlier text — superseded where Run 26c above differs)
- **Mic always on (wake word):** on-device Apple STT; audio is not stored; visible mic pill and one-click mute; Settings toggle.
- **Prompt injection via screen/pane/file/web text → tool calls:** text is wrapped as DATA and the system prompt says so, but the model is not trusted: `NovaGate` decides from tool name + arguments only.
- **Key storage:** Anthropic/ElevenLabs keys in Keychain service `net.prismlens.true`; reads via `/usr/bin/security` (argv has no secret), writes via Security.framework; never logged.

## Nova instant lane (Run 26b)
- **Mic-only lane:** the lane reads only the on-device recognizer's text; no network, no model; nothing in a pane, file or web page can reach it.
- **Addressed only:** ambient speech (a TV saying "open Safari") never fires it — only words after the wake name or while the hotkey is held.
- **Self-speech ignored:** input is dropped while Nova speaks plus a 400 ms tail; only "stop" barges in.
- **Quit is graceful:** `NSRunningApplication.terminate()` only, never force; the app's own save prompt protects work. Every instant act still passes `NovaGate` + `NovaHands`.
- **Undo:** the last 3 acts (8 s TTL) are reversible by a clause starting "no / undo / actually…".
- **Prewarm:** keyless `HEAD` requests only; keys never logged.

## Run 26e — verbatim `tell` sends (2026-10-10)

"Nova, tell the CTO to review the PR" sends his own words straight to the agent with no approval; approval still applies whenever the model writes or routes a message.

- **Origin tag, enforced in code:** `NovaGate.Origin.user` is set only by `NovaHands.runUser`, called only from the engine's tell lane. The model tool path is hard-coded `.model` and cannot pass `.user`. Only `send_to_pane` honours `.user`; `relay`, `spawn_agent`, `open_url` and every model send park as before.
- **Still enforced for `.user` sends:** addressed only (ambient never sends); Nova-speaking gate + tail; target pane mid-turn parks; any `DenyList` hit in the text is refused with the reason; control characters refused; the target must match the roster uniquely (else the normal path, where C2 parks); final end of turn only (eager start never sends); at most one send per turn.
- **Residual risk (accepted by Yahia 2026-10-10):** audio that says "Nova, tell <exact agent name> …" can send a message to an agent that runs without permission prompts.
