#!/bin/bash
# Glide check (tools/glide_check/glide_check.dm): does each self-moving thing's glide cover a tile in the time to its next step?
# Headless on Runtime Station, about two minutes. Results: data/glide_check.txt
# Usage: [EXCLUDE=glide_match.dm] tools/glide_check/run_glide_check.sh [port]
unset __COMPAT_LAYER
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TREE="$HERE/../.."
PORT="${1:-45441}"
BYOND_BIN="/c/Program Files (x86)/BYOND/bin"
cd "$TREE"
cp "$HERE/glide_check.dm" zz_glide_check.dm
# EXCLUDE=glide_match.dm leaves that file out of the build, for a before run
if [ -n "${EXCLUDE:-}" ]; then grep -v "$EXCLUDE" hippiestation.dme > glidecheck.mdme; else cp hippiestation.dme glidecheck.mdme; fi
printf '#include "zz_glide_check.dm"\r\n' >> glidecheck.mdme
"$BYOND_BIN/dm.exe" glidecheck.mdme | grep -E "error|dmb -"
rm -f data/glide_check.txt
rm -rf data/logs/glide_check_logs
"$BYOND_BIN/dd.exe" glidecheck.mdme.dmb "$PORT" -trusted -invisible -params "glide-check=1&log-directory=glide_check_logs&bot-map=testbench" > /dev/null 2>&1 &
dd=$!
began=$(date +%s)
while kill -0 $dd 2>/dev/null; do
	sleep 2
	[ -f data/glide_check.txt ] && break
	if [ $(($(date +%s) - began)) -gt 500 ]; then echo "stopped after 500 s"; break; fi
done
sleep 1
kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
rm -f zz_glide_check.dm glidecheck.mdme glidecheck.mdme.dmb glidecheck.mdme.rsc glidecheck.mdme.int glidecheck.mdme.lk glidecheck.mdme.dyn.rsc glidecheck.mdme.rsc.lk glidecheck.mdme.dyn.rsc.lk
cat data/glide_check.txt 2>/dev/null || echo "no result"
echo "runtimes: $(grep -c 'runtime error' data/logs/glide_check_logs/runtime.log 2>/dev/null)"
grep -A4 'runtime error' data/logs/glide_check_logs/runtime.log 2>/dev/null | head -40
