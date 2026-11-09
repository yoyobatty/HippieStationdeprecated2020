#!/bin/bash
# Update Server (the in-game +SERVER verb, hippiestation/code/modules/tgs/tgs_update.dm), Linux side.
# TGS runs this from the instance's EventScripts folder when the game asks (TgsTriggerEvent): $1 is the running game's
# folder, $2 the ckey of the admin who asked. It logs in to TGS, pulls the tracked branch from GitHub into the instance's
# repository (test merges stay; a merge conflict stops it), starts a deployment, and writes how it went to
# <game folder>/data/tgs_update.json for the game. Runs from this folder, not the game's code, so a test merge can't change it.
#
# Needs hippie_update.json beside it (copy hippie_update.example.json): the TGS address and a TGS login that can update
# this instance's repository and deploy. Keep that login to just those rights. Needs curl and python3.
#
# TGS runs an instance's event scripts one at a time, and the pull raises events of its own (RepoFetch, RepoCheckout) that
# wait their turn: so this only marks the update as running, starts itself again in the background (--worker) to do it,
# and returns at once. Waiting here instead hangs the pull until this script gives up.
set -u
WORKER=0
if [ "${1:-}" = "--worker" ]; then
	WORKER=1
	shift
fi
GAME_DIR="${1:-}"
CKEY="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# TGS_UPDATE_* reach the JSON helpers through the environment, so nothing is pasted into python code
export TGS_UPDATE_CKEY="$CKEY"

# save_state <running true|false> <ok true|false> <message>: what the game reads from data/tgs_update.json
save_state() {
	if [ -n "$GAME_DIR" ] && [ -d "$GAME_DIR" ]; then
		mkdir -p "$GAME_DIR/data"
		TGS_UPDATE_RUNNING="$1" TGS_UPDATE_OK="$2" TGS_UPDATE_MESSAGE="$3" python3 -c '
import json, os, datetime
print(json.dumps({"running": os.environ["TGS_UPDATE_RUNNING"] == "true", "ok": os.environ["TGS_UPDATE_OK"] == "true",
	"message": os.environ["TGS_UPDATE_MESSAGE"], "ckey": os.environ["TGS_UPDATE_CKEY"],
	"at": datetime.datetime.now().isoformat(timespec="seconds")}))
' > "$GAME_DIR/data/tgs_update.json"
	fi
}

result() {
	local ok="$1" message="$2"
	if [ "$ok" = true ]; then echo "OK: $message"; else echo "FAILED: $message"; fi
	save_state false "$ok" "$message"
	[ "$ok" = true ] && exit 0
	exit 1
}

if [ "$WORKER" = 0 ]; then
	save_state true false "pulling from GitHub"
	setsid nohup bash "$0" --worker "$GAME_DIR" "$CKEY" > /dev/null 2>&1 < /dev/null &
	echo "Update started in the background; it reports to $GAME_DIR/data/tgs_update.json"
	exit 0
fi

# json <expression on d (the document) and env (the environment)> < document: prints one value ("" for null or an error)
json() {
	TGS_UPDATE_EXPR="$1" python3 -c '
import json, os, sys
try:
	d = json.load(sys.stdin)
	v = eval(os.environ["TGS_UPDATE_EXPR"], {"__builtins__": {"len": len, "str": str}}, {"d": d, "env": os.environ})
except Exception:
	v = None
print("" if v is None else v)
'
}

CONFIG="$SCRIPT_DIR/hippie_update.json"
[ -f "$CONFIG" ] || result false "hippie_update.json is missing from TGS's EventScripts folder"
BASE="$(json 'd["url"].rstrip("/")' < "$CONFIG")"
USERNAME="$(json 'd["username"]' < "$CONFIG")"
PASSWORD="$(json 'd["password"]' < "$CONFIG")"
INSTANCE="$(json 'd.get("instance")' < "$CONFIG")"
[ -n "$BASE" ] || result false "hippie_update.json isn't valid JSON or has no url"

HEADERS=(-H "Api: Tgstation.Server.Api/10.0.0" -H "User-Agent: HippieUpdate/1.0" -H "Accept: application/json" -H "Content-Type: application/json")
BODY_FILE="$(mktemp)"
ERROR_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE" "$ERROR_FILE"' EXIT

