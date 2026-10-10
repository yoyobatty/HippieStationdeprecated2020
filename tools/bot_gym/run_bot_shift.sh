#!/bin/bash
# Bot Shift: compile, boot headless, run a fast-forwarded shift on the real station with a crew of
# bots, print the verdict. See hippiestation/code/modules/bots_ai/gym/bot_shift.dm.
# Usage: tools/bot_gym/run_bot_shift.sh [minutes] [crew]
#   tools/bot_gym/run_bot_shift.sh                          # 30 minute shift, the default crew
#   tools/bot_gym/run_bot_shift.sh 60                       # an hour
#   tools/bot_gym/run_bot_shift.sh 20 "Botanist*2,Chemist"  # pick the crew: job titles, *N for several
# Environment:
#   SPEED=0   no speed limit (default)    SPEED=10  at most 10x    SPEED=1  real time
#   EVENTS=1  leave random events on      BYOND_BIN, PORT to override the defaults
#   PROFILE=1 profile the shift (slower); read it with tools/bot_gym/shift_profile.py
#   EVAC=1    call the emergency shuttle eight minutes before the end and judge who makes it aboard
# Exit code: 0 if nothing failed, 1 otherwise.
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
MINUTES="${1:-30}"
CREW="${2:-}"
SPEED="${SPEED:-0}"
PORT="${PORT:-45124}"
LOG=data/bot_shift_dd.log

echo "Compiling..."
"$BYOND_BIN/dm.exe" hippiestation.dme | grep -E "error|warning|dmb -" || true
if [ ! -f hippiestation.dmb ]; then echo "Compile failed"; exit 1; fi

PARAMS="bot-shift=$MINUTES"
if [ "$SPEED" != "1" ]; then
	if [ ! -f timewarp.dll ]; then
		echo "Building timewarp.dll..."
		cmd //c "tools\\timewarp\\build.bat" > /dev/null
	fi
	if [ -f timewarp.dll ]; then
		PARAMS="$PARAMS&timewarp=$SPEED"
	else
		echo "No timewarp.dll (tools/timewarp/build.bat needs Visual Studio) - running in real time"
	fi
fi
if [ -n "$CREW" ]; then PARAMS="$PARAMS&bot-crew=${CREW// /_}"; fi
if [ "${EVENTS:-0}" = "1" ]; then PARAMS="$PARAMS&bot-events=1"; fi
if [ "${PROFILE:-0}" = "1" ]; then PARAMS="$PARAMS&bot-profile=1"; fi
if [ "${EVAC:-0}" = "1" ]; then PARAMS="$PARAMS&bot-evac=1"; fi

rm -rf data/bot_shift
mkdir -p data
echo "Running a $MINUTES minute Bot Shift ($PARAMS)..."
# Long enough for the whole shift in real time, plus booting.
timeout $((MINUTES * 75 + 600)) "$BYOND_BIN/dd.exe" hippiestation.dmb "$PORT" -trusted -invisible \
	-params "$PARAMS" > "$LOG" 2>&1 &
DD=$!
trap 'kill $DD 2>/dev/null' INT TERM
shown=0
while kill -0 $DD 2>/dev/null; do
	sleep 2
	lines=$(grep -c -E "BOT SHIFT: [0-9]|TIMEWARP:|Initializations complete" "$LOG" 2>/dev/null)
	if [ "${lines:-0}" -gt "$shown" ]; then
		grep -E "BOT SHIFT: [0-9]|TIMEWARP:|Initializations complete" "$LOG" | tail -n $((lines - shown)) | sed 's/^/  /'
		shown=$lines
	fi
done
wait $DD

if [ ! -f data/bot_shift/summary.txt ]; then
	echo "No results written - see $LOG"
	tail -20 "$LOG"
	exit 1
fi
echo
cat data/bot_shift/summary.txt
echo "What happened when: data/bot_shift/timeline.txt"
echo "How each bot moved and handled things: python tools/bot_gym/analyze_telemetry.py"
grep -q "^FAILED: 0$" data/bot_shift/summary.txt
