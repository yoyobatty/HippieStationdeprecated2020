#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Energy gun charge overlay self-test (tools/gun_charge_check/gun_charge_check.dm): every /obj/item/gun/energy type fired
# down, recharged, switched through its modes and EMP'd, its overlays compared with its cell after each step.
# Builds its own copy (guncharge.mdme -> guncharge.mdme.dmb), so hippiestation.dmb is left alone for whatever else is running.
# Usage: tools/gun_charge_check/run.sh        MAP= (any _maps/*.json name, default testbench); PORT= to move it
# Results: data/gun_charge_check/results.txt, the server's logs in data/logs/gun_charge_check_logs
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45419}"
MAP="${MAP:-testbench}"

cp hippiestation.dme guncharge.mdme
printf '#include "tools\\gun_charge_check\\gun_charge_check.dm"\r\n' >> guncharge.mdme
echo "Compiling..."
"$BYOND_BIN/dm.exe" guncharge.mdme | grep -E "error|warning|dmb -" || true
if [ ! -f guncharge.mdme.dmb ]; then echo "Compile failed"; rm -f guncharge.mdme; exit 1; fi

rm -rf data/gun_charge_check data/logs/gun_charge_check_logs
mkdir -p data/gun_charge_check
began=$(date +%s)
"$BYOND_BIN/dd.exe" guncharge.mdme.dmb "$PORT" -trusted -invisible -params "log-directory=gun_charge_check_logs&bot-map=$MAP" > data/gun_charge_check/dd.log 2>&1 &
dd=$!
while kill -0 $dd 2>/dev/null; do
	sleep 2
	grep -q "^done" data/gun_charge_check/results.txt 2>/dev/null && break
	if [ $(($(date +%s) - began)) -gt 300 ]; then echo "still going after 300 s - stopped"; break; fi
done
sleep 1
kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
rm -f guncharge.mdme guncharge.mdme.dmb guncharge.mdme.rsc guncharge.mdme.int guncharge.mdme.lk guncharge.mdme.dyn.rsc guncharge.mdme.rsc.lk guncharge.mdme.dyn.rsc.lk
echo "took $(($(date +%s) - began)) s"
cat data/gun_charge_check/results.txt 2>/dev/null || { echo "no results: see data/gun_charge_check/dd.log"; tail -20 data/gun_charge_check/dd.log; }
runtimes=$(grep -c 'runtime error' data/logs/gun_charge_check_logs/runtime.log 2>/dev/null)
echo "runtimes: ${runtimes:-0}"
grep -h -A4 'runtime error' data/logs/gun_charge_check_logs/runtime.log 2>/dev/null | head -60
