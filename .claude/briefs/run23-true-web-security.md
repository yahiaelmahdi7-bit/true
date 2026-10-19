# Brief: Run 23 — True on the web: security fixes before merge

Worktree. Do NOT push, do NOT launch True.app, do NOT run `tailscale` commands, never read `.claude/heldout/`.
Lane: `Sources/True/Remote/`, `Sources/True/` (only where Remote Access is wired), `Tests/`, `Resources/Remote/`,
`SPEC.md`, `docs/kb/remote-access.md`. Gate = docs/kb/conventions.md:5-9 exactly; weaken no test. No result.md in repo.

**FIRST STEP:** your worktree branches from `main`, but this work sits on top of Run 22, which is not merged yet.
Run `git merge --no-edit builder/true-web-p1-20261008-111109` in your worktree before anything else; confirm
`Sources/True/Remote/` exists. Run 22's brief: `.claude/briefs/run22-true-web-phase1.md` (context only).

## Why
A security review of Run 22 said FIX FIRST. The main path holds (no PTY without header + token; loopback bind;
SecRandom; off by default; no XSS; WebSocket parser sound). Fix every item below, each with a test.

## Fixes (line refs are on the Run 22 branch)
1. **P1 — no cookie** (`RemoteServer.swift:155`). Cookies ignore ports, so the paired-device cookie also goes to the
   unrelated service on 8800 of the same `*.ts.net` hostname. Drop the cookie entirely. After pairing, the server
   returns the token in the JSON body; the web app keeps it in `localStorage`, sends it as
   `Authorization: Bearer <token>` on every `/api/*` call, and for the WebSocket as the first text message
   `{"auth":"<token>"}` (server closes with 4401 if the first message isn't a valid token within 5 s; no PTY bytes
   flow before auth). Remove all `Set-Cookie` / cookie parsing. Unpaired → app shows the pairing screen.
2. **P2 — exact Origin + Host** (`RemoteAuth.swift:43-47`). Require `Origin == "https://<dnsName>:8444"` exactly
   (scheme + host + port; dnsName = Self.DNSName from `tailscale status --json` at runtime, trailing dot stripped)
   on every state-changing request and the WS upgrade. Reject any `Host` other than `<dnsName>:8444` or
   `<dnsName>` (kills DNS rebinding). Tests: origin without port → 403; http scheme → 403; foreign host → 403.
3. **P2 — headers** (`HTTPRequest.swift:74-78`) on every response: `X-Frame-Options: DENY`,
   `Content-Security-Policy: default-src 'self'; connect-src 'self'; frame-ancestors 'none'; object-src 'none';
   style-src 'self' 'unsafe-inline'`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`,
   `Cache-Control: no-store` on `/api/*`. Make sure the web app still works under that CSP (no inline scripts).
4. **P3 — pairing brute force** (`RemoteAuth.swift:82-93`): burn the current code after 5 wrong guesses and show
   "Code burned — show a new one" in the Mac sheet. `POST /pair` also requires the exact Origin from item 2.
5. **P3 — slowloris** (`RemoteServer.swift:108-122`): overall 10 s deadline to receive the full request head
   (not per read); also cap the head at 16 KB.
6. **P3 — file mode** (`RemoteAuth.swift:149-154`): create the device file 0600 from the start (open with mode, not
   chmod after), parent dir 0700.
7. **P3 — duplicate headers** (`HTTPRequest.swift:41-44`): reject (400) a request carrying more than one
   `tailscale-user-login`, `host`, `origin` or `authorization` header.
8. **Asset check:** re-run the generator for `RemoteWebAssets.swift` and confirm the embedded base64 xterm matches
   `Resources/Remote/xterm.js` byte-for-byte; regenerate if it doesn't. Say which in your final answer.

## Docs
Update SPEC.md and `docs/kb/remote-access.md` threat model: token in localStorage (not cookie) and why; exact
Origin/Host; headers; burn-after-5.

## Final answer
Files changed, test names per item 1-8, gate tail, and anything you could NOT fix.
