// Every kind of mob's stat panel lines (get_status_tab_items, spells, gear tabs) built without runtimes, and the panel as an AI,
// a cyborg and a ghost with a real client. Not part of the game:
//   HARNESS=stat_mobs_check.dm tools/keybind_check/run.sh statmobs
// Results in data/keycheck_statmobs.txt.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_LIST_EMPTY(sm_probes)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/proc/kc_log(text)
	text2file(text, "data/keycheck.txt")

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(50)
			stat_mobs_run(src)

/client/Topic(href, href_list, hsrc)
	if(href_list["probe"])
		GLOB.sm_probes[href_list["probe"]] = href_list["value"]
		return
	return ..()

/proc/sm_check(name, ok, detail)
	kc_log("[ok ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " ([detail])"]")

/// Status's text: the page opens on the tab the player picked last round (kept in their prefs), so Status is picked first
/proc/sm_text(client/C)
	C << output(url_encode("tab_change('Status');"), "statbrowser:eval")
	sleep(10)
	GLOB.sm_probes -= "text"
	C << output(url_encode("window.chrome.webview.postMessage('byond://?probe=text&value=' + encodeURIComponent(document.getElementById('statcontent').innerText));"), "statbrowser:eval")
	var/deadline = world.time + 5 SECONDS
	while(!("text" in GLOB.sm_probes) && world.time < deadline)
		sleep(1)
	return GLOB.sm_probes["text"]

/// A mob's panel, as the subsystem builds it, with any runtime caught
/proc/sm_lines(mob/M)
	var/list/out = list()
	try
		var/list/items = M.get_status_tab_items()
		out += "status: [islist(items) ? jointext(items, " | ") : "NOT A LIST: [items]"]"
		var/list/clickable = list()
		var/list/spells = M.get_stat_panel_spells(clickable)
		out += "spells: [length(spells)]"
		var/list/extra = M.get_stat_panel_extra_tabs()
		out += "extra: [length(extra) ? jointext(extra, ", ") : "none"]"
		json_encode(items)
		json_encode(spells)
		json_encode(extra)
	catch(var/exception/e)
		return "RUNTIME [e] at [e.file]:[e.line]"
	return jointext(out, "; ")

/proc/stat_mobs_run(client/C)
	var/wait = world.time + 30 SECONDS
	while(!C.stat_panel?.is_ready() && world.time < wait)
		sleep(2)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	var/turf/home = get_turf(pick(SSjob.latejoin_trackers))
	var/mob/living/carbon/human/H = new(home)
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/assistant)
	H.ckey = C.ckey
	sleep(3 SECONDS)

	var/list/types = list(
		/mob/living/carbon/human,
		/mob/living/carbon/monkey,
		/mob/living/carbon/alien/humanoid/drone,
		/mob/living/carbon/alien/larva,
		/mob/living/silicon/ai,
		/mob/living/silicon/robot,
		/mob/living/simple_animal/slime,
		/mob/living/simple_animal/parrot,
		/mob/living/simple_animal/revenant,
		/mob/living/simple_animal/hostile/guardian,
		/mob/living/simple_animal/hostile/swarmer,
		/mob/living/simple_animal/pet/dog/corgi,
		/mob/living/simple_animal/borer,
		/mob/living/simple_animal/hostile/true_changeling,
		/mob/camera/blob,
		/mob/camera/disease,
		/mob/dead/observer,
	)
	for(var/path in types)
		if(!ispath(path))
			sm_check("[path] exists", FALSE)
			continue
		var/mob/M
		try
			M = new path(home)
		catch(var/exception/e)
			kc_log("could not make [path] here: [e]")
			continue
		if(QDELETED(M))
			kc_log("[path] deleted itself on creation")
			continue
		var/lines = sm_lines(M)
		sm_check("[path] builds its panel", !findtext(lines, "RUNTIME") && !findtext(lines, "NOT A LIST"), lines)
		if(!istype(M, /mob/living/silicon/ai) && !istype(M, /mob/living/silicon/robot) && !istype(M, /mob/dead/observer))
			qdel(M)

	// Antagonists' own sections (stat_panel.dm stat_section() and the rest)
	var/list/antags = list(/datum/antagonist/changeling = "Chemicals", /datum/antagonist/vampire = "Total Blood", /datum/antagonist/hivemind = "Vessels")
	for(var/antag in antags)
		var/mob/living/carbon/human/A = new(home)
		A.mind_initialize()
		var/sent
		try
			A.mind.add_antag_datum(antag)
			sent = json_encode(A.get_status_tab_items())
		catch(var/exception/e)
			sent = "RUNTIME [e] at [e.file]:[e.line]"
		sm_check("[antag] gets its section", findtext(sent, "\"section\"") && findtext(sent, antags[antag]), sent)
		qdel(A)

	// With the client: an AI, a cyborg, a ghost. An AI made with nobody to go in it deletes itself (ai.dm Initialize()), and a
	// client put in that one sits in nullspace with a null eye: this one comes out of the human the client's in, as AIize() does it.
	var/mob/living/silicon/ai/AI = locate() in home
	if(!AI)
		AI = new(home, null, H)
	AI.ckey = C.ckey
	sleep(40)
	var/text = sm_text(C)
	sm_check("as an AI the panel shows its lines", findtext(text, "System integrity") && findtext(text, "Connected cyborgs"), copytext(text, 1, 300))
	var/mob/living/silicon/robot/R = locate() in home
	if(!R)
		R = new(home)
	R.ckey = C.ckey
	sleep(40)
	text = sm_text(C)
	sm_check("as a cyborg the panel shows its charge", findtext(text, "Charge Left"), copytext(text, 1, 300))
	var/mob/dead/observer/G = new(home)
	G.ckey = C.ckey
	sleep(40)
	text = sm_text(C)
	sm_check("as a ghost the panel shows the round", findtext(text, "Mode") && findtext(text, "Round") && findtext(text, "Station"), copytext(text, 1, 300))
	var/runtimes = 0
	for(var/line in world.file2list("data/logs/[GLOB.log_directory]/runtime.log"))
		if(findtext(line, "runtime error") && (findtext(line, "status_tab") || findtext(line, "stat_panel") || findtext(line, "statpanels")))
			runtimes++
	sm_check("no panel runtimes in the round's log", !runtimes, "[runtimes]")
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
