#!/bin/bash
# Deletes the big files of old rounds under data/logs: game.log, the bot trace and the bot telemetry, nearly all of what
# the logs weigh. Summaries, results, deaths, timelines, runtime and attack logs stay, so old batches still have their
# reports. A round with a player_telemetry.jsonl(.zst) in it (a person played) is left whole.
# Bot Shift batches (data/logs/shift_batch/<batch>) keep them only in the newest few batches, whatever their age: batches
# wrote about 50 GB a day, two days of them filled the drive to 99% on 2026-11-10, and a full drive froze the game. Since
# the trace and telemetry are compressed (bot_trace.log.zst, bot_telemetry.jsonl.zst, 2026-11-10), a shift is ~15 MB
# instead of ~170, and the newest 20 batches are kept. The rest of data/logs (dated rounds, live rounds, the gym) loses
# them after a number of days.
# run_shift_batch.sh starts this at the beginning of every batch, after making the new batch's folder; it can be run by hand too.
# Usage: tools/bot_gym/prune_logs.sh [days] [batches]    other rounds older than this many days (default 2); batches kept whole (default 20)
set -u
cd "$(dirname "$0")/../.." || exit 1
DAYS="${1:-2}"
BATCHES="${2:-20}"
[ -d data/logs ] || exit 0
count=0
bytes=0
BIG=(-name game.log -o -name bot_telemetry.jsonl -o -name bot_telemetry.jsonl.zst -o -name bot_trace.log -o -name bot_trace.log.zst)
prune() { # a big file, unless a person played in that round
	if [ -s "${1%/*}/player_telemetry.jsonl" ] || [ -s "${1%/*}/player_telemetry.jsonl.zst" ]; then return; fi
	local size
	size=$(stat -c %s -- "$1" 2>/dev/null) || return
	rm -f -- "$1" && count=$((count + 1)) && bytes=$((bytes + size))
}
# Batches: all but the newest $BATCHES, by when the batch folder was made
if [ -d data/logs/shift_batch ]; then
	while IFS= read -r batch; do
		while IFS= read -r -d '' f; do
			prune "$f"
		done < <(find "$batch" -type f \( "${BIG[@]}" \) -print0)
	done < <(ls -1dt data/logs/shift_batch/*/ 2>/dev/null | tail -n +$((BATCHES + 1)))
fi
# Everything else: by age
while IFS= read -r -d '' f; do
	prune "$f"
done < <(find data/logs -path data/logs/shift_batch -prune -o -type f \( "${BIG[@]}" \) -mtime +$((DAYS - 1)) -print0)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] pruned $count files ($((bytes / 1048576)) MB): batches past the newest $BATCHES, other rounds older than $DAYS days; $(df -h . 2>/dev/null | awk 'NR==2 {print $4}') free"
