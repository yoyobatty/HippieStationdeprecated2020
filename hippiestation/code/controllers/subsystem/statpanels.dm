// The stat panel's sender (tg's SSstatpanels, tgstation master ceb0ca2410d4b2bbade05f61a661ebdd684c0e79). Each player's open tab
// is sent at its own pace, and only that tab: Status every second, MC every second, Tickets and queries every 2 s, the
// alt-clicked tile twice a second, spells and gear tabs when they change, verbs when they change (checked every 2 s).
// The old panel called every mob's Stat() about five times a second for every player, whatever tab was open.

#ifndef FIRE_PRIORITY_STATPANEL
#define FIRE_PRIORITY_STATPANEL 390
#endif

/// What a subsystem's stat_entry() made last, for the MC tab
/datum/controller/subsystem
	var/stat_text

SUBSYSTEM_DEF(statpanels)
	name = "Stat Panels"
	wait = 5
	priority = FIRE_PRIORITY_STATPANEL
	flags = SS_NO_INIT
	runlevels = RUNLEVELS_DEFAULT | RUNLEVEL_LOBBY
	var/list/currentrun = list()
	/// The round's lines at the top of Status, the same for everybody
	var/list/global_data
	/// The MC tab, made once a fire if anybody's looking at it
	var/list/mc_data
	/// How many fires so far, for the slower tabs
	var/num_fires = 0
	/// Fires between Status updates, MC updates, the slower tabs and verb checks
	var/status_wait = 2
	var/mc_wait = 2
	var/default_wait = 4
	/// Icons for the tile list as data URIs, by icon, state and direction
	var/list/turf_icons = list()

/datum/controller/subsystem/statpanels/stat_entry(msg)
	return ..("P:[length(GLOB.clients)]")

/datum/controller/subsystem/statpanels/fire(resumed = FALSE)
	if(!resumed)
		num_fires++
		make_global_data()
		mc_data = null
		src.currentrun = GLOB.clients.Copy()

	var/list/currentrun = src.currentrun
	while(length(currentrun))
		var/client/target = currentrun[length(currentrun)]
		currentrun.len--
		if(!target?.stat_panel?.is_ready())
			continue
		update_client(target)
		if(MC_TICK_CHECK)
			return

/datum/controller/subsystem/statpanels/proc/update_client(client/target)
	var/datum/stat_panel/panel = target.stat_panel
	var/tab = panel.tab
	var/mob/viewer = target.mob

	if(tab == "Status" && num_fires % status_wait == 0)
		set_status_tab(target)

	// The tile you alt-clicked, while you're next to it (and gone if you're in another body now, which has none)
	if(viewer?.listed_turf)
		if(!viewer.TurfAdjacent(viewer.listed_turf))
			viewer.listed_turf = null
			panel.turf_shown = FALSE
			panel.clickable_turf = list()
			panel.send_message("remove_listedturf")
		else if(tab == viewer.listed_turf.name)
			set_turf_tab(target)
	else if(panel.turf_shown)
		panel.turf_shown = FALSE
		panel.clickable_turf = list()
		panel.send_message("remove_listedturf")

	if(num_fires % status_wait == 0 && viewer)
		set_spells(target)
		set_extra_tabs(target)

	if(num_fires % default_wait == 0)
		var/list/verbs_now = target.stat_panel_verbs()
		if(!(verbs_now ~= panel.sent_verbs))
			target.init_verbs()

	if(!target.holder)
		if(panel.admin_tabs)
			panel.admin_tabs = FALSE
			panel.clickable_admin = list()
			panel.send_message("remove_admin_tabs")
		return
	if(!panel.admin_tabs)
		panel.admin_tabs = TRUE
		panel.send_message("add_admin_tabs", target.holder.href_token)
	if(tab == "MC" && num_fires % mc_wait == 0)
		set_MC_tab(target)
	if(tab == "Tickets" && num_fires % default_wait == 0)
		set_tickets_tab(target)
	if(num_fires % default_wait == 0)
		if(length(GLOB.sdql2_queries))
			if(tab == "SDQL2" || !panel.clickable_admin["sdql2"])
				set_SDQL2_tab(target)
		else if(panel.clickable_admin["sdql2"])
			panel.clickable_admin -= "sdql2"
			panel.send_message("remove_sdql2")

