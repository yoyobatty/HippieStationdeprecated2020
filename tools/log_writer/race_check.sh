#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Whether log files land where the game asked while BYOND copies, makes and deletes files (race_check.dme), 3 runs each.
# Windows with ../../hippie_log.dll, and with LINUX=1 also Linux (WSL distro HippieLinux, tools/linux_check/setup_wsl.sh) with
# ../../libhippie_log.so. LIB=/path/to/other.dll (or SO=...) tries another build. Every run should say missing=0.
# n is 800: the writer keeps each file open, and a non-root Linux user may only have 1024.
set -u
cd "$(dirname "$0")"
HERE="$(pwd)"
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
N="${N:-800}"
WORK="$(mktemp -d)"
cp race_check.dme "$WORK/"
"$BYOND_BIN/dm.exe" "$WORK/race_check.dme" | grep -E "error|dmb -" || true
[ -f "$WORK/race_check.dmb" ] || { echo "Compile failed"; exit 1; }
LIB="${LIB:-$HERE/../../hippie_log.dll}"
for r in 1 2 3; do
	rm -rf "$WORK/data" "$WORK/race_result.txt"
	(cd "$WORK" && timeout 120 "$BYOND_BIN/dd.exe" race_check.dmb 0 -trusted -invisible -params "lib=$(cygpath -m "$LIB")&n=$N" > /dev/null 2>&1)
	echo "windows run $r: $(cat "$WORK/race_result.txt" 2>/dev/null || echo 'no result')"
done
if [ -n "${LINUX:-}" ]; then
	SO="${SO:-$HERE/../../libhippie_log.so}"
	cp "$SO" "$WORK/libhippie_log.so"
	WSL_WORK="$(wsl -d HippieLinux --exec wslpath -a "$(cygpath -w "$WORK")" | tr -d '\r')"
	# As root and as nobody: root skips permission checks, which hides a file opened under / (EACCES for anyone else)
	MSYS_NO_PATHCONV=1 wsl -d HippieLinux --exec bash -c '
		SRC="$1"; N="$2"; D=/srv/race_check
		for who in root nobody; do
			for r in 1 2 3; do
				rm -rf $D; mkdir -p $D; cp "$SRC/race_check.dmb" "$SRC/libhippie_log.so" $D/; chmod -R 777 $D
				RUN="cd $D && LD_LIBRARY_PATH=/byond/bin timeout 120 /byond/bin/DreamDaemon race_check.dmb 0 -trusted -invisible -params \"lib=$D/libhippie_log.so&n=$N\" >/dev/null 2>&1; cat race_result.txt"
				if [ $who = root ]; then R=$(bash -c "$RUN"); else R=$(runuser -u nobody -- bash -c "$RUN"); fi
				echo "linux $who run $r: ${R:-no result}"
			done
		done
		find / -xdev -path "*data/race_check*" -not -path "$D/*" -prune -exec rm -rf {} + 2>/dev/null
		rm -rf $D' _ "$WSL_WORK" "$N"
fi
rm -rf "$WORK"
