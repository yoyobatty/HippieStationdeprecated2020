#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# The every-query check, against a throwaway MariaDB (tools/db_setup, its own DB_HOME and port, never config/):
#   1. static: every query in the code is PREPAREd (syntax, tables, columns), tools/db_check/query_check.py
#   2. live:   a real boot and round with the database on, as the game's own limited user; every query that runs is
#              recorded with how it went, and mapped back to its site (db_live_check.dm)
#   3. bans:   tools/ban_check/run_ban_check.sh against the database (BANS=0 to skip)
# Usage: tools/db_check/run_db_check.sh            (~4 min; the first run downloads MariaDB, ~20 s more)
#        STATIC=1 tools/db_check/run_db_check.sh   (just the static half, a few seconds)
#        STOP_DB=1 ...                             (stop MariaDB afterwards if this run started it; it is left running by default, as other sessions share it)
# Results: data/db_check/ (report.txt, ran.json, steps.txt), server logs in data/logs/db_check_logs
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45410}"
MAP="${MAP:-testbench}"
export DB_HOME="${DB_HOME:-$(cygpath -u "$LOCALAPPDATA")/HippieDBCheck}"
export DB_PORT="${DB_PORT:-3307}"
export DB_NAME="${DB_NAME:-hippie_check}"
SETUP=tools/db_setup/db_setup.sh
began=$(date +%s)
fail=0

#other sessions may be using this MariaDB too: it is left running unless STOP_DB=1 (and then only if this run started it)
was_up=0
$SETUP status > /dev/null 2>&1 && was_up=1
$SETUP install start > /dev/null || { echo "couldn't start the test MariaDB"; exit 1; }
$SETUP drop create > /dev/null || { echo "couldn't make the test database"; exit 1; }
MARIADB="$DB_HOME/mariadb-11.4.13-winx64/bin/mariadb.exe"
ROOT_PASS="$(sed -n 's/^root=//p' "$DB_HOME/credentials.txt")"
USER_PASS="$(sed -n 's/^login_hippie=//p' "$DB_HOME/credentials.txt")"
stop_db() { [ "${STOP_DB:-0}" = 1 ] && [ $was_up = 0 ] && $SETUP stop > /dev/null; true; }
rm -rf data/db_check data/logs/db_check_logs
mkdir -p data/db_check

echo "== static: every query PREPAREd"
python tools/db_check/query_check.py --mariadb "$MARIADB" --port "$DB_PORT" --password "$ROOT_PASS" --db "$DB_NAME" --json data/db_check/static.json | grep -v "^TEMPLATED\|^DYNAMIC" | tee data/db_check/report.txt
[ "${PIPESTATUS[0]}" = 0 ] || fail=1
if [ "${STATIC:-0}" = 1 ]; then
	stop_db
	exit $fail
fi

