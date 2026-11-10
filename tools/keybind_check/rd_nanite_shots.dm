// Pictures of the R&D console on a nanite node, before and after it showed Nanite Research (rdconsole_tgui.dm, RdConsole.js): plenty
// of General Research, a little Nanite Research, and Mesh Nanite Programming (500 + 500) picked. Not part of the game.
//   after:  echo after > data/rd_nanite_label; HARNESS=rd_nanite_shots.dm SENDER=shot.ps1 tools/keybind_check/run.sh rdnanite
//   before: HEAD's rdconsole_tgui.dm in data/previews/rd_old/ and HEAD's bundle in data/previews/atmos_old/, then
//           echo before > data/rd_nanite_label; EXCLUDE='hippiestation\code\modules\research\rdconsole_tgui.dm'
//           HARNESS=rd_nanite_shots_before.dm SENDER=shot.ps1 tools/keybind_check/run.sh rdnanite
// Pictures in data/previews/popup_rdnanite_<label>_*.png; what the console says when told to research it in data/keycheck.txt.

GLOBAL_VAR_INIT(rd_nanite_running, FALSE)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/proc/rn_log(text)
	text2file(text, "data/keycheck.txt")

/client/New()
	. = ..()
	if(. && !GLOB.rd_nanite_running)
		GLOB.rd_nanite_running = TRUE
		spawn(50)
			rd_nanite_run(src)

/proc/rn_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/proc/rn_js(client/C, window_id, action)
	var/js
	if(findtext(action, "click:") == 1)
		var/text = copytext(action, 7)
		js = "var t=[json_encode(text)];var b=Array.prototype.slice.call(document.querySelectorAll('.Button, .Tabs__tab, \[style*=\"cursor\"\]')).filter(function(e){return e.textContent.trim().indexOf(t)===0;})\[0\];if(b){b.click();}"
	else if(findtext(action, "search:") == 1)
		var/text = copytext(action, 8)
		js = "var i=document.querySelector('input');if(i){i.value=[json_encode(text)];i.dispatchEvent(new Event('input',{bubbles:true}));}"
	if(js)
		C << output(url_encode(js), "[window_id].browser:eval")

/obj/machinery/computer/rdconsole/say(message, bubble_type, list/spans, sanitize, datum/language/language, ignore_spam, forced)
	rn_log("console says: [message]")
	return ..()

/proc/rd_nanite_run(client/C)
	var/label = trim(file2text("data/rd_nanite_label")) || "now"
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	var/turf/home = get_turf(pick(SSjob.latejoin_trackers))
	var/mob/living/carbon/human/H = new(home)
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/scientist)
	H.ckey = C.ckey
	sleep(3 SECONDS)
	var/obj/machinery/computer/rdconsole/core/console = new(get_step(H, EAST))
	console.stat &= ~(NOPOWER|BROKEN)
	var/datum/techweb/web = SSresearch.science_tech
	for(var/id in list("datatheory", "engineering", "nanite_base"))
		if(SSresearch.techweb_node_by_id(id))
			web.research_node_id(id, TRUE)
	web.research_points[TECHWEB_POINT_TYPE_GENERIC] = 12500
	web.research_points[TECHWEB_POINT_TYPE_NANITES] = 120
	console.ui_interact(H)
	sleep(4 SECONDS)
	var/datum/tgui/ui
	for(var/datum/tgui/open as anything in H.open_uis)
		if(open.src_object == console)
			ui = open
	rn_log("[ui ? "PASS" : "FAIL"] the console's window opens")
	if(ui)
		winset(C, ui.window_id, "pos=200,100")
		rn_js(C, ui.window_id, "search:nanite")
		sleep(10)
		rn_js(C, ui.window_id, "click:Mesh Nanite Programming")
		sleep(15)
		rn_shot("popup_rdnanite_[label]_1_mesh_node")
	usr = H
	console.research_node("nanite_mesh", H)
	rn_log("researched: [web.researched_nodes["nanite_mesh"] ? "yes" : "no"]")
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	rn_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
