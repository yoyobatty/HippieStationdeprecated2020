#!/bin/bash
# Local only. The drills with gc_hunt_para.dm in: what holds each thing that's hard deleted, searched the moment it is.
# Usage: tools/live_bench/boom_hunt.sh <drills...>   Results: data/boom/hunt-<drill>.txt
unset __COMPAT_LAYER
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Users/Keegan Eaton/BYOND-516.1666/byond/bin}"
sed 's|^// END_INCLUDE|#include "tools\\live_bench\\boom_drill.dm"\n#include "tools\\live_bench\\gc_hunt_para.dm"\n#include "tools\\live_bench\\pipe_debug.dm"\n// END_INCLUDE|' paradise.dme > boomhunt.dme
rm -f boomhunt.dmb
"$BYOND_BIN/dm.exe" boomhunt.dme | grep -E "error|warning|dmb -" | head -20
[ -f boomhunt.dmb ] || { echo "Compile failed"; exit 1; }
mkdir -p data/boom
for d in "$@"; do
	rm -f "data/boom/$d.txt" data/boom/gc_hunt.txt
	timeout 3000 "$BYOND_BIN/dd.exe" boomhunt.dmb 46460 -trusted -invisible -params "boom-drill=$d&boom-minds=1&boom-gc-wait=${GC_WAIT:-7}" > "data/boom/hunt-$d.log" 2>&1
	tr -d '\r' < "data/boom/$d.txt" 2>/dev/null; echo
	mv data/boom/gc_hunt.txt "data/boom/hunt-$d.txt" 2>/dev/null
	grep -c "^hard delete" "data/boom/hunt-$d.txt" 2>/dev/null
done
