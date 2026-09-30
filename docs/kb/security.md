# Security
Owner: security · Last verified: 2026-09-30

## Data classification
Local personal state, no server, no cloud. Sensitive: terminal scrollback (`~/.true/scrollback/*.ans`, mode 0600), workspace/agents JSON, Jev API key. [source: SPEC.md Run 4, Run 6]

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

## Incident steps
If a key leaks: rotate at TypeSafe, update Keychain item. If a runaway agent: `truectl status`, sleep the agent from the Hub/tab; never kill True.app from an agent. [assumption]