# tgs <method> <path> [body]: the response body to stdout, or why not to $ERROR_FILE and a failed status. Callers are
# in $( ), where exiting only leaves the subshell, so each one checks: X="$(tgs ...)" || result false "$(cat "$ERROR_FILE")"
tgs() {
	local code
	if ! code=$(curl -sS -o "$BODY_FILE" -w '%{http_code}' -X "$1" "${HEADERS[@]}" ${AUTH:+-H "Authorization: $AUTH"} \
		${INSTANCE:+-H "Instance: $INSTANCE"} ${3:+--data "$3"} "$BASE$2" 2> "$ERROR_FILE"); then
		echo "couldn't reach TGS at $BASE: $(head -c 200 "$ERROR_FILE")" > "$ERROR_FILE"
		return 1
	fi
	if [ "${code:0:1}" != 2 ]; then
		echo "TGS refused $1 $2 (HTTP $code): $(head -c 300 "$BODY_FILE")" > "$ERROR_FILE"
		return 1
	fi
	cat "$BODY_FILE"
}

AUTH="Basic $(printf '%s:%s' "$USERNAME" "$PASSWORD" | base64 | tr -d '\n')"
SAVED_INSTANCE="$INSTANCE"
INSTANCE=""
LOGIN="$(tgs POST /api)" || result false "couldn't log in: $(cat "$ERROR_FILE")"
TOKEN="$(echo "$LOGIN" | json 'd["bearer"]')"
[ -n "$TOKEN" ] || result false "couldn't log in to TGS at $BASE"
AUTH="Bearer $TOKEN"

INSTANCE="$SAVED_INSTANCE"
if [ -z "$INSTANCE" ]; then
	LIST="$(tgs GET '/api/Instance/List?pageSize=100')" || result false "$(cat "$ERROR_FILE")"
	INSTANCE="$(echo "$LIST" | TGS_UPDATE_ROOT="${TGS_INSTANCE_ROOT%/}" json '[i["id"] for i in d["content"] if str(i.get("path") or "").rstrip("/") == env.get("TGS_UPDATE_ROOT", "")][0]')"
	[ -n "$INSTANCE" ] || result false "couldn't tell which TGS instance this is: set \"instance\" in hippie_update.json"
fi

BEFORE="$(tgs GET /api/Repository)" || result false "$(cat "$ERROR_FILE")"
BUSY="$(echo "$BEFORE" | json '(d.get("activeJob") or {}).get("description")')"
[ -z "$BUSY" ] || result false "the repository is busy: $BUSY"
OLD_ORIGIN="$(echo "$BEFORE" | json 'd["revisionInformation"]["originCommitSha"]')"

UPDATE="$(tgs POST /api/Repository '{"updateFromOrigin":true}')" || result false "$(cat "$ERROR_FILE")"
JOB_ID="$(echo "$UPDATE" | json '(d.get("activeJob") or {}).get("id")')"
if [ -n "$JOB_ID" ]; then
	START=$(date +%s)
	while :; do
		JOB="$(tgs GET "/api/Job/$JOB_ID")" || result false "$(cat "$ERROR_FILE")"
		[ -n "$(echo "$JOB" | json 'd.get("stoppedAt")')" ] && break
		[ $(( $(date +%s) - START )) -lt 900 ] || result false "TGS job $JOB_ID is still running after 900 s"
		sleep 2
	done
	[ "$(echo "$JOB" | json 'd.get("cancelled")')" = True ] && result false "the pull was cancelled in TGS"
	ERROR_CODE="$(echo "$JOB" | json 'd.get("errorCode")')"
	ERROR_TEXT="$(echo "$JOB" | json 'str(d.get("exceptionDetails") or "").splitlines()[0] if d.get("exceptionDetails") else None')"
	if [ -n "$ERROR_CODE" ] || [ -n "$ERROR_TEXT" ]; then
		result false "pulling failed (TGS error $ERROR_CODE): $ERROR_TEXT"
	fi
fi

AFTER="$(tgs GET /api/Repository)" || result false "$(cat "$ERROR_FILE")"
NEW_ORIGIN="$(echo "$AFTER" | json 'd["revisionInformation"]["originCommitSha"]')"
TEST_MERGES="$(echo "$AFTER" | json 'len(d["revisionInformation"].get("activeTestMerges") or [])')"
if [ "$OLD_ORIGIN" = "$NEW_ORIGIN" ]; then
	PULLED="already up to date at ${NEW_ORIGIN:0:8}"
else
	PULLED="${OLD_ORIGIN:0:8} -> ${NEW_ORIGIN:0:8}"
fi
[ "${TEST_MERGES:-0}" -gt 0 ] && PULLED="$PULLED, $TEST_MERGES test merge(s) kept"

DEPLOY="$(tgs PUT /api/DreamMaker)" || result false "pulled, but the deploy didn't start: $(cat "$ERROR_FILE")"
DEPLOY_ID="$(echo "$DEPLOY" | json 'd.get("id")')"
result true "$PULLED; deploying (TGS job $DEPLOY_ID). It goes live next round."
