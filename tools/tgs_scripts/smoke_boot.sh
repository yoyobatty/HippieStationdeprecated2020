#!/bin/bash
# Smoke boot for TGS deploys (Linux): boots the freshly compiled game headless and fails the deploy unless it gets
# through initialization. TGS runs PostCompile.sh from the instance's EventScripts folder after compiling, which runs
# this copy from the new code, so the check always matches the build it checks.
#
#   smoke_boot.sh <deployment folder> <BYOND version TGS compiled with>
#   DREAMDAEMON=/path/to/DreamDaemon smoke_boot.sh <folder>      (by hand)
#
# At PostCompile TGS hasn't linked the instance's GameStaticFiles (config, data) into the deployment yet, so the boot
# uses the repository's config and writes its logs into a data folder of its own, deleted afterwards. If those are
# already links (a different TGS order), it refuses rather than write into the live server's files.
# TIMEOUT (seconds, default 300) and PARAMS (world params) can be set in the environment.
set -u

fail() {
	echo "SMOKE BOOT FAILED: $1"
	exit 1
}

GAME_DIR="$(cd "$1" && pwd)" || fail "no folder $1"
ENGINE_VERSION="${2:-}"
TIMEOUT="${TIMEOUT:-300}"

for name in data config; do
	if [ -L "$GAME_DIR/$name" ]; then
		fail "$name is already linked to the instance's static files: a boot here would write into the live server's files"
	fi
done

if [ -z "${DREAMDAEMON:-}" ]; then
	[ -n "${TGS_INSTANCE_ROOT:-}" ] || fail "TGS_INSTANCE_ROOT isn't set (TGS 6.17 or newer sets it). Run by hand with DREAMDAEMON=<path>."
	DREAMDAEMON="$TGS_INSTANCE_ROOT/Byond/$ENGINE_VERSION/byond/bin/DreamDaemon"
fi
[ -x "$DREAMDAEMON" ] || fail "no DreamDaemon at $DREAMDAEMON"
BYOND_BIN="$(dirname "$DREAMDAEMON")"
export LD_LIBRARY_PATH="$BYOND_BIN:$GAME_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

DMB="$(find "$GAME_DIR" -maxdepth 1 -name '*.dmb' | head -n 1)"
[ -n "$DMB" ] || fail "no .dmb in $GAME_DIR"

PORT=$(( 40000 + RANDOM % 20000 ))
DATA_EXISTED=0
[ -e "$GAME_DIR/data" ] && DATA_EXISTED=1
MARKER="$(mktemp)"

echo "Smoke boot: $(basename "$DMB") on port $PORT ($DREAMDAEMON)"
START=$(date +%s)
cd "$GAME_DIR" || fail "can't enter $GAME_DIR"
if [ -n "${PARAMS:-}" ]; then
	"$DREAMDAEMON" "$DMB" "$PORT" -trusted -invisible -params "$PARAMS" > /dev/null 2>&1 &
else
	"$DREAMDAEMON" "$DMB" "$PORT" -trusted -invisible > /dev/null 2>&1 &
fi
DD_PID=$!

READY=""
while [ $(( $(date +%s) - START )) -lt "$TIMEOUT" ]; do
	sleep 1
	if [ -d "$GAME_DIR/data/logs" ]; then
		READY="$(find "$GAME_DIR/data/logs" -name '*.log' -newer "$MARKER" -exec grep -l "Initializations complete" {} + 2>/dev/null | head -n 1)"
	fi
	[ -n "$READY" ] && break
	kill -0 "$DD_PID" 2>/dev/null || break
done
STOPPED=0
if kill -0 "$DD_PID" 2>/dev/null; then
	kill "$DD_PID" 2>/dev/null
	sleep 2
	kill -9 "$DD_PID" 2>/dev/null
else
	STOPPED=1
fi
TOOK=$(( $(date +%s) - START ))

RUNTIMES=0
UNFINISHED=""
if [ -d "$GAME_DIR/data/logs" ]; then
	# A runtime in a subsystem's Initialize() only ends that proc, so the MC still says "Initializations complete"; it also
	# says which subsystem didn't finish (master.dm), and that build is broken too
	UNFINISHED="$(find "$GAME_DIR/data/logs" -name '*.log' -newer "$MARKER" -exec grep -oh "MC watchdog alert: .* didn't finish initializing" {} + 2>/dev/null \
		| sed -e 's/^MC watchdog alert: //' -e "s/ didn't finish initializing\$//" | sort -u | paste -sd, - | sed 's/,/, /g')"
	RUNTIME_LOGS="$(find "$GAME_DIR/data/logs" -name runtime.log -newer "$MARKER")"
	if [ -n "$RUNTIME_LOGS" ]; then
		RUNTIMES=$(cat $RUNTIME_LOGS | grep -c "runtime error:")
		if [ "$RUNTIMES" -gt 0 ]; then
			echo "Runtime errors during the boot (first 5):"
			cat $RUNTIME_LOGS | grep "runtime error:" | head -n 5 | sed 's/^/  /'
		fi
		if [ -z "$READY" ]; then
			echo "--- last lines of runtime.log:"
			cat $RUNTIME_LOGS | tail -n 15 | sed 's/^/  /'
		fi
	fi
fi
rm -f "$MARKER"
if [ "$DATA_EXISTED" = 0 ]; then
	rm -rf "$GAME_DIR/data"
fi

if [ -z "$READY" ]; then
	if [ "$STOPPED" = 1 ]; then
		fail "DreamDaemon stopped after $TOOK s before initialization finished ($RUNTIMES runtime errors)"
	fi
	fail "initialization didn't finish within $TIMEOUT s ($RUNTIMES runtime errors)"
fi
if [ -n "$UNFINISHED" ]; then
	fail "didn't finish initializing: $UNFINISHED ($RUNTIMES runtime errors)"
fi
echo "Smoke boot passed: initialized in $TOOK s, $RUNTIMES runtime errors."
exit 0
