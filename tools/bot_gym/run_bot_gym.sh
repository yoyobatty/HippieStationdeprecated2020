#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Bot Gym: compile, boot headless, run the bot AI scenario suite, print the results.
# Usage: tools/bot_gym/run_bot_gym.sh [name filter|all] [runs per scenario]
#   tools/bot_gym/run_bot_gym.sh                 # everything, once
#   tools/bot_gym/run_bot_gym.sh "welded" 10     # scenarios with "welded" in the name, 10 runs each
# Runs fast-forwarded when timewarp.dll is there (tools/timewarp/build.bat); SPEED=1 for real time, SPEED=10 to cap it at 10x.
# Exit code: 0 if nothing unexpectedly failed, 1 otherwise. Set BYOND_BIN to override the BYOND path.
# NOCOMPILE=1 runs the hippiestation.dmb that's there; DMB=path/name (no extension) runs that build instead (tools/bot_gym/ab_gym.sh).
# JOBS=N shares the runs out over N servers at once (default 8 for the whole suite, 1 for a filter): one BYOND server uses one core.
#   Each takes its share longest first by data/bot_gym_times.json (the game seconds each scenario took last time, kept up to date by
#   every run), and tools/bot_gym/merge_gym_shards.py puts the results back together in the suite's order.
# OUT=dir writes the results there instead of data/bot_gym, so two gyms can run at once (ab_gym.sh runs before and after together).
# Each server's own results are in data/bot_gym_work/<run>/, its output in <OUT>/servers/; with JOBS>1 round logs go to
# data/logs/bot_gym/<run>/shard<i>/ (servers started in the same second would share the dated folder).
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
FILTER="${1:-all}"
RUNS="${2:-1}"
SPEED="${SPEED:-0}"
OUT="${OUT:-data/bot_gym}"
if [ -z "${JOBS:-}" ]; then
	if [ "$FILTER" = "all" ]; then JOBS=8; else JOBS=1; fi
fi
COMMON=""
if [ "$SPEED" != "1" ] && [ -f timewarp.dll ]; then COMMON="$COMMON&timewarp=$SPEED"; fi
if [ -n "${EXTRA_PARAMS:-}" ]; then COMMON="$COMMON&$EXTRA_PARAMS"; fi
# The small test map (_maps/testbench.json) unless MAP= names another: the arenas are built in a reservation, and the
# Hippie map only cost boot time (2026-11-07, full gym once: 362 s on Hippie, 201 s on testbench, every failure on either
# map passed on its own). MAP=hippiestation for a scenario that uses the station. A bot-map in EXTRA_PARAMS wins.
case "&${EXTRA_PARAMS:-}" in *"&bot-map="*) ;; *) COMMON="$COMMON&bot-map=${MAP:-testbench}" ;; esac
PARAMS="bot-gym=$FILTER&bot-gym-runs=$RUNS$COMMON"

DMB="${DMB:-hippiestation}"
if [ "${NOCOMPILE:-0}" != "1" ] && [ "$DMB" = "hippiestation" ]; then
	echo "Compiling..."
	"$BYOND_BIN/dm.exe" hippiestation.dme | grep -E "error|warning|dmb -" || true
fi
if [ ! -f "$DMB.dmb" ]; then echo "No $DMB.dmb"; exit 1; fi

RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
WORK="data/bot_gym_work/$RUN_ID"
mkdir -p "$WORK"
# Keep the last few runs' server folders, for looking into one that went wrong.
ls -1d data/bot_gym_work/*/ 2>/dev/null | head -n -5 | xargs -r rm -rf
rm -rf "$OUT"
mkdir -p "$OUT"

# One copy of the build, so the code can be recompiled while the gym runs; each server gets a hard link to it under its own name, since
# BYOND keeps a <name>.dyn.rsc beside each .dmb and two servers on one name fight over it. The copies sit in the repo root because a
# world's files (config/, data/) are found from where its .dmb is.
COPY="gymrun_$$"
cp "$DMB.dmb" "$COPY.dmb"
cp "$DMB.rsc" "$COPY.rsc"
trap 'rm -f "$COPY".* "$COPY"_*.*' EXIT

# run_server <slot> <results dir> <log> <params>: one headless server, which shuts itself down when its scenarios are done.
run_server() {
	local slot=$1 dir=$2 log=$3 params=$4
	ln -f "$COPY.dmb" "${COPY}_$slot.dmb" 2>/dev/null || cp "$COPY.dmb" "${COPY}_$slot.dmb"
	ln -f "$COPY.rsc" "${COPY}_$slot.rsc" 2>/dev/null || cp "$COPY.rsc" "${COPY}_$slot.rsc"
	mkdir -p "$dir"
	timeout "${GYM_TIMEOUT:-900}" "$BYOND_BIN/dd.exe" "${COPY}_$slot.dmb" 0 -trusted -invisible \
		-params "$params&bot-results=$dir/" > "$log" 2>&1
}

echo "Running Bot Gym ($PARAMS) on $JOBS server(s)..."
STARTED=$SECONDS
for ((i = 1; i <= JOBS; i++)); do
	SPLIT=""
	if [ "$JOBS" -gt 1 ]; then SPLIT="&bot-gym-shard=$i/$JOBS&log-directory=bot_gym/$RUN_ID/shard$i"; fi
	run_server "$i" "$WORK/shard$i" "$WORK/shard$i.log" "$PARAMS$SPLIT" &
done
wait
# A build from before split gyms (an old DMB=, a REV= build of bot_gym.dm) ignores bot-results and writes data/bot_gym itself.
if [ ! -f "$WORK/shard1/results.json" ] && [ ! -f "$WORK/shard1/planned.json" ] && [ data/bot_gym/results.json -nt "$COPY.dmb" ]; then
	if [ "$JOBS" -gt 1 ]; then echo "WARNING: this build is from before split gyms, so every server ran the whole suite. Use JOBS=1 with it."; fi
	rm -rf "$WORK/shard1"
	mv data/bot_gym "$WORK/shard1"
fi
python tools/bot_gym/merge_gym_shards.py "$OUT" "$WORK" --wall $((SECONDS - STARTED))

if [ ! -s "$OUT/results.json" ] || [ "$(head -c 2 "$OUT/results.json")" = "[]" ]; then
	echo "No results written - see $OUT/servers/"
	head -3 "$OUT/summary.txt" 2>/dev/null
	tail -20 "$OUT/servers/shard1.log" 2>/dev/null
	exit 1
fi
cat "$OUT/summary.txt"
echo "Transcripts: $OUT/transcripts/"
if grep -q "^FAILED: 0$" "$OUT/summary.txt"; then exit 0; fi

# A full run puts 300-odd scenarios on the servers, and a few of the slow ones time out under that load but pass alone. Each one that
# failed is run again on its own, JOBS at a time: passing then, it's reported as flaky under load rather than failed. RERUN=0 skips this.
if [ "${RERUN:-1}" = "0" ] || [ "$FILTER" != "all" ]; then exit 1; fi
mapfile -t FAILED_NAMES < <(python -c "import json, sys; [print(r['name']) for r in json.load(open(sys.argv[1])) if r['outcome'] in ('FAIL', 'PENDING')]" "$OUT/results.json" | sort -u)
echo "Running the ${#FAILED_NAMES[@]} that failed again, each on its own..."
for ((k = 0; k < ${#FAILED_NAMES[@]}; k++)); do
	ENC=$(python -c "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))" "${FAILED_NAMES[$k]}")
	while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done
	run_server "r$k" "$WORK/rerun$k" "$WORK/rerun$k.log" "bot-gym=$ENC&bot-gym-runs=1$COMMON&log-directory=bot_gym/$RUN_ID/rerun$k" &
done
wait
STILL=0
for ((k = 0; k < ${#FAILED_NAMES[@]}; k++)); do
	if [ -f "$WORK/rerun$k/summary.txt" ] && grep -q "^FAILED: 0$" "$WORK/rerun$k/summary.txt"; then
		echo "FLAKY  ${FAILED_NAMES[$k]}: failed in the full run, passed on its own"
	else
		echo "STILL FAILS ON ITS OWN  ${FAILED_NAMES[$k]}"
		STILL=1
	fi
done
exit $STILL
