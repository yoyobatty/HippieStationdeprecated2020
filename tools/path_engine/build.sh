#!/bin/bash
# Builds the path engine and puts hippie_path.dll in the repository root, next to hippie_lighting.dll.
# Needs Rust with the 32-bit target BYOND uses: rustup target add i686-pc-windows-msvc. No other dependencies.
# Run the engine's tests too with TEST=1, and build the Linux library (../../libhippie_path.so) too with LINUX=1. OUT=<name> builds
# the Windows one under another name (hippie_path_test.dll, say) while running
# servers have hippie_path.dll open; path-lib=<name> in the world params loads that one.
set -eu
cd "$(dirname "$0")"
export PATH="$HOME/.cargo/bin:$PATH"
if [ -n "${TEST:-}" ]; then
	cargo test --lib --target i686-pc-windows-msvc
fi
cargo build --release --target i686-pc-windows-msvc
cp target/i686-pc-windows-msvc/release/hippie_path.dll "../../${OUT:-hippie_path}.dll"
echo "Built ../../${OUT:-hippie_path}.dll"
if [ -n "${LINUX:-}" ]; then
	# The Linux library too (BYOND's Linux server is 32-bit as well), cross-built here with zig as the linker, as the atmos and lighting
	# engines are. Needs zig, cargo-zigbuild (cargo install cargo-zigbuild) and rustup target add i686-unknown-linux-gnu. Asking for
	# glibc 2.17 keeps it to what any Linux since 2012 has. cargo-zigbuild's wrappers break on a path with a space in it: if yours has
	# one, put zig on PATH by its short (8.3) path, set CARGO_ZIGBUILD_CACHE_DIR to a short path too, and run this from the short path.
	cargo zigbuild --release --target i686-unknown-linux-gnu.2.17
	cp target/i686-unknown-linux-gnu/release/libhippie_path.so ../../libhippie_path.so
	echo "Built ../../libhippie_path.so"
fi
