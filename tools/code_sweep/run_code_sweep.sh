#!/bin/bash
# Code sweep: one of everything, to see what breaks (hippiestation/code/modules/admin/code_sweep.dm).
# Usage: tools/code_sweep/run_code_sweep.sh [atoms,turfs,reagents,reactions,crafting,ui]
# Environment: NOCOMPILE=1, PORT=45300, MAP=boxstation
# Results in data/code_sweep/: report.txt, progress.txt, crashers.txt.
# If a type takes the server down, it goes in crashers.txt and the sweep carries on from the next one, up to 20 times.
set -u

main() {
	cd "$(dirname "$0")/../.." || exit 1
	BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
	KINDS="${1:-atoms,turfs,reagents,reactions,crafting,ui}"
	PORT="${PORT:-45300}"
	OUT=data/code_sweep

	if [ "${NOCOMPILE:-0}" != "1" ]; then
		echo "Compiling..."
		"$BYOND_BIN/dm.exe" hippiestation.dme | grep -E "error|warning|dmb -" || true
	fi
	if [ ! -f hippiestation.dmb ]; then echo "Compile failed"; exit 1; fi
	COPY="sweeprun_$$"
	cp hippiestation.dmb "$COPY.dmb"
	cp hippiestation.rsc "$COPY.rsc"

	rm -rf "$OUT"
	mkdir -p "$OUT"
	: > "$OUT/crashers.txt"
	local start
	start=$(date +%s)
	local tries=0
	local remaining="$KINDS"
	local skip=0
	while [ "$tries" -lt 20 ]; do
		tries=$((tries + 1))
		local params="code-sweep=$remaining&code-sweep-skip=$skip&timewarp=0"
		if [ -n "${MAP:-}" ]; then params="$params&bot-map=$MAP"; fi
		echo "[$(date +%H:%M:%S)] sweeping $remaining (from $skip)"
		timeout 3000 "$BYOND_BIN/dd.exe" "$COPY.dmb" "$PORT" -trusted -invisible -params "$params" >> "$OUT/dd_out.log" 2>&1
		if [ -f "$OUT/report.txt" ]; then break; fi
		# Down mid-sweep: the last line of progress.txt is what it was doing. Note it and go on from the one after.
		local last
		last="$(tail -1 "$OUT/progress.txt" 2>/dev/null)"
		if [ -z "$last" ]; then echo "The server never got going - see $OUT/dd_out.log"; break; fi
		echo "$last" >> "$OUT/crashers.txt"
		echo "[$(date +%H:%M:%S)] the server went down on: $last"
		local kind count
		kind="$(echo "$last" | cut -d' ' -f1)"
		count="$(echo "$last" | cut -d' ' -f2)"
		remaining="$(echo "$remaining" | sed -E "s/^.*\b$kind\b/$kind/")"
		skip=$count
	done
	rm -f "$COPY".*
	echo "Sweep took $((($(date +%s) - start) / 60)) minutes."
	if [ -s "$OUT/crashers.txt" ]; then echo "Took the server down:"; cat "$OUT/crashers.txt"; fi
	if [ -f "$OUT/report.txt" ]; then sed -n '1,12p' "$OUT/report.txt"; fi
}

main "$@"
exit $?
