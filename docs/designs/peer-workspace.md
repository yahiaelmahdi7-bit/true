# Run 36 — Peer workspace (live view, files both ways)
Status: approved 2026-10-26 (Yahia: Build it · files via relay · his Mac shows Mahmoud Everything + open) — building 36a

## Goal
Yahia's Claude and Mahmoud's Claude already pair, delegate jobs, chat and ask each other (Runs 29–35). In real
use on 2026-10-22..26 the work kept hitting walls: a background job is a black box until it ends, pane jobs show
only tool names, failures give no reason, results are cut at 16 KB, files cannot cross between the Macs, agents
pass paths from their own Mac, and "ask" says the brain is asleep when it is only cold. Run 36 removes those walls
in two parts, built and shipped in order, each with its own checks:

- **36a Live view** — every job's steps as they happen, failure reasons, results up to 64 KB, ask steadier.
- **36b Files + workspace** — send a file or folder to a peer's inbox (and open it on their screen), attach files to
  a job, get the job's `out/` folder back; a missing repo raises the Run 34 offer card instead of failing.

**What widens:** 36b adds one new write location per peer — their **inbox** on the receiver's Mac — plus job
`in/`/`out/` folders tied to jobs. Nothing else a peer can reach changes. The access switch (Folders only / Whole
Mac), reading a peer's files directly (`get`/`ls`), writing to arbitrary paths, and a sandbox for less-trusted
peers move to **Run 37**, which starts with a spike (see "Run 37 notes").

### Evidence (from `~/.true/peers/` on Yahia's Mac)
- Mahmoud's agent took 4 jobs (`0e1af033`, `9e1c6dd0`, `bbc9f83d`, `b184f7d8`) to copy two skill folders (32 KB):
  result cut at 16 KB → "part A / part B" → base64 tarballs pasted into `result.md`.
- Two dir jobs failed `Directory not allowed`: the sender passed paths on **its own** Mac
  (`/Users/mahmoudelbagir/Projects/skill-imports`, a `/private/tmp/...scratchpad` path).
- "Open the FDOS lecture 01 film" failed `Directory not allowed: ~/Desktop`; there is no way to send a file (12 MB).
- 4 background jobs on Mahmoud's Mac: activity = status lines only for 8–16 min, then "Stopped by sender"; one
  ended "Hit an error" with no reason. Pane jobs stream the tool name only ("Bash" ×243).
- Oracle answered "The brain … is asleep" to 3 questions at 18:3x; the brain server was up but cold (first
  `/api/status` > 5 s, the next 68 ms).
- 3 of 18 sent jobs failed `No local clone of <repo>`.

## Vocabulary (one name per thing, mapped to code)
- **Share level** — how much of a job's work the receiver shows the sender: `peer.share` / `PeerShare`
  (`PeerLogic.swift:487`), global as today. UI labels: Status · Activity (today) · **Everything** (new).
- **Folder list** — `peer.allowedDirs` (global). **Shares** — Run 34 shared repos (per peer).
- **Offer card** — the Run 34 Peers-sheet card with Accept / Decline (`PeerOfferStatus`).
- **Transfer** — one file or folder moving between the Macs.
- **Inbox** — `~/TruePeers/<peer-slug>/inbox/` on the receiver: where a peer's `put` lands.
- **Job folders** — `in/` (what the sender attached) and `out/` (what goes back), inside today's job dir
  `~/.true/peers/jobs/<id>/` (`PeerEngine.jobDir`) next to `envelope.md` and `result.md`.
- **Caps** — what a peer's True can do (version + features), announced on connect.
- **Secrets list** — never sent, on either side, matched against the realpath (case-insensitive) or, for file
  names, against the last path component with shell-glob rules: `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.config`,
  `~/.netrc`, `~/.true`, `~/Library/Keychains`, `~/.claude/.credentials*`, `*.pem`, `*.key`, `*.p12`, `id_rsa*`,
  `id_ed25519*`, `.env*`, `*credentials*`, `*.keychain*`.
- **UI stills** — screenshots of every changed screen, shown to Yahia and OK'd **before** the build is installed
  on his Mac (standing rule since a restyle reached his installed app unseen on 2026-10-13).

