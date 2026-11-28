#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Ban system self-test (tools/ban_check/ban_selftest.dm): bans with no database and with one that's down, in the real engine;
# with DB_PORT set, against that database as well (bans in it, its clock, edits, unbans, it going away and coming back).
# Builds its own copy (bancheck.mdme -> bancheck.mdme.dmb), so hippiestation.dmb is left alone for whatever else is running.
# Usage: tools/ban_check/run_ban_check.sh
#        DB_PORT=3307 DB_NAME=hippie_bancheck DB_USER=root DB_PASS=... tools/ban_check/run_ban_check.sh   (a throwaway database: it writes test bans,
#          and counts rows, so make it afresh for each run: DB_NAME=hippie_bancheck tools/db_setup/db_setup.sh drop create)
#        BOUNCE=1 DB_HOME=... DB_PORT=... (and the rest): also stops and starts that MariaDB under the running server, through
#          tools/db_setup, when the test asks (tools/ban_check/ban_bounce_selftest.dm: driver errors, pools, read timeouts,
#          connections killed under reads and writes, restarts, a crash, an outage, changes made while bans go in). DB_HOME is
#          that MariaDB's tools/db_setup home. It is stopped five times and killed hard once (InnoDB recovers), so nothing else
#          may be using it; it is left running afterwards.
# Results: data/ban_check/results.txt, and the server's logs in data/logs/ban_check_logs
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45390}"
# Boots the small test map (_maps/testbench.json: Runtime Station, no Lavaland or ruins): nothing here uses the station,
# and loading the Hippie map costs ~13 s more a boot. MAP=hippiestation (any _maps/*.json name) to boot another.
MAP="${MAP:-testbench}"
DB_PORT="${DB_PORT:-}"
BOUNCE="${BOUNCE:-}"
if [ -n "$BOUNCE" ]; then
	if [ -z "$DB_PORT" ] || [ -z "${DB_HOME:-}" ]; then echo "BOUNCE=1 needs DB_PORT and DB_HOME (the tools/db_setup MariaDB to stop and start)"; exit 1; fi
	export DB_HOME DB_PORT
	tools/db_setup/db_setup.sh status > /dev/null 2>&1 || { echo "BOUNCE=1: no MariaDB up on port $DB_PORT in $DB_HOME"; exit 1; }
fi

cp hippiestation.dme bancheck.mdme
printf '#include "tools\\ban_check\\ban_selftest.dm"\r\n' >> bancheck.mdme
printf '#include "tools\\ban_check\\ban_window_selftest.dm"\r\n' >> bancheck.mdme
printf '#include "tools\\ban_check\\ban_bounce_selftest.dm"\r\n' >> bancheck.mdme
echo "Compiling..."
"$BYOND_BIN/dm.exe" bancheck.mdme | grep -E "error|warning|dmb -" || true
if [ ! -f bancheck.mdme.dmb ]; then echo "Compile failed"; rm -f bancheck.mdme; exit 1; fi

