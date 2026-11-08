// Real-client check of the tgui vote panel (hippiestation/code/controllers/subsystem/vote_tgui.dm, VotePanel.js). Not part of
// the game: HARNESS=vote_check.dm SENDER=kb_panel.ps1 tools/keybind_check/run.sh <label>
// The panel is driven the way its page does it (ui_act with its ui), and what the page shows is read back from its DOM.
// Pictures in data/previews/popup_vote_*.png.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_VAR_INIT(vc_pass, 0)
GLOBAL_VAR_INIT(vc_fail, 0)
GLOBAL_VAR(vc_dom)

/proc/kc_log(text)
	text2file("[time2text(world.timeofday, "hh:mm:ss")] [text]", "data/keycheck.txt")

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(50)
			vc_run(src)

/client/Topic(href, list/href_list, hsrc)
	if(href_list["vc_dom"])
		GLOB.vc_dom = href_list["vc_dom"]
		return
	return ..()

/proc/vc_check(name, ok, detail = "")
	if(ok)
		GLOB.vc_pass++
	else
		GLOB.vc_fail++
	kc_log("[ok ? "ok   " : "WRONG"] [name][detail ? " ([detail])" : ""]")

/proc/vc_shot(name, title)
	fdel("data/keycheck_shot_title")
	if(title)
		text2file(title, "data/keycheck_shot_title")
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// The page's visible text, whitespace squeezed
/proc/vc_text(client/C, datum/tgui/ui)
	GLOB.vc_dom = null
	var/js = "window.__sendToByond__('byond://?vc_dom='+encodeURIComponent(document.body.innerText.replace(/\\s+/g,' ')));"
	C << output(url_encode(js), "[ui.window_id].browser:eval")
	for(var/i in 1 to 20)
		if(!isnull(GLOB.vc_dom))
			break
		sleep(1)
	return GLOB.vc_dom || ""

/proc/vc_ui(mob/M)
	return SStgui.get_open_ui(M, SSvote, "vote")

/proc/vc_run(client/C)
	for(var/i in 1 to 300)
		if(!C)
			return
		if(SSticker.current_state >= GAME_STATE_PREGAME && C.mob)
			break
		sleep(1)
	text2file("go", "data/keycheck_sendkeys") // starts shot.ps1 for the pictures
	sleep(40)
	var/mob/M = C.mob
	usr = M

	// no vote: the start page
	M.vote()
	sleep(15)
	var/datum/tgui/ui = vc_ui(M)
	vc_check("Vote verb opens the tgui panel", ui)
	if(!ui)
		kc_log("info giving up")
		text2file("x", "data/keycheck_shots_done")
		kc_log("done")
		shutdown()
		return
	var/t = vc_text(C, ui)
	vc_check("idle page lists the votes to start", findtext(t, "Start a vote") && findtext(t, "Restart") && findtext(t, "Call Shuttle") && findtext(t, "Game Mode"), t)
	vc_shot("popup_vote_idle", "400x360")

	// a vote starts with the panel open: it switches to the running page by itself
	CONFIG_SET(number/vote_period, 300) // 30 s
	SSvote.min_restart_time = 0
	CONFIG_SET(flag/allow_vote_restart, TRUE)
	ui.ui_act_proxy("start", list("type" = "restart"))
	sleep(20)
	vc_check("restart vote started from the panel", SSvote.mode == "restart", "[SSvote.mode]")
	t = vc_text(C, ui)
	vc_check("panel shows the running vote", findtext(t, "Vote: Restart") && findtext(t, "Restart Round") && findtext(t, "Continue Playing"), t)

	// voting, then changing it
	ui.ui_act_proxy("vote", list("index" = "2"))
	sleep(15)
	vc_check("vote counted", SSvote.choices["Continue Playing"] == 1 && !SSvote.choices["Restart Round"], "[SSvote.choices["Restart Round"]]/[SSvote.choices["Continue Playing"]]")
	t = vc_text(C, ui)
	vc_check("page shows 1 vote", findtext(t, "1 vote"), t)
	vc_shot("popup_vote_running", "400x360")
	ui.ui_act_proxy("vote", list("index" = "1"))
	sleep(15)
	vc_check("vote changed: moved, not added", SSvote.choices["Continue Playing"] == 0 && SSvote.choices["Restart Round"] == 1, "[SSvote.choices["Restart Round"]]/[SSvote.choices["Continue Playing"]]")
	ui.ui_act_proxy("vote", list("index" = "1"))
	sleep(5)
	vc_check("same vote twice counts once", SSvote.choices["Restart Round"] == 1)
	ui.ui_act_proxy("vote", list("index" = "9"))
	sleep(5)
	vc_check("bad index ignored", SSvote.choices["Restart Round"] == 1 && SSvote.choices["Continue Playing"] == 0)
	ui.ui_act_proxy("vote", list("index" = "2")) // back to Continue Playing, so the end doesn't restart this server
	sleep(5)

	// the countdown comes live, without reopening
	var/before = SSvote.time_remaining
	sleep(30)
	var/datum/tgui/same = vc_ui(M)
	vc_check("same window, not rebuilt", same == ui)
	vc_check("time left counts down", SSvote.time_remaining < before, "[before] -> [SSvote.time_remaining]")
	t = vc_text(C, ui)
	vc_check("page time follows", findtext(t, "0:[SSvote.time_remaining < 10 ? "0" : ""][SSvote.time_remaining]") || findtext(t, "0:[SSvote.time_remaining + 1 < 10 ? "0" : ""][SSvote.time_remaining + 1]"), t)

	// non-admins can't cancel
	if(!C.holder)
		ui.ui_act_proxy("cancel", list())
		sleep(5)
		vc_check("non-admin Cancel does nothing", SSvote.mode == "restart")

	// the chat link (Topic with no vote) and the action button open the same panel, not a browser page
	SStgui.close_uis(SSvote)
	sleep(5)
	SSvote.Topic("src=[REF(SSvote)]", list("src" = REF(SSvote)))
	sleep(15)
	vc_check("chat link opens the panel", vc_ui(M))
	SStgui.close_uis(SSvote)
	sleep(5)
	var/datum/action/vote/A = locate() in M.actions
	vc_check("vote action button was given", A)
	if(A)
		A.Trigger()
		sleep(15)
		vc_check("action button opens the panel", vc_ui(M))

	// the end: result, the window closes
	SSvote.started_time = world.time - CONFIG_GET(number/vote_period) - 10
	sleep(25)
	vc_check("vote ended", !SSvote.mode)
	vc_check("panel closed at the end", !vc_ui(M))

	kc_log("info [GLOB.vc_pass] passed, [GLOB.vc_fail] wrong")
	text2file("x", "data/keycheck_shots_done")
	sleep(10)
	kc_log("done")
	shutdown()

/// ui_act as the page sends it (with this ui), usr set to the player
/datum/tgui/proc/ui_act_proxy(action, list/params)
	usr = user
	update_status(push = FALSE)
	if(src_object.ui_act(action, params, src, state))
		SStgui.update_uis(src_object)
