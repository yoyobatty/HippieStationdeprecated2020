// The HTML stat panel with a real client: Status in the lobby and in a round, verb tabs and a verb run from one, the verb search,
// the alt-clicked tile with its icons and a click on what it lists, a spell's tab, a verb added mid-round, the nanosuit's tab,
// MC and Tickets for an admin, the light theme. Not part of the game:
//   echo after > data/stat_check_label; SHOT_MINUTES=7 HARNESS=stat_check.dm SENDER=shot.ps1 tools/keybind_check/run.sh stat
// Pictures in data/previews/stat_<label>_*.png (the whole game window), results in data/keycheck_stat.txt.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_VAR_INIT(sc_label, "now")
GLOBAL_LIST_EMPTY(sc_probes)

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
			stat_check_run(src)

/client/Topic(href, href_list, hsrc)
	if(href_list["probe"])
		GLOB.sc_probes[href_list["probe"]] = href_list["value"]
		return
	return ..()

/// A verb the harness gives the mob mid-round: its tab should turn up without anything else telling the panel
/mob/proc/statcheck_verb()
	set name = "Harness Check"
	set category = "Testing"
	to_chat(src, "Harness check.")

/proc/sc_check(name, ok, detail)
	kc_log("[ok ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " ([detail])"]")

/proc/sc_shot(name)
	text2file("stat_[GLOB.sc_label]_[name]", "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// Runs js in the stat panel. No square brackets: DM would read them as embedded expressions.
/proc/sc_js(client/C, js)
	C << output(url_encode(js), "statbrowser:eval")

/proc/sc_ask(client/C, name, expr)
	GLOB.sc_probes -= name
	sc_js(C, "try { window.chrome.webview.postMessage('byond://?probe=[name]&value=' + encodeURIComponent(String([expr]))); } catch (e) { window.chrome.webview.postMessage('byond://?probe=[name]&value=' + encodeURIComponent('error ' + e)); }")
	var/deadline = world.time + 5 SECONDS
	while(!(name in GLOB.sc_probes) && world.time < deadline)
		sleep(1)
	return GLOB.sc_probes[name]

/// The tab buttons the page shows, in order
/proc/sc_tabs(client/C)
	return sc_ask(C, "tabs", "Array.from(document.querySelectorAll('#menu .button')).sort(function (a, b) { return (a.style.order - b.style.order) || a.textContent.localeCompare(b.textContent); }).map(function (b) { return b.textContent; }).join(',')")

/proc/sc_text(client/C)
	return sc_ask(C, "text", "document.getElementById('statcontent').innerText")

/proc/sc_tab(client/C, tab)
	sc_js(C, "tab_change('[tab]');")
	sleep(10)

/proc/stat_check_run(client/C)
	if(fexists("data/stat_check_label"))
		GLOB.sc_label = trim(file2text("data/stat_check_label"))
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	var/wait = world.time + 30 SECONDS
	while(!C.stat_panel?.is_ready() && world.time < wait)
		sleep(2)
	sc_check("the panel comes up", C.stat_panel?.is_ready(), "[(world.time - wait + 30 SECONDS) / 10] s after the harness started")
	sleep(20)

	// The lobby (on Status: the page opens on the tab the player picked last round, kept in their prefs)
	sc_tab(C, "Status")
	var/text = sc_text(C)
	sc_check("lobby Status has the round's lines", findtext(text, "Map") && findtext(text, "Lobby Time") && findtext(text, "Time To Start"), copytext(text, 1, 300))
	sc_check("lobby has the OOC tab", findtext(sc_tabs(C), "OOC"), sc_tabs(C))
	sc_shot("lobby")

	// A round, as an assistant with admin rights (MC, Tickets)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	var/turf/home = get_turf(pick(SSjob.latejoin_trackers))
	var/mob/living/carbon/human/H = new(home)
	H.mind_initialize()
	H.fully_replace_character_name(null, "Alex Harness")
	H.equipOutfit(/datum/outfit/job/assistant)
	H.ckey = C.ckey
	sleep(3 SECONDS)
	C.fit_viewport()
	if(!C.holder)
		var/datum/admins/A = new(new /datum/admin_rank("!localhost!", R_EVERYTHING, R_DBRANKS, R_EVERYTHING), C.ckey, 1, 1)
		A.associate(C)
	sleep(4 SECONDS)
	sc_tab(C, "Status")
	sleep(15)
	text = sc_text(C)
	sc_check("crew Status: round time, intent, move mode", findtext(text, "Round Time") && findtext(text, "Intent") && findtext(text, "Move Mode"), copytext(text, 1, 400))
	var/tabs = sc_tabs(C)
	sc_check("tabs for a crewmember and admin", findtext(tabs, "Status") && findtext(tabs, "MC") && findtext(tabs, "IC") && findtext(tabs, "Admin"), tabs)
	sc_shot("status")

	// A verb tab, and a verb run from it
	sc_tab(C, "IC")
	text = sc_text(C)
	sc_check("the IC tab has its verbs", findtext(text, "Rest") && findtext(text, "Say"), copytext(text, 1, 300))
	sc_shot("ic")
	sc_js(C, "Array.from(document.querySelectorAll('.grid-item')).filter(function (a) { return a.textContent == 'Rest'; }).forEach(function (a) { a.click(); });")
	sleep(15)
	sc_check("clicking Rest runs it", H.resting, "resting [H.resting]")
	H.set_resting(FALSE, TRUE)

	// The search
	sc_js(C, "document.getElementById('verbsearch-input').value = 'ghost'; setSearch('ghost');")
	sleep(5)
	text = sc_text(C)
	sc_check("searching 'ghost' finds the ghost verbs across tabs", findtext(text, "Ghost") && !findtext(text, "Rest"), copytext(text, 1, 300))
	sc_shot("search")
	sc_js(C, "clearSearch(false);")
	sleep(5)

	// MC and Tickets
	sc_tab(C, "MC")
	sleep(15)
	text = sc_text(C)
	sc_check("MC lists the subsystems", findtext(text, "Stat Panels") && findtext(text, "Failsafe") && findtext(text, "Atmospherics") && findtext(text, "Not firing"), copytext(text, 1, 200))
	sc_shot("mc")
	sc_check("MC draws the last two minutes of CPU", text2num(sc_ask(C, "spark", "document.querySelector('.mc-spark-line').getAttribute('d').split('L').length")) >= 2, sc_ask(C, "spark", "document.querySelector('.mc-spark-line').getAttribute('d')"))
	sc_js(C, "mc_view.filter.focus(); mc_view.filter.value = 'atmos'; mc_view.filter.oninput();")
	sleep(25) // two updates: the filter's text and focus outlive them
	text = sc_text(C)
	sc_check("MC filter keeps its text and focus over updates", findtext(text, "Atmospherics") && !findtext(text, "Stat Panels") && sc_ask(C, "focus", "document.activeElement === mc_view.filter && mc_view.filter.value") == "atmos", copytext(text, 1, 200))
	sc_js(C, "mc_view.filter.value = ''; mc_view.filter.oninput(); mc_view.heads.name.click();")
	sleep(5)
	sc_check("MC sorts by name on its header", sc_ask(C, "first", "mc_view.body.querySelector('tr td.mc-name').innerText") == "Acid", sc_ask(C, "first", "mc_view.body.querySelector('tr td.mc-name').innerText"))
	sc_js(C, "mc_view.heads.cost.click();")
	sleep(5)
	sc_js(C, "mc_row_click({target: mc_view.body.querySelector('tr\[data-type] td.mc-cost')});")
	sleep(25) // the server sends the row's history with the next updates
	var/detail = sc_ask(C, "detail", "mc_view.detail.tr.style.display + '|' + mc_view.detail.facts.innerText + '|' + mc_view.detail.line.getAttribute('d').split('L').length")
	var/list/detail_parts = splittext("[detail]", "|")
	sc_check("MC row click opens its detail with history", findtext(detail, "|wait ") && findtext(detail, "priority") && length(detail_parts) == 3 && text2num(detail_parts[3]) >= 2, detail)
	sc_shot("mc_detail")
	sc_js(C, "mc_row_click({target: mc_view.body.querySelector('tr.open td.mc-cost')});")
	sleep(5)
	sc_check("MC row click again closes it", sc_ask(C, "closed", "mc_view.detail.tr.style.display") == "none", sc_ask(C, "closed", "mc_view.detail.tr.style.display"))
	sc_tab(C, "Tickets")
	sleep(25)
	text = sc_text(C)
	sc_check("Tickets has the counts", findtext(text, "Active Tickets") && findtext(text, "Resolved Tickets"), copytext(text, 1, 200))

	// The alt-clicked tile: what's on it, with icons; a click on one picks it up
	var/turf/open/next_to
	for(var/turf/open/floor/F in orange(1, H))
		if(!F.density && !(locate(/obj/structure) in F) && !(locate(/mob) in F) && !(locate(/obj/machinery) in F))
			next_to = F
			break
	var/obj/item/wrench/W = new(next_to)
	var/obj/item/crowbar/B = new(next_to)
	H.AltClickOn(next_to)
	sleep(15)
	tabs = sc_tabs(C)
	text = sc_text(C)
	sc_check("alt-click opens the tile's tab", findtext(tabs, next_to.name) && findtext(text, "wrench") && findtext(text, "crowbar"), "[tabs] / [copytext(text, 1, 200)]")
	var/icons = sc_ask(C, "icons", "Array.from(document.querySelectorAll('.turf-item img')).filter(function (i) { return i.naturalWidth > 0; }).length")
	sc_check("the tile's things have pictures", text2num(icons) >= 3, icons)
	sc_shot("turf")
	sc_js(C, "Array.from(document.querySelectorAll('.turf-item')).filter(function (a) { return a.innerText.indexOf('wrench') != -1; }).forEach(function (a) { a.dispatchEvent(new MouseEvent('mousedown', {button: 0, bubbles: true})); });")
	sleep(15)
	sc_check("clicking the wrench in the list picks it up", W.loc == H, "wrench in [W.loc]")
	qdel(B)

	// A spell: its tab, with its charge
	var/obj/effect/proc_holder/spell/aoe_turf/knock/K = new
	H.mind.AddSpell(K)
	sleep(20)
	tabs = sc_tabs(C)
	sc_check("a spell's tab turns up", findtext(tabs, K.panel), tabs)
	sc_tab(C, K.panel)
	text = sc_text(C)
	sc_check("the spell's button shows its charge", findtext(text, K.name) && findtext(text, "/"), copytext(text, 1, 200))
	sc_shot("spells")

	// A verb given mid-round
	H.verbs += /mob/proc/statcheck_verb
	sleep(35)
	// Its tab, Testing, has one verb, so it's folded into Other (statbrowser.js refold())
	sc_check("a verb given mid-round gets its tab", findtext(sc_tabs(C), "Other") && sc_ask(C, "verb", "verbs.some((v) => v\[1] == 'Harness Check')") == "true", sc_tabs(C))
	H.verbs -= /mob/proc/statcheck_verb
	sleep(35)
	sc_check("and loses it when taken away", sc_ask(C, "verb", "verbs.some((v) => v\[1] == 'Harness Check')") == "false", sc_tabs(C))

	// The nanosuit's tab
	var/obj/item/clothing/suit/space/hardsuit/nano/N = new(get_turf(H))
	H.dropItemToGround(H.wear_suit)
	H.equip_to_slot_or_del(N, ITEM_SLOT_OCLOTHING)
	sleep(20)
	tabs = sc_tabs(C)
	sc_check("the nanosuit adds its tab", findtext(tabs, "Crynet Nanosuit"), tabs)
	sc_tab(C, "Crynet Nanosuit")
	text = sc_text(C)
	sc_check("with its readings", findtext(text, "Energy Charge") && findtext(text, "Atmospheric Pressure"), copytext(text, 1, 200))
	sc_shot("nanosuit")

	// The light theme
	sc_tab(C, "Status")
	C.set_skin_theme(FALSE)
	sleep(15)
	sc_check("the panel goes light with the skin", sc_ask(C, "theme", "document.documentElement.className") == "light")
	sc_shot("light")
	C.set_skin_theme(TRUE)
	sleep(10)
	sc_check("and dark again", sc_ask(C, "theme2", "document.documentElement.className") == "dark")

	// Another body: the tile's tab goes, the new body's verbs come
	var/mob/dead/observer/ghost = H.ghostize(TRUE)
	sleep(35)
	tabs = sc_tabs(C)
	sc_check("as a ghost: the tile's tab is gone", !findtext(tabs, next_to.name), tabs)
	sc_check("as a ghost: the Ghost tab is there", findtext(tabs, "Ghost") && C.mob == ghost, tabs)
	sc_shot("ghost")

	sc_check("no runtimes from the panel", !fexists("data/keycheck_stop"))
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
