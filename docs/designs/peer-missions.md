# Missions — one plan, many Macs (the peer ecosystem)
Status: proposed (approved by Yahia 2026-10-27: Build it) — building M1. Blender layer (M2.5, M2.6, M3.4): approved by Yahia 2026-10-27 (Build it);
built only after M2's Done means pass.

## Goal
True's peer system (Runs 29–36a) lets Yahia's Claude send jobs to a **peer** (another Mac running True, paired by
invite; today the only one is Mahmoud's MacBook Air), watch them, chat and ask. In real use it behaves like sending
one job at a time and redoing it by hand when it fails: of 31 jobs sent 2026-10-20..27, 9 failed (29%), one task was
sent 4 times before it landed, and independent work waits in line behind unrelated work.
Missions turns the Macs into one production line, in three layers that ship and are measured one after another:
- **M1 Bulletproof jobs** — checked before sending, resume instead of re-send, independent jobs side by side.
- **M2 Missions + Board** — one goal → a plan of jobs across Macs with an order, one live board, a merge gate.
- **M3 Shared mind + Cross review** — decisions known on both Macs; the other Mac's Claude reviews before main.
Yahia chose all three as one ecosystem (2026-10-27). **One gate per layer = its Done means.** **Gate change (Yahia, 2026-10-27):** M2 no
longer waits for 7 days / 20 real jobs; each layer unlocks when its scripted drill passes (run by Foundry, see
`peers-foundry-run.md`). The real-traffic numbers are still reported, as a monitor; if M1's replay shows lanes alone removed
the waiting, Yahia is told before M2 starts and may re-scope. M3 starts after M2's Done means.

**North star (Yahia, 2026-10-27):** "two accounts working on one project with double the creative input." The second
Mac's value is its different ideas, not only its capacity. So both Claudes shape the work, and an agent **Blender**
merges their ideas: it finds the gaps in each side's idea and fills them from the other, producing ONE improved
plan. It never runs two builds to keep the better one. Three channels feed it: **two blind plans** (M2.5), **two takes
on creative jobs** (M2.6) and the **peer ideas feed** (M3.4). The Blender is its own layer: it is measured against
single-plan missions, so it starts only after M2's Done means pass (M3.4 also needs M3.1's Mind log).

### Evidence (`~/.true/peers/sent.json`, `inbound.json` on Yahia's Mac, 2026-10-27)
- Sent: 31 jobs, all by an agent. 18 done, 9 failed, 4 in flight.
- Failure reasons: `No local clone` ×2, `Couldn't fetch the repo` ×2, `Directory not allowed` ×1 (a sender-Mac path),
  `Stopped by sender` ×3 (black box), `Hit an error` ×1 (no reason), `Peer removed` ×1.
- "FDOS: bookkeeper brain gaps": 4 sends (stopped, error, stopped, done); each re-send started from zero.
- "Wave 1a" and "Wave 1b" sit `In line behind` the CRM job though none depends on another (Run 35: one desk session
  per peer project, one job at a time).
- Inbound: 10 jobs, 4 failed (2 sender-side paths, 1 fetch, 1 repo outside allowed roots).

## Vocabulary (one name per thing)
- **Peer** — another Mac running True, paired by invite (`PeerLink`). **Job** — unchanged (`SentJob` / `InboundJob`).
- **Card** — what a Mac can do, announced to its peers: today's `PeerCaps` (36a, `caps` payload, `caps.json`) extended
  in place with optional fields, not renamed. Shaped after the A2A Agent Card (A2A = the open agent-to-agent protocol).
- **Desk session** — Run 35: one Claude session a receiver keeps per (peer, project), running that peer's jobs in turn
  so context carries over. **Run N** — a numbered True build recorded in SPEC.md. **Hub** — True's agents/builders panel.
- **Resume request** — a small sealed message `{jobId}` the sender sends to ask about or restart a job it already sent.
- **Preflight** — checks before a job leaves the sender. **Accept check** — checks on the receiver before a job starts.
- **Resume** — a stopped job continues on its same Claude session from where it stopped.
- **Lane** — one slot on a receiver's peer project; each lane is its own desk session in its own worktree.
- **Mission** — one goal = a mission file of jobs plus their order (`needs:`). **Mission branch** — `mission/<id>`, where
  a mission's jobs merge. **Merge gate** — the owner's Mac fetches a job branch, runs the check, merges on green.
