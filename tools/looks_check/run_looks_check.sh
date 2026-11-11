#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Station looks self-test (tools/looks_check/looks_check.dm): the roll, weights, bans and forcing in the lobby, then each look
# put on and taken off again on the station, with the station's lighting snapshotted under each.
# Builds its own copy (lookscheck.mdme -> lookscheck.mdme.dmb), so hippiestation.dmb is left alone for whatever else is running.
# Usage: tools/looks_check/run_looks_check.sh, then python tools/looks_check/looks_sheet.py for the pictures
# Results: data/looks_check/results.txt and snapshot_*.txt, and the server's logs in data/logs/looks_check_logs
# Boots the Hippie map, since the pictures are drawn over it. MAP=<any _maps/*.json name> to boot another.
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45417}"
MAP="${MAP:-hippiestation}"

cp hippiestation.dme lookscheck.mdme
printf '#include "tools\\looks_check\\looks_check.dm"\r\n' >> lookscheck.mdme
echo "Compiling..."
"$BYOND_BIN/dm.exe" lookscheck.mdme | grep -E "error|warning|dmb -" || true
if [ ! -f lookscheck.mdme.dmb ]; then echo "Compile failed"; rm -f lookscheck.mdme; exit 1; fi

rm -rf data/looks_check data/logs/looks_check_logs
began=$(date +%s)
"$BYOND_BIN/dd.exe" lookscheck.mdme.dmb "$PORT" -trusted -invisible -params "looks-check=1&station-looks=plain&log-directory=looks_check_logs&bot-map=$MAP" > /dev/null 2>&1 &
dd=$!
while kill -0 $dd 2>/dev/null; do
	sleep 2
	[ -f data/looks_check/results.txt ] && break
	if [ $(($(date +%s) - began)) -gt 900 ]; then echo "still going after 900 s - stopped"; break; fi
done
sleep 1
kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
rm -f lookscheck.mdme lookscheck.mdme.dmb lookscheck.mdme.rsc lookscheck.mdme.int lookscheck.mdme.lk lookscheck.mdme.dyn.rsc lookscheck.mdme.rsc.lk lookscheck.mdme.dyn.rsc.lk
echo "took $(($(date +%s) - began)) s"
cat data/looks_check/results.txt 2>/dev/null || echo "no results: see data/logs/looks_check_logs"
runtimes=$(grep -c 'runtime error' data/logs/looks_check_logs/runtime.log 2>/dev/null)
echo "runtimes: ${runtimes:-0}"
grep -h -A3 'runtime error' data/logs/looks_check_logs/runtime.log 2>/dev/null | head -60
