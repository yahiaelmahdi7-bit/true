#!/bin/sh
# Re-run one Peers unit's [[check]] cmds on merged main, after it is merged. Usage: .claude/foundry/peers/recheck.sh u0
set -e
here="$(cd "$(dirname "$0")" && pwd)"
cd "$(git -C "$here" rev-parse --show-toplevel)"
python3 -I - "$here/$1.toml" <<'PY'
import subprocess, sys, tomllib
bad = []
for c in tomllib.load(open(sys.argv[1], "rb"))["check"]:
    ok = subprocess.run(c["cmd"], shell=True, timeout=c.get("timeout_s", 1800)).returncode == c.get("expect_exit", 0)
    print(("PASS " if ok else "FAIL ") + c["id"], flush=True)
    bad += [] if ok else [c["id"]]
sys.exit(1 if bad else 0)
PY
