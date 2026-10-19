# True — phone: merge the iPhone app, then add Sites + a streamed Mac browser

Repo ~/Projects/true (private, branch main). Work ONLY in your worktree; commit there; never push; never touch ~/Projects/true-public.
Never run `tailscale serve reset`; never change the existing serve entries :443 -> 127.0.0.1:8800 (not True's) or
:8444 -> 127.0.0.1:8801 (True Remote Access). Diff `tailscale serve status --json` before/after any live test; they must be identical.

## Context (verified)
- Mac True has Remote Access: Sources/True/Remote/ (RemoteServer.swift, RemoteAccess.swift, RemoteAuth.swift, RemoteBackendLive.swift,
  Resources/Remote web app). Phone reaches it via tailscale serve :8444 -> 127.0.0.1:8801 (real *.ts.net TLS), 6-digit pairing.
- The native iPhone app "True" (SwiftUI, iOS 26: Hub, Shots, Send, Start work, live panes, TrueShare, TrueActivity) lives ONLY on branch
  `builder/true-mobile-redesign` (last commit 2026-10-10), dir ios/ + Sources/TrueRemoteClient/. Read ios/README.md first. Same /api +
  WebSocket contract as the web app. Yahia has it installed on his iPhone from Xcode.
- main and that branch diverged (~72 / ~70 commits). `git merge` conflicts in: Package.swift, Resources/Remote/{app.css,app.js,index.html},
  Sources/True/Agents/PaneDelivery.swift, Sources/True/Remote/{RemoteServer.swift,RemoteWebAssets.swift}, scripts/package.sh.

## Phase 1 — merge (gate: do not start phase 2 until this is green)
Merge `builder/true-mobile-redesign` into your branch. Resolve each conflict keeping BOTH sides' behaviour (main's recent work: auto-update,
signed updates, TrueUpdateRepo/TrueUpdatePublicKey in package.sh, peers, autosuggest; the branch's: phone API/routes, TrueRemoteClient).
Then: `swift build`, full `swift test --no-parallel` (known flaky: Nova race/latency tests, note them), and
`cd ios && xcodegen generate && xcodebuild build -scheme True -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
Make sure scripts/export-public.sh EXCLUDES ios/ (add to its rm list if needed) and still runs: export to a temp dir, `swift build` there.
Commit the merge on its own with a message listing each conflict and how it was resolved.

## Phase 2a — Sites (localhost servers)
Mac: detect TCP LISTEN ports owned by descendants of True pane shells (lsof -nP -iTCP -sTCP:LISTEN -F pcn + process tree); ignore <1024 and
non-web (5432 6379 27017 3306 9229); confirm HTTP with a 300 ms HEAD. Poll every 3 s only while a pane has a foreground job.
Expose on request via `tailscale serve --bg --https=<P> http://127.0.0.1:<P>` (same port; if taken, next free in 8450-8499). Track
True-owned mappings in app support JSON; remove ONLY those (`tailscale serve --https=<P> off`) when the server stops / pane closes / toggled off;
reconcile at launch. Remote API: `GET /api/sites` -> [{port, title (from <title>), pane, project, exposed, url}], `POST /api/sites/{port}/expose|unexpose`.
Mac UI: small pane pill "● 3000 → Phone" + popover (URL, QR, Copy).
Phone: a **Sites** tab listing them; tap = expose if needed, then open in an in-app SFSafariViewController/WKWebView (pull to refresh, share, open in Safari).
Host-header gotcha: after exposing, fetch the URL; if Vite/Next blocks the *.ts.net host ("Blocked request"/"not allowed"/403), show the
one-line fix with Copy (`server: { allowedHosts: ['.ts.net'] }` / Next `allowedDevOrigins: ['*.ts.net']`). Never edit user projects.

## Phase 2b — Browser (a separate "True Chrome" streamed to the phone)
Mac: launch Google Chrome (or Chrome for Testing if present) with `--user-data-dir=~/Library/Application Support/True/BrowserProfile
--remote-debugging-port=<free port bound 127.0.0.1>` — a SEPARATE profile; never touch the user's main Chrome profile (Chrome refuses
remote debugging on the default profile anyway). Talk CDP over its local WebSocket (URLSessionWebSocketTask). Use `Page.startScreencast`
(jpeg, quality ~60, maxWidth = phone width × scale, everyNthFrame tuned) and ack frames; `Emulation.setDeviceMetricsOverride` to the phone's
viewport + `Emulation.setTouchEmulationEnabled` so sites render mobile layout; input via `Input.dispatchTouchEvent`/`dispatchMouseEvent`
(scroll as mouseWheel), `Input.insertText` + `dispatchKeyEvent` for keys. Tabs: Target.getTargets / createTarget / closeTarget / activateTarget.
Nav: Page.navigate, back/forward via Page.getNavigationHistory. CDP port is never exposed; only True's authenticated Remote API is.
Remote API: WebSocket `/api/browser/stream` (auth = existing bearer) carrying frames (binary jpeg + small JSON header) Mac->phone and input
events phone->Mac; `GET/POST /api/browser/tabs`. Throttle: drop frames if the socket is backed up; pause screencast when no viewer.
Phone: a **Browser** tab: URL bar (with Sites shortcuts, e.g. localhost:3000 works since the browser runs on the Mac), tab switcher, the
streamed view with touch → tap/scroll/pinch-zoom, keyboard input, back/forward/reload. Show latency/fps subtly in DEBUG.
Mac: a Settings toggle "Phone browser" (default on) + "Open True Chrome" so Yahia can sign into sites once in that profile.

## Done =
Phase 1 commit + phase 2 commits. `swift build` clean, full tests green (bar known flaky), iOS simulator build OK. Unit tests: port filter,
descendant match, port allocation avoiding taken/foreign (443, 8444), ownership-only cleanup, blocked-host detection, CDP message
encode/decode, input mapping (touch point → page coords at any scale), frame back-pressure. Live e2e on this Mac:
(1) `python3 -m http.server 8765` in a scratch dir in a True-like child process (or call the detector directly), expose,
`curl -sf https://yaes-macbook-pro.taild56e9a.ts.net:<P>/` = 200, unexpose, serve status JSON identical to before;
(2) launch True Chrome headful, open http://127.0.0.1:8765, receive ≥10 frames over the Remote WebSocket via a small test client,
send a tap and a text input, prove the page changed (Runtime.evaluate). Simulator screenshots of Sites + Browser tabs in
.out/phone-preview/. RESULT: files, merge resolution notes, test tails, e2e transcript, and the steps Yahia does: rebuild the iPhone
app from Xcode (ios/README.md), rebuild/restart True on the Mac.
