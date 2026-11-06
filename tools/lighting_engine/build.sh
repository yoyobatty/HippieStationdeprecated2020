#!/bin/bash
# Builds the lighting engine and puts hippie_lighting.dll in the repository root, next to rust_g.dll.
# Needs Rust with the 32-bit target BYOND uses: rustup target add i686-pc-windows-msvc. No other dependencies.
# Run the engine's tests too with TEST=1.
set -eu
cd "$(dirname "$0")"
export PATH="$HOME/.cargo/bin:$PATH"
if [ -n "${TEST:-}" ]; then
	cargo test --lib --target i686-pc-windows-msvc
fi
cargo build --release --target i686-pc-windows-msvc
cp target/i686-pc-windows-msvc/release/hippie_lighting.dll ../../hippie_lighting.dll
echo "Built ../../hippie_lighting.dll"
