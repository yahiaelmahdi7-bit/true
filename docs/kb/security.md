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

## Nova security (Run 26c) — only what the code enforces
Tests: `Tests/TrueTests/NovaSecurityTests.swift`, one per finding ID.
- **Approval (C1/H1/M2):** a parked action is approved only by an *addressed* yes ("Nova, go ahead"/"Nova, approve"), a yes while the hotkey is held, or the HUD Approve button. A bare "go ahead" never approves; ambient speech can only say NO. Any negation ("don't", "no", "cancel", "stop", "disapprove"…) anywhere means NO. Each approval is bound to one parked action id; a new park denies the old one, a stale id or click is a no-op. The card shows the exact command, text or URL.
- **Mic during Nova's speech (C1):** all input is dropped while Nova speaks and for 400 ms after (only "stop" barges in). Voice processing (echo cancellation) is requested on the input node best-effort (`try?`); whether the OS grants it is NOT verified here.
- **Agent sends (C2):** every model-initiated `send_to_pane`, `relay`, `spawn_agent` and `open_url` parks with the exact target and full text/URL. Only the instant lane's fixed known-site table opens URLs unparked (the user's own words, matched locally).
- **Shell (H2):** `run_shell` never goes through a shell on the free path. A strict tokenizer rejects any metacharacter (`$`, backtick, `;`, `&`, `|`, redirects, globs/qualifiers, `=(`, newline); allowlisted binaries run via `Process` with an argv array and an absolute path from a fixed table; per-command flag denylist; anything not provably read-only parks, and an approved park runs `zsh -f -c` on the exact card text. `DenyList` is checked first.
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
