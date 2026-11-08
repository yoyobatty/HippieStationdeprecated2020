#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Bot Gym: compile, boot headless, run the bot AI scenario suite, print the results.
# Usage: tools/bot_gym/run_bot_gym.sh [name filter|all] [runs per scenario]
#   tools/bot_gym/run_bot_gym.sh                 # everything, once
#   tools/bot_gym/run_bot_gym.sh "welded" 10     # scenarios with "welded" in the name, 10 runs each
# Runs fast-forwarded when timewarp.dll is there (tools/timewarp/build.bat); SPEED=1 for real time, SPEED=10 to cap it at 10x.
# Exit code: 0 if nothing unexpectedly failed, 1 otherwise. Set BYOND_BIN to override the BYOND path.
# NOCOMPILE=1 runs the hippiestation.dmb that's there; DMB=path/name (no extension) runs that build instead (tools/bot_gym/ab_gym.sh).
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
FILTER="${1:-all}"
RUNS="${2:-1}"
SPEED="${SPEED:-0}"
PARAMS="bot-gym=$FILTER&bot-gym-runs=$RUNS"
if [ "$SPEED" != "1" ] && [ -f timewarp.dll ]; then PARAMS="$PARAMS&timewarp=$SPEED"; fi
if [ -n "${EXTRA_PARAMS:-}" ]; then PARAMS="$PARAMS&$EXTRA_PARAMS"; fi
# The small test map (_maps/testbench.json) unless MAP= names another: the arenas are built in a reservation, and the
# Hippie map only cost boot time (2026-11-07, full gym once: 362 s on Hippie, 201 s on testbench, every failure on either
# map passed on its own). MAP=hippiestation for a scenario that uses the station. A bot-map in EXTRA_PARAMS wins.
case "&${EXTRA_PARAMS:-}" in *"&bot-map="*) ;; *) PARAMS="$PARAMS&bot-map=${MAP:-testbench}" ;; esac

DMB="${DMB:-hippiestation}"
if [ "${NOCOMPILE:-0}" != "1" ] && [ "$DMB" = "hippiestation" ]; then
	echo "Compiling..."
	"$BYOND_BIN/dm.exe" hippiestation.dme | grep -E "error|warning|dmb -" || true
fi
if [ ! -f "$DMB.dmb" ]; then echo "No $DMB.dmb"; exit 1; fi

rm -rf data/bot_gym
echo "Running Bot Gym ($PARAMS)..."
# From a copy, so the code can be recompiled while the gym runs.
COPY="gymrun_$$"
cp "$DMB.dmb" "$COPY.dmb"
cp "$DMB.rsc" "$COPY.rsc"
timeout 900 "$BYOND_BIN/dd.exe" "$COPY.dmb" 45123 -trusted -invisible \
	-params "$PARAMS" > data/bot_gym_dd.log 2>&1
rm -f "$COPY".*

if [ ! -f data/bot_gym/summary.txt ]; then
	echo "No results written - see data/bot_gym_dd.log"
	tail -20 data/bot_gym_dd.log
	exit 1
fi
cat data/bot_gym/summary.txt
echo "Transcripts: data/bot_gym/transcripts/"
if grep -q "^FAILED: 0$" data/bot_gym/summary.txt; then exit 0; fi

# A full run puts 200-odd scenarios on one server, and a few of the slow ones time out under that load but pass alone. Each one
# that failed is run again on its own: passing then, it's reported as flaky under load rather than failed. RERUN=0 skips this.
if [ "${RERUN:-1}" = "0" ] || [ "$FILTER" != "all" ]; then exit 1; fi
mapfile -t FAILED_NAMES < <(python -c "import json; [print(r['name']) for r in json.load(open('data/bot_gym/results.json')) if r['outcome'] == 'FAIL']" | sort -u)
rm -rf data/bot_gym_full
mv data/bot_gym data/bot_gym_full
STILL=0
for NAME in "${FAILED_NAMES[@]}"; do
	ENC=$(python -c "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))" "$NAME")
	ALONE="bot-gym=$ENC&bot-gym-runs=1${PARAMS#bot-gym=$FILTER&bot-gym-runs=$RUNS}"
	rm -rf data/bot_gym
	cp "$DMB.dmb" "$COPY.dmb"
	cp "$DMB.rsc" "$COPY.rsc"
	timeout 300 "$BYOND_BIN/dd.exe" "$COPY.dmb" 45123 -trusted -invisible -params "$ALONE" > data/bot_gym_dd_rerun.log 2>&1
	rm -f "$COPY".*
	if [ -f data/bot_gym/summary.txt ] && grep -q "^FAILED: 0$" data/bot_gym/summary.txt; then
		echo "FLAKY  $NAME: failed in the full run, passed on its own"
	else
		echo "STILL FAILS ON ITS OWN  $NAME"
		STILL=1
	fi
done
rm -rf data/bot_gym
mv data/bot_gym_full data/bot_gym
exit $STILL