## Users & journeys (with preconditions)
1. Mahmoud's agent delegates "copy `~/.claude/skills/sharpen` into out/" to Yahia's Mac; when the job ends the
   folder lands on Mahmoud's Mac in `~/TruePeers/yahia/jobs/<shortId>-<title>/`, checksum verified — one job, no
   base64. *Needs:* the job allowed by Yahia's inbound mode, as today.
2. Yahia's agent runs `true-peer put FDOS-lecture-01.mp4 mahmoud --open`; the film lands in Mahmoud's inbox from
   Yahia and opens on his screen. *Needs:* "Let peers open files on my screen" on at Mahmoud's (default off) and
   `.mp4` on the open list; in `ask` mode Mahmoud taps Open. Otherwise it is revealed in Finder.
3. Yahia delegates a background job to Mahmoud's Mac and watches each step (tool + its input, the agent's words)
   live in the Hub and `true-peer tail -f`, with Mahmoud's share level at Everything. If it fails he sees why.
4. Either agent delegates `--with ./spec ./data.csv`; the files are in the job's `in/` when it starts; whatever
   the job leaves in `out/`, plus `result.md` at any size, comes back when it ends.

---

## 36a — Live view

**A0. Quick fixes, no protocol change (ship first).**
- **Results to 64 KB.** `PeerValidate.maxResult` (`PeerLogic.swift:94`) 16 → 64 KB, counted in **UTF-8 bytes**
  (not characters: 64 K multi-byte characters would reach 256 KB and bust the seal). The status is sealed and
  size-checked before sending; if it would exceed `PeerSeal.maxBlob` (144 KB) the result is cut further and ends
  "(cut — full result in result.md)". Old senders clip at 16 KB on receipt.
- **Failure reasons.** "Hit an error" / "Ended without a result" add the last error: hook `error` message, the
  builder's last `is_error` result, or the last 3 lines of `stderr.log` — masked, ≤ 400 chars.
- **Paths are on the peer's Mac.** Role cards and `true-peer help` say it in one line: "Paths you give <peer> are
  paths on <peer>'s Mac. To send your own files use `--with` or `put`."

**A1. Caps.** New sealed payload `caps {version, features: ["watch"], home}` (36b adds `"files"`), sent on every
connect and pairing and **persisted per peer** (`~/.true/peers/caps.json`). A peer with no caps yet is *unknown*:
features wait up to 60 s for its next connect before saying "Mahmoud's True needs the update (v1.3+)". Old Trues
drop the unknown type, as today.

**A2. Own-path guard.** A `--dir` path that starts with the sender's own home, exists locally, and differs from the
peer's announced `home` is rejected: "That is a path on your Mac. Use --with to send it, or name a path on
Mahmoud's Mac." Off when the homes match.

**A3. Pane steps with input.** Today only PermissionRequest sends `input`, clipped at 300 chars by the forwarder
(`AgentHooks.swift:101-136`) and by `ToolSummary.summarize`'s `clean()` (`AgentEvents.swift:67`). The forwarder
now sends PreToolUse input too; both 300-char clips and `PeerActivityItem.maxText` (`PeerLogic.swift:549`) rise to
1 KB together. What leaves the Mac depends on the share level:

| share level | tool items | assistant items |
|---|---|---|
| Status | none | none |
| Activity (today) | name + a safe detail: `file_path`, `pattern`, URL host — never Bash commands or prompts | first line, ≤ 1 KB |
| Everything (new) | name + first line of `command` / `file_path` / `pattern` / `url` / `prompt`, ≤ 1 KB | ≤ 8 KB |

`PeerMask` (`PeerLogic.swift:569`) runs at every level and gains, each with table-driven test cases (new
`PeerMaskTests`): PEM blocks `-----BEGIN [A-Z ]*PRIVATE KEY-----`, `(?i)(token|secret|api_key|apikey|password|
passwd)\s*[=:]\s*\S+`, Resend `\bre_[A-Za-z0-9_]{16,}`, AWS `\bAKIA[0-9A-Z]{16}\b`, JWT
`\beyJ[\w-]{8,}\.[\w-]{8,}\.[\w-]{8,}\b`, Slack `\bxox[abposr]-[A-Za-z0-9-]{10,}`, `github_pat_\w{20,}`,
`sk_live_\w{10,}`, URL credentials `://[^/\s:@]+:[^/\s@]+@`. The Everything picker carries one line: "Shows
commands and the agent's words. Secrets are masked, not guaranteed."

