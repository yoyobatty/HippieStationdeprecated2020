#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Plastic explosives self-test (tools/charge_check/charge_check.dm): C4 and X4 planted as a player plants them, headless.
# Builds its own copy (chargecheck.mdme -> chargecheck.mdme.dmb), so hippiestation.dmb is left alone for whatever else is running.
# Usage: tools/charge_check/run.sh
# Results: data/charge_check/results.txt, and the server's logs in data/logs/charge_check_logs
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45417}"
MAP="${MAP:-testbench}"

cp hippiestation.dme chargecheck.mdme
printf '#include "tools\\charge_check\\charge_check.dm"\r\n' >> chargecheck.mdme
echo "Compiling..."
"$BYOND_BIN/dm.exe" chargecheck.mdme | grep -E "error|warning|dmb -" || true
if [ ! -f chargecheck.mdme.dmb ]; then echo "Compile failed"; rm -f chargecheck.mdme; exit 1; fi

rm -rf data/charge_check data/logs/charge_check_logs
began=$(date +%s)
"$BYOND_BIN/dd.exe" chargecheck.mdme.dmb "$PORT" -trusted -invisible -params "charge-check=1&log-directory=charge_check_logs&bot-map=$MAP" > /dev/null 2>&1 &
dd=$!
while kill -0 $dd 2>/dev/null; do
	sleep 2
	[ -f data/charge_check/results.txt ] && break
	if [ $(($(date +%s) - began)) -gt 900 ]; then echo "still going after 900 s - stopped"; break; fi
done
sleep 1
kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
rm -f chargecheck.mdme chargecheck.mdme.dmb chargecheck.mdme.rsc chargecheck.mdme.int chargecheck.mdme.lk chargecheck.mdme.dyn.rsc chargecheck.mdme.rsc.lk chargecheck.mdme.dyn.rsc.lk
echo "took $(($(date +%s) - began)) s"
cat data/charge_check/results.txt 2>/dev/null || echo "no results: see data/logs/charge_check_logs"
runtimes=$(grep -c 'runtime error' data/logs/charge_check_logs/runtime.log 2>/dev/null)
echo "runtimes: ${runtimes:-0}"
grep -h -A3 'runtime error' data/logs/charge_check_logs/runtime.log 2>/dev/null | head -60
