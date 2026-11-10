#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Shaped explosions on the real station (headless, about a minute a map): native against DM at 150 random spots in three sizes, the
# straight line (as before) against shaped, and six named rooms dumped for render.py's before/after pictures.
# Usage: tools/explosion_preview/run.sh [map] [path engine library]
#   tools/explosion_preview/run.sh hippiestation hippie_path_test
# EXTRA="explosion-block-weight=1.5" adds world params.
# Results: data/explosion_preview/<map>/results.txt and <room>.json, pictures in data/previews/explosions_<map>/
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
MAP="${1:-hippiestation}"
LIB="${2:-hippie_path}"
PORT="${PORT:-45341}"
START=$(date +%s)

rm -rf data/explosion_preview
mkdir -p data/explosion_preview
{
	cat hippiestation.dme
	printf '#include "tools\\explosion_preview\\explosion_preview.dm"\r\n'
} > xpreview.mdme
"$BYOND_BIN/dm.exe" xpreview.mdme | grep -E "error|dmb -"
[ -f xpreview.mdme.dmb ] || { echo "Build failed"; rm -f xpreview.mdme*; exit 1; }
echo "Built in $(( $(date +%s) - START )) s"

"$BYOND_BIN/dd.exe" xpreview.mdme.dmb "$PORT" -trusted -invisible -params "explosion-preview=1&bot-map=$MAP&path-lib=$LIB${EXTRA:+&$EXTRA}" > data/explosion_preview/dd.log 2>&1 &
DD=$!
for i in $(seq 1 600); do
	kill -0 "$DD" 2>/dev/null || break
	grep -q "^done" data/explosion_preview/results.txt 2>/dev/null && break
	sleep 1
done
sleep 2
kill "$DD" 2>/dev/null
echo "Ran in $(( $(date +%s) - START )) s"
grep -iE "runtime error" data/explosion_preview/dd.log | sort | uniq -c | sort -rn | head -5
sleep 3
rm -f xpreview.mdme xpreview.mdme.dmb xpreview.mdme.rsc xpreview.mdme.int xpreview.mdme.dyn.rsc xpreview.mdme.lk xpreview.mdme.rsc.lk xpreview.mdme.dyn.rsc.lk
OUTDIR="${OUTDIR:-explosions_$MAP}"
mkdir -p "data/$OUTDIR"
cp data/explosion_preview/* "data/$OUTDIR/" 2>/dev/null
cat "data/$OUTDIR/results.txt"
python tools/explosion_preview/render.py "data/$OUTDIR" "data/previews/$OUTDIR"
