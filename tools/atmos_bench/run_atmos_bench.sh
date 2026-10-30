#!/bin/bash
# Atmos bench: compile, boot headless, time every stage of SSair over a calm station, a gas release, a plasma fire and
# hull breaches, print the results. See hippiestation/code/modules/atmospherics/atmos_bench.dm.
# Usage: tools/atmos_bench/run_atmos_bench.sh [profile | machine-times | idle-check | blocker-check | machines]
#   profile: also profiles the scenes, into data/atmos_bench/profile.json (read it with tools/bot_gym/shift_profile.py)
#   machine-times: also times SSair's machines by type and its pipe networks one by one
#   idle-check: checks idle vents and scrubbers still wake up when their air changes (run it with ENGINE=linda too)
#   blocker-check: checks every kind of air blocker lets air through once deleted, wrecked or taken apart, and walls too
#   machines: just counts what's in SSair.atmos_machinery
# Compare runs: tools/atmos_bench/compare_runs.py
# Environment: SPEED=0 no speed limit (default), SPEED=1 real time; BYOND_BIN, PORT to override the defaults;
#   SKIP_BUILD=1 to run the build that's already there; OUT=<dir> to copy the results somewhere after;
#   ENGINE=linda to run LINDA instead of the tile engine.
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
OPTION="${1:-1}"
SPEED="${SPEED:-0}"
PORT="${PORT:-45126}"

if [ -z "${SKIP_BUILD:-}" ]; then
	echo "Compiling..."
	"$BYOND_BIN/dm.exe" hippiestation.dme | grep -E "error|warning|dmb -" || true
fi
if [ ! -f hippiestation.dmb ]; then echo "Compile failed"; exit 1; fi

PARAMS="atmos-bench=$OPTION"
if [ "$SPEED" != "1" ] && [ -f timewarp.dll ]; then PARAMS="$PARAMS&timewarp=$SPEED"; fi
# ENGINE=linda runs LINDA instead of the tile engine, for comparing the two
if [ -n "${ENGINE:-}" ]; then PARAMS="$PARAMS&atmos-engine=$ENGINE"; fi
# EXTRA_PARAMS="a=1&b=2" adds more world params, like atmos-engine-passes=3
if [ -n "${EXTRA_PARAMS:-}" ]; then PARAMS="$PARAMS&$EXTRA_PARAMS"; fi

rm -rf data/atmos_bench
mkdir -p data
echo "Running atmos bench ($PARAMS)..."
timeout "${BENCH_TIMEOUT:-1800}" "$BYOND_BIN/dd.exe" hippiestation.dmb "$PORT" -trusted -invisible \
	-params "$PARAMS" > data/atmos_bench_dd.log 2>&1

if [ ! -f data/atmos_bench/results.txt ]; then
	echo "No results written - see data/atmos_bench_dd.log"
	tail -20 data/atmos_bench_dd.log
	exit 1
fi
cat data/atmos_bench/results.txt
echo
echo "runtimes: $(grep -c 'runtime error\|Runtime in' data/atmos_bench_dd.log)"
if [ -n "${OUT:-}" ]; then mkdir -p "$OUT" && cp -r data/atmos_bench/. "$OUT/" && cp data/atmos_bench_dd.log "$OUT/"; fi