- **Board** — the live view of one mission, in the Hub. **Mind** — the synced decisions log per peer pair.
- **Cross review** — the other Mac's Claude reviews a diff cold before it reaches main.
- **Blind plan** — one Mac's draft of a mission file, written without seeing the other Mac's draft.
- **Blender** — the agent that reads both blind plans (or both sketches) and writes ONE blended plan plus a gap ledger.
- **Gap ledger** — `blend.md`: which plan gave the spine, what each side lacked and got from the other, conflicts and
  how they were settled, ideas dropped and why. Every job in the blended plan is tagged `from: X · Y · both · new`.
- **Sketch** — a capped, throwaway take on one creative job by one Mac; its branch is never merged.
- **Idea** — a suggestion or concern either Claude (or person) posts to the Mind; it waits on the Board as a suggestion.

## Open-source picks (Repo Radar index `~/.claude/sharpen/.repos-index.json` via `repos.py pick`; GitHub checked 2026-10-27)
True is a native Swift app with an MIT public export: each pick is **imported** (Swift package, permissive licence) or
**borrowed** (design re-written in Swift). GPL code is never copied (PairDrop, GPL-3.0: out).
| Need | Pick | Licence | How |
|---|---|---|---|
| Job states, Card, results | a2aproject/A2A (★26k, active) | Apache-2.0 | **Borrow** the task model: `submitted · working · input-required · completed · canceled · failed · rejected`, Agent Card fields, streamed status. Our end-to-end encrypted relay stays the transport. An A2A gateway for outside agents is later. |
| Resume, retries | dbos-inc/dbos-transact-ts (MIT), inngest | MIT / mixed | **Borrow** durable steps: the job's Claude session is the checkpoint, every send carries an idempotency key (`jobId`), a retry never runs finished work twice. No Node runtime enters True. |
| Review checklist | mattzcarey/shippie (github.com/mattzcarey/shippie) | MIT | **Borrow** its review areas into our checklist (in M3 below). |
| Shared state | automerge/automerge-swift (★330, active) | MIT | **Not now.** Every Mind entry has one author, so there is nothing to merge; a synced append-only log does the job without a Rust binary. Automerge is the upgrade if two people ever co-edit one record. |
| Agent memory | mem0 / memori | Apache / mixed | **Skip**: second brain + Ask desk (Run 33) cover it (Radar note: "no current gap"). |
| Queues | bullmq / pg-boss; hatchet, open-multi-agent also in the index | MIT | **Skip** the libraries (Redis / Postgres / servers); per-queue concurrency is borrowed into Lanes. Not weighed further. |

## Users & journeys
1. As Yahia, I type one goal ("FDOS Waves 1a + 1b, then CRM U0 on top"); my Claude writes a mission file, I glance at
   it, start it, and 1a and 1b run at once on Mahmoud's Mac, U0 after both have merged.
2. As Yahia's agent, I send a job; preflight sees the repo isn't cloned on Mahmoud's Mac and raises the share offer
   instead of letting the job fail 30 s later.
3. As Yahia, when a job stops halfway (usage limit, crash, restart), it resumes by itself on the same session; I never
   re-send it and it never redoes finished work.
4. As Mahmoud's Claude, my job arrives with the decisions Yahia's side recorded for this project; before the mission
   lands on main, Yahia's Claude reviews the diff cold.
5. As Yahia, I type one goal; both Claudes draft a plan without seeing each other's; I get ONE plan and a short ledger
   showing what each side added that the other missed; I approve that one plan.
6. As Yahia, a creative job (a screen, a name, copy) gets a quick sketch from each Mac; I get one build that keeps the
   best of both, not a choice between two.

## Scope
**In:** M1, M2, M3 as below, plus the Blender layer (M2.5, M2.6, M3.4), gated on M2's numbers. New files live in
`Sources/True/Peers/`. **Out:** two full builds of one job
to keep the better one (Yahia rejected it: the Blender fills gaps instead) · files/inbox (Run 36b as approved) · access levels + sandbox (Run 37) · LAN
pairing (Run 39) · more than two peers in the UI (data model allows N) · an A2A gateway for non-True agents ·
pooling Claude plans.

## Approach — M1 Bulletproof jobs (`PeerLogic.swift`, `PeerEngine.swift`, `PeerModels.swift`, `PeerCLI.swift`)
**M1.0 spike (first, half a day): capture the session id.** Background jobs: read `session_id` from the `init` line
of the job's `stream.jsonl` (36a already tails it) into a new `InboundJob.sessionId`. Pane/desk jobs: read it from
the pane's resume file (`PaneResume.swift` already stores `sessionId` per pane). Prove both on Yahia's Mac with a real
Claude run: kill mid-job, resume with `--resume <id>` + continue prompt, the transcript shows the same session and
no finished step repeated. If either mode cannot be captured, that mode keeps today's behaviour and the plan says so.

