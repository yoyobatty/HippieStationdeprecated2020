#!/bin/bash
# Local only. Builds this worktree with tools/live_bench/boom_drill.dm and runs the drills, a few at a time.
# Usage: tools/live_bench/boom_run.sh <label> [drills...]   Env: AT_ONCE=3, BASE_PORT=46400, SKIP_BUILD=1
unset __COMPAT_LAYER # with this set, dm.exe leaks kernel handles for every file it opens until the next reboot
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Users/Keegan Eaton/BYOND-516.1666/byond/bin}"
LABEL="${1:?a label}"
shift
DRILLS=("$@")
if [ ${#DRILLS[@]} -eq 0 ]; then DRILLS=(maxcap maxcap6 reactor tesla nuke); fi
AT_ONCE="${AT_ONCE:-3}"
BASE_PORT="${BASE_PORT:-46400}"
if [ -z "${SKIP_BUILD:-}" ]; then
	sed 's|^// END_INCLUDE|#include "tools\\live_bench\\boom_drill.dm"\n// END_INCLUDE|' paradise.dme > boom.dme
	rm -f boom.dmb
	"$BYOND_BIN/dm.exe" boom.dme | grep -E "error|warning|dmb -" | head -20
	[ -f boom.dmb ] || { echo "Compile failed"; exit 1; }
fi
mkdir -p data/boom
i=0
for d in "${DRILLS[@]}"; do
	while [ "$(jobs -rp | wc -l)" -ge "$AT_ONCE" ]; do wait -n; done
	(
		rm -f "data/boom/$d.txt"
		cp boom.dmb "boom_$d.dmb"
		cp boom.rsc "boom_$d.rsc" 2>/dev/null
		timeout 1200 "$BYOND_BIN/dd.exe" "boom_$d.dmb" $((BASE_PORT + i)) -trusted -invisible -params "boom-drill=$d${PARAMS:+&$PARAMS}" > "data/boom/$d.log" 2>&1
		rm -f "boom_$d.dmb" "boom_$d.rsc"
	) &
	i=$((i + 1))
	sleep 3
done
wait
for d in "${DRILLS[@]}"; do
	if [ -f "data/boom/$d.txt" ]; then tr -d '\r' < "data/boom/$d.txt"; echo; else echo "boom drill $d: no result"; tail -5 "data/boom/$d.log"; fi
	cp "data/boom/$d.txt" "data/boom/$LABEL-$d.txt" 2>/dev/null
	cp "data/boom/$d.log" "data/boom/$LABEL-$d.log" 2>/dev/null
	echo "  runtimes: $(grep -c 'Runtime in' "data/boom/$d.log")"
done
