// WRITE_LOG (code/__HELPERS/_logging.dm) through hippie_log.dll (tools/log_writer): the line is timestamped and queued, and
// a thread of the library's own writes it. rust_g wrote each line on the game's thread, so a stalling drive stalled the
// game: in the user's round on 2026-11-10, with the drive 99% full, single log lines held the server 3 to 7 s at a time
// (the watchdog named /datum/player_log/proc/write and /proc/log_emote). The files come out the same, line for line.
//
// Without the library (or booted with log-writer=rustg) the game writes through rust_g as before.
//
// The machine-read logs (the bot trace, bot and player telemetry) go to a path ending in ".zst", which the library's thread writes
// zstd-compressed: ~25 times smaller, and no cost to the game. hippie_log_compressed() gives the path to use, which is the plain one
// when rust_g writes the logs. Read them with tools/bot_gym/logread.py.

/// Whether hippie_log.dll writes the logs: null until the first log line asks
GLOBAL_REAL_VAR(hippie_log_native)
/// What the library can do beyond log_write (log_features): "zst replace", or "" for one built before those
GLOBAL_REAL_VAR(hippie_log_features)

/// `path` + ".zst" when the library writes the logs and can compress them, else `path`
/proc/hippie_log_compressed(path)
	if(isnull(hippie_log_native))
		hippie_log_native = hippie_log_try()
	return hippie_log_native && findtext(hippie_log_features, "zst") ? "[path].zst" : path

/// `text` and a line end added to the file as they are, as WRITE_FILE(file(path), text) adds them, but by the library's thread: no
/// rust_g time stamp. For investigate_log()'s .html files. Without the library, WRITE_FILE() here and now.
/proc/hippie_log_append(path, text)
	if(isnull(hippie_log_native))
		hippie_log_native = hippie_log_try()
	if(hippie_log_native)
		call_ext(HIPPIE_LOG, "log_write")("[path]", world.system_type == MS_WINDOWS ? "[text][ascii2text(13)]\n" : "[text]\n", "false")
		return
	WRITE_FILE(file(path), text)

/// The whole file, written over the old one by the library's thread. Without it, here and now (fdel and text2file).
/proc/hippie_log_replace(path, text)
	if(isnull(hippie_log_native))
		hippie_log_native = hippie_log_try()
	if(hippie_log_native && findtext(hippie_log_features, "replace"))
		call_ext(HIPPIE_LOG, "log_replace")("[path]", "[text]")
		return
	if(fexists(path))
		fdel(path)
	text2file(text, path)

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
		if(call_ext(HIPPIE_LOG, "log_version")() != "hippie_log 1")
			return FALSE
	catch
		return FALSE
	try
		hippie_log_features = call_ext(HIPPIE_LOG, "log_features")()
	catch
		hippie_log_features = "" // a library from before log_features: plain files only
	return TRUE

/// Waits (up to 10 s) for what's queued to be written, and closes the files. Before shutting down or rebooting.
/proc/hippie_log_close_all()
	if(!hippie_log_native)
		return
	var/result = call_ext(HIPPIE_LOG, "log_close_all")()
	if(result)
		SEND_TEXT(world.log, result)

/// Test runs end with qdel(world) (a Bot Shift, a Gym, the self-tests), which never gets to shutdown_logging(): the last second of a
/// compressed log would be lost with the thread, and its frame left without an end.
/world/Del()
	hippie_log_close_all()
	return ..()

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
