# Cloud jobs in the Mac app (P3)

True's Hub now runs coding jobs on the cloud factory (true-factory on streambox, `http://100.120.234.70:8788`, Tailscale only).
Code: `Sources/True/Cloud/`. Tests: `Tests/TrueTests/CloudTests.swift`.

## What was built
- **Cloud section** (Hub → All): jobs newest first, polled (5 s while the Hub is open, 15 s while a job works, 60 s idle),
  status chips Queued / Working / Needs you / Done / Failed. An unreachable factory shows one quiet line.
- **Run in cloud**: pick a project folder + prompt → repo sync → `POST /jobs {repo, job, base: <synced sha>}`.
- **Job detail sheet**: event timeline (SSE snapshot, refreshed every 3 s while working), the `needsYou` question with an
  answer box (`POST /answer`), Stop, Show diff, **Land**.
- **macOS notification** on a job turning needsYou or done (first poll only seeds, so launch never spams). A click opens the Hub.
- **Land**: applies the job diff in a sibling worktree `<repo>-cloud-<jobid>` on a new branch `cloud/<jobid>` (started from the
  job's base commit, else HEAD) and commits there. The checked-out branch and main are never touched; nothing is pushed.
  If the diff doesn't apply, the branch and worktree are removed again.
- Token: read from Keychain (`net.prismlens.true-factory` / `streambox`) via `/usr/bin/security` on every request; never
  logged, never in an error message (tested).

## Repo sync choice
The factory spec leaves Mac→VPS sync out of scope and the API has no upload route, so True uses the ssh door
(`~/.ssh/hermes_vps`, root@100.120.234.70): `git bundle` of local HEAD → `scp` to /tmp → `ssh` runs
`runuser -u truefactory -- git init` (if missing) + `git fetch <bundle> +HEAD:refs/true/sync` inside
`/var/lib/true-factory/repos/<folder-name>`. Git runs as the service user (`truefactory`, per `factory/deploy/true-factory.service`)
so the clone stays writable for worktrees. The job's `base` is the synced sha, so the VPS clone's own HEAD is never used.
Only committed work travels; uncommitted changes are not sent. Binary files are not in the diff (the factory's diff has no `--binary`).

## Verify
- `swift build` and `swift test --filter Cloud` (21 tests: API client against a mock transport, SSE parsing, notification
  transitions, sync command plan + failure, and Land against real throwaway git repos).
- Full `swift test` has pre-existing timing/fd-count flakes under parallel load (`FDLeakTests`, `LagTests`, some Nova latency
  tests; different ones fail per run, they pass in isolation and also fail with the Cloud tests skipped).
- Live read-only check done: `GET /health` and `GET /jobs` with the Keychain token returned 200 (`[]` at the time).
- By hand: Hub → All → Run in cloud → choose a repo, small prompt → watch the chip go Working → Done, open it, Show diff, Land,
  then `git -C <repo> log cloud/<id>`.

## Install in place (not done by this build)
The builder did not touch `/Users/y/Projects/true/True.app`. After merging this branch, in the main checkout: unload the Clip Studio
KeepAlive agent (it relaunches the app on quit), run `./scripts/package.sh`, then replace and restart True.
To inspect first without installing: `TRUE_APP_OUT=/tmp/True-cloud.app ./scripts/package.sh` from this worktree.
