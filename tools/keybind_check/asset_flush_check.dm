// client.asset_flush() with a real client (BYOND 516, WebView2). It opens a hidden page that navigates to
// ?asset_cache_confirm_arrival=N and waits for that to come back. If 516 drops that navigation, every flush waits out its whole
// timeout, and getFilesSlow() (3 files a flush, from connection on) crawls. This logs each flush: confirmed or timed out, and how
// long it took, in the lobby and in the round; then tries the same answer sent by chrome.webview.postMessage instead.
// Not part of the game: HARNESS=asset_flush_check.dm MAP=testbench tools/keybind_check/run.sh asset_flush

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_LIST_EMPTY(afc_lines)
GLOBAL_VAR_INIT(afc_confirmed, 0)
GLOBAL_VAR_INIT(afc_timed_out, 0)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/proc/kc_log(text)
	text2file(text, "data/keycheck.txt")

/client/asset_flush(timeout = 50)
	var/job = last_asset_job + 1
	var/real = REALTIMEOFDAY
	var/game = world.time
	. = ..()
	if(.)
		GLOB.afc_confirmed++
	else
		GLOB.afc_timed_out++
	if(length(GLOB.afc_lines) < 40)
		GLOB.afc_lines += "flush job [job] ([SSticker.current_state < GAME_STATE_PLAYING ? "lobby" : "round"], timeout [timeout]): [. ? "confirmed" : "TIMED OUT"] after [world.time - game] ds game, [REALTIMEOFDAY - real] ds real"

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(10)
			asset_flush_check_run(src)

/proc/afc_flushes(client/C, label, n)
	for(var/i in 1 to n)
		if(!C)
			return
		C.asset_flush()
	kc_log("[label]: [GLOB.afc_confirmed] confirmed, [GLOB.afc_timed_out] timed out so far")

/proc/asset_flush_check_run(client/C)
	SSticker.start_immediately = FALSE
	kc_log("connected, preload [length(SSassets.preload)] files (getFilesSlow flushes every 3 sent)")
	sleep(20 SECONDS) // getFilesSlow starts 5 s after connecting
	kc_log("lobby, 20 s in: [GLOB.afc_confirmed] confirmed, [GLOB.afc_timed_out] timed out, [length(C.sent_assets)] assets sent")
	afc_flushes(C, "lobby, 3 flushes of our own", 3)
	// two at once, as getFilesSlow's two callers can: the second page can replace the first in the hidden window before it answers
	var/timed_out = GLOB.afc_timed_out
	var/began = REALTIMEOFDAY
	for(var/i in 1 to 5)
		spawn(0)
			C?.asset_flush()
		C.asset_flush()
		sleep(5)
	kc_log("lobby, 5 pairs at once: [GLOB.afc_timed_out - timed_out] of 10 timed out, [(REALTIMEOFDAY - began) / 10] s")
	// the same answer through the bridge the tgui pages use
	var/job = ++C.last_asset_job
	C << browse({"<script>window.chrome.webview.postMessage('byond://?asset_cache_confirm_arrival=[job]')</script>"}, "window=asset_cache_browser&file=asset_cache_send_verify.htm")
	var/until = world.time + 5 SECONDS
	while(C && !C.completed_asset_jobs["[job]"] && world.time < until)
		sleep(1)
	kc_log("postMessage answer for job [job]: [C?.completed_asset_jobs["[job]"] ? "arrived" : "never came"]")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	afc_flushes(C, "round, 3 flushes of our own", 3)
	for(var/line in GLOB.afc_lines)
		kc_log(line)
	kc_log("[length(C?.sent_assets)] assets sent of [length(SSassets.preload)]")
	kc_log("done")
