#!/bin/bash
# Throwing check (tools/throw_check/throw_check.dm): flight, aim, strength, the toss, rebounds, a blast throwing a pile. Headless on
# Runtime Station, about a minute. Results: data/throw_check.txt
# Usage: tools/throw_check/run_throw_check.sh [port]
unset __COMPAT_LAYER
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TREE="$HERE/../.."
PORT="${1:-45437}"
BYOND_BIN="/c/Program Files (x86)/BYOND/bin"
cd "$TREE"
cp "$HERE/throw_check.dm" zz_throw_check.dm
cp hippiestation.dme throwcheck.mdme
printf '#include "zz_throw_check.dm"\r\n' >> throwcheck.mdme
"$BYOND_BIN/dm.exe" throwcheck.mdme | grep -E "error|dmb -"
rm -f data/throw_check.txt
rm -rf data/logs/throw_check_logs
"$BYOND_BIN/dd.exe" throwcheck.mdme.dmb "$PORT" -trusted -invisible -params "throw-check=1&log-directory=throw_check_logs&bot-map=testbench" > /dev/null 2>&1 &
dd=$!
began=$(date +%s)
while kill -0 $dd 2>/dev/null; do
	sleep 2
	[ -f data/throw_check.txt ] && break
	if [ $(($(date +%s) - began)) -gt 400 ]; then echo "stopped after 400 s"; break; fi
done
sleep 1
kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
rm -f zz_throw_check.dm throwcheck.mdme throwcheck.mdme.dmb throwcheck.mdme.rsc throwcheck.mdme.int throwcheck.mdme.lk throwcheck.mdme.dyn.rsc throwcheck.mdme.rsc.lk throwcheck.mdme.dyn.rsc.lk
cat data/throw_check.txt 2>/dev/null || echo "no result"
echo "runtimes: $(grep -c 'runtime error' data/logs/throw_check_logs/runtime.log 2>/dev/null)"
grep -A4 'runtime error' data/logs/throw_check_logs/runtime.log 2>/dev/null | head -40