**A4. Background-job steps.** `PeerBuilders.report` (`PeerLauncherLive.swift:160`) already delivers `BuilderRecord`
with `dir`; match `record.name == job.agentName` exactly. Extend the stream parser behind `HubStore.tail(ofStream:
lines:)` (`HubStore.swift:61`) to emit `PeerActivityItem`s (`tool_use` → tool, assistant `text` → assistant,
`result` with `is_error` → failure reason), same share-level table. Watch `stream.jsonl` with a DispatchSource; on
rename/delete (`builder resume` rotates it) re-open the new file.

**A5. Watch lease — extend `queueActivity` (`PeerEngine.swift:1171`).** The batcher, 200-item backlog and `true-peer
tail` exist. New: toward a peer whose caps include `watch`, activity is sent only while that peer holds a lease —
`watch {jobId, since: seq}` from the Hub job sheet or `tail -f`, TTL 90 s, renewed every 60 s; the receiver checks
`job.peerMailbox == lease sender`, then sends items after `since` (no duplicates in `events.jsonl`) and streams
while the lease lives. Toward peers without `watch` (old Trues) activity streams as today. Why: every relay message
costs relay storage rows, and the Cloudflare plan caps rows written per day for the whole account.
- **One activity budget per True:** ≤ 20 activity envelopes/min across all jobs (round-robin), leaving ≥ 40 of the
  relay's 60/min per socket for chat, status and jobs.
- **Nack reasons reach the sender.** `PeerSendResult.retry` (`PeerModels.swift:143`) gains a reason (`offline`,
  `rate`, `full`); `pump()` backs off activity on `rate`/`full` without holding chat or status behind it.

**A6. Ask, steadier** (own commit, diagnose first). First reproduce on this Mac (stop the brain, ask from the CLI)
and log which call returns nil and why. Then: the asker gets "Waking the brain…"; the question leaves the serial
`drain()` for its own task, polls `/api/status` every 2 s for up to 45 s, then answers. Still cold after 45 s →
"The brain is still waking up — ask again in a minute." `launchctl kickstart` (never `-k`) only if `launchctl
print` shows no pid. "Cold" = first status call after ≥ 5 min without one.

**36a steps** (one builder run; each step one commit)
1. A0. Check: a 60 KB result arrives whole; a 64 K-character emoji result arrives cut with the note and the seal
   never fails; a failed builder and a failed pane each report a reason; role card contains the paths line.
2. A1 + A2. Check: caps persisted and reloaded after restart; unknown → waits, then "needs the update"; guard
   rejects a local path, allows it when homes match.
3. A3. Check (new `AgentHooksTests`): a PreToolUse Bash event yields the command line at Everything and no command at
   Activity; `PeerMaskTests` table passes, plain prose untouched.
4. A4. Check: a recorded `stream.jsonl` (from `~/.claude/builders/fdos-migration-m1-*`) yields tool + assistant
   items in order; a rotated file keeps streaming; a failed run yields its reason.
5. A5. Check (`PeerEngineTests`): no lease → zero activity to a `watch` peer; lease → batched, ≤ 20/min across 3
   jobs, chat sent meanwhile goes out at once; `since` → no duplicate seqs; foreign lease ignored; old peer (no
   caps) still gets today's stream.
6. A6. Check (`OracleTests`): FakeBrain cold 10 s then up → one "Waking" line then the answer; another question is
   answered meanwhile; cold 60 s → the "still waking" line.
7. `swift build` + `swift test --filter "Peer|Agent|Oracle"` green; UI stills of the share-level control.

**36a Done means (real thing, not "it ran")**
- New opt-in harness `PeerLiveRelayTests` (`TRUE_LIVE_RELAY=1`, two fresh in-process engines through
  `wss://true-relay.yahia-xbox.workers.dev`): a real builder run as a peer job shows ≥ 1 tool item with an input line
  and ≥ 1 assistant item on the sender within 30 s of its first tool call while watched; zero activity envelopes
  while unwatched.
- Stop the brain (`launchctl kill TERM gui/$UID/com.secondbrain.server`), ask from the CLI → an answer within 60 s.

---

## 36b — Files + workspace