/datum/controller/subsystem/statpanels/proc/make_global_data()
	global_data = list("Map: [SSmapping.config?.map_name || "Loading..."]")
	var/datum/map_config/cached = SSmapping.next_map_config
	if(cached)
		global_data += "Next Map: [cached.map_name]"
	global_data += "Round ID: [GLOB.round_id ? GLOB.round_id : "NULL"]"
	global_data += "Server Time: [time2text(world.timeofday, "YYYY-MM-DD hh:mm:ss")]"
	if(SSticker.round_start_time)
		global_data += "Round Time: [gameTimestamp("hh:mm:ss", (world.time - SSticker.round_start_time))]"
	else
		global_data += "Lobby Time: [gameTimestamp("hh:mm:ss", 0)]"
	global_data += "Station Time: [station_time_timestamp()]"
	global_data += "Time Dilation: [round(SStime_track.time_dilation_current,1)]% AVG:([round(SStime_track.time_dilation_avg_fast,1)]%, [round(SStime_track.time_dilation_avg,1)]%, [round(SStime_track.time_dilation_avg_slow,1)]%)"
	if(SSshuttle.emergency)
		var/ETA = SSshuttle.emergency.getModeStr()
		if(ETA)
			global_data += "[ETA]: [SSshuttle.emergency.getTimerStr()]"

/datum/controller/subsystem/statpanels/proc/set_status_tab(client/target)
	if(!global_data)
		make_global_data()
	var/list/lines = list("Ping: [round(target.lastping, 1)] ms (average [round(target.avgping, 1)] ms)") + help_status_lines(target) + global_data // hippie -- their ahelp and question (help_window.dm)
	var/list/mine = target.mob?.get_status_tab_items()
	if(length(mine))
		lines += ""
		lines += mine
	target.stat_panel.send_message("update_stat", list("global_data" = lines, "other_str" = list()))

/datum/controller/subsystem/statpanels/proc/set_MC_tab(client/target)
	if(!mc_data)
		generate_mc_data()
	var/turf/eye_turf = get_turf(target.eye)
	target.stat_panel.send_message("update_mc", list("mc_data" = mc_data, "coord_entry" = COORD(eye_turf)))

/datum/controller/subsystem/statpanels/proc/generate_mc_data()
	mc_data = list(
		list("", "CPU:", "[world.cpu]"),
		list("", "Instances:", "[num2text(world.contents.len, 10)]"),
		list("", "World Time:", "[world.time]"),
		list("", "Globals:", "Edit", REF(GLOB)),
		list("", "[config]:", "Edit", REF(config)),
		list("", "Byond:", "(FPS:[world.fps]) (TickCount:[world.time/world.tick_lag]) (TickDrift:[round(Master.tickdrift,1)]([round((Master.tickdrift/(world.time/world.tick_lag))*100,0.1)]%)) (Internal Tick Usage: [round(MAPTICK_LAST_INTERNAL_TICK_USAGE,0.1)]%)"),
		list("", "Master Controller:", Master ? "(TickRate:[Master.processing]) (Iteration:[Master.iteration]) (TickLimit: [round(Master.current_ticklimit, 0.1)])" : "ERROR", Master ? REF(Master) : null),
		list("", "Failsafe Controller:", Failsafe ? "Defcon: [Failsafe.defcon_pretty()] (Interval: [Failsafe.processing_interval] | Iteration: [Failsafe.master_iteration])" : "ERROR", Failsafe ? REF(Failsafe) : null),
		list("", "Watchdog:", MCWatchdog ? MCWatchdog.stat_line() : "not running", MCWatchdog ? REF(MCWatchdog) : null), // hippie (mc_watchdog.dm)
		list("", "", ""),
	)
	if(Master)
		for(var/datum/controller/subsystem/sub_system as anything in Master.subsystems)
			sub_system.stat_entry()
			mc_data[++mc_data.len] = list("\[[sub_system.state_letter()]]", sub_system.name, sub_system.stat_text, REF(sub_system))
	mc_data[++mc_data.len] = list("", GLOB.cameranet.name, "Cameras: [GLOB.cameranet.cameras.len] | Chunks: [GLOB.cameranet.chunks.len]", REF(GLOB.cameranet))

