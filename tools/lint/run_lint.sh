#!/bin/bash
# Lint: SpacemanDMM's dreamchecker over the whole codebase (about 3 seconds), compared with the known diagnostics in
# tools/lint/baseline.txt so only what's new shows.
#
# Usage: tools/lint/run_lint.sh [--update-baseline] [file.dme]      (default hippiestation.dme)
#
# Exit 1 on a new error, or when the parse stopped early; new warnings are listed but don't fail. After fixing old
# diagnostics, --update-baseline rewrites the baseline from this run. Signal handlers are checked for anything that can
# sleep (SpacemanDMM.toml, SIGNAL_HANDLER in code/__DEFINES/spaceman_dmm.dm); handlers missing the mark are listed.
# The dreamchecker binary is fetched once into tools/lint/bin/ (gitignored): the release named by SPACEMAN_DMM_VERSION
# in dependencies.sh, checked against that release's sha256 list. Change the pin there and the next run fetches it.
set -u
cd "$(dirname "$0")/../.." || exit 1

UPDATE=""
DME="hippiestation.dme"
for arg in "$@"; do
	case "$arg" in
		--update-baseline) UPDATE="--update" ;;
		*) DME="$arg" ;;
	esac
done

PY=""
for p in python python3; do
	if "$p" -c "" > /dev/null 2>&1; then PY="$p"; break; fi
done
if [ -z "$PY" ]; then echo "lint: needs python"; exit 1; fi

VERSION="$(sed -n 's/^export SPACEMAN_DMM_VERSION=\(.*\)$/\1/p' dependencies.sh | tr -d '\r')"
BIN_DIR=tools/lint/bin
case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*) EXE=dreamchecker.exe ;;
	*) EXE=dreamchecker ;;
esac

if [ ! -x "$BIN_DIR/$EXE" ] || [ "$(cat "$BIN_DIR/VERSION" 2>/dev/null)" != "$VERSION" ]; then
	echo "lint: fetching dreamchecker $VERSION"
	mkdir -p "$BIN_DIR"
	URL="https://github.com/SpaceManiac/SpacemanDMM/releases/download/$VERSION"
	if ! curl -sSfL -o "$BIN_DIR/$EXE.part" "$URL/$EXE" || ! curl -sSfL -o "$BIN_DIR/sums.txt" "$URL/$VERSION.sha256"; then
		echo "lint: download failed"; rm -f "$BIN_DIR/$EXE.part"; exit 1
	fi
	WANT="$(grep " target/dist/$EXE\$" "$BIN_DIR/sums.txt" | cut -d' ' -f1)"
	GOT="$(sha256sum "$BIN_DIR/$EXE.part" | cut -d' ' -f1)"
	if [ -z "$WANT" ] || [ "$WANT" != "$GOT" ]; then
		echo "lint: checksum mismatch for $EXE ($GOT, release says ${WANT:-nothing})"; rm -f "$BIN_DIR/$EXE.part"; exit 1
	fi
	mv "$BIN_DIR/$EXE.part" "$BIN_DIR/$EXE"
	chmod +x "$BIN_DIR/$EXE"
	echo "$VERSION" > "$BIN_DIR/VERSION"
fi

"$BIN_DIR/$EXE" -e "$DME" 2>&1 | "$PY" tools/lint/lint_diff.py tools/lint/baseline.txt $UPDATE
STATUS="${PIPESTATUS[1]}"
# Raw .proc/ references skip overrides (BYOND 515+): each one is an error.
if [ -z "$UPDATE" ] && ! "$PY" tools/lint/raw_proc_refs.py; then
	STATUS=1
fi
# Procs registered as signal handlers without SIGNAL_HANDLER, which the sleep check can't see into: listed, not failing.
if [ -z "$UPDATE" ]; then
	"$PY" tools/lint/signal_handlers.py | sed -n 's/^UNMARKED handler: \(.*\)$/NEW warning: \1 has no SIGNAL_HANDLER (python tools\/lint\/signal_handlers.py --apply)/p'
fi
exit "$STATUS"
