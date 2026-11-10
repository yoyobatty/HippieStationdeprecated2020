// The log writer in the real engine (hippiestation/code/__HELPERS/log_writer.dm). Not part of the game: tools/log_writer/run_log_check.sh
// The lines come out as rust_g's do; a stalled writer doesn't hold the game up; nothing is lost or reordered; closing waits for the
// queue. Booted with log-writer=rustg, the game writes through rust_g.

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("log-check" in world.params)
		sleep_offline_after_initializations = FALSE
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_log_check))
	return ..()

#define LOG_CHECK_DIR "data/log_check/"

GLOBAL_LIST_EMPTY(log_check_lines)

/proc/lc_check(name, ok, detail)
	GLOB.log_check_lines += "[ok ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " - [detail]"]"

/// A log file's lines with their timestamps taken off
/proc/lc_untimed(path)
	. = list()
	var/regex/stamp = regex(@"^\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}\] ")
	for(var/line in splittext(file2text(path), "\n"))
		. += stamp.Replace(line, "")

/proc/run_log_check()
	sleep(3 SECONDS)
	var/mode = world.params["log-writer"] == "rustg" ? "rustg" : "native"
	var/out = "[LOG_CHECK_DIR][mode]/"
	if(mode == "rustg")
		WRITE_LOG("[out]plain.log", "one line")
		lc_check("booted with log-writer=rustg, rust_g writes the logs", hippie_log_native == FALSE, "[hippie_log_native]")
		lc_check("and they're still written", findtext(file2text("[out]plain.log"), "] one line"))
		lc_check("the round's own logs too", findtext(file2text(GLOB.world_game_log), "Starting up round ID"))
	else
		var/list/texts = list("EMOTE: <b>Bob</b> waves.", "Starting up round ID 7.\n-------------------------", "trailing newline\n", "tab\there \"quotes\" and ünïcödé", "")
		for(var/text in texts)
			WRITE_LOG("[out]native.log", text)
			rustg_log_write("[out]rustg.log", text, "true")
		lc_check("hippie_log.dll writes the logs", hippie_log_native == TRUE, "[hippie_log_native]")
		lc_check("flush answers", isnull(hippie_log_flush(5000)))
		var/native_text = file2text("[out]native.log")
		var/rustg_text = file2text("[out]rustg.log")
		var/regex/stamp = regex(@"^\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}\] ", "m")
		lc_check("the lines are rust_g's, but for the time", stamp.Replace(native_text, "") == stamp.Replace(rustg_text, ""), "[length(native_text)] / [length(rustg_text)] bytes")
		var/regex/first = regex(@"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\.\d{3}\]")
		var/native_time = first.Find(native_text) ? first.group[1] : "none"
		var/rustg_time = first.Find(rustg_text) ? first.group[1] : "none"
		lc_check("and the time is the same clock (UTC)", copytext(native_time, 1, 17) == copytext(rustg_time, 1, 17), "[native_time] / [rustg_time]")
		lc_check("the round's own logs come through it", findtext(file2text(GLOB.world_game_log), "Starting up round ID"))

		// a drive that takes 50 ms a line: the game hands over 200 lines and goes on
		call_ext(HIPPIE_LOG, "log_stall")("50")
		var/began = REALTIMEOFDAY
		for(var/i in 1 to 200)
			WRITE_LOG("[out]stall.log", "line [i]")
		var/took = REALTIMEOFDAY - began
		var/list/status = hippie_log_status()
		lc_check("200 lines with the drive stalled cost the game almost nothing", took < 5, "[took / 10] s, [status["queued"]] waiting")
		call_ext(HIPPIE_LOG, "log_stall")("0")
		lc_check("the queue empties once the drive is back", isnull(hippie_log_flush(10000)))
		var/list/lines = lc_untimed("[out]stall.log")
		var/in_order = TRUE
		for(var/i in 1 to 200)
			if(i > length(lines) || lines[i] != "line [i]")
				in_order = FALSE
				break
		lc_check("every line, in order", in_order && length(lines) == 201, "[length(lines) - 1] lines")

		// closing waits for the queue, and writing again appends
		call_ext(HIPPIE_LOG, "log_stall")("5")
		for(var/i in 1 to 100)
			WRITE_LOG("[out]close.log", "before close [i]")
		hippie_log_close_all()
		call_ext(HIPPIE_LOG, "log_stall")("0")
		WRITE_LOG("[out]close.log", "after close")
		hippie_log_flush(5000)
		lines = lc_untimed("[out]close.log")
		lc_check("closing writes out what's queued first", length(lines) == 102 && lines[100] == "before close 100" && lines[101] == "after close", "[length(lines) - 1] lines, last [length(lines) > 1 ? lines[length(lines) - 1] : "none"]")
		status = hippie_log_status()
		lc_check("nothing dropped or failed", status["dropped"] == 0 && status["failed"] == 0, "[status["written"]] written, [status["dropped"]] dropped, [status["failed"]] failed [status["error"]]")

		// a speed check against rust_g, the drive as it is
		began = REALTIMEOFDAY
		for(var/i in 1 to 20000)
			rustg_log_write("[out]speed_rustg.log", "EMOTE: a line about as long as an emote line is, [i]", "true")
		var/rustg_took = REALTIMEOFDAY - began
		began = REALTIMEOFDAY
		for(var/i in 1 to 20000)
			WRITE_LOG("[out]speed_native.log", "EMOTE: a line about as long as an emote line is, [i]")
		var/native_took = REALTIMEOFDAY - began
		hippie_log_flush(10000)
		GLOB.log_check_lines += "     20000 lines: rust_g [rustg_took * 100000 / 20000] us each, hippie_log [native_took * 100000 / 20000] us each (game's side)"
	var/passed = 0
	var/checks = 0
	for(var/line in GLOB.log_check_lines)
		if(copytext(line, 1, 5) == "PASS")
			passed++
		if(copytext(line, 1, 5) == "PASS" || copytext(line, 1, 5) == "FAIL")
			checks++
	GLOB.log_check_lines += "done: [passed] of [checks] passed"
	text2file(jointext(GLOB.log_check_lines, "\n"), "[LOG_CHECK_DIR]results_[mode].txt")
	shutdown_logging()
	qdel(world)