rm -rf data/ban_check data/logs/ban_check_logs data/ban_check_config
params="ban-selftest=1&log-directory=ban_check_logs"
if [ -n "$DB_PORT" ]; then
	# SQL on from boot, in a copy of the config; the boot's copy of the bans goes to data/bans.json, so that's put back after
	mkdir -p data/ban_check_config
	cp config/*.txt config/*.json data/ban_check_config/
	sed -i -E 's/^(SQL_ENABLED|ADDRESS|PORT|FEEDBACK_DATABASE|FEEDBACK_LOGIN|FEEDBACK_PASSWORD)\b/#&/' data/ban_check_config/dbconfig.txt
	printf '\nSQL_ENABLED\nADDRESS 127.0.0.1\nPORT %s\nFEEDBACK_DATABASE %s\nFEEDBACK_LOGIN %s\nFEEDBACK_PASSWORD %s\n' "$DB_PORT" "${DB_NAME:-hippie_bancheck}" "${DB_USER:-root}" "${DB_PASS:-}" >> data/ban_check_config/dbconfig.txt
	params="ban-selftest=db&config=data/ban_check_config&log-directory=ban_check_logs"
	for f in data/bans.json data/bans.json.bak; do [ -f "$f" ] && cp -f "$f" "$f.before_ban_check"; done
	[ -n "$BOUNCE" ] && params="$params&ban-bounce=1"
fi
began=$(date +%s)
"$BYOND_BIN/dd.exe" bancheck.mdme.dmb "$PORT" -trusted -invisible -params "$params&bot-map=$MAP" > /dev/null 2>&1 &
dd=$!
watcher=
if [ -n "$BOUNCE" ]; then
	# the test asks with data/ban_check/bounce/N_stop.req or N_start.req, and waits for N_....done ("ok" or "failed")
	(
		while kill -0 $dd 2>/dev/null; do
			for req in data/ban_check/bounce/*.req; do
				[ -f "$req" ] || continue
				done_file="${req%.req}.done"
				[ -f "$done_file" ] && continue
				action="$(tr -dc 'a-z' < "$req")"
				case "$action" in
					stop|start)
						if tools/db_setup/db_setup.sh "$action" > data/ban_check/bounce/last_db_setup.txt 2>&1; then echo ok > "$done_file.part"; else echo failed > "$done_file.part"; fi ;;
					crash) # killed hard, as a crash would: its connections are reset, not closed
						if taskkill //F //PID "$(cat "$DB_HOME"/data/*.pid 2>/dev/null)" > data/ban_check/bounce/last_db_setup.txt 2>&1; then
							for i in $(seq 1 20); do tools/db_setup/db_setup.sh status > /dev/null 2>&1 || break; sleep 0.5; done
							echo ok > "$done_file.part"
						else echo failed > "$done_file.part"; fi ;;
					*) echo "failed: unknown '$action'" > "$done_file.part" ;;
				esac
				echo "$(date +%T) $action: $(cat "$done_file.part")" >> data/ban_check/bounce/log.txt
				mv -f "$done_file.part" "$done_file"
			done
			sleep 0.3
		done
	) &
	watcher=$!
fi
while kill -0 $dd 2>/dev/null; do
	sleep 2
	[ -f data/ban_check/results.txt ] && break
	if [ $(($(date +%s) - began)) -gt 600 ]; then echo "still going after 600 s - stopped"; break; fi
done
sleep 1
kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
if [ -n "$watcher" ]; then
	kill $watcher 2>/dev/null
	# left running, as it was found, even if the test stopped partway
	tools/db_setup/db_setup.sh status > /dev/null 2>&1 || tools/db_setup/db_setup.sh start > /dev/null
fi
rm -f bancheck.mdme bancheck.mdme.dmb bancheck.mdme.rsc bancheck.mdme.int bancheck.mdme.lk bancheck.mdme.dyn.rsc bancheck.mdme.rsc.lk bancheck.mdme.dyn.rsc.lk
if [ -n "$DB_PORT" ]; then
	for f in data/bans.json data/bans.json.bak; do
		if [ -f "$f.before_ban_check" ]; then mv -f "$f.before_ban_check" "$f"; else rm -f "$f"; fi
	done
	rm -rf data/ban_check_config
fi
echo "took $(($(date +%s) - began)) s"
cat data/ban_check/results.txt 2>/dev/null || echo "no results: see data/logs/ban_check_logs"
runtimes=$(grep -c 'runtime error' data/logs/ban_check_logs/runtime.log 2>/dev/null)
echo "runtimes: ${runtimes:-0}"
grep -h -A2 'runtime error' data/logs/ban_check_logs/runtime.log 2>/dev/null | head -30
if [ -n "$BOUNCE" ]; then
	sql=data/logs/ban_check_logs/sql.log
	echo "sql.log: $(grep -c 'Lost the database connection' $sql 2>/dev/null) lost connections, $(grep -c 'Connection reestablished' $sql 2>/dev/null) reestablished, $(grep -c 'Connect() failed' $sql 2>/dev/null) failed connects"
	cat data/ban_check/bounce/log.txt 2>/dev/null
fi
