# True ↔ True peers — delegate real work to a friend's True (Run 29)

Repo: True, a SwiftPM macOS app (read `SPEC.md` hard rules + `CLAUDE.md` first; SPEC stays the source of truth).
You work ONLY in the worktree you were started in, on its builder branch.

## Goal (one sentence)
Yahia's agents (and Yahia) can hand a task to a paired friend's True, which runs it as a real Claude
session on the friend's Mac and sends status + the result back — and the friend's True can do the same to Yahia.

Today, cross-session work (lead → helpers via SendMessage) only works inside one Claude account on one Mac.
True already has the pieces to bridge Macs: Remote Access (Run 22–25: Tailscale serve on :8444, pairing
codes, bearer devices, route table), the ⌘K launch path (`CommandBar/CommandExecutor.swift`, `fromPhone`),
`Hub/BuilderSpawn.swift`, the Hub model, per-agent hooks → `agent-events.sock`, `PaneDelivery`,
`Duty/InjectionScreen.swift`. Extend them; do not build a parallel stack.

## Yahia's decisions — settled, do not re-litigate or soften
1. **Transport:** Tailscale machine sharing (each shares his Mac with the other's Tailscale account), reusing
   the Remote Access server. No cloud relay.
2. **Inbound jobs auto-accept.** No approval click, no daily cap, no per-job job-count limit.
3. **Inbound jobs run with `--dangerously-skip-permissions` straight on the Mac** (no sandbox/container), in
   a git worktree of the target repo.
4. **v1 scope = delegation + live status + result return.** No live chat between leads.
5. Each receiver chooses its own inbound mode — setting `peer.inboundMode`: `bypass | auto | ask`.
   Yahia's Mac = `bypass`. A fresh install defaults to `ask` (the friend picks his own).
   `auto` = `--permission-mode auto`; `ask` = a Hub "Needs you" row with Accept / Decline, then runs as `auto`.

## Non-negotiables (these do NOT conflict with the decisions above — keep every one)
- **Only paired peers can send.** New device scope `PairedDevice.Scope.peer`. A peer token may reach ONLY
  `/api/peer/*`; every other route and the pane WebSocket → 403/4401. Phone/full/dropOnly tokens → 403 on
  `/api/peer/*`. `Tailscale-User-Login` must equal the login recorded for that peer at pairing (fail closed).
  Exact `Host` still required. Peer routes accept a request with no `Origin` (machine-to-machine; bearer is
  not ambient, same reasoning as Run 24's Shortcut routes); a present Origin must still be exact.
- **No exec endpoint.** A job is a brief for Claude, never a shell command. Extend `RemoteServer.routeTable`
  and its test.
- **InjectionScreen runs on every inbound title + brief.** Flags are shown on the receiver's Hub row and
  logged. They do NOT block in `bypass`/`auto` (Yahia's choice); in `ask` they show in the Accept sheet.
- **Log** `~/.true/peers/jobs.jsonl` (0600): time, jobId, peer label, repo, mode, inboundMode, SHA-256 of the
  brief, flags, final status. Brief text lives only in the job dir (the agent needs it).
- **Kill switch.** Peers sheet: **Revoke** (token dead at once, queued work for that peer dropped) and
  **Stop all peer jobs** (ends running peer panes/builders cleanly via the existing sleep/teardown path).
- Remote Access stays off by default; peers only work while it is on. Idle ≈ 0% CPU still holds.

## Protocol
**Pairing (one direction per pairing; they pair twice for both directions).**
Receiver: Shell ▸ **Peers…** sheet → "Invite a peer" shows its `https://<MagicDNS>:8444` URL + a 6-digit
code (reuse `PairingCodes` rules: single use, 5 min, burned after 5 wrong). Sender: "Add a peer" → URL +
code + label → sender's True calls `POST /pair {"code","kind":"peer","label"}`. Receiver stores a `.peer`
device with label + the `Tailscale-User-Login` seen on that request, returns the token. Sender stores
{label, url, token} — Keychain (True already uses it), else a 0600 file. Normal phone pairing unchanged.

**Send a job.** `POST /api/peer/job`
`{jobId (sender UUID), title ≤120, brief ≤64 KB, repo (git remote URL), base (default "main"),
mode "pane"|"background", fromAgent (sender agent name or "yahia"), replyToken (32 random bytes, b64url)}`
→ `202 {jobId, status}`. Idempotent on jobId (a retry returns the existing status). Validate everything;
control chars other than tab/newline in brief → 400.

**Run it (receiver).**
- Repo: a clone under `BuilderSpawn.allowedRoots` whose normalized `origin` equals the normalized job repo
  (ssh ↔ https, trailing `.git`, case of host). None → status `failed` "no local clone of <repo>" (no auto-clone in v1).
- `git fetch origin`, worktree `<repoParent>/<repoName>.peers/<shortId>` on branch `peer/<label>/<shortId>`
  from `origin/<base>`.
- `pane`: a new visible True tab through the CommandExecutor path with a new origin `.peer(label)` (title
  chip "· from <label>", like `RemoteOrigin`): `claude --name peer-<label>-<shortId>` + the inboundMode flag +
  the per-agent `--settings` hook + `--append-system-prompt-file` peer role card; first prompt = the envelope.
  `background`: `BuilderSpawn` with the same envelope, `--parent peer-<label>` (builder's own runaway
  checkpoints stay as they are).
- Peer role card / envelope: "This job came from <label>'s True on another Mac. Do the brief in this worktree.
  You may hand parts to local helpers with SendMessage. When finished: commit, push branch
  `peer/<label>/<shortId>` to origin, write `~/.true/peers/jobs/<jobId>/result.md` (summary, what changed, how
  you verified it, open questions), then stop." The brief is quoted inside clearly marked delimiters.

**Status + result back (receiver → sender).** `POST <senderURL>/api/peer/event`
`{jobId, status accepted|working|needsYou|idle|done|failed, note, branch?, sha?, result? (≤16 KB, on done)}`
authorized by `Authorization: Bearer <replyToken>` — the sender stored only its SHA-256 per jobId, and the
request's Tailscale login must match that peer. A one-way pairing does not tell the receiver the sender's
URL, so the job body also carries `replyURL`; accept only `https://<host>.ts.net:8444` forms. Map hook events → status (deterministic code):
UserPromptSubmit/PreToolUse → working; Notification/PermissionRequest → needsYou; Stop → done ONLY if
result.md exists, else idle; launch/repo/push failure → failed.

**Outbox.** Undelivered jobs/events persist in `~/.true/peers/outbox/` and retry with backoff
(30 s → 10 min cap) only while items exist — no idle timer. Also flush when Remote Access starts.

**Sender UI.** Hub group **Sent to peers** (row: title, peer, status pill, elapsed; click → sheet with the
result text, branch, and a Copy button for `git fetch origin peer/<label>/<shortId> && git checkout …`).
Receiver Hub group **From peers** (flags badge if InjectionScreen flagged). When a job ends done/failed and
`fromAgent` is an awake local agent, deliver ONE line into its pane via `PaneDelivery`:
`[peer <label>] "<title>" done — branch peer/<label>/<shortId> — result: <path>`.

**Agents can delegate.** A tiny `true-peer` CLI installed by True (beside the hook scripts in `~/.true/`)
that talks to True over a 0600 unix socket `~/.true/peer.sock` (tokens never leave True):
`true-peer list` · `true-peer delegate <peer> --repo <path|url> --title T --brief-file F [--base B] [--background]`
(prints jobId) · `true-peer status [jobId]` · `true-peer result <jobId>`. Pick the simplest robust
implementation and say why. Lead role cards (`AgentLaunch` role file) gain one short paragraph on delegating
to a peer.

## Tests (pure logic + one in-process end-to-end)
Auth decision table with the peer scope (every cross-scope case above; wrong login; missing Origin allowed
only on peer routes) · job validation + repo URL normalization fixtures · jobId idempotency · repo resolution
· worktree/branch naming · envelope + role card builder · hook-event → status mapping (done needs result.md) ·
outbox backoff schedule · replyToken verification · route table assertion · InjectionScreen flag reaches the
row model. Plus an **in-process end-to-end test**: two RemoteServer instances on loopback with injected
identity headers and a fake launcher — pair, send a job, receive events through to done.

## Known open question (do not paper over)
Whether `tailscale serve` sets `Tailscale-User-Login` for a user who reaches a *shared* machine from another
tailnet must be checked live with a second account. Implement fail-closed (missing header → 403). Do not add
any fallback that weakens auth; list it in your result as the first live check.

## Also
- Add `## Run 29 — Peers (True ↔ True delegation)` to SPEC.md describing what was built (as-built, like Runs 24–25).
- Make sure `scripts/export-public.sh` / the public overlay picks up the new files so the friend's public
  build has Peers (do not push or publish anything).
- Do NOT launch True. Build with `scripts/package.sh` only.

## Done =
`swift build` clean with no warnings you introduced, full test suite green (paste the output with the CLT
flags from SPEC), `scripts/package.sh` produced True.app, atomic commits on your branch. Result lists: what
was built, files, test output, the live checks Yahia must run (Tailscale shared-user identity header; a
self-peer loopback job on a scratch repo), and anything you could not do.

DISCIPLINE (non-negotiable):
- Lane: you work ONLY in your builder worktree/branch. Do not touch, checkout, or revert anything outside it —
  other sessions have uncommitted work in the main True tree.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge,
  NEVER 'ship' — the user pushes, not you.
- Gates: run build/tests in the FOREGROUND and wait for them. NO background shells, NO watch modes,
  NO until-loops. Kill anything you started before finishing.
- Claims: 'done' means you ran the gate and pasted the passing output. Code written ≠ working.
- Decisions: status mapping and auth are deterministic code. Do not add LLM prompt-and-parse steps.
- If blocked: say BLOCKED + one line why. Do not invent extra scope.