**B1. Transfers** (new `Peers/PeerFiles.swift`; payloads in `PeerModels`; wire version stays 1; caps gain `files`).
- Payloads: `xfer-start {xferId, jobId?, kind: file|folder, name, size, sha256, chunks, open}` · `xfer-chunk
  {xferId, idx, data}` · `xfer-ack {xferId, upTo, ok?, reason?}` · `xfer-cancel {xferId, reason}`.
- **Frame size.** 64 KB raw per chunk by default: base64 in the payload (≈ 85 KB) then base64 of the ciphertext in
  the seal (≈ 114 KB + envelope) stays under `PeerSeal.maxBlob` 144 KB and the relay's `MAX_BLOB` 192 KB; 96 KB
  would seal at ≈ 171 KB and fail. A unit test seals a full chunk and asserts the size. B4 tests bigger frames.
- **Own lane.** Transfers skip the persisted outbox: one lane per peer, ≤ 16 chunks in flight (≈ 1.8 MB, under the
  relay's 8 MB / 200-message mailbox), self-limited to half the relay's per-socket rate. Receiver acks every 8 with
  the highest contiguous index. Unacked chunks are re-sent **as the same sealed envelope (same id)**, so the relay
  de-duplicates them (`index.ts:161`); back-off 20 s doubling to 5 min; 10 min without any ack → "Paused — Mahmoud's
  Mac isn't answering", and the transfer restarts (new `xferId`) when the next envelope of any kind arrives from
  that peer. `rate`/`full` nacks slow only the lane. Chunks skip `seen.json`; the receiver keeps a received-bitmap.
- **Restart, not resume.** Each attempt has a new `xferId`; stale chunks of an old attempt are dropped. If either
  True quits, the transfer starts over: job-linked ones (B2) are kept in `~/.true/peers/xfer/pending.json` and
  restart on launch; a plain `put` reports "True restarted — run it again". `.part` files and sender temp archives
  are swept after 1 h.
- **Sender prep.** Files and folders are checked against the secrets list: a single secret file fails ("Won't send
  secrets: id_rsa"); inside a folder secrets are skipped and listed in a note. Folders are packed to
  `~/.true/peers/xfer/out/<xferId>.tgz` with `/usr/bin/tar -czf --no-mac-metadata -L` (follow symlinks, so skill
  folders whose files are links arrive as real files), except links to a folder outside the one being sent or to
  the secrets list, which are skipped and listed. Then the archive is hashed with the streaming
  `UpdateLogic.sha256Hex(fileAt:)`, then `xfer-start` goes out. Needs free space ≥ the archive.
- **Receiver checks** before acking `xfer-start`: sender is a pinned peer; caps say `files`; `xferId` is a UUID
  never seen; `size ≤ 100 MB`; `chunks == ceil(size / frame)`; ≤ 2 transfers at a time from that peer; name passes
  `DropName.sanitize`; free space ≥ 2 × size (`DropFS.freeBytes`); inbox quota (2 GB per peer). Each chunk: `idx` in
  range, total bytes ≤ declared. Data lands in `~/.true/peers/xfer/<xferId>.part` (0600).
- **Landing reuses `DropFS`** (`RemoteDrop.swift:96-160`: free-bytes, quarantine, never-overwrite `name-2.ext`, 0700
  dir, the Run 24 drop threat model). New on top: SHA-256 check (mismatch → one automatic restart, then "File arrived
  damaged"); for folders `tar -tvzf` lists members and any absolute path, `..`, symlink, hardlink or device fails
  it; the listed total must be ≤ 500 MB, ≤ 20,000 entries and fit on disk; extract into a temp folder on the same
  volume (never `-P`, `--no-same-owner`), **strip every exec, setuid and setgid bit**, set `com.apple.quarantine`,
  then rename into place exclusively (`DropName.numbered` on a clash).
- **Where things land.** `put` → the receiver's inbox; the sender cannot name a destination. Job-linked transfers →
  a folder derived from `jobId` (B2); any destination the sender names is ignored.
- **Open.** `open: true` runs `/usr/bin/open` on the landed file only if "Let peers open files on my screen" is on
  (global, default off), the extension is on the open list (pdf png jpg jpeg gif heic webp mp4 mov m4v mp3 m4a wav
  txt md csv), and in `ask` mode only after the owner taps Open on the inbox card. Otherwise it is revealed in Finder.
- **Plain reasons** (one line each, the exact strings): "Not enough space on Mahmoud's Mac" · "Mahmoud's inbox from
  you is full (2 GB)" · "Too big — 100 MB per file" · "Relay busy, retrying" · "Relay daily limit reached — resets at
  midnight UTC" (Cloudflare quota errors, shown distinctly) · "Paused — Mahmoud's Mac isn't answering" · "File arrived
  damaged" · "Won't send secrets: <name>" · "Mahmoud's True needs the update (v1.3+)".
- **CLI:** `true-peer put <file|folder> <peer> [--open]` (new).

**B2. Jobs.**
- `--with <path>…`: the job payload gains a manifest `with: [{xferId, name, size}]`, offered only to a peer whose
  caps say `files`. The job and its attachments queue like jobs do today (7 days) while the peer is away. The
  receiver accepts an `xfer-start` with a `jobId` only for an inbound job it holds, after that job is approved (in
  `ask` mode the card shows "3 files · 12 MB attached"; on decline nothing is transferred), lands it in that job's
  `in/` with no tap, and starts the job when every manifest entry has landed ("Receiving files 1/3"). No progress for
  30 min → the job fails "Attachments didn't arrive".
- **Return.** When the job's agent ends it (done or failed), True packs `out/` + `result.md` into one folder transfer
  back, if `out/` is non-empty or the result is over 64 KB. Jobs ended by the owner (Stop, decline, kill switch,
  revoke, unpair) return nothing. `out/` over 100 MB is not sent: the result says "out/ is 230 MB — left on Yahia's
  Mac". The sender accepts it only for a job in its `sent` list, into `~/TruePeers/<peer-slug>/jobs/<shortId>-
  <title-slug>/`. The status carries `files: {xferId, count, bytes}`; the sender's job shows "Done · receiving files
  40 %"; `true-peer result` and the new `true-peer wait <jobId> [--timeout 30m]` return only after the files land
  or fail.
- **Missing repo → offer card** (Run 34, no auto-clone). A repo job with no local clone raises an offer card:
  "Mahmoud's job needs <name> (github.com/owner/name) — Accept / Decline". The URL is `https://<host>/<owner>/
  <name>.git` from the normalised repo (never ssh; host github.com, gitlab.com, bitbucket.org, or one the owner
  already has a clone from). Accept → `PeerLauncherLive.cloneRepo` into `<projectsRoot>/<slug>.peers/<peer-slug>`,
  recorded as a share, `#<slug>` joined (Run 34); Accept also approves this job, and later jobs on that repo are
  share jobs (always `ask`, Run 34). No deviation from Run 34.
- **Revoke / unpair** cancels that peer's transfers both ways and deletes their `.part` and temp files.
- **Folders.** `~/TruePeers/<peer-slug>/` uses the peer's label slug, with `-<4 hex of mailbox>` added if two peers
  would share a slug. Inbox files and returned job folders are the owner's files and are never swept; `in/` and
  `out/` inside `~/.true/peers/jobs/<id>/` are deleted with the job record after 30 days. Don't add `~/TruePeers` to
  the folder list (help text says so).
- Hub job sheet: a **Files** row ("3 in · 2 out · Show in Finder") on both sides and a progress line while a transfer
  runs ("Sending FDOS-lecture-01.mp4 · 42 %"). Peers sheet: inbox card per received file (Open / Show in Finder) and
  the "Let peers open files on my screen" toggle.

**B3. Teaching the agents.** Role cards and `true-peer help` lead with a 6-line "how to work with <peer>" block: paths
are on the peer's Mac; `put` sends a file or folder to their inbox; `--with` attaches files to a job; leave files in
`out/` to send them back; results have no size limit; `wait` blocks until a job and its files are back. The
envelope names `in/` and `out/`: "Files the sender attached are in <in>. Put anything that should go back in <out>."

**B4. Measure the relay, then set frames and caps** (dev relay first). Deploy the relay code to a separate
`true-relay-dev` Worker with `SENDS_PER_MIN` 600 and `MAX_BLOB` raised; run the harness there with 64 KB and
256 KB frames (a 256 KB chunk seals at ≈ 460 KB, under the Workers 1 MiB WebSocket message limit — confirm). Read
rows written per message from the Worker's Durable Object analytics (expected 5–6: AUTOINCREMENT, the unique id,
`setAlarm` — `index.ts:70,170,194`). Record the number in SPEC, pick the frame size, and set the daily caps from it.
Until then the conservative caps hold: per True per day ≤ 50 MB of transfers and ≤ 2,000 activity envelopes. Then
`vitest`, and `wrangler deploy` of the live `true-relay` with `SENDS_PER_MIN` 600 and the chosen `MAX_BLOB`.

**36b steps** (one builder run; each step one commit)
1. SPEC.md "Run 36" section (as-built deviations at the end).
2. B1 core. Check (new `PeerFilesTests` over `FakeRelay`): full chunk seals under maxBlob; 50 MB file + 200-file
   folder round trip; a folder of symlinked skill files arrives as real files; a 4.5×-compressible text folder
   passes; `../`, absolute, symlink, hardlink and device members refused; exec bits stripped and quarantine set;
   secret file refused, secrets in a folder skipped with the note; dropped chunk re-sent with the same envelope id;
   peer offline 10 min (lid closed) → "Paused", restarts with a new xferId when it answers, stale chunks dropped;
   bad checksum → restart then "damaged"; oversized `size`, wrong `chunks`, out-of-range `idx`, overlong data, reused
   `xferId`, a third concurrent transfer → each refused; disk full (fake free-space) and inbox quota → their
   reasons; a `full` nack on a chunk does not delay a chat message; kill switch and revoke mid-transfer → cancelled,
   `.part` gone; `--open` with the toggle off → revealed; in `ask` → waits for the tap.
3. B2. Check (`PeerEngineTests`): a job held until its 3 files land; ask-mode attachments refused before Approve,
   nothing sent on decline; unsolicited `xfer-start` with a `jobId` the receiver doesn't hold → refused; return on
   done **and** agent-failed, not on Stop/kill switch; a 200 KB result arrives whole as a file; `wait` blocks until
   files land and times out; missing repo → offer card → fake `cloneRepo` → job runs; old peer (no caps) →
   "needs the update"; desk reuse: two jobs on one desk each get their own `in/`/`out/`.
4. B4 on `true-relay-dev`: rows-per-message + frame decision recorded in SPEC, caps set from it; `vitest` green;
   live `true-relay` deployed; it accepts 200 sends in 30 s from a test identity without `rate`.
5. B3 + Peers-sheet and Hub controls. Check: UI stills shown to Yahia before install.
6. `swift build` + `swift test --filter "Peer|Chat|Files"` green.

**36b Done means**
- Live-relay harness: a 50 MB file and a 200-file folder each way, SHA-256 match, wall time recorded (target ≤ 3 min
  for 50 MB at 64 KB frames); peer offline mid-transfer → paused, then completes after it reconnects; a chat message
  sent mid-transfer arrives within 5 s; a `--with` job whose `out/` and a 200 KB `result.md` come back whole.
- **Mixed versions:** the harness runs one engine with `files`/`watch` switched off; the new side shows "needs the
  update" for `put`/`--with` and today's activity stream still flows both ways.
- **Live check owed to Yahia + Mahmoud** (after both Trues update): `true-peer put FDOS-lecture-01.mp4 mahmoud
  --open` opens on Mahmoud's screen; Mahmoud's agent delegates "copy ~/.claude/skills/goldfish into out/" to Yahia's
  Mac and the folder lands intact.

---

## Alternatives considered
- **Cloudflare R2 for files** (full speed, GB files, no row quota): needs R2 switched on with a card, and today's
  relay runs on the Workers Free plan. Yahia's call. Transfers sit behind a `PeerFileTransport` protocol so R2 can be
  added later without touching jobs or the CLI.
- **Direct Mac-to-Mac (Tailscale / LAN)**: fastest, but Mahmoud would need to join a tailnet; Run 29 removed it.
- **Relay-side per-identity daily cap**: a Durable Object's memory resets on hibernation and a stored counter costs a
  row per message. Rejected; both clients are ours and keep their own budgets.

## Risks
- **Relay row quota** is shared by everything on the relay. Signal: quota errors or 429s in `drops.log`. Mitigation:
  watch lease, per-True budgets, B4 measurement, the distinct "daily limit" message; R2 if real use outgrows it.
- **Everything level** sends command lines and the agent's words; masking is best-effort. The picker says so.
- **TCC prompts:** the inbox lives in `~/TruePeers`, outside Desktop/Documents/Downloads, so landing never triggers one.

## Run 37 notes (access level + sandbox — not built in Run 36)
Run 37 opens with a spike, then its own plan and review. Inputs already known:
- Per peer **Folders only / Whole Mac**, with `get`/`ls`/put-to-path. Whole Mac excludes hidden path components
  (`.git/hooks`, `.claude/`, `.zshrc`), `~/Library`, `~/Library/LaunchAgents`, the secrets list and other peers'
  `~/TruePeers` folders; file ops on shares always tap; `auto` taps for writes.
- First weigh the cheaper lever: a per-peer inbound mode (bypass/auto/ask per peer) may meet the need without a sandbox.
- Sandbox facts: Seatbelt wraps Bash only; Read/Edit/Write follow `permissions.deny`; `--settings` is one file per
  session (merge with the pane hooks); `allowUnsandboxedCommands: false`; `claude --restricted` refuses bypass and
  **removes Bash/WebFetch unless `--tools` lists them**, so its argv must name the tools, the network domains and how
  headless git is approved.
- Known escapes to close and probe: a writable `<clone>/.git` lets the agent plant hooks, `core.fsmonitor`,
  `credential.helper` or `core.sshCommand` that True's own unsandboxed git would run — allow only objects/refs/logs/
  index/`worktrees/<desk>`, run True's git with hooks and fsmonitor off and `push --no-verify`. The agent must not
  reach True's control socket (`~/.true/peer.sock`) or it can act as the owner. Dir jobs need their folder in
  `allowWrite` per job. Job paperwork would have to leave `~/.true` (denied).

## Review
**Round 1 — 2026-10-26: 8 blockers / 18 shoulds / 4 nits, verdict rethink.** All resolved: 64 KB chunks with the
seal arithmetic and a test; consent for file ops; merged hooks+sandbox settings, job dirs vs the sandbox, tool-level
probes (now Run 37 notes); auto-clone dropped for the Run 34 offer card with an https URL from the normalised repo;
per-peer vs global settings stated (Run 37). Shoulds and nits applied (split into parts, 100 MB cap,
restart-not-resume, own lane, quota budgets, name sanitiser, manifest, no return on owner stop, errno reasons,
forwarder rewrite, mask patterns, Oracle diagnose-first, builder view via `PeerBuilders.report`, `DropName`,
`sha256Hex(fileAt:)`, `tar -tvzf`). `~/True Peers` became `~/TruePeers`: a space breaks unquoted agent shell commands.

**Round 2 — 2026-10-26: 6 blockers / 22 shoulds / 2 nits, verdict buildable after fixes.**
- Blockers: the 4 sandbox blockers (`--restricted` drops Bash, the bypass probe row can't run, dir jobs can't write,
  `.git` escape) → the sandbox and access level moved to Run 37 with these as spike inputs. Symlinked skill folders
  and the 4× ratio → follow links on the sender, absolute size/entry bounds. `put` into `.git/hooks` / exec bits →
  `put` lands only in the inbox, every exec bit stripped.
- Shoulds applied: smallest wedge first (A0); workspace stays in today's job dir (no migration); `get`/`ls` deferred
  (journey 1 now uses `out/`); bigger frames measured in B4; `DropFS` reused; the inbox named as the new write
  location; watch lease keeps old peers streaming, uses `since`, checks the lease owner; one activity budget per True
  plus nack reasons in `PeerSendResult`; caps measured on a dev relay before the live deploy, conservative caps until
  then; resend with the same envelope id, back-off, pause and restart, attachment and `wait` timeouts; full receiver
  validation and a fresh `xferId` per attempt; job-linked transfers bound to held/sent jobs with no tap; caps
  persisted; share-level × content table and widened masks; added test cases and new test files marked; vocabulary
  mapped to code (`PeerShare`, offer card, `wait` new); secret-glob and refusal strings; Oracle's still-cold reply;
  UI stills defined; "Free plan" restated as today's setup and Yahia's call. Nits: code refs corrected, lease TTL
  stated, retention and slug-collision rules added.
- Rejected: *cut 36c entirely without notes* — kept as Run 37 notes so the round-2 findings aren't lost.
  *Per-peer read isolation of `~/TruePeers`* — only matters once Whole Mac exists; moved to Run 37 notes.
  No round 3 (one more round was allowed after round 1's rethink; this is it).
