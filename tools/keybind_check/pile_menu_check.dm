// How long a huge pile takes to show when it's right-clicked or alt-clicked, with a real client. Not part of the game:
//   MAP=testbench HARNESS=pile_menu_check.dm SENDER=pile_menu.ps1 tools/keybind_check/run.sh <label>
// For each pile size (PILE_SIZES=0,300,1500,4000; a mix of 16 everyday items, no stacks, they'd merge):
// - right-clicks on the pile: BYOND's menu up to 100 things (pile_menu.ps1 posts the button to the map and times the menu window),
//   past that the tile list instead (stat_panel.dm PILE_MENU_LIMIT), timed from the press to the list drawn in the panel;
// - a right-click on plain floor that beats its hover to the server (nothing happens, the menu comes back), then one after it;
// - an alt-click, timed to the list drawn, left open a few seconds to count the refreshes and the longest stall.
// PILE_EXPERIMENT=<count> and PILE_VERBS=<count> take BYOND's menu apart instead: names alike or not, which verbs, how many
// clickable. What they found is in stat_panel.dm above PILE_MENU_LIMIT.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_VAR_INIT(pm_running, TRUE)
GLOBAL_VAR_INIT(pm_probed, FALSE)
/// The longest gap between two ticks since the last pm_gap_reset(), in ms
GLOBAL_VAR_INIT(pm_max_gap, 0)
GLOBAL_LIST_EMPTY(pm_probes)
/// set_turf_tab() calls and their ms since the last reset
GLOBAL_LIST_EMPTY(pm_tab_ms)

#define PM_TIMER "pile_menu"
#define PM_NOW rustg_time_microseconds(PM_TIMER) / 1000

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
			pile_menu_run(src)

/client/MouseDown(object, location, control, params)
	if(!GLOB.pm_probed)
		GLOB.pm_probed = TRUE
		text2file("ok", "data/keycheck_probe_ok")
	return ..()

GLOBAL_VAR_INIT(pm_debug, 0)

/atom/MouseEntered(location, control, params)
	if(GLOB.pm_debug > 0)
		GLOB.pm_debug--
		var/turf/T = get_turf(src)
		kc_log("      hover [type] on [T ? "[T.x],[T.y] with [length(T.contents)]" : "nothing"], menu off before: [usr?.client?.pile_menu_off]")
	return ..()

/client/MouseUp(object, location, control, params)
	if(GLOB.pm_debug > 0)
		kc_log("      release on [object] ([control]): [params], menu off: [pile_menu_off]")
	return ..()

/client/Topic(href, href_list, hsrc)
	if(href_list["probe"])
		GLOB.pm_probes[href_list["probe"]] = href_list["value"]
		GLOB.pm_probes["[href_list["probe"]] at"] = PM_NOW
		return
	return ..()

/datum/controller/subsystem/statpanels/set_turf_tab(client/target)
	var/started = PM_NOW
	. = ..()
	GLOB.pm_tab_ms += PM_NOW - started

/proc/pm_watch()
	set waitfor = FALSE
	var/last = PM_NOW
	while(GLOB.pm_running)
		sleep(world.tick_lag)
		var/now = PM_NOW
		GLOB.pm_max_gap = max(GLOB.pm_max_gap, now - last)
		last = now

/proc/pm_gap_reset()
	GLOB.pm_max_gap = 0
	GLOB.pm_tab_ms = list()

/proc/pm_js(client/C, js)
	C << output(url_encode(js), "statbrowser:eval")

/proc/pm_wait_probe(name, seconds)
	var/deadline = world.time + seconds SECONDS
	while(!(name in GLOB.pm_probes) && world.time < deadline)
		sleep(world.tick_lag)
	return GLOB.pm_probes[name]

/// The panel tells the server each time it's taken in and drawn a tile list: rows, ms in the page, size of the message
/proc/pm_hook_panel(client/C)
	pm_js(C, {"(function () {
		if (window.kcHooked) return;
		window.kcHooked = true;
		window.kcDraws = 0;
		var original = byondMessage;
		byondMessage = function (raw) {
			if (raw.indexOf('update_listedturf') < 0) { original(raw); return; }
			var t = performance.now();
			original(raw);
			var ms = performance.now() - t;
			window.kcDraws++;
			var rows = document.querySelectorAll('.turf-item').length;
			var value = window.kcDraws + ' ' + rows + ' ' + ms.toFixed(1) + ' ' + raw.length + ' ' + Date.now();
			window.chrome.webview.postMessage('byond://?probe=draw' + window.kcDraws + '&value=' + encodeURIComponent(value));
		};
		window.chrome.webview.postMessage('byond://?probe=hooked&value=1');
	})();"})
	return pm_wait_probe("hooked", 10)