/datum/controller/subsystem/statpanels/proc/set_tickets_tab(client/target)
	var/datum/admin_help_tickets/tickets = GLOB.ahelp_tickets
	var/datum/stat_panel/panel = target.stat_panel
	var/list/entries = list()
	var/list/clickable = panel.clickable_admin
	entries[++entries.len] = list("Admin hub:", admin_hub_stat_text(target), null, ticket_click(GLOB.admin_hub_statclick, clickable)) // admin_hub.dm
	entries[++entries.len] = list("Active Tickets:", "[tickets.active_tickets.len]", null, ticket_click(tickets.astatclick, clickable))
	var/num_disconnected = 0
	for(var/datum/admin_help/AH as anything in tickets.active_tickets)
		if(AH.initiator)
			entries[++entries.len] = list("#[AH.id]. [AH.initiator_key_name]:", AH.name, null, ticket_click(AH.statclick, clickable))
		else
			++num_disconnected
	if(num_disconnected)
		entries[++entries.len] = list("Disconnected:", "[num_disconnected]", null, ticket_click(tickets.astatclick, clickable))
	entries[++entries.len] = list("Closed Tickets:", "[tickets.closed_tickets.len]", null, ticket_click(tickets.cstatclick, clickable))
	entries[++entries.len] = list("Resolved Tickets:", "[tickets.resolved_tickets.len]", null, ticket_click(tickets.rstatclick, clickable))
	panel.send_message("update_tickets", entries)

/datum/controller/subsystem/statpanels/proc/ticket_click(obj/effect/statclick/click, list/clickable)
	if(!click)
		return null
	clickable[REF(click)] = TRUE
	return "src=[REF(click)];statpanel_item_click=left"

/datum/controller/subsystem/statpanels/proc/set_SDQL2_tab(client/target)
	var/datum/stat_panel/panel = target.stat_panel
	var/list/clickable = panel.clickable_admin
	clickable["sdql2"] = TRUE
	clickable[REF(GLOB.sdql2_vv_statobj)] = TRUE
	var/list/entries = list(list("", "Access Global SDQL2 List", REF(GLOB.sdql2_vv_statobj)))
	for(var/datum/SDQL2_query/query as anything in GLOB.sdql2_queries)
		entries += query.stat_panel_entries(clickable)
	panel.send_message("update_sdql2", entries)

/datum/SDQL2_query/proc/stat_panel_entries(list/clickable)
	. = list()
	if(!allow_admin_interact)
		return
	if(!delete_click)
		delete_click = new(null, "INITIALIZING", src)
	if(!action_click)
		action_click = new(null, "INITIALIZNG", src)
	delete_click.update("DELETE QUERY | STATE : [text_state()] | ALL/ELIG/FIN \
	[islist(obj_count_all)? length(obj_count_all) : (isnull(obj_count_all)? "0" : obj_count_all)]/\
	[islist(obj_count_eligible)? length(obj_count_eligible) : (isnull(obj_count_eligible)? "0" : obj_count_eligible)]/\
	[islist(obj_count_finished)? length(obj_count_finished) : (isnull(obj_count_finished)? "0" : obj_count_finished)] - [get_query_text()]")
	action_click.update("[SDQL2_IS_RUNNING? "HALT" : "RUN"]")
	clickable[REF(delete_click)] = TRUE
	clickable[REF(action_click)] = TRUE
	. += list(list("[id]", delete_click.name, REF(delete_click)))
	. += list(list("", action_click.name, REF(action_click)))

