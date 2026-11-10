// WRITE_LOG (code/__HELPERS/_logging.dm) through hippie_log.dll (tools/log_writer): the line is timestamped and queued, and
// a thread of the library's own writes it. rust_g wrote each line on the game's thread, so a stalling drive stalled the
// game: in the user's round on 2026-11-10, with the drive 99% full, single log lines held the server 3 to 7 s at a time
// (the watchdog named /datum/player_log/proc/write and /proc/log_emote). The files come out the same, line for line.
//
// Without the library (or booted with log-writer=rustg) the game writes through rust_g as before.

/// Whether hippie_log.dll writes the logs: null until the first log line asks
GLOBAL_REAL_VAR(hippie_log_native)

/proc/hippie_log_write(log, text)
	if(!log)
		return // a log whose file isn't set up yet (a couple at boot): rust_g failed these too
	if(isnull(hippie_log_native))
		hippie_log_native = hippie_log_try()
	if(hippie_log_native)
		call_ext(HIPPIE_LOG, "log_write")("[log]", "[text]", "true")
	else
		rustg_log_write(log, text, "true")

/proc/hippie_log_try()
	if(world.params["log-writer"] == "rustg" || !fexists(HIPPIE_LOG))
		return FALSE
	try
		return call_ext(HIPPIE_LOG, "log_version")() == "hippie_log 1"
	catch
		return FALSE

/// Waits (up to 10 s) for what's queued to be written, and closes the files. Before shutting down or rebooting.
/proc/hippie_log_close_all()
	if(!hippie_log_native)
		return
	var/result = call_ext(HIPPIE_LOG, "log_close_all")()
	if(result)
		SEND_TEXT(world.log, result)

/// Waits up to ms for what's queued to be on the drive. Null when it is, else what's wrong.
/proc/hippie_log_flush(ms = 10000)
	if(!hippie_log_native)
		return null
	var/result = call_ext(HIPPIE_LOG, "log_flush")("[ms]")
	return result || null

/// list("queued", "written", "dropped", "failed", "error"), or null when rust_g writes the logs
/proc/hippie_log_status()
	if(!hippie_log_native)
		return null
	var/list/parts = splittext(call_ext(HIPPIE_LOG, "log_status")(), ";")
	if(length(parts) < 5)
		return null
	return list("queued" = text2num(parts[1]), "written" = text2num(parts[2]), "dropped" = text2num(parts[3]), "failed" = text2num(parts[4]), "error" = jointext(parts.Copy(5), ";"))
