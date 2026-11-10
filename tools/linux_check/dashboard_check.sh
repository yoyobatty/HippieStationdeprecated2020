#!/bin/bash
# The admins' dashboard on Linux (WSL, as root, from the repository through /mnt/c): runs a short shift from a Windows-built .dmb that has
# tools/dashboard/dashboard_check.dm in it (it makes a link with no admin there), and asks the dashboard for its page and a snapshot.
#   bash tools/linux_check/dashboard_check.sh <build, no extension, in the repo root>
set -u
BUILD="${1:?a build with tools/dashboard/dashboard_check.dm in it}"
WEB=47821
EXTRA="dashboard-port=$WEB&dashboard-check=1" bash tools/linux_check/run.sh "$BUILD" 3 testbench > /root/dashboard_run.log 2>&1 &
RUN=$!
LINK=""
for i in $(seq 1 180); do
	LINK="$(cat /root/hippie/data/dashboard_check/link.txt 2>/dev/null)"
	[ -n "$LINK" ] && break
	sleep 1
done
[ -n "$LINK" ] || { echo "No link: the dashboard didn't start"; grep -i dashboard /root/hippie/dd.log | head -5; wait $RUN; exit 1; }
BASE="http://127.0.0.1:$WEB"
echo "Bad token: $(curl -s -o /dev/null -w '%{http_code}' "$BASE/?t=nope")"
echo "Link: $(curl -s -o /dev/null -c /root/dash_cookies -w '%{http_code}' "$LINK")"
echo "Page: $(curl -s -b /root/dash_cookies -o /dev/null -w '%{http_code}, %{size_download} bytes' "$BASE/")"
curl -s -b /root/dash_cookies -o /dev/null "$BASE/snapshot"
sleep 5
echo "Snapshot: $(curl -s -b /root/dash_cookies "$BASE/snapshot" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(sorted(d.keys()), len(d.get("crew", [])), "crew,", len(d.get("map_live", {}).get("mobs", [])), "on the map")')"
echo "Stream for 4 s: $(curl -s -N -b /root/dash_cookies --max-time 4 "$BASE/events" | grep -c '^event:') events"
wait $RUN
grep -E "Dashboard|runtime error" /root/hippie/dd.log | sort | uniq -c | head -5
