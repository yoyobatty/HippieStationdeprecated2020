#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Human combat and damage self-test (tools/combat_check/combat_check.dm): the 2026-11-10 fixes driven headless on a
# real round, PASS/FAIL each, plus a few regressions.
# Builds its own copy (combatcheck2.mdme -> combatcheck2.mdme.dmb), so hippiestation.dmb is left alone for whatever else is running.
# Usage: tools/combat_check/run.sh        MAP=hippiestation (any _maps/*.json name) to boot another map; PORT= to move it
# Results: data/combat_check/results.txt, the server's logs in data/logs/combat_check_logs
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45417}"
MAP="${MAP:-testbench}"

cp hippiestation.dme combatcheck2.mdme
printf '#include "tools\\combat_check\\combat_check.dm"\r\n' >> combatcheck2.mdme
echo "Compiling..."
"$BYOND_BIN/dm.exe" combatcheck2.mdme | grep -E "error|warning|dmb -" || true
if [ ! -f combatcheck2.mdme.dmb ]; then echo "Compile failed"; rm -f combatcheck2.mdme; exit 1; fi

rm -rf data/combat_check data/logs/combat_check_logs
mkdir -p data/combat_check
began=$(date +%s)
"$BYOND_BIN/dd.exe" combatcheck2.mdme.dmb "$PORT" -trusted -invisible -params "log-directory=combat_check_logs&bot-map=$MAP" > data/combat_check/dd.log 2>&1 &
dd=$!
while kill -0 $dd 2>/dev/null; do
	sleep 2
	grep -q "^done" data/combat_check/results.txt 2>/dev/null && break
	if [ $(($(date +%s) - began)) -gt 600 ]; then echo "still going after 600 s - stopped"; break; fi
done
sleep 1
kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
rm -f combatcheck2.mdme combatcheck2.mdme.dmb combatcheck2.mdme.rsc combatcheck2.mdme.int combatcheck2.mdme.lk combatcheck2.mdme.dyn.rsc combatcheck2.mdme.rsc.lk combatcheck2.mdme.dyn.rsc.lk
echo "took $(($(date +%s) - began)) s"
cat data/combat_check/results.txt 2>/dev/null || { echo "no results: see data/combat_check/dd.log"; tail -20 data/combat_check/dd.log; }
runtimes=$(grep -c 'runtime error' data/logs/combat_check_logs/runtime.log 2>/dev/null)
echo "runtimes: ${runtimes:-0}"
grep -h -A4 'runtime error' data/logs/combat_check_logs/runtime.log 2>/dev/null | head -80
