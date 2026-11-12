#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Flat icon check: mobs flattened by getFlatIcon() and by iconforge (hippiestation/code/modules/asset_cache/flat_icon_forge.dm) on
# the test map, headless, then compare.py checks every picture pixel by pixel and prints the times.
# Usage: tools/flat_icon_check/run.sh [map, default testbench]
# Results: data/flat_icon_check/results.txt, rows.json, the pictures in data/flat_icon_check/dm and /forge
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
MAP="${1:-testbench}"
PORT="${PORT:-45341}"
START=$(date +%s)

rm -rf data/flat_icon_check
mkdir -p data/flat_icon_check/dm data/flat_icon_check/forge
{
	cat hippiestation.dme
	printf '#include "tools\\flat_icon_check\\flat_icon_check.dm"\r\n'
} > ficheck.mdme
"$BYOND_BIN/dm.exe" ficheck.mdme | grep -E "error|dmb -"
[ -f ficheck.mdme.dmb ] || { echo "Build failed"; rm -f ficheck.mdme*; exit 1; }
echo "Built in $(( $(date +%s) - START )) s"

"$BYOND_BIN/dd.exe" ficheck.mdme.dmb "$PORT" -trusted -invisible -params "flat-icon-check=1&bot-map=$MAP" > data/flat_icon_check/dd.log 2>&1 &
DD=$!
for i in $(seq 1 420); do
	kill -0 "$DD" 2>/dev/null || break
	grep -q "^done" data/flat_icon_check/results.txt 2>/dev/null && break
	sleep 1
done
sleep 2
kill "$DD" 2>/dev/null
echo "Ran in $(( $(date +%s) - START )) s"
cat data/flat_icon_check/results.txt 2>/dev/null
grep -iE "runtime error" data/flat_icon_check/dd.log | sort | uniq -c | sort -rn | head -5
sleep 3
rm -f ficheck.mdme ficheck.mdme.dmb ficheck.mdme.rsc ficheck.mdme.int ficheck.mdme.dyn.rsc ficheck.mdme.lk ficheck.mdme.rsc.lk ficheck.mdme.dyn.rsc.lk
python tools/flat_icon_check/compare.py
