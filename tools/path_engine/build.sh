#!/bin/bash
# Builds the path engine and puts hippie_path.dll in the repository root, next to hippie_lighting.dll.
# Needs Rust with the 32-bit target BYOND uses: rustup target add i686-pc-windows-msvc. No other dependencies.
# Run the engine's tests too with TEST=1. OUT=<name> builds it under another name (hippie_path_test.dll, say) while running
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
