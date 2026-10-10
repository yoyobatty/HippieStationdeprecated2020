#!/bin/bash
# Bot Gym: compile, boot headless, run the bot AI scenario suite, print the results.
# Usage: tools/bot_gym/run_bot_gym.sh [name filter|all] [runs per scenario]
#   tools/bot_gym/run_bot_gym.sh                 # everything, once
#   tools/bot_gym/run_bot_gym.sh "welded" 10     # scenarios with "welded" in the name, 10 runs each
# Runs fast-forwarded when timewarp.dll is there (tools/timewarp/build.bat); SPEED=1 for real time, SPEED=10 to cap it at 10x.
# Exit code: 0 if nothing unexpectedly failed, 1 otherwise. Set BYOND_BIN to override the BYOND path.
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
FILTER="${1:-all}"
RUNS="${2:-1}"
SPEED="${SPEED:-0}"
PARAMS="bot-gym=$FILTER&bot-gym-runs=$RUNS"
if [ "$SPEED" != "1" ] && [ -f timewarp.dll ]; then PARAMS="$PARAMS&timewarp=$SPEED"; fi

echo "Compiling..."
"$BYOND_BIN/dm.exe" hippiestation.dme | grep -E "error|warning|dmb -" || true
if [ ! -f hippiestation.dmb ]; then echo "Compile failed"; exit 1; fi

rm -rf data/bot_gym
echo "Running Bot Gym ($PARAMS)..."
timeout 900 "$BYOND_BIN/dd.exe" hippiestation.dmb 45123 -trusted -invisible \
	-params "$PARAMS" > data/bot_gym_dd.log 2>&1

if [ ! -f data/bot_gym/summary.txt ]; then
	echo "No results written - see data/bot_gym_dd.log"
	tail -20 data/bot_gym_dd.log
	exit 1
fi
cat data/bot_gym/summary.txt
echo "Transcripts: data/bot_gym/transcripts/"
grep -q "^FAILED: 0$" data/bot_gym/summary.txt
