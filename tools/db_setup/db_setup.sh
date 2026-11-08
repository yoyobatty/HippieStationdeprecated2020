#!/bin/bash
# One-step MariaDB for HippieStation: download, set up, create the tables, write the server's config.
#
#   tools/db_setup/db_setup.sh                 everything: install, start, create, config (a live server)
#   tools/db_setup/db_setup.sh install         download MariaDB (checksum checked) and set up its data folder
#   tools/db_setup/db_setup.sh start | stop | status
#   tools/db_setup/db_setup.sh create          the database, its user and every table (tg + hippie), schema version
#   tools/db_setup/db_setup.sh config          write config/dbconfig_local.txt (gitignored, read last by dbconfig.txt)
#   tools/db_setup/db_setup.sh service         register MariaDB as a Windows service that starts with the machine (run as admin)
#   tools/db_setup/db_setup.sh shell           a mariadb prompt on the database
#   tools/db_setup/db_setup.sh drop            delete the database and its user (throwaway test databases)
#   tools/db_setup/db_setup.sh uninstall       stop and delete DB_HOME (asks first)
#
# Settings (environment):
#   DB_HOME   where MariaDB and its data live         default %LOCALAPPDATA%\HippieDB
#   DB_PORT   3306        DB_NAME   feedback        DB_USER   hippie        PREFIX   SS13_ (FEEDBACK_TABLEPREFIX)
# Passwords are made up on first use and kept in DB_HOME/credentials.txt (root=, login_<user>=), never in the repo.
# One MariaDB can hold several databases (other sessions' test ones too): drop removes only DB_NAME, and a user keeps one password.
#
# Test harnesses use their own DB_HOME/DB_PORT/DB_NAME and skip "config", so config/ stays untouched:
#   DB_HOME=... DB_PORT=3307 DB_NAME=hippie_check tools/db_setup/db_setup.sh install start create
unset __COMPAT_LAYER
set -e

MARIADB_VERSION=11.4.13
MARIADB_ZIP=mariadb-$MARIADB_VERSION-winx64.zip
MARIADB_URL=https://downloads.mariadb.org/rest-api/mariadb/$MARIADB_VERSION/$MARIADB_ZIP
MARIADB_SHA256=d62986d433eeebfde218560b276103831604a61e929e87f1a17f5aebd80257e2

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DB_HOME="${DB_HOME:-$(cygpath -u "$LOCALAPPDATA")/HippieDB}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-feedback}"
DB_USER="${DB_USER:-hippie}"
PREFIX="${PREFIX-SS13_}"

BIN="$DB_HOME/mariadb-$MARIADB_VERSION-winx64/bin"
DATA="$DB_HOME/data"
CRED="$DB_HOME/credentials.txt"

die() { echo "db_setup: $*" >&2; exit 1; }
# MariaDB wants Windows paths; the 8.3 form has no spaces and stays under MAX_PATH.
winpath() { local p; p="$(cygpath -d "$1" 2>/dev/null)" || p="$(cygpath -w "$1")"; echo "$p"; }

cred_get() { [ -f "$CRED" ] || return 0; sed -n "s/^$1=//p" "$CRED" | tail -1; }
cred_set() {
	mkdir -p "$DB_HOME"
	touch "$CRED"
	sed -i "/^$1=/d" "$CRED"
	echo "$1=$2" >> "$CRED"
}
new_password() { head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24; }

root_pass() {
	local p; p="$(cred_get root)"
	[ -n "$p" ] || die "no root password in $CRED (run install first)"
	echo "$p"
}
# one password per user, whichever databases it's on: several test databases (other sessions' too) share one MariaDB
user_pass() {
	local p; p="$(cred_get "login_$DB_USER")"
	if [ -z "$p" ]; then p="$(new_password)"; cred_set "login_$DB_USER" "$p"; fi
	echo "$p"
}

sql_root() { "$BIN/mariadb.exe" -h127.0.0.1 -P"$DB_PORT" -uroot -p"$(root_pass)" --default-character-set=utf8mb4 "$@"; }

is_up() { "$BIN/mariadb-admin.exe" -h127.0.0.1 -P"$DB_PORT" -uroot -p"$(root_pass)" ping >/dev/null 2>&1; }