/proc/pm_floor()
	var/datum/turf_reservation/R = SSmapping.RequestBlockReservation(20, 20)
	var/x0 = R.bottom_left_coords[1]
	var/y0 = R.bottom_left_coords[2]
	var/z = R.bottom_left_coords[3]
	var/area/bot_gym/A = new
	for(var/turf/T in block(locate(x0, y0, z), locate(x0 + 19, y0 + 19, z)))
		var/area/old_area = T.loc
		old_area.contents -= T
		A.contents += T
		T.change_area(old_area, A)
		T.ChangeTurf(/turf/open/floor/plasteel, flags = CHANGETURF_IGNORE_AIR)
	return locate(x0 + 10, y0 + 10, z)

/proc/pm_fill(turf/T, count)
	var/static/list/kinds = list(/obj/item/crowbar, /obj/item/screwdriver, /obj/item/wrench, /obj/item/paper, /obj/item/pen,
		/obj/item/reagent_containers/food/drinks/soda_cans/cola, /obj/item/clothing/under/color/grey, /obj/item/clothing/shoes/sneakers/black,
		/obj/item/flashlight, /obj/item/storage/box, /obj/item/toy/crayon/red, /obj/item/reagent_containers/glass/beaker,
		/obj/item/bikehorn/rubberducky, /obj/item/trash/chips, /obj/item/wirecutters, /obj/item/weldingtool)
	for(var/atom/movable/AM as anything in T.contents.Copy())
		if(!ismob(AM))
			qdel(AM)
	for(var/i in 1 to count)
		var/kind = kinds[(i % kinds.len) + 1]
		new kind(T)
		if(i % 200 == 0)
			CHECK_TICK

/// One command to pile_menu.ps1, back when it's done: what it answered (a right-click: the wall clock ms it was pressed)
/proc/pm_command(text, seconds = 120)
	fdel("data/pm_cmd_done")
	text2file(text, "data/pm_cmd")
	var/deadline = world.time + seconds SECONDS
	while(!fexists("data/pm_cmd_done") && world.time < deadline)
		sleep(world.tick_lag)
	if(!fexists("data/pm_cmd_done"))
		kc_log("  (no answer from pile_menu.ps1 to: [text])")
		return null
	. = trim(file2text("data/pm_cmd_done"))
	fdel("data/pm_cmd_done")

/proc/pm_clear_draws(client/C)
	for(var/key in GLOB.pm_probes.Copy())
		if(findtext(key, "draw") == 1)
			GLOB.pm_probes -= key
	pm_js(C, "window.kcDraws = 0;")
	sleep(5)

/// A right-click on a pile over the limit: no BYOND menu, the tile list on the screen, nothing picked up or hit
/proc/pm_pile_right_click(client/C, mob/living/carbon/human/H, x, y, label)
	pm_clear_draws(C)
	pm_gap_reset()
	// The hover, as screentips.dm passes it on: posted moves get undone by the desktop's real cursor (pile_menu.ps1)
	var/turf/pile = get_step(H, EAST)
	C.check_pile_menu(pile.contents[length(pile.contents)])
	sleep(2)
	var/answer = pm_command("rclick [x] [y] [label] 2500 nomove")
	var/drawn = pm_wait_probe("draw1", 10)
	if(!drawn)
		kc_log("    no tile list in 10 s; longest stall [round(GLOB.pm_max_gap)] ms")
	else
		var/list/parts = splittext(drawn, " ")
		// Wall clock ms are past what a DM number holds exactly: the last six digits of each
		var/took = text2num(copytext(parts[5], -6)) - text2num(copytext(splittext(answer, " ")[1], -6))
		if(took < 0)
			took += 1000000
		kc_log("    tile list on the screen [took] ms after the press ([parts[2]] rows); longest stall [round(GLOB.pm_max_gap)] ms")
	GLOB.pm_debug = 0
	kc_log("    after: menu off [C.pile_menu_off], map right-click [winget(C, "mapwindow.map", "right-click")], listed [H.listed_turf]")
	var/obj/item/held = H.get_active_held_item() || H.get_inactive_held_item()
	if(held)
		kc_log("    WRONG: the right-click picked up [held]")
		qdel(held)
	H.listed_turf = null
	sleep(15)

