#!/bin/bash
# Builds the log writer and puts hippie_log.dll in the repository root, next to rust_g.dll.
# Needs Rust with the 32-bit target BYOND uses: rustup target add i686-pc-windows-msvc, and a C compiler for zstd (the zstd-sys
# crate builds zstd itself: MSVC here, zig for Linux).
# Run its tests too with TEST=1, and build the Linux library (../../libhippie_log.so) too with LINUX=1: cross-built with zig
# as the linker and C compiler, which needs zig, cargo-zigbuild (cargo install cargo-zigbuild) and rustup target add
# i686-unknown-linux-gnu; glibc 2.17 or later. cargo-zigbuild's wrappers break on a path with a space in it: if yours has one,
# put zig on PATH by its short (8.3) path, set CARGO_ZIGBUILD_CACHE_DIR to a short path too, and run this from the short path
# (here: /c/Users/KEEGAN~1/DOWNLO~1/HIPPIE~1/HIPPIE~1/tools/LOG_WR~1). Checked on Linux with tools/linux_check/run.sh (WSL):
# EXTRA=log-check=1 with a logcheck.mdme build runs log_check.dm there.
# Without the library the game writes its logs through rust_g as before.
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
