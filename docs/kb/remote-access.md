# Decision: True on the web (phase 1)
Owner: cto · Last verified: 2026-10-08

**Decision.** Serve existing panes to Yahia's phone from True itself (it owns the PTYs), over the tailnet, instead of moving to a VPS. Spec: [SPEC.md "True on the web"](../../SPEC.md).

**Threat model (5 lines).**
1. Reachable only through `tailscale serve` on the tailnet; never Funnel, never 0.0.0.0 — the server binds 127.0.0.1:8801.
2. Tailscale's `Tailscale-User-Login` header must equal the allowed login, else 403 (loopback clients can forge it, so the bind is what makes it trustworthy).
3. A paired device cookie is also required: 6-digit code (5 min, single use, 5 tries/min) → 32-byte random token, stored only as SHA-256, revocable in the sheet; WebSockets also check `Origin`.
4. Blast radius is "type into panes that already exist": no file browser, no command endpoint, no new tabs; off by default.
5. Residual risk: a stolen unlocked paired phone = shell access to open panes — revoke from the Mac sheet.

Consequences: Mac must be awake; the Mac PTY size stays authoritative.
