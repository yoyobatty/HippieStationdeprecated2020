#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Keybind check with a real client (see keybind_check.dm). A BYOND window opens on the desktop for a minute or two.
# Usage: tools/keybind_check/run.sh [label]     results in data/keycheck_<label>.txt
# Won't start with a game window already open: DreamSeeker is one instance per machine and it would take that window over.
set -u
LABEL="${1:-now}"
PORT="${PORT:-45311}"
# MAP=testbench boots the small test map (_maps/testbench.json, ~4 s of init against ~17 s for the Hippie map) for
# windows and checks that never use the station; leave it unset for anything that needs Hippie's rooms.
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
HERE="$(cd "$(dirname "$0")" && pwd -W)"
cd "${CHECKOUT:-$(dirname "$0")/../..}"
# A console_shots section that never uses the station (console_shots_testbench.txt) boots the small test map by itself.
if [ -z "${MAP:-}" ] && [ "${HARNESS:-}" = "console_shots.dm" ] && [ -f data/console_shots_which ]; then
	WHICH=$(tr -d '\r\n ' < data/console_shots_which)
	if tr -d '\r' < "$HERE/console_shots_testbench.txt" | grep -qx "$WHICH"; then
		MAP=testbench
		echo "Section $WHICH doesn't use the station: booting the small test map (MAP=hippiestation to override)"
	fi
fi

if tasklist 2>/dev/null | grep -qi dreamseeker; then
	echo "A game window is open: close it first."
	exit 1
fi

mkdir -p data
rm -f data/keycheck_shots_done data/keycheck.txt data/keycheck_sendkeys data/keycheck_keys_sent data/keycheck_focus_away data/keycheck_focus_gone data/keycheck_focus_back data/keycheck_alttab data/keycheck_alttab_done data/keycheck_alttab_back data/keycheck_phase data/keycheck_probe_ok data/keycheck_mouse_steps
BEFORE=$(find data/player_saves -name preferences.sav -exec md5sum {} + 2>/dev/null | sort)

echo "Building..."
sed 's/^#include "hippiestation\\code\\modules\\bots_ai\\bot_brain.dm"/#include "keybind_check_tmp.dm"\r\n&/' hippiestation.dme > keycheck.dme
cp "$HERE/${HARNESS:-keybind_check.dm}" keybind_check_tmp.dm
# EXCLUDE=<text> leaves out the include lines containing it: a "before" build without a new file (console_shots.dm)
if [ -n "${EXCLUDE:-}" ]; then
	grep -v -F "$EXCLUDE" keycheck.dme > keycheck_excluded.dme && mv keycheck_excluded.dme keycheck.dme
	echo "Left out: $EXCLUDE"
fi
"$BYOND_BIN/dm.exe" keycheck.dme | grep -E "error|dmb -"
[ -f keycheck.dmb ] || { echo "Build failed"; exit 1; }

# Guests allowed: the only way in without touching the saved BYOND login.
rm -rf data/keycheck_config
cp -r config data/keycheck_config
sed -i '/^GUEST_BAN/d' data/keycheck_config/config.txt
sed -i '/^BOT_CREW/d' data/keycheck_config/hippiestation_config.txt

"$BYOND_BIN/dd.exe" keycheck.dmb "$PORT" -trusted -invisible -params "config=data/keycheck_config&keycheck=1${MAP:+&bot-map=$MAP}" > data/keycheck_dd.log 2>&1 &
DD=$!
echo "Server $DD booting..."
for i in $(seq 1 240); do
	grep -q "Initializations complete" data/keycheck_dd.log 2>/dev/null && break
	sleep 1
done
grep -q "Initializations complete" data/keycheck_dd.log || { echo "Server never finished starting"; kill "$DD"; exit 1; }
sleep 3

# The last run's game window browser (WebView2) can still be shutting down: a window opened on top of it came up blank and took no
# clicks (twice in a row of quick runs, 2026-11-04). Wait for any of DreamSeeker's to go first.
for i in $(seq 1 30); do
	powershell -NoProfile -Command "if (Get-CimInstance Win32_Process -Filter \"name='msedgewebview2.exe'\" | Where-Object { \$_.CommandLine -match 'dreamseeker' }) { exit 1 } else { exit 0 }" && break
	sleep 1
done
"$BYOND_BIN/dreamseeker.exe" "byond://127.0.0.1:$PORT##guest" &
CLIENT=$!
echo "Client $CLIENT connecting..."

SENT=0
AWAY=0
for i in $(seq 1 400); do
	kill -0 "$DD" 2>/dev/null || break
	grep -q "^done" data/keycheck.txt 2>/dev/null && break
	if [ "$SENT" = "0" ] && [ -f data/keycheck_sendkeys ]; then
		SENT=1
		powershell -NoProfile -ExecutionPolicy Bypass -File "$HERE/${SENDER:-sendkeys.ps1}"
		echo sent > data/keycheck_keys_sent
	fi
	if [ "${TABBED:-0}" = "0" ] && [ -f data/keycheck_alttab ]; then
		TABBED=1
		powershell -NoProfile -ExecutionPolicy Bypass -File "$HERE/alttab.ps1" &
	fi
	if [ "$AWAY" = "0" ] && [ -f data/keycheck_focus_away ]; then
		AWAY=1
		powershell -NoProfile -ExecutionPolicy Bypass -File "$HERE/focusaway.ps1" &
	fi
	sleep 1
done
kill "$DD" 2>/dev/null
kill "$CLIENT" 2>/dev/null
AFTER=$(find data/player_saves -name preferences.sav -exec md5sum {} + 2>/dev/null | sort)
[ "$BEFORE" = "$AFTER" ] || echo "WRONG: a preferences file changed during this run"

cp data/keycheck.txt "data/keycheck_$LABEL.txt" 2>/dev/null
rm -f keycheck.* keybind_check_tmp.dm
cat "data/keycheck_$LABEL.txt" 2>/dev/null || { echo "No results"; tail -20 data/keycheck_dd.log; }
