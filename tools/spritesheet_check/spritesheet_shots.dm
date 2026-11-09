// Pictures, in a real client, of the windows that show spritesheet icons: R&D console (designs), vending (vending), crafting menu
// (crafting), uplink (uplink), RPD (pipes) and circuit printer (circuits). Not part of the game. Run through tools/keybind_check's
// run.sh with SENDER=shot.ps1; spritesheets=dm in the world params gives the old DM-built sheets for the "before" pictures.
// Pictures in data/previews/popup_sheets_<label>_<n>.png (label from data/sheet_shots_label), notes in data/keycheck.txt.

GLOBAL_VAR_INIT(keycheck_running, FALSE)

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
			sheet_shots_run(src)

/proc/sheet_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// Opens a window, places it, takes its picture, closes it
/proc/sheet_window(client/C, mob/living/carbon/human/H, datum/thing, label, name, list/actions)
	thing.ui_interact(H)
	sleep(4 SECONDS)
	var/datum/tgui/ui
	for(var/datum/tgui/open as anything in H.open_uis)
		if(open.src_object == thing)
			ui = open
	if(!ui)
		kc_log("FAIL [name]: no window opened")
		return
	winset(C, ui.window_id, "pos=200,100")
	for(var/action in actions)
		C << output(url_encode(action), "[ui.window_id].browser:eval")
		sleep(1 SECONDS)
	sleep(1 SECONDS)
	sheet_shot("popup_sheets_[label]_[name]")
	kc_log("shot [name]")
	SStgui.close_uis(thing)
	sleep(1 SECONDS)

/proc/sheet_shots_run(client/C)
	var/label = trim(file2text("data/sheet_shots_label")) || "now"
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	UNTIL(!SSassets.can_fire) // the after-init sheets are made
	kc_log("spritesheets [spritesheet_mode()]: [GLOB.spritesheet_counts["forge"]] by iconforge, [GLOB.spritesheet_counts["dm"]] by DM, [round(GLOB.spritesheet_main_ms)] ms on the main thread")
	sleep(2 SECONDS)
	var/turf/home = get_turf(pick(SSjob.latejoin_trackers))
	var/mob/living/carbon/human/H = new(home)
	H.mind_initialize()
	H.status_flags |= GODMODE
	H.equipOutfit(/datum/outfit/job/scientist)
	H.ckey = C.ckey
	sleep(3 SECONDS)
	var/turf/at = get_step(H, EAST)

	// R&D console with its lathe, so the protolathe page lists designs with their icons
	var/obj/machinery/rnd/production/protolathe/lathe = new(get_step(at, NORTH))
	var/obj/machinery/computer/rdconsole/core/console = new(at)
	for(var/obj/machinery/M in list(lathe, console))
		M.stat &= ~(NOPOWER|BROKEN)
	var/datum/techweb/web = SSresearch.science_tech
	web.add_point_list(list(TECHWEB_POINT_TYPE_GENERIC = 12500))
	for(var/id in list("engineering", "datatheory", "high_efficiency", "adv_engi", "basic_tools"))
		if(SSresearch.techweb_node_by_id(id))
			web.research_node_id(id, TRUE)
	lathe.update_research()
	var/click_protolathe = "var b=Array.prototype.slice.call(document.querySelectorAll('.Button')).filter(function(e){return e.textContent.trim().indexOf('Protolathe')===0;})\[0\];if(b){b.click();}"
	sheet_window(C, H, console, label, "1_rd_nodes")
	sheet_window(C, H, console, label, "2_rd_protolathe", list(click_protolathe))
	qdel(console)
	qdel(lathe)

	var/obj/machinery/vending/clothing/vendor = new(at)
	vendor.stat &= ~(NOPOWER|BROKEN)
	sheet_window(C, H, vendor, label, "3_vending")
	qdel(vendor)

	var/datum/component/personal_crafting/crafting = H.GetComponent(/datum/component/personal_crafting)
	if(crafting)
		sheet_window(C, H, crafting, label, "4_crafting")
	else
		kc_log("FAIL crafting: no crafting component")

	var/obj/item/uplink/radio = new(H.loc)
	H.put_in_hands(radio) // the uplink's window only stays open for something held
	var/datum/component/uplink/uplink = radio.GetComponent(/datum/component/uplink)
	if(uplink)
		uplink.locked = FALSE
		uplink.telecrystals = 20
		sheet_window(C, H, uplink, label, "5_uplink")
	else
		kc_log("FAIL uplink: no uplink component")
	qdel(radio)

	var/obj/item/pipe_dispenser/rpd = new(H.loc)
	H.put_in_hands(rpd)
	sheet_window(C, H, rpd, label, "6_rpd")
	qdel(rpd)

	var/obj/item/integrated_circuit_printer/printer = new(H.loc)
	H.put_in_hands(printer)
	sheet_window(C, H, printer, label, "7_circuit_printer")
	qdel(printer)

	text2file("done", "data/keycheck_shots_done")
	kc_log("done")
	sleep(10)
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