/// The alt-clicked tile's contents: what the old panel listed (no mouse-transparent, hidden or covered things), each with its icon
/datum/controller/subsystem/statpanels/proc/set_turf_tab(client/target)
	var/mob/viewer = target.mob
	var/turf/listed = viewer?.listed_turf
	if(!listed)
		return
	var/datum/stat_panel/panel = target.stat_panel
	var/list/clickable = list()
	var/list/overrides = list()
	for(var/image/I in target.images)
		if(I.loc && I.loc.loc == listed && I.override)
			overrides += I.loc
	var/list/contents = list(list(listed.name, REF(listed), turf_icon(listed)))
	clickable[REF(listed)] = TRUE
	for(var/atom/A as anything in listed)
		if(!A.mouse_opacity)
			continue
		if(A.invisibility > viewer.see_invisible)
			continue
		if(overrides.len && (A in overrides))
			continue
		if(A.IsObscured())
			continue
		contents[++contents.len] = list(A.name, REF(A), turf_icon(A))
		clickable[REF(A)] = TRUE
	panel.clickable_turf = clickable
	panel.send_message("update_listedturf", contents)

/// An atom's icon for the tile list, as a data URI: its own icon and state, facing as it is. Mobs' own icons are mostly blank
/// (they're drawn from overlays), so a mob gets its flattened picture, kept a few seconds.
/datum/controller/subsystem/statpanels/proc/turf_icon(atom/A)
	var/key
	if(ismob(A))
		key = "[REF(A)]-[round(world.time, 50)]"
	else
		key = "[A.icon]|[A.icon_state]|[A.dir]"
	. = turf_icons[key]
	if(!isnull(.))
		return
	if(length(turf_icons) > 1000)
		turf_icons.Cut()
	var/icon/picture
	if(ismob(A))
		picture = getFlatIcon(A, no_anim = TRUE)
	else if(A.icon)
		picture = icon(A.icon, A.icon_state, A.dir, 1, FALSE)
	. = picture ? "data:image/png;base64,[icon2base64(picture)]" : ""
	turf_icons[key] = .

/datum/controller/subsystem/statpanels/proc/set_spells(client/target)
	var/datum/stat_panel/panel = target.stat_panel
	var/list/clickable = list()
	var/list/spells = target.mob.get_stat_panel_spells(clickable)
	var/text = json_encode(spells)
	panel.clickable_spells = clickable
	if(text == panel.sent_spells)
		return
	panel.sent_spells = text
	panel.send_message("update_spells", spells)

/datum/controller/subsystem/statpanels/proc/set_extra_tabs(client/target)
	var/datum/stat_panel/panel = target.stat_panel
	var/list/tabs = target.mob.get_stat_panel_extra_tabs() || list()
	var/text = json_encode(tabs)
	if(text == panel.sent_extra)
		return
	panel.sent_extra = text
	panel.send_message("update_extra", tabs)

/// The open tab now, after the player picked it
/datum/controller/subsystem/statpanels/proc/immediate_send_stat_data(client/target)
	if(!target?.stat_panel?.is_ready())
		return FALSE
	var/tab = target.stat_panel.tab
	if(tab == "Status")
		set_status_tab(target)
		return TRUE
	if(target.mob?.listed_turf && tab == target.mob.listed_turf.name)
		set_turf_tab(target)
		return TRUE
	if(!target.holder)
		return FALSE
	if(tab == "MC")
		set_MC_tab(target)
		return TRUE
	if(tab == "Tickets")
		set_tickets_tab(target)
		return TRUE
	if(tab == "SDQL2" && length(GLOB.sdql2_queries))
		set_SDQL2_tab(target)
		return TRUE
	return FALSE
