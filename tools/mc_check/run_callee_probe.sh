#!/bin/bash
# Checks the BYOND behaviour the MC's stale-fire guard leans on (callee_probe.dm): a woken proc finds its waitfor = FALSE
# caller's arguments through `caller`. A few seconds. Builds in a temp folder; nothing is written to the repo.
# Usage: tools/mc_check/run_callee_probe.sh     PORT=45511 by default
unset __COMPAT_LAYER
set -u
here="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45511}"
work="$(mktemp -d)"
printf '#include "%s/callee_probe.dm"\r\n' "$here" > "$work/callee_probe.dme"
"$BYOND_BIN/dm.exe" "$work/callee_probe.dme" | grep -E "^.*: (error|warning)"
[ -f "$work/callee_probe.dmb" ] || { echo "compile failed"; rm -rf "$work"; exit 1; }
timeout 60 "$BYOND_BIN/dd.exe" "$work/callee_probe.dmb" "$PORT" -trusted -invisible -logself 2>&1 | grep -E "PASS|FAIL|NOTE"
cat "$work"/callee_probe.log 2>/dev/null | grep -E "PASS|FAIL|NOTE"
rm -rf "$work"
