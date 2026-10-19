# REA — how Claude Code does cross-session messaging locally (v2.1.300, 2026-10-15)

Method: runtime files + string/code fragments from `~/.local/share/claude/versions/2.1.300` (Bun Mach-O).
Auth handshake internals were deliberately NOT inspected; no key contents read. Labels: confirmed / likely / guess.

| Piece | What Claude does | Label (check) |
|---|---|---|
| Registry | `~/.claude/sessions/<pid>.json`: name, sessionId, cwd, status idle/busy, `messagingSocketPath`, `peerProtocol: 1`, `peerFeatures: [notify_idle, reply_across_default_dirs, artifact_yield]` | confirmed (file read) |
| Transport | one Unix socket per session, `/tmp/cc-socks/<pid>.sock` (dir 0700, socket 0600); path vetted for owner, symlinks, sticky bit; `--messaging-socket-path` override | confirmed (ls + strings) |
| Auth | `[uds-auth]` publishes a per-session key `~/.claude/sessions/<pid>.<sha256>.key` (0600); peer proc-start verified | confirmed exists; handshake not inspected |
| Addresses | `uds:` (local socket), `bridge:` (cloud, account-scoped), `did:` | confirmed (regex strings); bridge = account relay is likely |
| Envelope | `<cross-session-message from="…" from-name="…">\n…\n</cross-session-message>`, typed `peer_message` in the transcript | confirmed (regex + classifier code) |
| Receipts | `peer_message_status` keyed by `orig_msg_id`: delivered / held for approval / declined / expired | confirmed (strings) |
| Approval gate | recipient may hold a message for its user's approval ("permission-mode parity") | confirmed (strings) |
| Idle notify | `notify_when_idle` → recipient sends `peer_idle_notice` when its turn ends | confirmed (strings) |
| Busy recipient | message queued and delivered at the next turn boundary | likely |

## The official door for outside processes: channels
`--channels <servers…>` = "MCP servers whose channel notifications (inbound push) should register this session".
An MCP server that declares `capabilities.experimental["claude/channel"]` can push
`notifications/claude/channel` into a live session; `experimental["claude/channel/permission"]` relays
permission prompts. Custom (non-allowlisted) servers need `--dangerously-load-development-channels`
(startup confirmation dialog). Org gate exists: "Channels are not enabled for your org". — confirmed (strings + code)
Not yet tested live on Yahia's account.

## Replication for True across Macs (proposed Run 30, on top of Run 29 pairing/auth)
- Registry → each True publishes its live roster to paired peers (`GET /api/peer/roster`).
- Transport → True ↔ True over Tailscale (Run 29). Address form `true:<peer>/<session-name>`.
- Last mile → a `true-channel` MCP server (stdio) loaded into every True-launched Claude via `--channels`:
  inbound remote messages are pushed as channel notifications; tools `list_peers`, `send(to, text)`,
  `notify_when_idle(to)` send outbound through True. No typing into panes.
- Receipts + idle notify mirror Claude's (`orig_msg_id`, delivered/held/declined/expired, idle notice).
- Approval → per-receiver `peer.inboundMode` (Yahia: bypass, no hold).
- Step 1 of the build = live spike: a 30-line channel server pushing one message into a session on this account.
