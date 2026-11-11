#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Machine and item interaction checks (tools/qol_check/qol_check.dm), headless. Builds its own copy, so hippiestation.dmb is left alone.
# Usage: tools/qol_check/run_qol_check.sh
# Results: data/qol_check/results.txt, and the server's logs in data/logs/qol_check_logs
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45394}"
# Boots the small test map (_maps/testbench.json: Runtime Station, no Lavaland or ruins): the test builds its own room,
# and loading the Hippie map costs ~17 s a boot. MAP=hippiestation (any _maps/*.json name) to boot another.
MAP="${MAP:-testbench}"

cp hippiestation.dme qolcheck.mdme
printf '#include "tools\\qol_check\\qol_check.dm"\r\n' >> qolcheck.mdme
echo "Compiling..."
"$BYOND_BIN/dm.exe" qolcheck.mdme | grep -E "error|warning|dmb -" || true
if [ ! -f qolcheck.mdme.dmb ]; then echo "Compile failed"; rm -f qolcheck.mdme; exit 1; fi

rm -rf data/qol_check data/logs/qol_check_logs
began=$(date +%s)
"$BYOND_BIN/dd.exe" qolcheck.mdme.dmb "$PORT" -trusted -invisible -params "qol-check=1&log-directory=qol_check_logs&bot-map=$MAP" > /dev/null 2>&1 &
dd=$!
while kill -0 $dd 2>/dev/null; do
	sleep 2
	[ -f data/qol_check/results.txt ] && break
	if [ $(($(date +%s) - began)) -gt 900 ]; then echo "still going after 900 s - stopped"; break; fi
done
sleep 1
kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
rm -f qolcheck.mdme qolcheck.mdme.dmb qolcheck.mdme.rsc qolcheck.mdme.int qolcheck.mdme.lk qolcheck.mdme.dyn.rsc qolcheck.mdme.rsc.lk qolcheck.mdme.dyn.rsc.lk
echo "took $(($(date +%s) - began)) s"
cat data/qol_check/results.txt 2>/dev/null || echo "no results: see data/logs/qol_check_logs"
runtimes=$(grep -c 'runtime error' data/logs/qol_check_logs/runtime.log 2>/dev/null)
echo "runtimes: ${runtimes:-0}"
grep -h -A3 'runtime error' data/logs/qol_check_logs/runtime.log 2>/dev/null | head -60
