#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# A batch of Bot Shifts, several at a time, with one report at the end. A single shift is one roll of the
# dice (the MC schedules by real CPU time, so nothing replays); the same crew over a dozen shifts shows what
# fails every time and what fails one time in ten.
# Usage: tools/bot_gym/run_shift_batch.sh [runs] [minutes] [crew]
#   tools/bot_gym/run_shift_batch.sh 12 30                          # twelve 30 minute shifts
#   MAPS="boxstation metastation" tools/bot_gym/run_shift_batch.sh 4 # takes the maps in turn
# Environment:
#   JOBS=3       servers at a time (each wants about 1.6 GB and one core)
#   MAPS="..."   map names from _maps/*.json, used in turn; unset is the default map
#   NAME=label   names the batch; results are in data/logs/shift_batch/<name>/run<n>/
#   EVENTS=1 EVAC=1 ENGINE=linda SPEED=10 PROFILE=1   as for run_bot_shift.sh
#   ROUND=1      whole rounds, over when the crew has called the shuttle and left; [minutes] is then the limit.
#                ROUND=20 has the heads call it at 20 minutes instead of somewhere after the hour
#   QUIET=1      no bot AI logs (for measuring speed; the WHY part of the report goes)
#   ANTAGS=traitor*2   a couple of the crew are traitors
#   NOCOMPILE=1  use the hippiestation.dmb that's there
#   EXTRA_PARAMS="a=1&b=2"  more world params, like lighting-unseen=off to update every light at once
#   BASE_PORT=45200
# Each shift runs from its own copy of the .dmb, so the code can be edited and recompiled while a batch runs.
# Everything is inside main() so that editing this file during a batch can't change what the batch does next:
# bash reads a script as it goes, and would otherwise carry on from the same byte of the new text.
# Exit code: 0 if no shift failed, 1 otherwise.
set -u

clock() {
	local s=$1
	printf '%dm %02ds' $((s / 60)) $((s % 60))
}

# Takes the lowest free port slot. mkdir either makes the directory or fails, so two shifts can't get the same one.
claim_slot() {
	local i
	while :; do
		for i in $(seq 1 "$JOBS"); do
			if mkdir "$DIR/.slot$i" 2>/dev/null; then
				echo "$i"
				return
			fi
		done
		sleep 1
	done
}

run_shift() {
	local n=$1
	local slot
	slot=$(claim_slot)
	local out="$DIR/run$n"
	local map=""
	if [ "${#MAP_LIST[@]}" -gt 0 ]; then map="${MAP_LIST[$(((n - 1) % ${#MAP_LIST[@]}))]}"; fi
	mkdir -p "$out"
	local params="bot-shift=$MINUTES&log-directory=$LOGS/run$n&bot-results=$out/"
	if [ "$SPEED" != "1" ] && [ -f timewarp.dll ]; then params="$params&timewarp=$SPEED"; fi
	if [ -n "$CREW" ]; then params="$params&bot-crew=${CREW// /_}"; fi
	if [ -n "$map" ]; then params="$params&bot-map=$map"; fi
	if [ "${EVENTS:-0}" = "1" ]; then params="$params&bot-events=1"; fi
	if [ "${PROFILE:-0}" = "1" ]; then params="$params&bot-profile=1"; fi
	if [ "${EVAC:-0}" = "1" ]; then params="$params&bot-evac=1"; fi
	if [ "${ROUND:-0}" != "0" ]; then params="$params&bot-round=$ROUND"; fi
	if [ "${QUIET:-0}" = "1" ]; then params="$params&bot-quiet=1"; fi
	if [ -n "${ANTAGS:-}" ]; then params="$params&bot-antags=${ANTAGS// /_}"; fi
	if [ -n "${ENGINE:-}" ]; then params="$params&atmos-engine=$ENGINE"; fi
	if [ -n "${EXTRA_PARAMS:-}" ]; then params="$params&$EXTRA_PARAMS"; fi
	local began
	began=$(date +%s)
	timeout $((MINUTES * 75 + 600)) "$BYOND_BIN/dd.exe" "${COPY}_$slot.dmb" $((BASE_PORT + slot)) -trusted -invisible \
		-params "$params" > "$out/dd_out.log" 2>&1
	local now
	now=$(date +%s)
	rmdir "$DIR/.slot$slot"
	local verdict="NO RESULTS - see $out/dd_out.log"
	if [ -f "$out/summary.txt" ]; then
		verdict="$(grep -m1 '^FAILED:' "$out/summary.txt"), $(sed -n '2p' "$out/summary.txt" | sed -E 's/^Took [^(]*\(([^)]*)\).*/\1/')"
	fi
	echo "$n" >> "$DIR/finished.txt"
	local done_count
	done_count=$(wc -l < "$DIR/finished.txt")
	local elapsed=$((now - START))
	local left=$(((RUNS - done_count) * elapsed / done_count))
	echo "[$(date +%H:%M:%S)] run $n${map:+ ($map)} took $(clock $((now - began))): $verdict - $done_count/$RUNS done, $(clock $elapsed) so far, about $(clock $left) left"
}

main() {
	cd "$(dirname "$0")/../.." || exit 1
	BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
	RUNS="${1:-6}"
	MINUTES="${2:-30}"
	CREW="${3:-}"
	JOBS="${JOBS:-3}"
	MAPS="${MAPS:-}"
	SPEED="${SPEED:-0}"
	BASE_PORT="${BASE_PORT:-45200}"
	local stamp
	stamp="$(date +%m%d-%H%M%S)"
	NAME="${NAME:-$stamp}"
	LOGS="shift_batch/$NAME"
	DIR="data/logs/$LOGS"

	if [ "${NOCOMPILE:-0}" != "1" ]; then
		echo "Compiling..."
		"$BYOND_BIN/dm.exe" hippiestation.dme | grep -E "error|warning|dmb -" || true
	fi
	if [ ! -f hippiestation.dmb ]; then echo "Compile failed"; exit 1; fi

	mkdir -p "$DIR"
	# One copy for each slot: a server writes icons it builds at runtime into <name>.dyn.rsc, and two sharing one fail
	# with "cannot open savefile buffer" the first time both want it.
	COPY="shiftbatch_$stamp"
	local copy_slot
	for copy_slot in $(seq 1 "$JOBS"); do
		cp hippiestation.dmb "${COPY}_$copy_slot.dmb"
		cp hippiestation.rsc "${COPY}_$copy_slot.rsc"
	done
	trap 'kill $(jobs -p) 2>/dev/null' INT TERM

	read -r -a MAP_LIST <<< "$MAPS"
	START=$(date +%s)
	: > "$DIR/finished.txt"

	echo "Running $RUNS ${MINUTES}-minute shifts, $JOBS at a time${MAPS:+, on: $MAPS} -> $DIR"
	local n
	for n in $(seq 1 "$RUNS"); do
		while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done
		run_shift "$n" &
		sleep 3 #boots a little apart
	done
	wait
	echo "Batch took $(clock $(($(date +%s) - START))) in all."
	rm -f "$COPY"_*
	python tools/bot_gym/batch_report.py "$DIR" | tee "$DIR/report.txt"
	! grep -q "^FAILED SHIFTS" "$DIR/report.txt"
}

main "$@"
exit $?
