#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# The admins' dashboard, checked headless: builds its own .dmb with dashboard_check.dm (which makes a link with no admin there), runs a
# Bot Shift on the test map with the dashboard on, then checks the way in (a bad token turned away, the link setting the cookie, the
# page), reads the live stream for a few seconds and says what came down it, and takes a picture of the page with headless Edge.
# Usage: tools/dashboard/check.sh [map=testbench] [seconds the bots get first=40]
# Results: data/dashboard_check/ (results.txt, events.txt, dashboard.png)
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
MAP="${1:-testbench}"
WAIT="${2:-40}"
PORT="${PORT:-47810}"
WEB="${WEB:-47811}"
OUT=data/dashboard_check
EDGE="/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
rm -rf "$OUT"
mkdir -p "$OUT"
{
	cat hippiestation.dme
	printf '#include "tools\\dashboard\\dashboard_check.dm"\r\n'
} > dashcheck.mdme
"$BYOND_BIN/dm.exe" dashcheck.mdme | grep -E "error|dmb -"
[ -f dashcheck.mdme.dmb ] || { echo "Build failed"; rm -f dashcheck.mdme*; exit 1; }

"$BYOND_BIN/dd.exe" dashcheck.mdme.dmb "$PORT" -trusted -invisible -params "bot-shift=10&bot-map=$MAP&bot-crew=fill:15&dashboard-port=$WEB&dashboard-check=1" > "$OUT/dd.log" 2>&1 &
DD=$!
for i in $(seq 1 120); do
	[ -s "$OUT/link.txt" ] && break
	sleep 1
done
LINK="$(cat "$OUT/link.txt" 2>/dev/null)"
if [ -z "$LINK" ]; then
	echo "No link: the dashboard didn't start"
	grep -i "dashboard" "$OUT/dd.log" | head -5
	kill "$DD" 2>/dev/null
	exit 1
fi
echo "Link made; letting the bots get going for $WAIT s (a small explosion goes off a minute in, for the alerts feed)"
sleep "$WAIT"
BASE="http://127.0.0.1:$WEB"
{
	echo "Bad token: $(curl -s -o /dev/null -w '%{http_code}' "$BASE/?t=nope")"
	echo "No cookie, page: $(curl -s -o /dev/null -w '%{http_code}' "$BASE/")"
	echo "No cookie, stream: $(curl -s -o /dev/null -w '%{http_code}' "$BASE/events")"
	echo "Link: $(curl -s -o /dev/null -c "$OUT/cookies" -w '%{http_code} -> %{redirect_url}' "$LINK")"
	echo "Page with the cookie: $(curl -s -b "$OUT/cookies" -o "$OUT/page.html" -w '%{http_code}, %{size_download} bytes' "$BASE/")"
	echo "Snapshot: $(curl -s -b "$OUT/cookies" -o "$OUT/snapshot.json" -w '%{http_code}, %{size_download} bytes' "$BASE/snapshot"), $(python -c "import json,sys; print(sorted(json.load(open(sys.argv[1])).keys()))" "$OUT/snapshot.json" 2>&1)"
} > "$OUT/results.txt"
curl -s -N -b "$OUT/cookies" --max-time 6 "$BASE/events" > "$OUT/events.txt"
{
	echo "Stream for 6 s: $(wc -c < "$OUT/events.txt") bytes"
	grep "^event:" "$OUT/events.txt" | sort | uniq -c
} >> "$OUT/results.txt"
if [ -x "$EDGE" ]; then
	timeout 60 "$EDGE" --headless=new --disable-gpu --hide-scrollbars --window-size=1600,1000 --virtual-time-budget=15000 --user-data-dir="$(cygpath -w "$PWD/$OUT/edge")" --screenshot="$(cygpath -w "$PWD/$OUT/dashboard.png")" "$LINK#still" > /dev/null 2>&1
	timeout 60 "$EDGE" --headless=new --disable-gpu --hide-scrollbars --window-size=600,1100 --virtual-time-budget=15000 --user-data-dir="$(cygpath -w "$PWD/$OUT/edge_phone")" --screenshot="$(cygpath -w "$PWD/$OUT/dashboard_phone.png")" "$LINK#still" > /dev/null 2>&1
	echo "Pictures: $OUT/dashboard.png, $OUT/dashboard_phone.png" >> "$OUT/results.txt"
fi
kill "$DD" 2>/dev/null
sleep 3
grep -i "runtime error" "$OUT/dd.log" | sort | uniq -c | sort -rn | head -5 >> "$OUT/results.txt"
rm -f dashcheck.mdme dashcheck.mdme.dmb dashcheck.mdme.rsc dashcheck.mdme.int dashcheck.mdme.dyn.rsc dashcheck.mdme.lk dashcheck.mdme.rsc.lk dashcheck.mdme.dyn.rsc.lk
cat "$OUT/results.txt"
