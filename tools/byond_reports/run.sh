#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Builds and runs the stand-alone BYOND repros on each install, results in tools/byond_reports/results/<name>_<build>.txt.
# Usage: tools/byond_reports/run.sh [name]     ref_stall, area_scan or list_union, every one by default
set -u
cd "$(dirname "$0")"
BINS=("/c/Program Files (x86)/BYOND/bin" "/c/Users/Keegan Eaton/BYOND-516.1666/byond/bin")
NAMES=("${@:-ref_stall}")
[ $# -eq 0 ] && NAMES=(ref_stall area_scan list_union)
mkdir -p results

for name in "${NAMES[@]}"; do
	for bin in "${BINS[@]}"; do
		[ -x "$bin/dd.exe" ] || { echo "No BYOND at $bin"; continue; }
		rm -f "$name/$name.dmb" "$name/$name.rsc" "$name/$name.lk" "$name/$name.dyn.rsc"
		"$bin/dm.exe" "$name/$name.dm" | grep -E "error|warning: |dmb -"
		[ -f "$name/$name.dmb" ] || { echo "Build failed: $name"; continue; }
		out="results/tmp_$name.txt"
		flags=""; [ -f "$name/$name.dll" ] && flags="-trusted"
		timeout 300 "$bin/dd.exe" "$name/$name.dmb" $flags -invisible > "$out" 2>&1
		echo "exit $?" >> "$out"
		build=$(grep -m1 -o -E "BYOND [0-9]+\.[0-9]+" "$out" | cut -d' ' -f2)
		mv "$out" "results/${name}_${build:-unknown}.txt"
		cat "results/${name}_${build:-unknown}.txt"
		rm -f "$name/$name.dmb" "$name/$name.rsc" "$name/$name.lk" "$name/$name.dyn.rsc"
	done
done