do_install() {
	if [ -x "$BIN/mariadbd.exe" ]; then
		echo "MariaDB $MARIADB_VERSION already in $DB_HOME"
	else
		mkdir -p "$DB_HOME"
		local zip="$DB_HOME/$MARIADB_ZIP"
		if [ ! -f "$zip" ]; then
			echo "Downloading MariaDB $MARIADB_VERSION..."
			curl -fL --retry 3 -o "$zip.part" "$MARIADB_URL" || die "download failed"
			mv "$zip.part" "$zip"
		fi
		echo "$MARIADB_SHA256  $zip" | sha256sum -c --status || { rm -f "$zip"; die "checksum mismatch on $MARIADB_ZIP (deleted, run again)"; }
		echo "Unpacking..."
		unzip -q -o "$zip" -d "$DB_HOME"
		rm -f "$zip"
	fi
	if [ -f "$DATA/my.ini" ]; then
		echo "Data folder already set up: $DATA"
		return
	fi
	local rp; rp="$(cred_get root)"
	if [ -z "$rp" ]; then rp="$(new_password)"; cred_set root "$rp"; fi
	echo "Setting up the data folder (port $DB_PORT)..."
	"$BIN/mariadb-install-db.exe" --datadir="$(winpath "$DB_HOME")\\data" --port="$DB_PORT" --password="$rp" >/dev/null
	# utf8mb4 and strict mode whatever the MariaDB defaults become; the game's names and emoji need utf8mb4.
	# (my.ini ends in its [client] section, so these need their own [mysqld] header)
	cat >> "$DATA/my.ini" <<'EOF'
[mysqld]
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
sql_mode=STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION
bind-address=127.0.0.1
EOF
	echo "Installed. Root password is in $CRED"
}

do_start() {
	[ -x "$BIN/mariadbd.exe" ] || die "not installed (run install first)"
	if is_up; then echo "MariaDB already running on port $DB_PORT"; return; fi
	echo "Starting MariaDB on port $DB_PORT..."
	nohup "$BIN/mariadbd.exe" --defaults-file="$(winpath "$DATA/my.ini")" --console > "$DB_HOME/mariadbd.log" 2>&1 &
	local i
	for i in $(seq 1 60); do
		if is_up; then echo "Up (log: $DB_HOME/mariadbd.log)"; return; fi
		sleep 0.5
	done
	tail -20 "$DB_HOME/mariadbd.log" >&2
	die "MariaDB didn't come up in 30 s"
}

do_stop() {
	if ! is_up; then echo "MariaDB isn't running on port $DB_PORT"; return; fi
	"$BIN/mariadb-admin.exe" -h127.0.0.1 -P"$DB_PORT" -uroot -p"$(root_pass)" shutdown
	echo "Stopped"
}

do_status() {
	if is_up; then
		echo "MariaDB $MARIADB_VERSION up on 127.0.0.1:$DB_PORT ($DB_HOME)"
		sql_root -N -e "SELECT CONCAT('database ', SCHEMA_NAME) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME NOT IN ('mysql','information_schema','performance_schema','sys')"
		if sql_root -N -e "USE \`$DB_NAME\`" 2>/dev/null; then
			sql_root -N "$DB_NAME" -e "SELECT CONCAT('schema ', major, '.', minor) FROM \`${PREFIX}schema_revision\` ORDER BY date DESC LIMIT 1" 2>/dev/null || true
		fi
	else
		echo "MariaDB not running on port $DB_PORT"
		return 1
	fi
}

# the schema version the game expects, read from the code so it can't drift
schema_version() {
	local major minor
	major="$(sed -n 's/^#define DB_MAJOR_VERSION \([0-9]*\).*/\1/p' "$REPO/code/__DEFINES/subsystems.dm")"
	minor="$(sed -n 's/^#define DB_MINOR_VERSION \([0-9]*\).*/\1/p' "$REPO/code/__DEFINES/subsystems.dm")"
	echo "$major $minor"
}

