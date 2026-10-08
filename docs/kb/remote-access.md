# Decision: True on the web (phase 1)
Owner: cto · Last verified: 2026-10-08

**Decision.** Serve existing panes to Yahia's phone from True itself (it owns the PTYs), over the tailnet, instead of moving to a VPS. Spec: [SPEC.md "True on the web"](../../SPEC.md).

**Threat model.**
1. Reachable only through `tailscale serve` on the tailnet; never Funnel, never 0.0.0.0 — the server binds 127.0.0.1:8801.
2. Tailscale's `Tailscale-User-Login` header must equal the allowed login, else 403 (loopback clients can forge it, so the bind is what makes it trustworthy).
3. A paired-device **bearer token** is also required: 6-digit code (5 min, single use, 5 tries/min, **burned after 5 wrong guesses**) → 32-byte random token, stored server-side only as SHA-256, revocable in the sheet. The phone keeps the token in `localStorage` and sends `Authorization: Bearer` on `/api/*`; the WebSocket's first message is `{"auth":"<token>"}` (close 4401 if missing/invalid within 5 s; no PTY bytes before). **No cookie, on purpose:** cookies ignore ports, so a cookie would also be sent to the unrelated service on 8800 of the same `*.ts.net` hostname.
4. Exact `Host` (`<dns>:8444` or `<dns>`, kills DNS rebinding) on every request, and exact `Origin == https://<dns>:8444` on every state-changing request (`POST /pair`) and the WS upgrade. Every response carries `X-Frame-Options: DENY`, a strict CSP (no inline script), `nosniff`, `Referrer-Policy: no-referrer`, `Cache-Control: no-store`. Request head must arrive within 10 s overall (slowloris) and ≤ 16 KB; duplicate `Tailscale-User-Login`/`Host`/`Origin`/`Authorization` headers → 400; device file 0600 (created so), directory 0700.
5. Blast radius is "type into panes that already exist": no file browser, no command endpoint, no new tabs; off by default.
6. Residual risk: localStorage is readable by any script on the origin (none inline; CSP forbids foreign ones); a stolen unlocked paired phone = shell access to open panes — revoke from the Mac sheet.

Consequences: Mac must be awake; the Mac PTY size stays authoritative.
