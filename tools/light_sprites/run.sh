#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Real-client runs for the light sprite prototype: tools/keybind_check/run.sh with names of its own, so a keybind check in
# another session doesn't share files with it. A BYOND window opens on the desktop for a few minutes.
# Usage: HARNESS=<file in this folder> [MAP=testbench] [PRESENTMON=1] [PARAMS="a=b&c=d"] tools/light_sprites/run.sh <label>
# Notes in data/lsp_<label>.txt, pictures in data/previews/ (shot.ps1), PresentMon frames in data/lsp_frames_<label>_<phase>.csv
set -u
LABEL="${1:-now}"
PORT="${PORT:-45333}"
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
HERE="$(cd "$(dirname "$0")" && pwd -W)"
KC="$(cd "$(dirname "$0")/../keybind_check" && pwd -W)"
PM="${PM:-/c/Program Files (x86)/CapFrameX/PresentMon/PresentMon-2.2.0-x64.exe}"
cd "$(dirname "$0")/../.."

if tasklist 2>/dev/null | grep -qi dreamseeker; then
	echo "A game window is open: close it first."
	exit 1
fi

mkdir -p data/previews
rm -f "data/lsp_cpu_${LABEL}.txt" data/lsp_frames_"${LABEL}"_*.csv data/keycheck_shots_done data/keycheck.txt data/keycheck_sendkeys data/keycheck_shot data/lsp_pm_start data/lsp_pm_done
BEFORE=$(find data/player_saves -name preferences.sav -exec md5sum {} + 2>/dev/null | sort)

echo "Building..."
sed 's/^#include "hippiestation\\code\\modules\\bots_ai\\bot_brain.dm"/#include "lsp_harness_tmp.dm"\r\n&/' hippiestation.dme > lsp.dme
cp "$HERE/${HARNESS:?HARNESS=<file>}" lsp_harness_tmp.dm
"$BYOND_BIN/dm.exe" lsp.dme | grep -E "error|warning: .*lsp_harness|dmb -"
[ -f lsp.dmb ] || { echo "Build failed"; rm -f lsp.* lsp_harness_tmp.dm; exit 1; }

rm -rf data/lsp_config
cp -r config data/lsp_config
sed -i '/^GUEST_BAN/d' data/lsp_config/config.txt
sed -i '/^BOT_CREW/d' data/lsp_config/hippiestation_config.txt

"$BYOND_BIN/dd.exe" lsp.dmb "$PORT" -trusted -invisible -params "config=data/lsp_config&keycheck=1${MAP:+&bot-map=$MAP}${PARAMS:+&$PARAMS}" > data/lsp_dd.log 2>&1 &
DD=$!
echo "Server $DD booting..."
for i in $(seq 1 240); do
	grep -q "Initializations complete" data/lsp_dd.log 2>/dev/null && break
	sleep 1
done
grep -q "Initializations complete" data/lsp_dd.log || { echo "Server never finished starting"; kill "$DD"; exit 1; }
sleep 3
for i in $(seq 1 30); do
	powershell -NoProfile -Command "if (Get-CimInstance Win32_Process -Filter \"name='msedgewebview2.exe'\" | Where-Object { \$_.CommandLine -match 'dreamseeker' }) { exit 1 } else { exit 0 }" && break
	sleep 1
done
"$BYOND_BIN/dreamseeker.exe" "byond://127.0.0.1:$PORT##guest" &
CLIENT=$!
echo "Client $CLIENT connecting..."

SHOTS=0
for i in $(seq 1 ${MAX_SECONDS:-600}); do
	kill -0 "$DD" 2>/dev/null || break
	grep -q "^done" data/keycheck.txt 2>/dev/null && break
	if [ "$SHOTS" = "0" ] && [ -f data/keycheck_sendkeys ]; then
		SHOTS=1
		SHOT_MINUTES=${SHOT_MINUTES:-9} powershell -NoProfile -ExecutionPolicy Bypass -File "$KC/shot.ps1" &
	fi
	# The harness asks for a PresentMon capture: data/lsp_pm_start holds "<phase> <seconds>"; data/lsp_pm_done when it's over
	if [ -f data/lsp_pm_start ]; then
		read -r PHASE SECS < <(tr -d '\r' < data/lsp_pm_start)
		rm -f data/lsp_pm_start
		# DreamSeeker's own CPU time over the capture too: PresentMon's CPUBusy includes the wait for vsync here
		CPU0=$(powershell -NoProfile -ExecutionPolicy Bypass -File "$HERE/cpu.ps1" | tr -d '\r')
		T0=$(date +%s.%N)
		"$PM" --process_name dreamseeker.exe --timed "$SECS" --terminate_after_timed --no_console_stats \
			--output_file "data/lsp_frames_${LABEL}_${PHASE}.csv" > /dev/null 2>&1
		CPU1=$(powershell -NoProfile -ExecutionPolicy Bypass -File "$HERE/cpu.ps1" | tr -d '\r')
		T1=$(date +%s.%N)
		echo "$PHASE $CPU0 $CPU1 $T0 $T1" >> "data/lsp_cpu_${LABEL}.txt"
		echo "$PHASE" > data/lsp_pm_done
	fi
	sleep 1
done
touch data/keycheck_shots_done
kill "$DD" 2>/dev/null
kill "$CLIENT" 2>/dev/null
AFTER=$(find data/player_saves -name preferences.sav -exec md5sum {} + 2>/dev/null | sort)
[ "$BEFORE" = "$AFTER" ] || echo "WRONG: a preferences file changed during this run"
cp data/keycheck.txt "data/lsp_$LABEL.txt" 2>/dev/null
sleep 3
rm -f lsp.dmb lsp.dme lsp.rsc lsp.int lsp.lk lsp.dyn.rsc lsp_harness_tmp.dm
cat "data/lsp_$LABEL.txt" 2>/dev/null || { echo "No results"; tail -20 data/lsp_dd.log; }