/proc/pm_alt_click(client/C, mob/living/carbon/human/H, turf/pile, count)
	pm_clear_draws(C)
	pm_gap_reset()
	var/started = PM_NOW
	H.AltClickOn(pile)
	var/server_ms = PM_NOW - started
	var/drawn = pm_wait_probe("draw1", 60)
	if(!drawn)
		kc_log("  alt-click: server [round(server_ms)] ms, never drawn in 60 s")
	else
		var/list/parts = splittext(drawn, " ")
		var/end_ms = GLOB.pm_probes["draw1 at"] - started
		kc_log("  alt-click: on the screen in [round(end_ms)] ms (server [round(server_ms)] ms; page [parts[3]] ms for [parts[2]] rows, message [round(text2num(parts[4]) / 1024)] KB)")
	// Left open a while, as a player would
	pm_gap_reset()
	var/open_from = PM_NOW
	sleep(6 SECONDS)
	var/open_ms = PM_NOW - open_from
	var/list/tab_ms = GLOB.pm_tab_ms.Copy()
	var/total = 0
	var/most = 0
	for(var/ms in tab_ms)
		total += ms
		most = max(most, ms)
	var/draws = 0
	for(var/key in GLOB.pm_probes)
		if(findtext(key, "draw") == 1 && !findtext(key, " at"))
			draws++
	kc_log("  left open [round(open_ms / 1000, 0.1)] s: [length(tab_ms)] refreshes, [round(total)] ms on the server ([round(total / max(1, open_ms / 1000))] ms a second, longest [round(most)]), [draws] drawn, longest stall [round(GLOB.pm_max_gap)] ms")
	H.listed_turf = null
	sleep(15)

/proc/pile_menu_run(client/C)
	fdel("data/pm_cmd")
	fdel("data/pm_cmd_done")
	rustg_time_reset(PM_TIMER)
	pm_watch()
	var/turf/home = pm_floor()
	var/mob/living/carbon/human/H = new(home)
	H.status_flags |= GODMODE
	H.equipOutfit(/datum/outfit/bot_gym)
	C.mob = H
	var/turf/pile = locate(home.x + 1, home.y, home.z)
	sleep(30)
	var/deadline = world.time + 30 SECONDS
	while(!C.stat_panel?.is_ready() && world.time < deadline)
		sleep(5)
	kc_log("BYOND [C.byond_version].[C.byond_build], admin: [C.holder ? "yes" : "no"], panel ready: [C.stat_panel?.is_ready() ? "yes" : "no"], hooked: [pm_hook_panel(C) ? "yes" : "no"]")

	var/list/map_size = splittext(winget(C, "mapwindow.map", "size"), "x")
	var/wide = text2num(map_size[1])
	var/high = text2num(map_size[2])
	var/zoom = text2num(winget(C, "mapwindow.map", "zoom"))
	var/list/view_size = getviewsize(C.view)
	var/tile = zoom ? world.icon_size * zoom : min(wide / view_size[1], high / view_size[2])
	var/pile_x = round(wide / 2 + tile)
	var/pile_y = round(high / 2)
	text2file("map [wide] [high]\nprobe [round(wide / 2)] [round(high / 2 - 3 * tile)]", "data/keycheck_mouse_steps")
	text2file("go", "data/keycheck_sendkeys")
	deadline = world.time + 60 SECONDS
	while(!GLOB.pm_probed && world.time < deadline)
		sleep(5)
	if(!GLOB.pm_probed)
		kc_log("the map never took a click")
	else if(world.GetConfig("env", "PILE_VERBS"))
		pm_verb_prices(C, H, pile, pile_x, pile_y, text2num(world.GetConfig("env", "PILE_VERBS")))
	else if(world.GetConfig("env", "PILE_EXPERIMENT"))
		pm_experiment(C, H, pile, pile_x, pile_y, text2num(world.GetConfig("env", "PILE_EXPERIMENT")))
	else
		var/list/sizes = splittext(world.GetConfig("env", "PILE_SIZES") || "0,300,1500,4000", ",")
		for(var/size_text in sizes)
			var/count = text2num(size_text)
			pm_fill(pile, count)
			sleep(20)
			kc_log("pile of [count] ([length(pile.contents)] things on the tile):")
			for(var/i in 1 to 2)
				if(length(pile.contents) > 100) // stat_panel.dm PILE_MENU_LIMIT
					pm_pile_right_click(C, H, pile_x, pile_y, "[count]-[i]")
				else
					pm_gap_reset()
					pm_command("rclick [pile_x] [pile_y] [count]-[i] 90000")
					kc_log("    longest stall around it: [round(GLOB.pm_max_gap)] ms")
					sleep(10)
			// Off the pile: a right-click that beats its hover to the server does nothing and brings the menu back
			var/floor_x = round(wide / 2)
			var/floor_y = round(high / 2 + 2 * tile)
			if(C.pile_menu_off)
				pm_command("rclick [floor_x] [floor_y] floor-before-its-hover 3000 nomove")
				kc_log("    menu back on after it: [C.pile_menu_off ? "no" : "yes"]")
			C.check_pile_menu(locate(H.x, H.y - 2, H.z))
			sleep(2)
			pm_command("rclick [floor_x] [floor_y] floor-after-its-hover 10000 nomove")
			pm_alt_click(C, H, pile, count)
	pm_command("quit", 10)
	GLOB.pm_running = FALSE
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)

