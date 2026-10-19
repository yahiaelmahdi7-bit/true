# Run 29b — Peers over a global relay (no Tailscale)

You are building True (macOS SwiftUI terminal, ~/Projects/true). Your cwd is a git worktree that already contains
Run 29 (Peers: True ↔ True delegation) on top of main. Read `SPEC.md` § "Run 29 — Peers" and `Sources/True/Peers/`
first. Run 29 moved jobs between two Macs over Tailscale. **Yahia rejected that: peers must work between ANY two True
users anywhere, with no Tailscale, no port forwarding, no accounts.** Your job: replace Run 29's transport + identity
layer with a global relay, keep everything else.

## Settled (do not re-litigate)
- **No Tailscale anywhere in Peers.** Peers must work with Remote Access switched OFF. Phone Remote Access (Runs 22–25)
  is untouched and stays on Tailscale.
- **Relay = Cloudflare Worker + SQLite-backed Durable Objects**, open to every True user; the public build ships the
  default relay URL. It must stay inside the Workers **Free** plan (no paid features).
- **The relay is untrusted.** It must be unable to read, forge, replay, or redirect a job or event. Security comes from
  per-install keys pinned at pairing, never from the relay.
- Unchanged from Run 29: `peer.inboundMode` bypass|auto|ask (fresh default ask), `PeerMode.effective` (background only
  in bypass with the builder installed), InjectionScreen flags (shown, never blocking), `jobs.jsonl`, Revoke + Stop all,
  job engine/launcher/worktrees/branches, `true-peer` CLI verbs, Peers sheet + Hub groups, result return.

## Remove (Tailscale-specific Run 29 pieces)
`Remote/RemoteServer+Peers.swift`, `/api/peer/*` + `POST /pair kind=peer`, `PairedDevice.Scope.peer` + `login`,
`peerCodes`, the peer lines in `HTTPRequest.bodyRoutes` / routeTable / the peer-token 403 block, `PeerAuth`,
`replyURL`/`replyToken`, `PeerTransportLive` (https). Revert those RemoteServer/RemoteAuth/HTTPRequest edits to main's
shape (keep the route-table test consistent). Remove Tailscale/URL wording from Peers UI + SPEC.

## Identity
First Peers use generates CryptoKit `Curve25519.Signing` + `Curve25519.KeyAgreement` key pairs, stored in a 0600
`~/.true/peers/identity.json` (0700 dir) — same class as Run 29's token file, no Keychain prompts on re-signed builds.
`mailboxId` = lowercase hex of the first 16 bytes of SHA-256(signing public key).

## Relay protocol (`relay/` in this repo, TypeScript)
- `wss://<relay>/v1/connect`. Relay sends `{"t":"challenge","nonce":<b64 32B>}`; client answers
  `{"t":"hello","pub":<b64 ed25519 pub>,"sig":<sign("true-relay-v1|"+nonce+"|"+host)>}`. Relay verifies (WebCrypto
  Ed25519), binds the socket to `mailboxId(pub)`. Unauthenticated sockets close after 5 s. ≤ 4 sockets per mailbox.
- `{"t":"send","to":<mailboxId>,"id":<uuid>,"blob":<b64>}` → `{"t":"ack","id"}`. Delivered as
  `{"t":"msg","from":<mailboxId>,"id","blob"}` to the recipient's live socket(s), else queued. Client confirms with
  `{"t":"got","id"}` → relay deletes it. Queued messages flush on connect.
- Limits: blob ≤ 192 KB; per mailbox ≤ 200 queued / ≤ 8 MB; TTL 7 days (DO alarm sweeps); 60 sends/min per socket;
  anything off-schema → close. Never log blob contents. `GET /v1/health` → `{ok,version}`.
- One Durable Object per mailbox (`idFromName(mailboxId)`), **WebSocket Hibernation API** (idle sockets ≈ free).
  `wrangler.jsonc`: name `true-relay`, `new_sqlite_classes` migration. `relay/.gitignore` node_modules.
- `from` from the relay is a routing hint only; the sender is proven by the signature inside the envelope.

## Envelope (Swift, CryptoKit only)
key = HKDF-SHA256(ECDH(my KA priv, their KA pub), salt: msg id, info: "true-peer-v1|"+from+"|"+to);
ct = ChaChaPoly.seal(payload JSON). Outer `{v:1, from, to, id, ts, ct, sig}`, sig = Ed25519 over v|from|to|id|ts|ct.
Receiver drops (log one line, never surface content) unless: sig verifies against the **pinned** signing key for
`from`, `to` == me, ts within 7 days (+5 min skew), id unseen (persisted seen-set, 8-day expiry), decrypt succeeds.
Payloads: `pair-request`, `pair-accept`, `job` (Run 29 job fields minus replyURL/replyToken), `event` (Run 29 event
fields; accepted only from the peer the job was sent to), `unpair`.

