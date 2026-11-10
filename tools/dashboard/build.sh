#!/bin/bash
# Builds the admins' dashboard server and puts hippie_dashboard.dll in the repository root, next to the other engines.
# Needs Rust with the 32-bit target BYOND uses: rustup target add i686-pc-windows-msvc. No other dependencies.
# Run its tests too with TEST=1, and build the Linux library (../../libhippie_dashboard.so) too with LINUX=1: cross-built with zig as the
# linker, as tools/path_engine/build.sh says (zig and cargo-zigbuild, the 8.3 short path if the repository's path has a space in it).
# OUT=<name> builds the Windows one under another name while a running server has hippie_dashboard.dll open.
set -eu
cd "$(dirname "$0")"
export PATH="$HOME/.cargo/bin:$PATH"
if [ -n "${TEST:-}" ]; then
	cargo test --lib --target i686-pc-windows-msvc
fi
cargo build --release --target i686-pc-windows-msvc
cp target/i686-pc-windows-msvc/release/hippie_dashboard.dll "../../${OUT:-hippie_dashboard}.dll"
echo "Built ../../${OUT:-hippie_dashboard}.dll"
if [ -n "${LINUX:-}" ]; then
	cargo zigbuild --release --target i686-unknown-linux-gnu.2.17
	cp target/i686-unknown-linux-gnu/release/libhippie_dashboard.so ../../libhippie_dashboard.so
	echo "Built ../../libhippie_dashboard.so"
fi
