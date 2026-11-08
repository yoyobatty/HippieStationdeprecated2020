#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Lathe groups self-test (tools/lathe_check/lathe_check.dm): every protolathe/imprinter design's one home, the machines' window
# data, and the remembered category. Builds its own copy (lathecheck.mdme), so hippiestation.dmb is left alone.
# Usage: tools/lathe_check/run_lathe_check.sh
# Results: data/lathe_check/results.txt and groups.tsv; the server's logs in data/logs/lathe_check_logs
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45393}"
MAP="${MAP:-testbench}"

cp hippiestation.dme lathecheck.mdme
printf '#include "tools\\lathe_check\\lathe_check.dm"\r\n' >> lathecheck.mdme
echo "Compiling..."
"$BYOND_BIN/dm.exe" lathecheck.mdme | grep -E "error|warning|dmb -" || true
if [ ! -f lathecheck.mdme.dmb ]; then echo "Compile failed"; rm -f lathecheck.mdme; exit 1; fi

rm -rf data/lathe_check data/logs/lathe_check_logs
began=$(date +%s)
"$BYOND_BIN/dd.exe" lathecheck.mdme.dmb "$PORT" -trusted -invisible -params "lathe-check=1&log-directory=lathe_check_logs&bot-map=$MAP" > /dev/null 2>&1 &
dd=$!
while kill -0 $dd 2>/dev/null; do
	sleep 2
	[ -f data/lathe_check/groups.tsv ] && break
	if [ $(($(date +%s) - began)) -gt 600 ]; then echo "still going after 600 s - stopped"; break; fi
done
sleep 1
kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
rm -f lathecheck.mdme lathecheck.mdme.dmb lathecheck.mdme.rsc lathecheck.mdme.int lathecheck.mdme.lk lathecheck.mdme.dyn.rsc lathecheck.mdme.rsc.lk lathecheck.mdme.dyn.rsc.lk
echo "took $(($(date +%s) - began)) s"
cat data/lathe_check/results.txt 2>/dev/null || echo "no results: see data/logs/lathe_check_logs"
runtimes=$(grep -c 'runtime error' data/logs/lathe_check_logs/runtime.log 2>/dev/null)
echo "runtimes: ${runtimes:-0}"
grep -h -A3 'runtime error' data/logs/lathe_check_logs/runtime.log 2>/dev/null | head -40