## Pairing (invite string replaces the 6-digit code)
- Inviter: Peers ▸ Invite makes `true-peer:v1:<mailboxId>.<KA pub b64url>.<sign pub b64url>.<secret b64url 16B>`.
  Copy button; copy text: "Send this to one person. It works once, for 24 hours." Store only SHA-256(secret), expiry.
- Joiner: Peers ▸ Add a peer → paste invite + name them. Joiner pins the inviter keys FROM THE INVITE (so the relay
  cannot substitute keys), sends sealed `pair-request {secret, joiner keys, suggested label}`.
- Inviter checks the secret (constant-time, unexpired, unused) → pins joiner keys → sealed `pair-accept {name}`. The
  valid secret IS the consent; show "Paired with <label>". Wrong/expired/reused secret → drop silently.
- Revoke = delete pinned keys + best-effort sealed `unpair`. Anything from unknown/revoked keys is dropped.

## Swift transport
`URLSessionWebSocketTask`; connected only while ≥ 1 paired peer or a live invite exists. Reconnect backoff 1 s
doubling to 5 min with jitter; no polling timers (0% idle CPU — True rule); a WS ping at most every 5 min.
Run 29's outbox stays for when the relay is unreachable. `PeerTransport` becomes message-based
(`send(to:blob:)` + inbound handler) so tests run two engines over an in-memory `FakeRelay`.
Relay URL: constant `PeerRelay.defaultURL = "wss://RELAY_URL_PLACEHOLDER"` (exact marker — Yahia's session fills it after
deploying) + override `peer.relayURL` (UserDefaults) in a small "Advanced" disclosure in the Peers sheet. Peers sheet
shows one status line: "Connected" / "Offline — retrying".

## Tests (all must pass)
- Swift: envelope round trip; each of ct/sig/from/to/ts tampered → rejected; wrong recipient; replay; stale ts; invite
  format/parse round trip + garbage; pairing over FakeRelay (ok, wrong secret, expired, reused, relay swaps keys →
  fails); in-process E2E two engines: pair → job → events → done with result → one-line delivery to the lead;
  revoke → later job dropped; Run 29 engine tests adapted (inboundMode, PeerMode.effective, stop-all, injection flags).
- Relay: `vitest` + `@cloudflare/vitest-pool-workers` in `relay/`: good/bad hello, unauth timeout, live delivery,
  offline queue then flush, `got` deletes, TTL sweep, each cap (size, count, bytes, rate), 5th socket refused.
  `npx wrangler deploy --dry-run` must succeed. **Never run a real `wrangler deploy` or `wrangler login`.**

## Done =
`swift build` clean (no new warnings); full `swift test` with the CLT flags (SPEC "Stack") pasted — known flakes not
yours: `NovaSecurity26f.tellLatencyWithin10PercentOf26e`, `LagTests.overlappingChecksAreSkipped`; relay vitest output
pasted; dry-run output pasted; `scripts/package.sh` (never launch True.app); `scripts/export-public.sh <temp dir>`
(never the default target) shows `relay/` + Peers shipped with no personal strings. SPEC.md: rewrite the Run 29
section as-built: "## Run 29 — Peers (True ↔ True over a global relay)". Final report: files, pasted outputs, what
Yahia's session must do next (deploy relay, fill RELAY_URL_PLACEHOLDER, live test with a friend off-tailnet).

DISCIPLINE (non-negotiable):
- Lane: you work ONLY in your builder worktree/branch. Do not touch, checkout, or revert anything outside it —
  other sessions have uncommitted work in the main True tree.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge,
  NEVER 'ship' — the user pushes, not you. Never deploy anything.
- Gates: run build/tests in the FOREGROUND and wait for them. NO background shells, NO watch modes,
  NO until-loops. Kill anything you started before finishing.
- Claims: 'done' means you ran the gate and pasted the passing output. Code written ≠ working.
- Decisions: auth, crypto checks and status mapping are deterministic code. Do not add LLM prompt-and-parse steps.
- Crypto: CryptoKit / WebCrypto primitives only — no hand-rolled crypto, no new Swift packages.
- If blocked: say BLOCKED + one line why. Do not invent extra scope.
- Commit trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`
