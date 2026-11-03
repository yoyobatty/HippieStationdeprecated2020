#!/bin/bash
# Local only. The drills again with Paradise's own reference finder on (REFERENCE_TRACKING, GC_FAILURE_HARD_LOOKUP): every failed
# delete searched before it's hard deleted, results in the round's gc_debug.log. Usage: tools/live_bench/boom_refs.sh <drills...>
unset __COMPAT_LAYER
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Users/Keegan Eaton/BYOND-516.1666/byond/bin}"
{ printf '#define REFERENCE_TRACKING\n#define GC_FAILURE_HARD_LOOKUP\n'; sed 's|^// END_INCLUDE|#include "tools\\live_bench\\boom_drill.dm"\n// END_INCLUDE|' paradise.dme; } > boomrefs.dme
rm -f boomrefs.dmb
"$BYOND_BIN/dm.exe" boomrefs.dme | grep -E "error|warning|dmb -" | head -20
[ -f boomrefs.dmb ] || { echo "Compile failed"; exit 1; }
mkdir -p data/boom
for d in "$@"; do
	rm -f "data/boom/$d.txt"
	timeout 2400 "$BYOND_BIN/dd.exe" boomrefs.dmb 46450 -trusted -invisible -params "boom-drill=$d&boom-minds=1&boom-gc-wait=${GC_WAIT:-12}" > "data/boom/refs-$d.log" 2>&1
	cp "data/boom/$d.txt" "data/boom/refs-$d.txt" 2>/dev/null
	tr -d '\r' < "data/boom/$d.txt" 2>/dev/null; echo
	gc=$(ls -t data/logs/*/round-*/gc_debug.log data/logs/*/*/gc_debug.log 2>/dev/null | head -1)
	echo "gc log: $gc"
	[ -n "$gc" ] && cp "$gc" "data/boom/refs-$d-gc.log"
done
