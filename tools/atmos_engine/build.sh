#!/bin/bash
# Builds the tile atmos engine and puts hippie_atmos.dll in the repository root, next to rust_g.dll.
# Needs Rust with the 32-bit target BYOND uses: rustup target add i686-pc-windows-msvc. No other dependencies.
# Run the engine's tests too with TEST=1, and build the Linux library (../../libhippie_atmos.so) too with LINUX=1.
set -eu
cd "$(dirname "$0")"
export PATH="$HOME/.cargo/bin:$PATH"
if [ -n "${TEST:-}" ]; then
	cargo test --lib --target i686-pc-windows-msvc
fi
cargo build --release --target i686-pc-windows-msvc
cp target/i686-pc-windows-msvc/release/hippie_atmos.dll "../../${OUT:-hippie_atmos}.dll"
if [ -n "${LINUX:-}" ]; then
	# The Linux library too (BYOND's Linux server is 32-bit as well), cross-built here with zig as the linker. Needs zig, cargo-zigbuild
	# (cargo install cargo-zigbuild) and rustup target add i686-unknown-linux-gnu. Asking for glibc 2.17 keeps it to what any Linux
	# since 2012 has. cargo-zigbuild's wrappers break on a path with a space in it: if yours has one, put zig on PATH by its short
	# (8.3) path and set CARGO_ZIGBUILD_CACHE_DIR to a short path too.
	cargo zigbuild --release --target i686-unknown-linux-gnu.2.17
	cp target/i686-unknown-linux-gnu/release/libhippie_atmos.so ../../libhippie_atmos.so
	echo "Built ../../libhippie_atmos.so"
fi
echo "Built ../../${OUT:-hippie_atmos}.dll"
