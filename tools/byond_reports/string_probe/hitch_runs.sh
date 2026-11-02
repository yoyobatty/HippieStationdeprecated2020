#!/bin/bash
# The late tick hunt several times in a row. Usage: tools/byond_reports/string_probe/hitch_runs.sh <label> [runs]; results in data/hitch_<label>_<n>.txt
cd "$(dirname "$0")/../../.."
for n in $(seq 1 "${2:-3}"); do
	AT_END=1 SECONDS_LIMIT=300 HARNESS=../string_probe/hitch_hunt.dm PARAMS="bot-shift=30&bot-crew=fill:20&bot-events=1&bot-quiet=1&timewarp=0" bash tools/byond_reports/ref_stall/hippie_check.sh > "data/hitch_$1_$n.log" 2>&1
	cp data/ref_stall.txt "data/hitch_$1_$n.txt"
	cp data/ref_stall_dd.log "data/hitch_$1_$n.dd.log"
	grep -E "^=== twenty|^=== station|^registry check" "data/hitch_$1_$n.txt" | cut -c1-200
done
