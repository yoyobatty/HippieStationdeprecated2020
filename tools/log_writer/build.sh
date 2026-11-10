#!/bin/bash
# Builds the log writer and puts hippie_log.dll in the repository root, next to rust_g.dll.
# Needs Rust with the 32-bit target BYOND uses: rustup target add i686-pc-windows-msvc. No other dependencies.
# Run its tests too with TEST=1, and build the Linux library (../../libhippie_log.so) too with LINUX=1 (see
# tools/atmos_engine/build.sh for what that needs). Without the library the game writes its logs through rust_g as before.
set -eu
cd "$(dirname "$0")"
export PATH="$HOME/.cargo/bin:$PATH"
if [ -n "${TEST:-}" ]; then
	cargo test --lib --target i686-pc-windows-msvc
fi
cargo build --release --target i686-pc-windows-msvc
cp target/i686-pc-windows-msvc/release/hippie_log.dll ../../hippie_log.dll
if [ -n "${LINUX:-}" ]; then
	cargo zigbuild --release --target i686-unknown-linux-gnu.2.17
	cp target/i686-unknown-linux-gnu/release/libhippie_log.so ../../libhippie_log.so
	echo "Built ../../libhippie_log.so"
fi
echo "Built ../../hippie_log.dll"
