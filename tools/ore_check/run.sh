#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Ore redemption machine + ore silo round trips (tools/ore_check/ore_check.dm): nothing made, nothing lost.
# Builds its own copy (orecheck.mdme -> orecheck.mdme.dmb), so hippiestation.dmb is left alone for whatever else is running.
# Usage: tools/ore_check/run.sh        MAP=hippiestation (any _maps/*.json name) to boot another map; PORT= to move it
# Results: data/ore_check/results.txt, the server's logs in data/logs/ore_check_logs
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45419}"
MAP="${MAP:-testbench}"

cp hippiestation.dme orecheck.mdme
printf '#include "tools\\ore_check\\ore_check.dm"\r\n' >> orecheck.mdme
echo "Compiling..."
"$BYOND_BIN/dm.exe" orecheck.mdme | grep -E "error|warning|dmb -" || true
if [ ! -f orecheck.mdme.dmb ]; then echo "Compile failed"; rm -f orecheck.mdme; exit 1; fi

rm -rf data/ore_check data/logs/ore_check_logs
mkdir -p data/ore_check
began=$(date +%s)
"$BYOND_BIN/dd.exe" orecheck.mdme.dmb "$PORT" -trusted -invisible -params "log-directory=ore_check_logs&bot-map=$MAP" > data/ore_check/dd.log 2>&1 &
dd=$!
while kill -0 $dd 2>/dev/null; do
	sleep 2
	grep -q "^done" data/ore_check/results.txt 2>/dev/null && break
	if [ $(($(date +%s) - began)) -gt 600 ]; then echo "still going after 600 s - stopped"; break; fi
done
sleep 1
kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
rm -f orecheck.mdme orecheck.mdme.dmb orecheck.mdme.rsc orecheck.mdme.int orecheck.mdme.lk orecheck.mdme.dyn.rsc orecheck.mdme.rsc.lk orecheck.mdme.dyn.rsc.lk
echo "took $(($(date +%s) - began)) s"
cat data/ore_check/results.txt 2>/dev/null || { echo "no results: see data/ore_check/dd.log"; tail -20 data/ore_check/dd.log; }
runtimes=$(grep -c 'runtime error' data/logs/ore_check_logs/runtime.log 2>/dev/null)
echo "runtimes: ${runtimes:-0}"
grep -h -A4 'runtime error' data/logs/ore_check_logs/runtime.log 2>/dev/null | head -80
