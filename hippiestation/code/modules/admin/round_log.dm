// The round log: every line the game logs this round, kept in memory with who did it and where, so admins can search it in
// the game (Search Logs, log_search.dm) instead of downloading files. Lines are caught where they're written: the log_*()
// procs, atom/log_message() (which knows who acted, so the line gets their ckey, name and place), log_combat() (and who
// they did it to), investigate_log() and log_bomber(). The newest ROUND_LOG_MAX lines are kept; the files keep everything.
// The user asked for investigating made super easy, 2026-11-07.

// An entry's fields (kept defined: log_search.dm reads them too)
#define RL_ID 1
#define RL_TIME 2
#define RL_CAT 3
#define RL_TEXT 4
#define RL_CKEY 5
#define RL_NAME 6
#define RL_REF 7
#define RL_X 8
#define RL_Y 9
#define RL_Z 10
#define RL_AREA 11
#define RL_TCKEY 12
#define RL_TNAME 13
#define RL_TREF 14
#define RL_LEN 14

#define ROUND_LOG_MAX 80000
#define ROUND_LOG_TRIM 10000

GLOBAL_LIST_EMPTY(round_log)
/// Lines logged this round (an entry's id is its number)
GLOBAL_VAR_INIT(round_log_total, 0)
/// Inside atom/log_message(): its line is already caught, the log_*() it calls mustn't catch it again
GLOBAL_VAR_INIT(round_log_in_message, FALSE)
/// Set by log_combat() and log_bomber() around their log_message() call: who it was done to, and a category of their own
GLOBAL_DATUM(round_log_target, /atom)
GLOBAL_VAR(round_log_category)

/// The log types (LOG_*) as the search window names them
/proc/round_log_category_of(message_type)
	switch(message_type)
		if(LOG_ATTACK)
			return "Attack"
		if(LOG_SAY)
			return "Say"
		if(LOG_WHISPER)
			return "Whisper"
		if(LOG_EMOTE)
			return "Emote"
		if(LOG_DSAY)
			return "Dead chat"
		if(LOG_PDA)
			return "PDA"
		if(LOG_CHAT)
			return "Chat"
		if(LOG_COMMENT)
			return "Comment"
		if(LOG_TELECOMMS)
			return "Radio"
		if(LOG_OOC)
			return "OOC"
		if(LOG_ADMIN)
			return "Admin"
		if(LOG_ADMIN_PRIVATE)
			return "Admin (private)"
		if(LOG_ASAY)
			return "Asay"
		if(LOG_MECHA)
			return "Mecha"
	return "Game"

/// A line from one of the log_*() procs, unless log_message() already has it
/proc/round_log_plain(category, text)
	if(GLOB.round_log_in_message)
		return
	round_log_add(category, text)

/// Keeps a line. actor and target are what did it and what it was done to, when the caller knows.
/proc/round_log_add(category, text, atom/actor, atom/target)
	var/list/entry = new /list(RL_LEN)
	entry[RL_ID] = ++GLOB.round_log_total
	entry[RL_TIME] = world.time
	entry[RL_CAT] = GLOB.round_log_category || category
	entry[RL_TEXT] = "[text]"
	if(istype(actor))
		entry[RL_NAME] = actor.name
		entry[RL_REF] = WEAKREF(actor)
		if(ismob(actor))
			var/mob/M = actor
			entry[RL_CKEY] = M.ckey
		var/turf/T = get_turf(actor)
		if(T)
			entry[RL_X] = T.x
			entry[RL_Y] = T.y
			entry[RL_Z] = T.z
			var/area/A = T.loc
			entry[RL_AREA] = A?.name
	if(istype(target))
		entry[RL_TNAME] = target.name
		entry[RL_TREF] = WEAKREF(target)
		if(ismob(target))
			var/mob/TM = target
			entry[RL_TCKEY] = TM.ckey
	if(entry[RL_CAT] == "Attack" && findtext(entry[RL_TEXT], " has died "))
		entry[RL_CAT] = "Death"
	var/kind = findtext(entry[RL_CAT], "Investigate") == 1 ? "Investigate" : entry[RL_CAT]
	GLOB.round_log_counts[kind]++
	GLOB.round_log += list(entry)
	if(GLOB.round_log.len > ROUND_LOG_MAX)
		GLOB.round_log.Cut(1, ROUND_LOG_TRIM + 1)

/// Who last hurt this mob, from the round log, for its death line: "last hurt by X, 12 s before"
/proc/round_log_last_hurt(mob/living/victim)
	var/list/log = GLOB.round_log
	var/since = world.time - 3 MINUTES
	for(var/i in log.len to max(1, log.len - 3000) step -1)
		var/list/entry = log[i]
		if(entry[RL_TIME] < since)
			break
		if(entry[RL_CAT] != "Attack" || entry[RL_REF] == victim.weak_reference)
			continue
		var/datum/weakref/target = entry[RL_TREF]
		if(target && target.resolve() == victim)
			return "last hurt by [entry[RL_CKEY] ? "[entry[RL_CKEY]]/" : ""]([entry[RL_NAME]]), [round((world.time - entry[RL_TIME]) / 10)] s before"
	return "nobody hurt them in the last 3 minutes"

#undef ROUND_LOG_MAX
#undef ROUND_LOG_TRIM
