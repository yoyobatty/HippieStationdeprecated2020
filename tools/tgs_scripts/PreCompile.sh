#!/bin/bash
# TGS PreCompile (Linux): $1 is the new deployment folder. Puts librust_g.so in it: the prebuilt i686 library from the
# rust-g release named by RUST_G_VERSION in dependencies.sh, kept in a cache beside this script so each version is
# downloaded once. Everything else the game loads on Linux (libhippie_atmos.so, libhippie_lighting.so, libhippie_path.so,
# libquickwrite.so)
# is committed, and the tgui bundle is committed too, so there's nothing to build.
# Windows needs no PreCompile: rust_g.dll and the other DLLs are committed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/InstallDeps.sh"

RUST_G_VERSION="$(sed -n 's/^export RUST_G_VERSION=\([^[:space:]]*\).*$/\1/p' "$1/dependencies.sh" | tr -d '\r')"
if [ -z "$RUST_G_VERSION" ]; then
	echo "PreCompile: no RUST_G_VERSION in $1/dependencies.sh"
	exit 1
fi

CACHE="$SCRIPT_DIR/cache/rust_g/$RUST_G_VERSION"
if [ ! -s "$CACHE/librust_g.so" ]; then
	echo "Downloading librust_g.so $RUST_G_VERSION..."
	mkdir -p "$CACHE"
	curl -fsSL -o "$CACHE/librust_g.so.part" "https://github.com/tgstation/rust-g/releases/download/$RUST_G_VERSION/librust_g.so"
	mv "$CACHE/librust_g.so.part" "$CACHE/librust_g.so"
fi
cp -f "$CACHE/librust_g.so" "$1/librust_g.so"
echo "librust_g.so $RUST_G_VERSION in place"
