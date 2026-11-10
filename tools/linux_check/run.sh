#!/bin/bash
# The game on Linux (a WSL distro set up by setup_wsl.sh): deploys a .dmb built on Windows (a .dmb runs on either) into the Linux file
# system with tools/deploy.sh, adds rust_g's Linux library, runs a short Bot Shift headless, and says what each native engine did.
# In WSL, as root, from the repository through /mnt/c:
#   bash tools/linux_check/run.sh <build, no extension, in the repo root> [minutes=4] [map=testbench] [crew=fill:15]
#   bash tools/linux_check/run.sh linuxcheck.mdme 4 testbench
# EXTRA="a=1&b=2" adds world params. The deploy is in /root/hippie; its logs in /root/hippie/data/logs.
set -u
REPO="$(pwd)"
BUILD="${1:?a build in the repo root, without .dmb}"
MINUTES="${2:-4}"
MAP="${3:-testbench}"
CREW="${4:-fill:15}"
DEST=/root/hippie
RUST_G_VERSION="$(sed -n 's/^export RUST_G_VERSION=\([^[:space:]]*\).*$/\1/p' dependencies.sh | tr -d '\r')"
[ -x /byond/bin/DreamDaemon ] || { echo "No /byond: run tools/linux_check/setup_wsl.sh first"; exit 1; }
[ -f "$BUILD.dmb" ] || { echo "No $BUILD.dmb"; exit 1; }

START=$(date +%s)
rm -rf "$DEST"
mkdir -p "$DEST"
bash tools/deploy.sh "$DEST" > /dev/null 2>&1
cp "$BUILD.dmb" "$DEST/hippiestation.dmb"
cp "$BUILD.rsc" "$DEST/hippiestation.rsc"
cp -r config "$DEST/"
if [ ! -s "/root/librust_g-$RUST_G_VERSION.so" ]; then
	curl -fsSL "https://github.com/tgstation/rust-g/releases/download/$RUST_G_VERSION/librust_g.so" -o "/root/librust_g-$RUST_G_VERSION.so"
fi
cp "/root/librust_g-$RUST_G_VERSION.so" "$DEST/librust_g.so"
echo "Deployed in $(( $(date +%s) - START )) s: $(ls "$DEST"/*.so | xargs -n1 basename | tr '\n' ' ')"

cd "$DEST"
export LD_LIBRARY_PATH="/byond/bin:$DEST"
PARAMS="bot-shift=$MINUTES&bot-map=$MAP&bot-crew=${CREW// /_}&bot-results=$DEST/results/${EXTRA:+&$EXTRA}"
mkdir -p results
timeout $(( MINUTES * 60 + 300 )) /byond/bin/DreamDaemon hippiestation.dmb 45900 -trusted -invisible -params "$PARAMS" > dd.log 2>&1
echo "Ran in $(( $(date +%s) - START )) s (exit $?)"
LOG="$(find data/logs -name world.log -newer hippiestation.dmb | head -n 1)"
echo "== engines ($LOG)"
grep -hE "Path engine|Atmos:|Lighting|rust_g|Shaped explosions|Initializations complete" "$LOG" dd.log 2>/dev/null | sort -u | head -20
echo "== runtimes"
grep -h "runtime error" "$(dirname "$LOG")"/*.log dd.log 2>/dev/null | sed 's/^\[[^]]*\] //' | sort | uniq -c | sort -rn | head -10
echo "== shift"
head -20 results/summary.txt 2>/dev/null || echo "no results/summary.txt"