**Desk lanes share one session.** A desk lane runs many jobs in turn on one Claude session, so its session id belongs to
the lane, not the job. Resuming a desk job resumes the lane's session with a prompt that names the job and repeats its
envelope: "Continue job <title> (<jobId>) from where it stopped. The jobs before it are finished; don't touch them."
A background job owns its session alone and resumes with "Continue from where you stopped."

**Where the new fields live.** `InboundJob` (`inbound.json`): `sessionId`, `lane`, `resumes`, `pausedReason`,
`resumeAt`. `SentJob` (`sent.json`): `retryOf`, plus `pausedReason` / `resumeAt` mirrored from status. All optional,
so old files still decode. (`fixRounds` belongs to M2's mission events, not M1.)

**States.** Add `PeerStatus.paused` (with `reason`, `resumeAt` in the receiver's local time, labelled as such).
| Today (`PeerStatus`) | A2A on the wire | Notes |
|---|---|---|
| queued, accepted | submitted | |
| working | working | |
| paused (new) | working + status note | "Paused: usage limit, resumes 23:00 (Mahmoud's time)" |
| needsYou | input-required | also accept-check failures and fix rounds |
| idle | input-required | a pane job's Claude stopped without `result.md` (`PeerEventMap`); stays `idle` on the wire (old peers know it); not auto-resumed; a resume request asks it to finish |
| done | completed | |
| failed | failed | only after the caps below, always with the last reason |
| declined | rejected | |
| "Stopped by sender" (today `failed`, or `declined` if still queued: `PeerEngine.handleStop`) | canceled | both cases; no longer counted as a failure |
Old peers: a True without the new states reads `paused` as `working` and `canceled` as `failed` (one decoder table);
tests cover new→old and old→new, including an old receiver mid-job (it never sends `paused`). `blocked` (M2) is a
Board state for a mission job not yet sent, never a `PeerStatus`.

**Stop causes → behaviour.** Usage limit → `paused`, resume at the reset time. True quit/crash/auto-restart (Run 31)
→ `paused`, resume on launch. Receiver offline → stays `working`, sender shows "peer offline", reconcile on reconnect.
Claude error → resume; after **3 resumes** → `failed` with the last error line. Sender stop → `canceled`. Two separate
counters: `resumes` (max 3, crashes/limits) and `fixRounds` (max 2, red checks and review blockers in M2/M3).

**Duplicates and resume requests.** A job message whose `jobId` the receiver already holds is dropped, as today
(`PeerEngine` inbound check); the sender never re-sends a job to nudge it. To ask about or restart a job it sends a
**resume request** `{jobId}`, sealed and checked like today's stop request (only the job's own sender). Receiver:
`paused` → resume now; `needsYou` from a failed accept check → re-run the accept check, then start; `needsYou`
waiting on an answer, or `idle` → re-send status (for `idle`, also prompt "Finish the job and write result.md");
any other known state → re-send current status; no record → reply "unknown job", and the sender marks it `failed`
("<peer> has no record of this job") with Retry. An old peer ignores the request; the sender keeps the last known
state. A deliberate retry is a new job with `retryOf: <jobId>`, which inherits the session id when there is one.

**Card.** `version`, `kinds` (job kinds it accepts), `repos` (SHA-256 of each normalized remote URL cloned under
allowed roots: lower-cased host/path, no `.git`, no credentials; the sender hashes its job's repo the same way and
compares, so a Card never lists repo names to a peer that doesn't already know them), `lanes`
(`total`, `free`), `tools` (`gh`, `vercel`, `wrangler`, `docker`: present yes/no only, never tokens or accounts).
Sent on connect and when any field changes; a Card older than 10 min is **stale**.

**Preflight (sender) — refuse vs queue.** Refuse with a plain reason + fix (nothing is sent): repo not in a fresh Card
and no Run 34 share → the refusal names the share step (the agent's CLI output says it; Yahia sees the Run 34 share
offer card on his own Mac). Preflight never shares by itself; the share goes only on Yahia's click or an explicit
share command. Any path in the job is a sender-Mac path (36a own-path guard, extended
to dir jobs); the peer's `version`/`kinds` lack this job kind → "needs update". Queue (as today's outbox): peer offline
or Card stale; preflight re-runs on reconnect.

**Accept check (receiver).** Before starting: fetch the repo, check the directory is allowed. Failure → `needsYou` with
the reason (not `failed`); the sender fixes it and sends a resume request for the same job.

**Lanes.** The Run 35 desk key `(peer, project)` becomes `(peer, project, lane)`. A job naming a branch already held by a
lane goes to that lane (if that lane is busy, the job waits for it: "In line behind <job> (same branch)"); otherwise
the first free lane; otherwise it waits (as today). Each lane is its own desk session (Run 35 context-keeping, per
lane) in its own git worktree. **Migration:** lane 1 IS today's desk, same key `deskKey(mailbox, project)` and same
worktree `<clone>.peers/<peer-slug>/desk`, so a desk job running during the upgrade carries on untouched; lane n ≥ 2
uses key `…|<n>` and worktree `…/desk-<n>`, created (`git worktree add`) on first use and removed once the setting
drops below n and its job has ended. Git operations on one clone (fetch, worktree add/remove) run one at a time under
a per-clone lock. Default 2 lanes; the receiver sets it with `true-peer lanes <1-4>` (their CPU and their Claude plan),
stored in UserDefaults `peer.lanes` beside `peer.desk`. No new control: the Peers sheet's existing desk list shows one
row per lane.

## Approach — M2 Missions + Board (new `Missions.swift`, `MissionBoardView.swift`; `PeerCLI.swift`; Hub)
**Re-scope (Yahia, 2026-10-28: "Slim M2").** M1's drill showed independent jobs already start side by side (16 pairs, all ≤ 30 s), so M2 drops what M1 covers and keeps order + merge. Router lane juggling and the "jobs overlap" goal are dropped; the Board screen moves to U4 with the Blender (one design pass, one stills gate).
**Mission file** (Markdown, written by Yahia's Claude from his goal, editable before start; copied to
`~/.true/missions/<id>/mission.md` at start and never changed after; events in `events.jsonl`, append-only):
```
# Mission: FDOS data plane + CRM
into: mission/fdos-dp          (optional; default mission/<id>)
check: npm test                (optional; the merge gate command, run on the owner's Mac)

## Wave 1a: period locks
repo: https://github.com/yahiaelmahdi7-bit/finance-director-os
where: auto
<the job's prompt, any length>

## Wave 1b: original store
repo: https://github.com/yahiaelmahdi7-bit/finance-director-os
where: mahmoud

## CRM U0: craft pass
repo: https://github.com/yahiaelmahdi7-bit/finance-director-os
needs: Wave 1a, Wave 1b
tool: vercel
```
Fields: `repo` (required), `where` (`auto` · `mine` · a peer label), `needs` (titles in this file), `tool` (Card tool
the job needs), `review` (`cross` to cross-review this job alone). Validation at start, refusing with a plain line:
unique titles, every `needs` title exists, no cycles, `where` is valid, `repo` present. No `check:` → the merge gate
asks Yahia instead of merging.

**Router (`where: auto`) — a rule in code (slim).** The peer if its fresh Card has the repo and the `tool`; otherwise Yahia's
Mac. No free-lane counting: M1 lanes run jobs side by side. Neither fits (no repo here either) → the job waits with the reason in its status.

**Runner — reuse, don't rebuild.** Remote jobs go through today's `PeerEngine` send (M1 behaviour included); jobs on
Yahia's own Mac start through `AgentLaunch` as background sessions in worktrees. `Missions.swift` holds only the order,
the merge gate and mission state. A job starts when all its `needs` are merged into the mission branch, from that
branch's latest commit.

**Branch transport + merge gate.** A code job pushes `peer/<mission-id>/<job-slug>` to the repo's own git remote (both
Macs already push there: today's jobs push `peer/<peer-slug>/<shortId>` from `PeerLogic`'s branch naming; mission
jobs get the mission name, single jobs keep today's). The owner's Mac fetches it, merges into the mission
branch in a fresh worktree, runs `check:` (taken **only** from the owner's mission file, never from the job), and on
green pushes the mission branch. Merges are one at a time per repo. Conflict or red check → the job goes back
`input-required` with "rebase on <sha>" or the failing output (a fix round). No shared remote or push refused → the job
ends `input-required` "can't merge: no shared remote" for Yahia. Owner offline → fetch on next launch. The mission
branch reaches **main** only by Yahia's click (after M3, after cross review).

**Mission states.** `running · needs-you · done · canceled`. A job that fails or is declined: its dependents become
`blocked`, independent jobs carry on, the mission goes `needs-you` with three buttons: Retry job · Skip it (dependents
run without it) · Cancel mission. Cancel stops every unfinished job (sender stop → `canceled`). After a True crash or
restart the runner reconciles from `events.jsonl` + the jobs' statuses and carries on.

**Board (moved to U4, with the Blender).** Until then: the mission name on each job's existing row and `true-peer mission status <id>`.
Later, in the Hub, one card per mission, one row per job: Mac · state · current step (36a live view) · time · cost
when known; `blocked` rows say what they wait for. `true-peer mission start|status|cancel <id>` on the CLI. Plain labels.

**Two blind plans + Blender (M2.5; new `MissionBlend.swift`).** Turned on only after M2.1–M2.4 have run a few
single-plan missions, so those are the baseline. `true-peer mission plan "<goal>" --project <p>` (and the Board's
New mission field):
1. **Seal.** The owner's Claude drafts plan A (same mission-file format, plus a one-line *why* per job) and it is
   written to `~/.true/missions/<id>/plan-a.md` **before** the peer's draft can arrive. At the same time a read-only job
   of new kind `plan` goes to the peer with the goal, the repo and the Mind block (M3, when present). Its envelope
   never carries plan A. The peer's Claude returns plan B → `plan-b.md`. The `plan` job takes a lane, and its cost
   shows on the Board.
   **Read-only is a launch flag, not a request.** `AgentLaunch` gains a tool list beside `--permission-mode`. A `plan`
   job runs with `--permission-mode plan` and only read tools allowed (Read, Grep, Glob): it can read the repo but not
   write, run commands or reach the network. M2.5's first step proves the exact flags against the installed `claude`
   (a write attempt is refused), the same way M1.0 proves resume.
2. **No peer, no wait.** Peer offline, plan job failed, or no plan B within 15 min → the Blender is skipped and the
   mission continues with plan A, and the plan job is canceled (sender stop) so it frees the peer's lane. The Board
   says "Single plan: <peer> didn't answer". A mission never blocks on the second plan.
3. **Blend.** A background Claude session on the owner's Mac (`AgentLaunch`, `--permission-mode plan`, **no tools at
   all**: the goal, the plans, the Mind block and the ideas go inline in its prompt, and it gets no repo access, so
   untrusted peer text has nothing to act on) gets the goal, the two plans **with labels shuffled to X/Y** (it cannot tell which Mac wrote which, so it
   has no home bias), and the Mind block. Its instructions: pick the stronger plan as the **spine** and say why; for
   every job, check whether the other plan covers something this one lacks (a step, a risk, a test, an order, a better
   approach), and graft it in; settle each conflict with one line of why; list what was dropped and why. Never
   average two approaches into a third that neither proposed, unless the ledger says why. If the plans agree, say
   "Plans agree" and list only the small differences.
4. **Check (in code, not by the model).** The blended file passes M2.1 validation; every job has a `from:` tag; the
   ledger has the five sections (spine · gaps filled X→Y · gaps filled Y→X · conflicts · dropped), and at least one
   gap is filled in total, or the ledger says "Plans agree". Fail → one fix round, then Yahia sees both plans and
   the reason.
5. **Approve.** The Board shows the ONE plan with each job's tag, now revealed as "Yahia's Mac / Mahmoud's Mac /
   both / new", and the ledger folded under it. Yahia starts it (or edits, then starts). From there it is a normal
   mission: `mission.md` is frozen, and `plan-a.md`, `plan-b.md` and `blend.md` are kept beside it.
6. **Rate.** The mission card keeps a **Compare** fold (plan A, plan B and the blend side by side) and three one-tap
   buttons: *Better than either · As good as the better one · Worse*. The tap is stored as a `rated` event in
   `events.jsonl`; the Done means count reads those events.

**Two takes → two sketches → one build (M2.6).** A job carrying `take: two` (the Blender proposes it for creative
jobs: a screen's look, naming, copy, a visual; Yahia can add or remove it before start):
1. Each Mac runs a **sketch** of the job (kind `sketch`, capped at $2 and 20 min, branch
   `sketch/<mission>/<job>/<mac>`; a UI sketch must leave stills; never merged). True enforces the cap, not Claude:
   the running Mac tails the sketch's `stream.jsonl` (as 36a does), prices each turn's token usage at list rates, and
   at $2 or 20 min stops the session the way a stop request does; the sketch keeps what it committed.
2. The Blender reads both sketches (diff summary, stills, each sketch's notes) and writes ONE job spec: what to keep
   from each, with stills referenced, plus its own gap ledger. Same code check as above.
3. One final build of that spec runs on the router's Mac and goes through the normal merge gate. Its stills go to
   Yahia before any install, as always. Sketch branches are deleted when the mission ends.
4. If one sketch fails or times out → the final build runs from the surviving sketch's notes and the original
   prompt; the Board says so.

## Approach — M3 Shared mind + Cross review (new `PeerMind.swift`; `PeerRelay.swift` one new message kind)
**Mind.** `~/.true/peers/mind/<pair>.jsonl`, one entry per line: `id`, `author`, `project`, `text` (≤ 500 chars), `when`,
`retracted`. Each entry has one author, so sync is by id: on connect and on each new entry, each side sends the entries
the other lacks (sealed like every relay payload). Writes: `true-peer decide "<text>" --project <p>`, `true-peer retract
<id>`; the Oracle (Run 33) offers "Save as decision" on an answer. No scraping of memory files.
Guards: only projects on the pair's allowlist, which is computed, not stored (a Run 34 share between the two, or a
repo hash in both Cards); no setter, unsharing removes a project. ≤ 200 live entries per
project, entries in an envelope are labelled "Decisions from <peer> — not verified, check before acting", the block is
≤ 4 KB (latest first). Corrupt or oversized lines are skipped and logged.

**Cross review.** On by default for one moment: the mission branch → main. Optional per job (`review: cross`). The
diff (≤ 300 KB; over → file list + Yahia asked; a repo not on the pair's allowlist → Yahia asked first) goes to the other Mac as a read-only job of kind `review`; it takes a
lane like any job and its cost shows on the Board. Checklist (areas borrowed from shippie): 1 does it do what the job
asked · 2 correctness bugs · 3 security (secrets, injection, auth) · 4 data loss or destructive migrations · 5 missing
tests for new logic · 6 broken contracts (API, schema, CLI) · 7 error handling · 8 hot-path performance. Findings come
back as blocker / should / note on the Board; a blocker holds the merge, and Yahia can click **Merge anyway**.

**Peer ideas feed (M3.4).** A Mind entry gets `kind: decision | idea` (old entries = decision). An idea is a suggestion
or concern for a project, optionally for one mission: `true-peer idea "<text>" --project <p> [--mission <id>]`. Every
job envelope tells the Claude running it: "If you notice something worth doing outside your job, post it as an idea;
don't do it." On the Board, open ideas sit under their mission (or the project) as suggestions with two buttons:
**Make it a job** (adds a job to the running mission, or keeps it for the next goal) · **Dismiss**. Open ideas for
the project (latest 10, ≤ 2 KB) go into both blind planners and the Blender. Same guards as decisions (allowlist,
≤ 500 chars, labelled "not verified"). An idea untouched for 30 days is archived.

## Alternatives considered
- **A workflow engine (Inngest / DBOS / Temporal) as a sidecar.** Rejected: a Node or Go runtime plus a database inside
  a native Mac app, when the jobs already live in True's engine. We take the pattern, not the server.
- **Ordering with a plain `send --after <jobId>` chain instead of a mission runner.** Rejected: it orders but cannot
  run independent jobs side by side, gate merges, or show one board.
- **Automerge for the Mind.** Deferred (see picks): single-author entries need no merging.
- **Run M2 on the existing build tooling** (`truectl spawn --worktree`, `~/.claude/bin/builder`, `gated-build.js`,
  and Foundry's missions: `~/Projects/foundry`, jobs with Foundry-run checks + approve/reject gates, already built).
  Open, decided in the M2 brief: they spawn, resume and gate on one Mac but don't speak the peer relay; the M2 brief
  weighs wrapping them for own-Mac jobs plus a thin merge script before writing a new runner. If Foundry's missions
  are reused, one of the two meanings of "mission" gets renamed first (one name per thing).
- **Two full builds, keep the better one.** Rejected by Yahia: it spends a whole build to throw away the other
  side's good ideas. Capped sketches + the Blender keep both sides' ideas for a fraction of the cost.
- **A debate (the two Claudes argue in rounds until they agree).** Rejected: cost grows per round, it is slow, and it
  ends in a winner, not a blend. One blind pass each + one Blender pass with a ledger is cheaper and can be audited.

## Steps (each names its check)
- **M1.0** session-id spike. Check: the two-mode proof above, written into SPEC Deviations.
- **M1.1** states + decoder table + Card fields. Check: unit tests for every row of the state table both directions;
  an old receiver mid-job (never sends `paused`); Card round-trips; a 36a-era Card still parses; repo hashes match
  across URL spellings (`.git`, case, `https`/`ssh` of the same repo).
- **M1.2** preflight + accept check. Check: one test per evidence failure (no clone, fetch, sender path, version,
  offline) → refuse or queue as specified; `sealAndQueue` not called on refuse.
- **M1.3** resume + resume requests + counters. Check: fake launcher records `--resume <same id>`; two jobs on one
  desk lane, killed mid-second → the resume prompt names the second job and the first isn't re-run; resume-request
  rules per state, including "unknown job"; a replayed job message is still dropped; 3-resume cap, and `resumes`
  survives a relaunch; `resumeAt` is scheduled on the receiver's own clock (the sender only displays it); an
  unparseable usage-limit reset → retry in 30 min, labelled "reset time unknown".
- **M1.4** lanes. Check: two independent jobs on one project start ≤ 30 s apart in separate worktrees; same-branch
  jobs share a lane; a desk job running before the upgrade continues on lane 1 after it; two lanes fetching one clone
  at once run one after the other.
- **M2.1** mission file + validation + router. Check: the example file parses; each validation error refuses with its line; router rule table.
- **M2.2** runner + states + reconcile. Check: fake launcher runs the example in order; a failed `needs` blocks only its dependents; kill + relaunch carries on.
- **M2.3** merge gate. Check: green merges and pushes the mission branch; red and conflict return `input-required`; no `check:` asks.
- **M2.4** Board + CLI. Check: stills (empty, running, one blocked, done) shown to Yahia before install.
- **M2.5** blind plans + Blender. Check: the peer's `plan` envelope never contains plan A (test on the sealed
  payload); the `plan` job and the Blender launch with the read-only / no-tool flags (a write attempt is refused);
  labels are shuffled before the Blender sees them; a blend missing a section or a `from:` tag fails the code check;
  peer offline → single plan within 15 min and the plan job canceled; a rating tap writes a `rated` event; stills of
  the plan + ledger card + Compare fold → Yahia before install.
- **M2.6** two takes. Check: a fake sketch is stopped at $2 and at 20 min; sketch branches never reach the mission branch; one sketch failing
  still yields a final build; branches deleted at mission end.
- **M3.1** Mind log + sync + guards. Check: two engines, entries made offline on both, reconnect → identical; corrupt and oversized lines skipped; retract propagates.
- **M3.2** decisions in envelopes. Check: labelled block present, ≤ 4 KB, only allowlisted projects.
- **M3.3** cross review. Check: a planted bug in a test diff comes back as a blocker and holds the merge; Merge anyway works.
- **M3.4** ideas feed. Check: an idea posted on one Mac appears on the other's Board; Make it a job adds a job to a
  running mission; open ideas appear in both planners' envelopes within the 2 KB cap; 30-day archive.

## Done means (on the real two Macs, after both run the same build; anything not runnable yet is reported pending)
- **M1 drill (scripted, one sitting):** (a) kill the receiver's Claude mid-job → resumes on the same session, no
  finished step repeated; (b) simulated usage limit → `paused` with a resume time → resumes; (c) duplicate send →
  ignored; (d) job with a sender path → refused before sending; (e) repo not cloned → share offer, not a failure;
  (f) two independent jobs start ≤ 30 s apart. **Then real traffic for 7 days or 20 jobs, whichever first:** failure
  rate and hand re-sends reported as measured from `sent.json` (target < 5% and 0), before/after shown to Yahia. The
  rate is reported two ways, with `canceled` counted as a failure (like the 29% baseline) and without, and with the
  raw counts, because 20 jobs is a small sample.
- **M2:** one real FDOS mission with ≥ 3 jobs and ≥ 1 `needs` edge runs from one command; one forced red check goes
  through a fix round. (Slim M2: overlap and wall-clock are a monitor only; M1's drill already proves side-by-side starts.)
- **M2.5 Blender, does it actually help:** (a) every blend passes the code check (a ledger with sections, or
  "Plans agree"); (b) Yahia rates the first 10 blends with one tap: *better than either plan · as good as the better
  one · worse*, target ≥ 6 of 10 "better than either" and ≤ 1 "worse"; (c) across the next missions, fix rounds +
  failed jobs per mission for blended vs the single-plan baseline missions (M2.1–M2.4 era), reported with the
  counts (small numbers are stated as such, not dressed up as a rate); (d) the extra cost per mission (plan job + Blender
  session) is shown on the Board and in the report.
- **M2.6:** one real creative job runs as two sketches → one build; Yahia sees both sketches' stills and the final
  side by side and says whether the final kept the best of both.
- **M3:** a decision written on Yahia's Mac appears, labelled, in Mahmoud's next envelope; retract removes it; the
  mission → main cross review returns a report on the Board. An idea posted from Mahmoud's Mac shows on Yahia's Board
  and, once promoted, runs as a job.
- Every layer: stills OK'd by Yahia before install; Mahmoud's Mac on the same build (Run 31 auto-restart) before any two-Mac check.

## Risks
- **Mahmoud's Claude plan.** Two lanes can double his usage. Signal: `paused: usage limit` rows. Mitigation: lanes are his setting; limits become pauses.
- **Session id not capturable in one mode.** Signal: M1.0 spike fails. Mitigation: that mode keeps today's behaviour; the plan says so.
- **Version drift.** Signal: Card `version` mismatch. Mitigation: preflight refuses mission jobs to an old peer with "needs update".
- **Peer code runs on Yahia's Mac in the merge gate** (building and testing it). Same exposure as merging their branch by hand today; the check command comes only from Yahia's mission file and runs in its own worktree.
- **The two Claudes think alike** (same model), so blends say "Plans agree" most of the time and add cost for nothing.
  Signal: "Plans agree" in more than half of the first 10 blends. Mitigation: the diversity comes from each Mac's own
  context (its memory, brain, Mind, repo state), so if agreement stays high, the peer planner gets a different
  brief angle (e.g. "plan for the risks first") before the Blender is kept on by default.
- **Mush.** A blend that grafts everything becomes incoherent. Mitigation: one spine, grafts justified line by line,
  M2.1 validation, and Yahia approves before start. Signal: "worse" ratings.
- **Home bias.** The Blender runs on the owner's Mac. Mitigation: shuffled X/Y labels; revealed only on the Board.
- **Cost.** A plan job (on the peer's Claude plan) + a Blender session per mission; two sketches per creative job.
  Mitigation: sketch caps; `take: two` only on creative jobs; the cost shows on the Board; blind plans can be
  switched off per mission (`--single`).
- **The peer's plan is untrusted text** steering the Blender. Same stance as the Mind: labelled as data, the Blender
  is read-only, the blended file is validated in code, and Yahia approves start.
- **Scope.** About 5 builder runs (M1, M2 ×2, Blender M2.5–2.6, M3). Each layer ships and is measured alone; the next does not start before the previous Done means pass.

## Review
Goldfish round 1 (2026-10-27): 6 blockers, 13 shoulds, 4 nits. All blockers fixed (session-id spike + state table,
36a now merged, duplicate rules + lanes over desks, mission file format + validation, failure/cancel/reconcile policy,
branch transport via the repo's remote). Shoulds fixed except:
- "Make it M1 only" — rejected: Yahia chose all three; kept, gated layer by layer.
- "Drop the lanes setting" — partly: no new UI, a CLI setting stays because lanes spend the receiver's Claude plan.
- "Add `send --after`" — rejected, listed under Alternatives.
Nits applied: peer defined, Radar index cited, Mind corrupt/size tests, receiver-time label.

Goldfish round 2 (Blender, 2026-10-27): 5 blockers, 23 shoulds, 11 nits. M1 was still queued and its builder reads
this file when it starts, so M1 findings were fixed here, not deferred. All 5 blockers fixed: desk lanes resume the
lane's session with a prompt naming the job; a sealed resume request replaces "re-send the job" (replays stay
dropped, "unknown job" handled); `needsYou` / `idle` rules no longer contradict the accept check; read-only is a
launch flag (`plan` job: read tools only; Blender: no tools, plans inline); preflight never sends a share offer by
itself. Shoulds fixed: one gate per layer, `idle` + `blocked` + queued-stop rows, field homes, Card = `PeerCaps`
extended with hashed repos, lanes migration (lane 1 = today's desk) + per-clone git lock + same-branch wait,
branch-name claim corrected, test plan (old receiver, receiver-clock resume, unknown reset, counter persistence),
M1 rate reported two ways, sketch cap enforced by True, rating tap + Compare fold, allowlist computed, cross review
asks for non-allowlisted repos. Partly:
- "Blender is speculative, move it out" → made its own layer, gated on M2's Done means; the spec stays here beside
  the layers it feeds.
- "M1 + lanes may be enough" → M2 is re-scoped before briefing if M1's report shows lanes removed the waiting.
Carried to the M2 brief (written only after M1's drill): merge gate consent for peer code (first-merge click or
stripped env, diff stat first), merge idempotency by remote sha, the reconcile state table (`events.jsonl` vs
`sent.json`, Skip on a half-merged branch), reusing the build tooling (listed under Alternatives as open).
