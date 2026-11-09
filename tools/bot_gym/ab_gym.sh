#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Before and after for a fix, in the Bot Gym: the scenarios matching a filter, N runs each, on a build with the named files as they
# are in HEAD ("before") and on the working tree ("after"). Everything else is the working tree's in both, so a new scenario that
# tests the fix runs against the old code too: name the files the fix is in, not the scenario's.
# Usage: tools/bot_gym/ab_gym.sh "<name filter>" <runs> <file> [file...]
#   tools/bot_gym/ab_gym.sh "lava between it" 3 hippiestation/code/modules/bots_ai/goals/exploring.dm
# REV=<commit> takes "before" from that commit instead of HEAD: REV=e6118c4a~1 for a fix that's already committed.
# The named files are put back byte for byte whatever happens, and hippiestation.dmb is left the "after" build.
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
if [ $# -lt 3 ]; then
	sed -n '3,8p' "$0"
	exit 2
fi
REV="${REV:-HEAD}"
FILTER="$1"
RUNS="$2"
shift 2
SAVE=$(mktemp -d)
for f in "$@"; do
	if [ ! -f "$f" ]; then echo "No such file: $f"; exit 2; fi
	mkdir -p "$SAVE/$(dirname "$f")"
	cp "$f" "$SAVE/$f"
done
put_back() {
	for f in "$@"; do cp "$SAVE/$f" "$f"; done
}
trap 'put_back "$@"; rm -rf "$SAVE"' EXIT

# Before: REV's copies of the named files. A file REV hasn't got stays as it is.
SAME=1
for f in "$@"; do
	git show "$REV:$f" > "$SAVE/rev_version" 2>/dev/null && cp "$SAVE/rev_version" "$f"
	cmp -s "$f" "$SAVE/$f" || SAME=0
done
if [ "$SAME" = "1" ]; then echo "The named files are the same in $REV and the working tree: nothing to compare (REV=<commit>?)"; exit 2; fi
echo "Compiling before ($REV's $*)..."
OUT=$("$BYOND_BIN/dm.exe" hippiestation.dme 2>&1 | grep -E "dmb - ")
echo "  $OUT"
case "$OUT" in *" 0 errors"*) ;; *) echo "Before doesn't compile"; exit 1 ;; esac
cp hippiestation.dmb "$SAVE/before.dmb"
cp hippiestation.rsc "$SAVE/before.rsc"

put_back "$@"
echo "Compiling after (the working tree)..."
OUT=$("$BYOND_BIN/dm.exe" hippiestation.dme 2>&1 | grep -E "dmb - ")
echo "  $OUT"
case "$OUT" in *" 0 errors"*) ;; *) echo "After doesn't compile"; exit 1 ;; esac

# Both at once, each on its own servers: before's results in data/bot_gym_before/, after's in data/bot_gym/. Not when bot_gym.dm itself is
# one of the files, since a build from before split gyms writes data/bot_gym whatever it's told and the two would collide.
echo
DMB="$SAVE/before" OUT=data/bot_gym_before RERUN=0 tools/bot_gym/run_bot_gym.sh "$FILTER" "$RUNS" > "$SAVE/before.out" 2>&1 &
case " $* " in *bot_gym.dm*) wait ;; esac
NOCOMPILE=1 RERUN=0 tools/bot_gym/run_bot_gym.sh "$FILTER" "$RUNS" > "$SAVE/after.out" 2>&1 &
wait
echo "BEFORE"
grep -E "^(PASS|FAIL|XFAIL|XPASS|PENDING) |^BOT GYM|^Took|^WARNING" "$SAVE/before.out" | cut -c1-220
echo "(before's transcripts: data/bot_gym_before/transcripts/)"
echo
echo "AFTER"
grep -E "^(PASS|FAIL|XFAIL|XPASS|PENDING) |^BOT GYM|^Took|^WARNING" "$SAVE/after.out" | cut -c1-220
