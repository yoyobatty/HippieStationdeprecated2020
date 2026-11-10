#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Pre-push check: what's COMMITTED, built and checked by itself, away from the working tree.
#
# Several sessions share this working tree, and each commits only its own files and its own lines of hippiestation.dme.
# The tree as it stands compiles; a commit made from part of it may not: a new file left out, an #include line not staged,
# a proc another session hasn't committed yet. This checks out the commit somewhere else and builds that.
#
# Usage: tools/prepush/run_prepush.sh [rev]        (default HEAD)
#   GYM=1            also run a short Bot Gym on that build (GYM_FILTER picks the scenarios, default "dept:|knowledge:")
#   PREPUSH_DIR=dir  where the checkout lives (default ../hippie_prepush_wt, kept between runs so the next one is quick)
# Exit 0 if the commit compiles with no errors and the lint finds nothing new.
set -u
cd "$(dirname "$0")/../.." || exit 1
ROOT="$(pwd)"
REV="${1:-HEAD}"
SHA="$(git rev-parse --verify --quiet "$REV^{commit}")" || { echo "prepush: no such commit: $REV"; exit 1; }
SHORT="$(git rev-parse --short "$SHA")"
WT="${PREPUSH_DIR:-$ROOT/../hippie_prepush_wt}"
DM="/c/Program Files (x86)/BYOND/bin/dm.exe"
[ -x "$DM" ] || DM="$(command -v DreamMaker 2>/dev/null || command -v dm.exe 2>/dev/null)"
[ -n "$DM" ] || { echo "prepush: can't find Dream Maker"; exit 1; }

START=$SECONDS
if [ -e "$WT/.git" ]; then
	# Ours to throw away: back to exactly the commit, whatever the last run left in it
	git -C "$WT" reset -q --hard || exit 1
	git -C "$WT" checkout -q --detach "$SHA" || exit 1
else
	echo "prepush: checking out $SHORT into $WT (once; later runs reuse it)"
	git worktree add -q --detach "$WT" "$SHA" || exit 1
fi

FAILED=0
echo "prepush: $SHORT $(git log -1 --format=%s "$SHA" | cut -c1-70)"

# 1. It compiles
OUT="$(cd "$WT" && "$DM" hippiestation.dme 2>&1)"
LAST="$(echo "$OUT" | grep -E "[0-9]+ errors?, [0-9]+ warnings?" | tail -1)"
if echo "$LAST" | grep -q " 0 errors"; then
	echo "PASS   compiles: $LAST"
else
	echo "FAIL   compiles: ${LAST:-no result from Dream Maker}"
	echo "$OUT" | grep -E "error" | head -20 | sed 's/^/         /'
	FAILED=1
fi

# 2. The lint finds nothing new (its binary is fetched once into tools/lint/bin, which git ignores: borrowed from here)
if [ -d "$ROOT/tools/lint/bin" ] && [ ! -d "$WT/tools/lint/bin" ]; then
	mkdir -p "$WT/tools/lint/bin" && cp "$ROOT"/tools/lint/bin/* "$WT/tools/lint/bin/" 2>/dev/null
fi
LINT="$(cd "$WT" && tools/lint/run_lint.sh 2>&1)"
if [ $? -eq 0 ]; then
	echo "PASS   $(echo "$LINT" | grep "^lint:" | tail -1)"
else
	echo "FAIL   lint"
	echo "$LINT" | tail -15 | sed 's/^/         /'
	FAILED=1
fi

# 3. No type names an icon_state its sheet doesn't have, beyond the known ones (tools/icon_check)
if [ -f "$WT/tools/icon_check/icon_check.py" ]; then
	ICONS="$(cd "$WT" && python tools/icon_check/icon_check.py 2>&1)"
	if [ $? -eq 0 ]; then
		echo "PASS   $(echo "$ICONS" | tail -1)"
	else
		echo "FAIL   $(echo "$ICONS" | tail -1)"
		echo "$ICONS" | head -15 | sed 's/^/         /'
		FAILED=1
	fi
fi

# 4. A short gym on that build, if asked
if [ "${GYM:-0}" = "1" ] && [ "$FAILED" = "0" ]; then
	GYM_OUT="$(cd "$WT" && NOCOMPILE=1 tools/bot_gym/run_bot_gym.sh "${GYM_FILTER:-dept:|knowledge:}" 1 2>&1)"
	LINE="$(echo "$GYM_OUT" | grep "BOT GYM" | tail -1)"
	if echo "$GYM_OUT" | grep -q "^FAILED: 0"; then
		echo "PASS   $LINE"
	else
		echo "FAIL   ${LINE:-no result from the gym}"
		echo "$GYM_OUT" | grep -E "^(FAIL|STILL)" | head -10 | sed 's/^/         /'
		FAILED=1
	fi
fi

# What the working tree has and the commit lacks: not a failure, but "it works here" was resting on it
LEFT=$(git status --short | grep -vc "^??")
if [ "$REV" = "HEAD" ] && [ "$LEFT" != "0" ]; then
	echo "note   $LEFT tracked file(s) changed in the working tree and not in this commit"
fi
echo "prepush: $([ "$FAILED" = "0" ] && echo OK || echo FAILED) in $((SECONDS - START)) s"
exit $FAILED
