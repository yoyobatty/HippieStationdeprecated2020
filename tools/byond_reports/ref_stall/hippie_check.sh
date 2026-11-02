#!/bin/bash
unset __COMPAT_LAYER # Git Bash sets it, and under it dm.exe leaks two kernel handles for every file it opens until the next reboot
# Builds the game with hippie_check.dm in it, boots it headless once, prints data/ref_stall.txt. About a minute.
set -u
PORT="${PORT:-45317}"
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
HERE="$(cd "$(dirname "$0")" && pwd -W)"
cd "$(dirname "$0")/../../.."

if [ "${AT_END:-0}" = "1" ]; then # after everything, so it can wrap procs from any file
	sed '/^\/\/ END_INCLUDE/i #include "ref_stall_tmp.dm"' hippiestation.dme > refstall.dme
else
	sed 's/^#include "hippiestation\\code\\modules\\bots_ai\\bot_brain.dm"/#include "ref_stall_tmp.dm"\r\n&/' hippiestation.dme > refstall.dme
fi
cp "$HERE/${HARNESS:-hippie_check.dm}" ref_stall_tmp.dm
"$BYOND_BIN/dm.exe" refstall.dme | grep -E "error|dmb -"
rm -f ref_stall_tmp.dm refstall.dme refstall.int refstall.lk
[ -f refstall.dmb ] || { echo "Build failed"; exit 1; }

rm -f data/ref_stall.txt
rm -rf data/ref_stall_config
cp -r config data/ref_stall_config
sed -i '/^BOT_CREW/d' data/ref_stall_config/hippiestation_config.txt
"$BYOND_BIN/dd.exe" refstall.dmb "$PORT" -trusted -invisible -params "config=data/ref_stall_config${PARAMS:+&$PARAMS}" > data/ref_stall_dd.log 2>&1 &
DD=$!
for i in $(seq 1 "${SECONDS_LIMIT:-240}"); do
	kill -0 "$DD" 2>/dev/null || break
	grep -q "^done" data/ref_stall.txt 2>/dev/null && break
	sleep 1
done
sleep 1
kill "$DD" 2>/dev/null
rm -rf data/ref_stall_config
rm -f refstall.dmb refstall.rsc refstall.dyn.rsc
cat data/ref_stall.txt 2>/dev/null || { echo "No results"; tail -15 data/ref_stall_dd.log; }
