#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# A blast's set-up cost and the per-turf block cache's check (tools/explosion_preview/block_bench.dm), headless on the real station.
# Builds its own copy (xblock.mdme), so hippiestation.dmb is left alone. Works on a build without the cache too (the bench and the
# severity lines only), so a checkout from before can be set against one after: diff the two severity.txt, they have to match.
# Usage: tools/explosion_preview/run_block_bench.sh <label> [bench|round] [map]
#   bench: CaculateExplosionBlock() and the whole set-up timed at 100 spots in three sizes, an item's step, the severity lines
#   round: that, then a round of doors, windows, walls, shuttles and blasts with the full map recount after each (cache builds only)
# EXTRA="explosion-realism=off" adds world params. PORT (45620) picks the port.
# Results: data/explosion_block_bench/<label>/results.txt, severity.txt, mismatches.txt (if any), dd.log
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
LABEL="${1:?a label}"
MODE="${2:-bench}"
MAP="${3:-hippiestation}"
PORT="${PORT:-45620}"
START=$(date +%s)
OUT="data/explosion_block_bench/$LABEL"

python tools/gpu_share.py wait "block bench build $LABEL"
rm -rf data/explosion_block_bench/results.txt data/explosion_block_bench/severity.txt data/explosion_block_bench/mismatches.txt
mkdir -p data/explosion_block_bench "$OUT"
{
	cat hippiestation.dme
	printf '#include "tools\\explosion_preview\\block_bench.dm"\r\n'
} > xblock.mdme
"$BYOND_BIN/dm.exe" xblock.mdme | grep -E "error|dmb -"
[ -f xblock.mdme.dmb ] || { echo "Build failed"; rm -f xblock.mdme*; exit 1; }
echo "Built in $(( $(date +%s) - START )) s"

python tools/gpu_share.py wait "block bench run $LABEL"
"$BYOND_BIN/dd.exe" xblock.mdme.dmb "$PORT" -trusted -invisible -params "explosion-block-bench=$MODE&bot-map=$MAP&log-directory=block_bench_$LABEL${EXTRA:+&$EXTRA}" > "$OUT/dd.log" 2>&1 &
DD=$!
for i in $(seq 1 1200); do
	kill -0 "$DD" 2>/dev/null || break
	grep -q "^done" data/explosion_block_bench/results.txt 2>/dev/null && break
	sleep 1
done
sleep 2
kill "$DD" 2>/dev/null; sleep 1; kill -9 "$DD" 2>/dev/null
echo "Ran in $(( $(date +%s) - START )) s"
sleep 2
rm -f xblock.mdme xblock.mdme.dmb xblock.mdme.rsc xblock.mdme.int xblock.mdme.dyn.rsc xblock.mdme.lk xblock.mdme.rsc.lk xblock.mdme.dyn.rsc.lk
mv data/explosion_block_bench/results.txt data/explosion_block_bench/severity.txt "$OUT/" 2>/dev/null
mv data/explosion_block_bench/mismatches.txt "$OUT/" 2>/dev/null
runtimes=$(grep -c 'runtime error' "data/logs/block_bench_$LABEL/runtime.log" 2>/dev/null)
echo "runtimes: ${runtimes:-0}"
grep -h -A2 'runtime error' "data/logs/block_bench_$LABEL/runtime.log" 2>/dev/null | head -30
cat "$OUT/results.txt"
