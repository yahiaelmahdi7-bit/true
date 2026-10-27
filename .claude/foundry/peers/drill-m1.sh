#!/bin/sh
# Foundry check `drill-m1`: the held-out fixture must still be the frozen one, then the M1 drill replays it (3 runs).
# Passes only on 3 PASS lines, so a run where the drill was skipped (0 tests) can't pass.
# Usage (from the repo root): sh .claude/foundry/peers/drill-m1.sh Tests/TrueTests/PeersDrillM1Tests.swift
set -e
H="$HOME/.foundry/heldout/peers"
test -f "$1"
(cd "$H" && shasum -a 256 -c m1.sha256)
out="$(mktemp)"
rc=0
TRUE_DRILL=1 TRUE_DRILL_FIXTURE="$H/m1.json" swift test --filter PeersDrillM1 >"$out" 2>&1 || rc=$?
cat "$out"
n="$(grep -c '^DRILL M1 run=[123] .* PASS$' "$out" || true)"
rm -f "$out"
echo "drill-m1: $n/3 runs PASS (swift test exit $rc)"
test "$rc" -eq 0 && test "$n" -eq 3
