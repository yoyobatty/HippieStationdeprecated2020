#!/bin/bash
# Headless check on the real station, no game window (see update_check.dm). Results in data/update_check_<label>.txt
# Usage: tools/power_check/run.sh [label]     HARNESS=other.dm picks another check in this folder
# Builds its own dmb, so a server running hippiestation.dmb isn't touched.
set -u
LABEL="${1:-now}"
PORT="${PORT:-45312}"
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
START=$(date +%s)
HERE="$(cd "$(dirname "$0")" && pwd -W)"
cd "${CHECKOUT:-$(dirname "$0")/../..}"

rm -f data/update_check.txt
sed 's/^#include "hippiestation\\code\\modules\\bots_ai\\bot_brain.dm"/#include "update_check_tmp.dm"\r\n&/' hippiestation.dme > updatecheck.dme
cp "$HERE/${HARNESS:-update_check.dm}" update_check_tmp.dm
"$BYOND_BIN/dm.exe" updatecheck.dme | grep -E "error|warning|dmb -"
[ -f updatecheck.dmb ] || { echo "Build failed"; rm -f updatecheck.* update_check_tmp.dm; exit 1; }
echo "built after $(( $(date +%s) - START )) s"

rm -rf data/update_check_config
cp -r config data/update_check_config
sed -i '/^BOT_CREW/d' data/update_check_config/hippiestation_config.txt

"$BYOND_BIN/dd.exe" updatecheck.dmb "$PORT" -trusted -invisible -params "config=data/update_check_config${EXTRA_PARAMS:+&$EXTRA_PARAMS}" > data/update_check_dd.log 2>&1 &
DD=$!
for i in $(seq 1 ${WAIT_SECONDS:-420}); do
	kill -0 "$DD" 2>/dev/null || break
	grep -q "^done" data/update_check.txt 2>/dev/null && break
	sleep 1
done
sleep 2
kill "$DD" 2>/dev/null
cp data/update_check.txt "data/update_check_$LABEL.txt" 2>/dev/null
rm -f updatecheck.* update_check_tmp.dm
rm -rf data/update_check_config
cat "data/update_check_$LABEL.txt" 2>/dev/null || { echo "No results"; tail -20 data/update_check_dd.log; }
echo "--- runtimes in the server log: $(grep -c "runtime error" data/update_check_dd.log)"
grep -A5 "runtime error" data/update_check_dd.log | head -60
echo "took $(( $(date +%s) - START )) s"
