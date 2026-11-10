// hippie -- What's kept of a round after it ends, for its page in Round Stats (round_stats.dm). The blackbox already keeps the
// antagonists with their objectives and the round-end numbers (the feedback table); this adds the round's runtimes. Each is
// counted by file and line as it happens (world/Error(), error_handler.dm) and the lot goes into the runtime table at shutdown,
// one row a site (hippiestation/SQL/runtime.sql). tools/runtime_ledger/ledger.py reads the same out of the kept logs.

/// The most sites kept for a round: a runaway loop shouldn't make a thousand rows
#define RUNTIME_LEDGER_SITES 500

/// "file:line" = list(file, line, message, count, world.time first seen)
GLOBAL_LIST_EMPTY(runtime_ledger)

/// Runs inside the error handler: plain list work only, nothing that could runtime again.
/proc/runtime_ledger_note(exception/E)
	var/list/ledger = GLOB?.runtime_ledger
	if(!islist(ledger) || !istype(E))
		return
	var/uid = "[E.file]:[E.line]"
	var/list/entry = ledger[uid]
	if(entry)
		entry[4]++
	else if(length(ledger) < RUNTIME_LEDGER_SITES)
		ledger[uid] = list("[E.file]", E.line, copytext("[E.name]", 1, 512), 1, world.time)

/// Into the database, as the blackbox's feedback is: blocking, as dbcore's Shutdown() closes the connection right after.
/datum/controller/subsystem/blackbox/Shutdown()
	. = ..()
	var/list/ledger = GLOB.runtime_ledger
	var/round_id = text2num(GLOB.round_id)
	if(!length(ledger) || !round_id || !SSdbcore.Connect())
		return
	var/list/rows = list()
	var/began = SSticker.round_start_time
	for(var/uid in ledger)
		var/list/entry = ledger[uid]
		//first_seen: seconds into the round, 0 for before it began (the lobby, the map loading)
		rows += list(list("round_id" = round_id, "file" = entry[1], "line" = entry[2], "message" = entry[3], "count" = entry[4], "first_seen" = began ? max(0, round((entry[5] - began) / 10)) : 0))
	SSdbcore.MassInsert(format_table_name("runtime"), rows, ignore_errors = TRUE, async = FALSE)

#undef RUNTIME_LEDGER_SITES