do_create() {
	is_up || die "MariaDB isn't running on port $DB_PORT (run start first)"
	local up; up="$(user_pass)"
	if sql_root -N -e "SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='${PREFIX}schema_revision'" | grep -q 1; then
		echo "Database $DB_NAME already has the tables"
	else
		echo "Creating database $DB_NAME (prefix '$PREFIX')..."
		sql_root -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
		local schema="$REPO/SQL/tgstation_schema_prefixed.sql"
		if [ "$PREFIX" = "SS13_" ]; then
			sql_root "$DB_NAME" < "$schema"
		else
			sed "s/\`SS13_/\`$PREFIX/g" "$schema" | sql_root "$DB_NAME"
		fi
		local f
		for f in "$REPO"/hippiestation/SQL/*.sql "$REPO"/hippiestation/SQL/*/*.sql; do
			[ -f "$f" ] || continue
			sed -E "s/(CREATE TABLE( IF NOT EXISTS)?|DROP TABLE IF EXISTS|ALTER TABLE|INSERT INTO) \`/\1 \`$PREFIX/g" "$f" | sql_root "$DB_NAME"
		done
		set -- $(schema_version)
		sql_root "$DB_NAME" -e "INSERT INTO \`${PREFIX}schema_revision\` (major, minor) VALUES ($1, $2)"
	fi
	# ALTER too: a user left from before (another database, an older run) gets the password on file
	sql_root -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$up';
CREATE USER IF NOT EXISTS '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$up';
ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$up';
ALTER USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$up';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE TEMPORARY TABLES, EXECUTE ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE TEMPORARY TABLES, EXECUTE ON \`$DB_NAME\`.* TO '$DB_USER'@'127.0.0.1';
FLUSH PRIVILEGES;"
	cred_set "user_$DB_NAME" "$up" #the older per-database key, for anything still reading it
	local n; n="$(sql_root -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$DB_NAME'")"
	echo "Database $DB_NAME: $n tables, user $DB_USER (password in $CRED)"
}

do_config() {
	local out="$REPO/config/dbconfig_local.txt"
	local up; up="$(user_pass)"
	cat > "$out" <<EOF
## Written by tools/db_setup/db_setup.sh. Not in git: it holds the password.
## dbconfig.txt includes this file last, so these lines win. Delete it to turn the database off.
SQL_ENABLED
ADDRESS 127.0.0.1
PORT $DB_PORT
FEEDBACK_DATABASE $DB_NAME
FEEDBACK_TABLEPREFIX $PREFIX
FEEDBACK_LOGIN $DB_USER
FEEDBACK_PASSWORD $up
EOF
	grep -q '^\$include dbconfig_local.txt' "$REPO/config/dbconfig.txt" || die "config/dbconfig.txt is missing its '\$include dbconfig_local.txt' line"
	echo "Wrote config/dbconfig_local.txt (database on at next boot)"
}

do_service() {
	[ -x "$BIN/mariadbd.exe" ] || die "not installed (run install first)"
	is_up && do_stop
	"$BIN/mariadbd.exe" --install HippieDB --defaults-file="$(winpath "$DATA/my.ini")" || die "couldn't register the service (run this from an administrator shell)"
	sc.exe start HippieDB >/dev/null
	echo "Registered service HippieDB (starts with Windows)"
}

do_shell() { is_up || die "MariaDB isn't running"; "$BIN/mariadb.exe" -h127.0.0.1 -P"$DB_PORT" -u"$DB_USER" -p"$(user_pass)" "$DB_NAME"; }

# the database only: its user may be on others
do_drop() {
	is_up || die "MariaDB isn't running"
	sql_root -e "DROP DATABASE IF EXISTS \`$DB_NAME\`; REVOKE ALL PRIVILEGES ON \`$DB_NAME\`.* FROM '$DB_USER'@'localhost', '$DB_USER'@'127.0.0.1';" 2>/dev/null || true
	echo "Dropped database $DB_NAME"
}

do_uninstall() {
	[ -d "$DB_HOME" ] || { echo "Nothing at $DB_HOME"; return; }
	if [ "$YES" != 1 ]; then
		read -r -p "Delete $DB_HOME and every database in it? [y/N] " a
		[ "$a" = y ] || [ "$a" = Y ] || die "kept"
	fi
	is_up && do_stop
	sleep 1
	rm -rf "$DB_HOME"
	echo "Deleted $DB_HOME"
}

[ $# -gt 0 ] || set -- install start create config
for cmd in "$@"; do
	case "$cmd" in
		install) do_install ;;
		start) do_start ;;
		stop) do_stop ;;
		status) do_status ;;
		create) do_create ;;
		config) do_config ;;
		service) do_service ;;
		shell) do_shell ;;
		drop) do_drop ;;
		uninstall) do_uninstall ;;
		*) die "unknown step '$cmd' (install start stop status create config service shell drop uninstall)" ;;
	esac
done
