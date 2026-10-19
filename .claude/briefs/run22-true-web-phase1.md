# Brief: Run 22 — True on the web, phase 1 (live panes on the phone, tailnet-only)

Worktree. Do NOT push, do NOT launch True.app, do NOT run `tailscale` commands (Claude wires `tailscale serve` after
review), never read `.claude/heldout/`. Lane: `Sources/True/`, `Tests/`, `Resources/` (if any), `SPEC.md`, `docs/kb/`.
Gate = docs/kb/conventions.md:5-9 exactly; weaken no test. No result.md in the repo.

Yahia, verbatim: "make true a web live vps feel i can use remotly and contninue where i left off on my phone from
anywhere". He chose "True on the web" (over a VPS move / a Claude lead session).

## Facts
- True owns every PTY in-process (SwiftTerm `LocalProcess`, `Terminal/EmbeddedTerminal.swift`, `TrueTerminalView.swift`).
- Tailscale is logged in; iPhone is on the tailnet. `tailscale serve` already uses `/` → 127.0.0.1:8800 (NOT ours —
  never use 8800). Ours will be exposed later by Claude as `tailscale serve --https=8444 http://127.0.0.1:8801`.
  Tailscale serve adds `Tailscale-User-Login` to proxied requests.
- Existing pure-BSD-socket style: `Agents/AgentEvents.swift` `LineSocketServer`. No new heavy deps; a tiny HTTP/1.1 +
  RFC 6455 WebSocket server in Swift (BSD sockets or Network.framework) is preferred over adding a package.

## Build
1. **Server (off by default).** Shell menu ▸ "Remote Access…" sheet: toggle On/Off (UserDefaults), shows status, the
   URL `https://<host>.taild56e9a.ts.net:8444` (read MagicDNS name from `tailscale status --json` is NOT allowed at
   build time — at runtime it's fine to read it via `/opt/homebrew/bin/tailscale status --json` Self.DNSName, with a
   fallback text), a QR code of it (CoreImage `CIQRCodeGenerator`), and a 6-digit **pairing code** that rotates each
   time it is shown and expires after 5 min. Listens on **127.0.0.1:8801 ONLY** (never 0.0.0.0).
2. **Auth, all three required.** (a) loopback bind; (b) request header `Tailscale-User-Login` must equal the allowed
   login (stored setting, default `yahiaelmahdi7-bit@` as shown by `tailscale status` — make it the Self user's login
   read at runtime); missing/other → 403; (c) pairing: first visit asks for the code → server issues a random 32-byte
   device token in an HttpOnly, Secure, SameSite=Strict cookie, stored hashed (SHA-256) in Application Support with a
   device label + last-seen; Remote Access sheet lists paired devices with Revoke. WebSocket upgrade requires the same
   cookie + header + an `Origin` matching the served host. Rate-limit code attempts (5/min). Log every connect/deny.
3. **API.** `GET /` the web app; `GET /api/tabs` → tabs/panes (id, title, cwd, agent name if any, busy/needs-you flag
   if True already tracks it); `WS /api/pane/<id>`: on connect send the pane's current screen + recent scrollback
   (SwiftTerm buffer → text with ANSI is fine), then stream PTY output live (tee the same bytes the local view gets),
   and write client input bytes into the PTY. Resize from phone must NOT resize the Mac's PTY (Mac stays authoritative);
   client renders at the Mac's cols and scales/scrolls horizontally. Multiple viewers allowed. Backpressure: drop to a
   fresh screen snapshot if a client falls > 1 MB behind.
4. **Web app (single static page embedded in the binary/bundle, xterm.js vendored locally — no CDN).** Mobile-first,
   dark, matches True. Tab list → tap → full-screen terminal. Bottom key bar for phone: Esc, Tab, Ctrl, ↑ ↓ ← →, ⌃C,
   a "paste" button, plus a text field with Send (sends line + Enter) because phone keyboards fight raw terminals.
   Auto-reconnect with backoff; shows "Mac asleep / offline" state clearly. Add to Home Screen ready (manifest + icon),
   so it opens like an app. "Needs you" panes badged in the tab list.
5. **Never**: no Funnel / public exposure, no file browser, no arbitrary command endpoint — only panes that already
   exist in True. Creating new tabs is phase 2.

## Design bar
Read `~/.claude/skills/taste/SKILL.md` first and say so in your final answer. Phone-first; 44 pt targets.

## Tests (no app launch)
WebSocket handshake accept-key (RFC sample), frame encode/decode incl. masking + fragmentation + >125/>65535 lengths,
HTTP request parsing, auth decision table (no header / wrong login / no cookie / bad cookie / revoked / good), pairing
code expiry + rate limit, token hashing round-trip, bind address is loopback, backpressure snapshot rule.
SPEC.md section + docs/kb decision note (threat model in 5 lines). Final answer: files, gate tail, what Claude must run
for `tailscale serve`, eyeball checklist for the phone.
