#!/bin/sh
# Foundry check `drill-m2`: the held-out M2 drill must still be the frozen one, then it runs the fix-round scenarios (3 runs).
# Passes only on 3 PASS lines, so a run where the drill was skipped (0 tests) can't pass.
# Usage (from the repo root): sh .claude/foundry/peers/drill-m2.sh Tests/TrueTests/PeersDrillM2Tests.swift
set -e
H="$HOME/.foundry/heldout/peers"
test -f "$1"
test -f "$H/m2.sha256" || { echo "drill-m2: $H/m2.sha256 is missing"; exit 1; }
want="$(cut -d' ' -f1 "$H/m2.sha256")"
have="$(shasum -a 256 "$1" | cut -d' ' -f1)"
test "$want" = "$have" || { echo "drill-m2: $1 differs from the frozen drill (have $have, want $want)"; exit 1; }
out="$(mktemp)"
rc=0
TRUE_DRILL=1 swift test --filter PeersDrillM2 >"$out" 2>&1 || rc=$?
cat "$out"
n="$(grep -c '^DRILL M2 run=[123] .* PASS$' "$out" || true)"
rm -f "$out"
echo "drill-m2: $n/3 runs PASS (swift test exit $rc)"
test "$rc" -eq 0 && test "$n" -eq 3