/proc/pm_rclicks(label, x, y, times = 2)
	for(var/i in 1 to times)
		pm_command("rclick [x] [y] [label]-[i]")
		sleep(10)

/// What the menu's time goes on: one pile, taken apart a piece at a time (PILE_EXPERIMENT=<count>)
/proc/pm_experiment(client/C, mob/living/carbon/human/H, turf/pile, x, y, count)
	pm_fill(pile, count)
	sleep(20)
	kc_log("experiment, pile of [count]:")
	pm_rclicks("as_is", x, y)
	var/n = 0
	for(var/obj/item/I in pile)
		I.name = "thing [++n]"
	sleep(50)
	pm_rclicks("all_names_different", x, y)
	for(var/obj/item/I in pile)
		I.name = "thing"
	sleep(50)
	pm_rclicks("all_one_name", x, y)
	for(var/obj/item/I in pile)
		I.name = initial(I.name)
	sleep(50)
	pm_rclicks("names_back", x, y)
	if(C.holder)
		C.remove_admin_verbs()
		sleep(20)
	pm_rclicks("no_admin_verbs", x, y)
	H.verbs -= /mob/verb/examinate
	sleep(20)
	pm_rclicks("no_Examine", x, y)
	H.verbs -= /mob/living/verb/pulled
	sleep(20)
	pm_rclicks("no_Pull", x, y)
	for(var/i in 1 to 5)
		H.verbs -= /mob/verb/pointed
	kc_log("  Point To still on the mob: [(/mob/verb/pointed in H.verbs) ? "yes" : "no"], on the client: [(/mob/verb/pointed in C.verbs) ? "yes" : "no"]")
	sleep(20)
	pm_rclicks("no_Point", x, y)
	for(var/obj/item/I in pile)
		I.verbs.Cut()
	sleep(20)
	pm_rclicks("no_item_verbs", x, y)
	n = 0
	for(var/obj/item/I in pile)
		if(++n > 100)
			I.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	sleep(20)
	pm_rclicks("100_clickable", x, y)
	n = 0
	for(var/obj/item/I in pile)
		I.mouse_opacity = MOUSE_OPACITY_ICON
		if(++n > 100)
			I.invisibility = INVISIBILITY_ABSTRACT
	sleep(20)
	pm_rclicks("100_seen", x, y)

/// Each kind of verb alone, on a pile of one name (PILE_VERBS=<count>)
/proc/pm_verb_prices(client/C, mob/living/carbon/human/H, turf/pile, x, y, count)
	pm_fill(pile, count)
	for(var/obj/item/I in pile)
		I.name = "thing"
	sleep(50)
	kc_log("verb prices, pile of [count] all called the same:")
	pm_rclicks("all", x, y, 1)
	var/list/item_verbs = list(/obj/item/verb/verb_pickup, /obj/item/verb/move_to_top)
	var/list/mob_verbs = list(/mob/verb/examinate, /mob/living/verb/pulled, /mob/verb/pointed)
	if(C.holder)
		C.remove_admin_verbs()
	H.verbs -= mob_verbs
	for(var/obj/item/I in pile)
		I.verbs -= item_verbs
	var/list/left = list()
	for(var/v in H.verbs + C.verbs)
		var/procpath/P = v
		if(findtext("[P]", "point") || findtext("[P]", "examin") || findtext("[P]", "pull"))
			left += "[P]"
	kc_log("  left: [jointext(left, ", ")]")
	sleep(20)
	pm_rclicks("none", x, y, 1)
	for(var/v in mob_verbs)
		H.verbs += v
		sleep(20)
		pm_rclicks("only_[v]", x, y, 1)
		H.verbs -= v
	for(var/obj/item/I in pile)
		I.verbs += /obj/item/verb/verb_pickup
	sleep(20)
	pm_rclicks("only_Pick_up", x, y, 1)
	for(var/obj/item/I in pile)
		I.verbs -= /obj/item/verb/verb_pickup
	if(C.holder)
		C.add_admin_verbs()
		sleep(20)
		pm_rclicks("only_admin", x, y, 1)
		C.remove_admin_verbs()
	var/n = 0
	for(var/obj/item/I in pile)
		I.name = "thing [++n]"
	sleep(50)
	pm_rclicks("none_names_different", x, y, 1)
	H.verbs += /mob/verb/examinate
	sleep(20)
	pm_rclicks("only_examine_names_different", x, y, 1)

#undef PM_TIMER
#undef PM_NOW
