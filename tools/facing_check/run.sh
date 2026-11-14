#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Mech facing armour self-test (tools/facing_check/facing_check.dm): a mech hit from all eight sides, headless.
# Builds its own copy (facingcheck.mdme -> facingcheck.mdme.dmb), so hippiestation.dmb is left alone for whatever else is running.
# Usage: tools/facing_check/run.sh
# Results: data/facing_check/results.txt, and the server's logs in data/logs/facing_check_logs
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45419}"
MAP="${MAP:-testbench}"

cp hippiestation.dme facingcheck.mdme
printf '#include "tools\\facing_check\\facing_check.dm"\r\n' >> facingcheck.mdme
echo "Compiling..."
"$BYOND_BIN/dm.exe" facingcheck.mdme | grep -E "error|warning|dmb -" || true
if [ ! -f facingcheck.mdme.dmb ]; then echo "Compile failed"; rm -f facingcheck.mdme; exit 1; fi

rm -rf data/facing_check data/logs/facing_check_logs
began=$(date +%s)
"$BYOND_BIN/dd.exe" facingcheck.mdme.dmb "$PORT" -trusted -invisible -params "facing-check=1&log-directory=facing_check_logs&bot-map=$MAP" > /dev/null 2>&1 &
dd=$!
while kill -0 $dd 2>/dev/null; do
	sleep 2
	[ -f data/facing_check/results.txt ] && break
	if [ $(($(date +%s) - began)) -gt 900 ]; then echo "still going after 900 s - stopped"; break; fi
done
sleep 1
kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
rm -f facingcheck.mdme facingcheck.mdme.dmb facingcheck.mdme.rsc facingcheck.mdme.int facingcheck.mdme.lk facingcheck.mdme.dyn.rsc facingcheck.mdme.rsc.lk facingcheck.mdme.dyn.rsc.lk
echo "took $(($(date +%s) - began)) s"
cat data/facing_check/results.txt 2>/dev/null || echo "no results: see data/logs/facing_check_logs"
runtimes=$(grep -c 'runtime error' data/logs/facing_check_logs/runtime.log 2>/dev/null)
echo "runtimes: ${runtimes:-0}"
grep -h -A3 'runtime error' data/logs/facing_check_logs/runtime.log 2>/dev/null | head -60
