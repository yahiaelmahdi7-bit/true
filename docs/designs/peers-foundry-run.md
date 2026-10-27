# Peers Foundry run — the full Missions roadmap, driven by Foundry
Status: proposed

## Goal
Finish the Peers roadmap in `docs/designs/peer-missions.md` (M1 → M2 Missions + Board → M2.5/M2.6 Blender → M3 Shared
mind) as a chain of **units** run by **Foundry** (`~/Projects/foundry`: Yahia's job runner over `builder`; each job
carries checks that Foundry runs itself, so a worker's "done" never decides). Both Macs then work as one production
line where both Claudes shape the result. **Gate change (Yahia, 2026-10-27, this session):** M2 no longer waits for
7 days / 20 real jobs; each layer unlocks when its **scripted drill** passes. The real-traffic report is still produced
but only as a monitor (Risks), never a gate; peer-missions.md's Goal paragraph is updated to say so in Step 0.
peer-missions.md stays the source of truth for *what* each step builds; this plan is *how the run executes it*.

## Users & journeys
- As Yahia, I say one goal ("FDOS data plane + CRM") and both Macs plan, build and merge it while I watch one board.
- As Yahia, I get one blended plan that took the best of my Claude's and Mahmoud's Claude's ideas, never two builds.
- As Mahmoud, my Mac's jobs survive a crash or usage limit and resume instead of restarting from zero.
- As either of us, a decision made on one Mac is known to the other Mac's Claude before it plans or reviews.

## Scope
- In: M1 merge + follow-up, M2.1–M2.6, M3.1–M3.4 (per peer-missions.md), one drill per layer, stills for every new
  screen, a release after each layer so Mahmoud's Mac runs the same build.
- Out: Foundry's own ship loop and Foundry-side blending (I blend plans by hand for this run), the iPhone app, 36b file
  sharing, the Lander (builder-autonomy Phase B).
- Names: **unit** = one Foundry mission file of this run. **Mission** (capital M) = the True feature built in M2. They
  are different things: True Missions route jobs across two Macs over the relay, which Foundry does not do, so M2
  builds its own runner (the peer-missions.md:291 wrap-vs-new question is settled as "new", reusing only Foundry's
  idea that checks are run by the owner, not the worker).

## Approach
**Step 0 (before any unit, by me on Yahia's Build-it):** add `/Users/y/Projects/true` to Foundry's allowlist in
`~/.foundry/foundry.toml` (today it allows only `~/.foundry/repos`); commit peer-missions.md + this plan; write unit
files to `.claude/foundry/peers/<unit>.toml` and load each once with `foundry.jobfile` to prove it parses.

**Units.** `repo = /Users/y/Projects/true`, `budget_usd` per the table (Foundry caps a file at $10), phases = the unit's
peer-missions.md steps, each phase `fulfills` its checks. Builder prompt = the matching peer-missions.md section +
`/dispatch-brief`. Checks are Foundry `[[check]]` entries (`id`, `cmd`, `expect_exit = 0`):

| Unit | Steps | `[[check]]` ids → cmd | Gate | Budget |
|---|---|---|---|---|
| U0 | M1 follow-up: builder `waiting` → peer `paused` + `resume_at`; engine never also resumes | `peer` → `swift test --filter Peer`; `drill-m1` → drill below | — | $8 |
| U1 | M2.1 mission file + router, M2.2 runner + reconcile | `missions` → `swift test --filter Mission` | — | $10 |
| U2 | M2.3 merge gate, M2.4 Board + CLI | `missions`; `board-stills` → `swift test --filter MissionBoardSnapshot` | stills | $8 |
| U3 | M2 drill | `drill-m2` → `TRUE_DRILL=1 swift test --filter PeersDrillM2` | — | $5 |
| U4 | M2.5 blind plans + Blender | `blender` → `swift test --filter Blender`; stills | stills | $10 |
| U5 | M2.6 two takes | `takes` → `swift test --filter TwoTakes` | — | $6 |
| U6 | M3.1 Mind log + sync, M3.2 decisions in envelopes | `mind` → `swift test --filter PeerMind` | — | $8 |
| U7 | M3.3 cross review, M3.4 ideas feed | `review` → `swift test --filter CrossReview\|IdeasFeed`; stills | stills | $10 |

**Lanes (Yahia 2026-10-27: "use codex n deepseek").** Builds run off Claude: `lane = "codex"` for U0, U1, U2, U4,
U6, U7 (the larger Swift units, UI ones included: the stills gate still guards taste); `lane = "deepseek"` for U3 and
U5 (smaller). Foundry passes the lane to `builder start --lane` (Foundry commit "Job files take a lane"). Claude stays
on my side of the run: merges, drill tests, the fixture, review of each unit's diff before merge.

U0 adds idempotency tests: two resume triggers at once start one session; True restarted while `paused` resumes once at
`resume_at`; builder keep and peer engine never both resume (f89353a now reports `waiting` as running).

**Drills are Swift test suites, written by me before the unit's builder starts.** `PeersDrillM1Tests` /
`PeersDrillM2Tests` use the in-process two-engine harness (`PeerLanFlowTests.World`, loopback seam from Run 39).
Fault injection points: fake launcher (receiver Claude killed mid-job, usage-limit exit), fake repo fetcher (no
clone, fetch fails), sender path outside allowed roots, sender Stop, unknown error, peer removed. Relay traffic, when
used, goes through fresh per-run identities and mailboxes; a relay outage is reported as `infra`, retried once and
never counted as a job failure.

**Held-out fixture.** I freeze `~/.true/peers/sent.json` once into `~/.foundry/heldout/peers/m1.json`
(outside the repo) with a small freeze script that drops titles/notes/paths/peer names, keeps job shape, and assigns
each failed job its cause from its `note` by an explicit table. Raw file never edited. Its sha256 is part of the check
cmd (`shasum -a 256 -c m1.sha256 && TRUE_DRILL=1 TRUE_DRILL_FIXTURE=... swift test --filter PeersDrillM1`), and the
drill test file is named in the cmd, so Foundry marks the job `contract-tampered` if a builder edits either. The
builder prompt never mentions the fixture. (Builders have full disk access, so this is tamper detection, not secrecy.)

**The M1 number.** Each replayed job ends `landed`, `refused` (stopped before sending, with a human reason),
`stopped` (the sender pressed Stop) or `failed` (sent, then failed). **Failure rate = failed ÷ (landed + failed +
refused)**; stops and in-flight jobs are left out of it. Stops are reported on their own as wait-before-stop (how
long the sender waited before giving up; lanes should shrink it). Baseline from today's log: 32 finished, 6 of them
Stop presses; 6 real failures of the other 26 = **23 %** (peer removed 1, no local clone 2, couldn't fetch 1,
directory not allowed 1, unknown error 1). Pass: failure rate ≤ 4 % (≤ 1 of 26), every
kill/limit case resumes on the same session with zero re-sends, every refusal has a reason, and independent jobs on one
project start ≤ 30 s apart (M1.4). The replay is deterministic, so it runs 3 times and all 3 must pass.

**Order, merging, releases.** Units run one after another; the next unit starts by itself when the previous one's
drill passes (no wait for me). I merge each passed unit into main, then `.claude/foundry/peers/recheck.sh <unit>`
re-runs that unit's `[[check]]` cmds on merged main. After U0, U3, U5 and U7 I release only if the drill passes on
merged main: bump → `scripts/package.sh` → `scripts/export-public.sh` → public commit + tag → release.yml (Deck-signed
from secrets) → `scripts/sign-release.sh` → verify-release green. New relay message kinds must decode-tolerant (an old
receiver ignores them; M1.1's Card round-trip tests cover the pattern), so a release never strands a Mac on an older build.

**Gates and pending checks.** A stills gate pauses the chain (Foundry `gate-paused`) and re-pings Yahia every 24 h;
nothing auto-proceeds. Two-Mac checks run once Mahmoud is on the release; until then they are **pending**, owned by me
(asking Yahia to nudge Mahmoud), flagged on every ping after 7 days. Pending two-Mac M2 checks do not block U4 (the
Blender is built and drilled on one Mac), but the Blender's release (after U5) waits for the M2 two-Mac check to pass.

**Budget.** Unit budgets total $65; backstop **$75** for the whole run. Tally = Foundry's ledger (`foundry ls`). At the
backstop: no new unit starts, I ping with what is left; caps are checkpoints, the run resumes on his word.

## Alternatives considered
- U0 only, then wait 7 days of real traffic (Yahia's earlier rule) — he lifted it 2026-10-27; the scripted drill
  replays the same real traffic deterministically instead.
- Plain `builder` + the `gated-build` workflow — no tamper detection and no owner-run checks; those are why Foundry exists.
- One big builder per layer (as M1 was) — a worker's "done" decides; the failure this run exists to avoid.

## Steps
0. On Build-it: allowlist edit, commit both docs, update peer-missions.md Goal (gate change), write + parse unit files.
1. Finish v1.2.3 release (in flight). Check: verify-release green.
2. Merge M1 by hand: branch `builder/true-missions-m1-20261027-004218` (builder finished; commits 819664d..f3f6730;
   keep Nova removed). Check: `swift test` on main. Then freeze fixture + write `PeersDrillM1Tests`; run it on main
   to record M1's number before U0 (shows what M1 alone fixed).
3. U0 → U1 → U2 (stills) → U3. Release. Check: each unit's checks + recheck on main; M2 drill 3/3.
4. U4 (stills) → U5. Release after the M2 two-Mac check passes. Check: M2.5/M2.6 checks.
5. U6 → U7 (stills). Release. Check: M3 checks; two-Mac checks run or pending.

## Done means
- Each unit: Foundry `passed`, and `recheck.sh` green on merged main.
- M1: replay failure rate ≤ 5 % vs 37.5 % baseline, 3/3 runs, numbers shown to Yahia.
- M2: one real goal run as a Mission on both Macs (or pending, with owner and age).
- Blender: first 5 real blended plans rated by Yahia (one tap); kept only if rated better than single plans.
- M3: a decision made on one Mac appears in the other Mac's planner envelope (two Macs, or pending).
- Stills OKed before install: Board (empty, running, one blocked, done), plan + ledger card + Compare fold, ideas on Board.

## Risks
- Drill overfits the harness → signal: drill green but the first 10 real jobs after a release fail above 5 %; those
  are counted in every ping (the real-traffic monitor).
- M2 may be built for waiting M1's lanes already fixed → Step 2 records M1's waiting number before U1 starts; if
  independent jobs no longer wait, I tell Yahia before U1 and he may re-scope.
- Mahmoud lags on updates → two-Mac checks stay pending (owned, aged), never marked passed.
- Builder concurrency cap (3) shared with other sessions → a unit queued > 30 min is pinged.

## Review
Goldfish 2026-10-27 (naive-reader 4/7/3, zoom-out 0/4/2, critic 2/5/2 → merged 6 blockers, 16 should, 5 nits).
All 6 blockers and 16 shoulds fixed in the plan above (allowlist step, fixture outside repo + hash-checked, defined
failure-rate metric with sourced 37.5 % baseline, gate change written into peer-missions.md, U4 vs pending M2 rule,
named checks, drills as Swift tests with named injection points, budget table + tally, release + decode-tolerance,
idempotency tests, alternatives, M1 branch named, stills states, Foundry explained). Nits applied: stills-gate
timeout, pending owner/age, "Mission" vs "unit" naming, commit peer-missions.md.
Rejected: "shrink scope to U0 + its drill" — Yahia chose the full roadmap; kept, but each unit unlocks only on the
previous drill, and Step 2 measures what M1 alone fixed before U1 so he can re-scope. "Cite sources for v1.2.3" — the
release is this session's own work, tracked in the handoff, not a design input.