echo "== live: a boot and a round with the database on"
cp hippiestation.dme dbcheck.mdme
printf '#include "tools\\db_check\\db_live_check.dm"\r\n' >> dbcheck.mdme
"$BYOND_BIN/dm.exe" dbcheck.mdme | grep -E "error|warning|dmb -" || true
if [ ! -f dbcheck.mdme.dmb ]; then echo "Compile failed"; rm -f dbcheck.mdme; exit 1; fi
mkdir -p data/db_check/config
cp config/*.txt config/*.json data/db_check/config/
rm -f data/db_check/config/dbconfig_local.txt
sed -i -E 's/^(SQL_ENABLED|ADDRESS|PORT|FEEDBACK_DATABASE|FEEDBACK_LOGIN|FEEDBACK_PASSWORD|FEEDBACK_TABLEPREFIX)\b/#&/' data/db_check/config/dbconfig.txt
printf '\nSQL_ENABLED\nADDRESS 127.0.0.1\nPORT %s\nFEEDBACK_DATABASE %s\nFEEDBACK_TABLEPREFIX SS13_\nFEEDBACK_LOGIN hippie\nFEEDBACK_PASSWORD %s\n' "$DB_PORT" "$DB_NAME" "$USER_PASS" >> data/db_check/config/dbconfig.txt
sed -i -E 's/^(BOT_CREW_TARGET|LOBBY_COUNTDOWN|MAPROTATION|RESUME_AFTER_INITIALIZATIONS)\b/#&/' data/db_check/config/*.txt
printf '\nBOT_CREW_TARGET 6\nLOBBY_COUNTDOWN 10\nRESUME_AFTER_INITIALIZATIONS\n' >> data/db_check/config/config.txt
cp -f data/next_map.json data/db_check/next_map.json.bak 2>/dev/null || true
live_began=$(date +%s)
"$BYOND_BIN/dd.exe" dbcheck.mdme.dmb "$PORT" -trusted -invisible -params "db-check=1&config=data/db_check/config&log-directory=db_check_logs&bot-map=$MAP&bot-mode=extended&bot-round-limit=60" > /dev/null 2>&1 &
dd=$!
while kill -0 $dd 2>/dev/null; do
	sleep 2
	[ -f data/db_check/done.txt ] && break
	if [ $(($(date +%s) - live_began)) -gt 600 ]; then echo "still going after 600 s - stopped"; fail=1; break; fi
done
sleep 1
kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
rm -f dbcheck.mdme dbcheck.mdme.dmb dbcheck.mdme.rsc dbcheck.mdme.int dbcheck.mdme.lk dbcheck.mdme.dyn.rsc dbcheck.mdme.rsc.lk dbcheck.mdme.dyn.rsc.lk
cp -f data/db_check/next_map.json.bak data/next_map.json 2>/dev/null || true
echo "live round took $(($(date +%s) - live_began)) s"
if [ -f data/db_check/steps.txt ]; then
	cat data/db_check/steps.txt | tee -a data/db_check/report.txt
	grep -q "^FAIL" data/db_check/steps.txt && fail=1
else
	echo "no results: see data/logs/db_check_logs" | tee -a data/db_check/report.txt
	fail=1
fi
python tools/db_check/query_check.py --ran data/db_check/ran.json --json data/db_check/static.json | tee -a data/db_check/report.txt
[ "${PIPESTATUS[0]}" = 0 ] || fail=1
runtimes=$(grep -c 'runtime error' data/logs/db_check_logs/runtime.log 2>/dev/null)
echo "runtimes: ${runtimes:-0}" | tee -a data/db_check/report.txt
grep -h -A2 'runtime error' data/logs/db_check_logs/runtime.log 2>/dev/null | head -20
if [ -s data/logs/db_check_logs/sql.log ]; then
	echo "sql.log:" | tee -a data/db_check/report.txt
	head -20 data/logs/db_check_logs/sql.log | tee -a data/db_check/report.txt
fi

if [ "${BANS:-1}" = 1 ]; then
	echo "== bans against the database"
	DB_NAME=hippie_bancheck $SETUP drop create > /dev/null
	DB_PORT="$DB_PORT" DB_NAME=hippie_bancheck DB_USER=root DB_PASS="$ROOT_PASS" tools/ban_check/run_ban_check.sh > data/db_check/bans.txt 2>&1
	pass=$(grep -c "^PASS" data/db_check/bans.txt); bad=$(grep -c "^FAIL" data/db_check/bans.txt)
	echo "ban check: $pass passed, $bad failed, $(grep '^runtimes' data/db_check/bans.txt)" | tee -a data/db_check/report.txt
	grep "^FAIL" data/db_check/bans.txt | tee -a data/db_check/report.txt
	[ "$bad" = 0 ] && [ "$pass" -gt 0 ] || fail=1
	DB_NAME=hippie_bancheck $SETUP drop > /dev/null
fi

stop_db
echo "took $(($(date +%s) - began)) s: $([ $fail = 0 ] && echo PASSED || echo FAILED)" | tee -a data/db_check/report.txt
exit $fail
