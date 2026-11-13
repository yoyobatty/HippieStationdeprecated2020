#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Href fixes with a real client (href_check.dm). A BYOND window opens on the desktop for a minute or two.
# Usage: tools/keybind_check/run_href_check.sh [label]     results in data/hrefcheck_<label>.txt
# Its own build names and port, so run.sh's runs (keycheck.*, 45311) aren't touched. Won't start with a game window open.
set -u
LABEL="${1:-now}"
PORT="${PORT:-45323}"
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
cd "$(dirname "$0")/../.."

if tasklist 2>/dev/null | grep -qi dreamseeker; then
	echo "A game window is open: close it first."
	exit 1
fi

mkdir -p data
rm -rf data/hrefcheck.txt data/hrefcheck_history data/logs/hrefcheck_logs
BEFORE=$(find data/player_saves -name preferences.sav -exec md5sum {} + 2>/dev/null | sort)

echo "Building..."
began=$(date +%s)
# As run.sh builds: a .dme (an .mdme copy's client came up without the skin's chat control) with the harness before the bot AI
sed 's/^#include "hippiestation\\code\\modules\\bots_ai\\bot_brain.dm"/#include "hrefcheck_tmp.dm"\r\n&/' hippiestation.dme > hrefcheck.dme
cp tools/keybind_check/href_check.dm hrefcheck_tmp.dm
"$BYOND_BIN/dm.exe" hrefcheck.dme | grep -E "error|dmb -"
[ -f hrefcheck.dmb ] || { echo "Build failed"; rm -f hrefcheck.dme hrefcheck_tmp.dm; exit 1; }

# Guests allowed: the only way in without touching the saved BYOND login. No bot crew.
rm -rf data/hrefcheck_config
cp -r config data/hrefcheck_config
sed -i '/^GUEST_BAN/d' data/hrefcheck_config/config.txt
sed -i '/^BOT_CREW/d' data/hrefcheck_config/hippiestation_config.txt

"$BYOND_BIN/dd.exe" hrefcheck.dmb "$PORT" -trusted -invisible -params "config=data/hrefcheck_config&bot-map=testbench&log-directory=hrefcheck_logs" > data/hrefcheck_dd.log 2>&1 &
DD=$!
echo "Server $DD booting..."
for i in $(seq 1 240); do
	grep -q "Initializations complete" data/hrefcheck_dd.log 2>/dev/null && break
	kill -0 "$DD" 2>/dev/null || break
	sleep 1
done
grep -q "Initializations complete" data/hrefcheck_dd.log || { echo "Server never finished starting"; kill "$DD" 2>/dev/null; exit 1; }
sleep 3

# A last run's WebView2 can still be shutting down: a window opened on top of it comes up blank
for i in $(seq 1 30); do
	powershell -NoProfile -Command "if (Get-CimInstance Win32_Process -Filter \"name='msedgewebview2.exe'\" | Where-Object { \$_.CommandLine -match 'dreamseeker' }) { exit 1 } else { exit 0 }" && break
	sleep 1
done
"$BYOND_BIN/dreamseeker.exe" "byond://127.0.0.1:$PORT##guest" &
CLIENT=$!
echo "Client $CLIENT connecting..."

for i in $(seq 1 300); do
	kill -0 "$DD" 2>/dev/null || break
	grep -q "done: " data/hrefcheck.txt 2>/dev/null && break
	sleep 1
done
sleep 2
kill "$DD" 2>/dev/null
kill "$CLIENT" 2>/dev/null
sleep 1
kill -9 "$DD" 2>/dev/null
AFTER=$(find data/player_saves -name preferences.sav -exec md5sum {} + 2>/dev/null | sort)
[ "$BEFORE" = "$AFTER" ] || echo "WRONG: a preferences file changed during this run"

cp data/hrefcheck.txt "data/hrefcheck_$LABEL.txt" 2>/dev/null
sleep 3
rm -f hrefcheck.dme hrefcheck_tmp.dm hrefcheck.dmb hrefcheck.rsc hrefcheck.int hrefcheck.lk hrefcheck.dyn.rsc hrefcheck.rsc.lk hrefcheck.dyn.rsc.lk
echo "took $(($(date +%s) - began)) s"
cat "data/hrefcheck_$LABEL.txt" 2>/dev/null || { echo "No results"; tail -20 data/hrefcheck_dd.log; }
runtimes=$(grep -c 'runtime error' data/logs/hrefcheck_logs/runtime.log 2>/dev/null)
echo "runtimes: ${runtimes:-0}"
grep -h -A4 'runtime error' data/logs/hrefcheck_logs/runtime.log 2>/dev/null | head -40
