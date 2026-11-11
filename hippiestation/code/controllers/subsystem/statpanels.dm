// The stat panel's sender (tg's SSstatpanels, tgstation master ceb0ca2410d4b2bbade05f61a661ebdd684c0e79). Each player's open tab
// is sent at its own pace, and only that tab: Status every second, MC every second, Tickets and queries every 2 s, the
// alt-clicked tile twice a second, spells and gear tabs when they change, verbs when they change (checked every 2 s).
// The old panel called every mob's Stat() about five times a second for every player, whatever tab was open.

#ifndef FIRE_PRIORITY_STATPANEL
#define FIRE_PRIORITY_STATPANEL 390
#endif

/// How many seconds of CPU, map CPU, time dilation and each subsystem's time the MC tab draws
#define MC_HISTORY_LENGTH 120

/// What a subsystem's stat_entry() made last, for the MC tab
/datum/controller/subsystem
	var/stat_text
	/// The subsystem's own part of it, without the cost figures in front
	var/stat_extra
	/// The ms it ran in each of the last MC_HISTORY_LENGTH seconds, oldest first (from total_ms), for the MC tab's row detail
	var/list/mc_ms_history
	/// total_ms at the last of those samples
	var/mc_last_total_ms = 0

SUBSYSTEM_DEF(statpanels)
	name = "Stat Panels"
	wait = 5
	priority = FIRE_PRIORITY_STATPANEL
	flags = SS_NO_INIT
	runlevels = RUNLEVELS_DEFAULT | RUNLEVEL_LOBBY
	var/list/currentrun = list()
	/// The round at the top of Status, the same for everybody (make_global_data())
	var/list/global_data
	/// The MC tab, made once a fire if anybody's looking at it
	var/list/mc_data
	/// The last MC_HISTORY_LENGTH seconds of CPU, map CPU and time dilation, oldest first, kept whether anyone looks or not
	var/list/mc_history = list(list(), list(), list())
	/// REALTIMEOFDAY at the last sample, to turn each subsystem's total_ms into ms a second
	var/mc_last_sample = 0
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
		if(num_fires % mc_wait == 0)
			sample_mc_history()
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

/// The round, the same for everybody: the top of Status (statbrowser.js draw_status()). Shuttle is its mode code (ETA, ETD,
/// ESC, RCL...) and timer; start, in the lobby, is seconds to the start or "DELAYED"/"SOON".
/datum/controller/subsystem/statpanels/proc/make_global_data()
	global_data = list(
		"map" = SSmapping.config?.map_name || "Loading...",
		"next_map" = SSmapping.next_map_config?.map_name,
		"round_id" = GLOB.round_id ? "[GLOB.round_id]" : null,
		"server_time" = time2text(world.timeofday, "YYYY-MM-DD hh:mm:ss"),
		"round_time" = SSticker.round_start_time ? gameTimestamp("hh:mm:ss", world.time - SSticker.round_start_time) : null,
		"station_time" = station_time_timestamp(),
		"tidi" = list(round(SStime_track.time_dilation_current, 1), round(SStime_track.time_dilation_avg_fast, 1), round(SStime_track.time_dilation_avg, 1), round(SStime_track.time_dilation_avg_slow, 1)),
	)
	if(SSshuttle.emergency)
		var/mode = SSshuttle.emergency.getModeStr()
		if(mode)
			global_data["shuttle"] = list(mode, SSshuttle.emergency.getTimerStr())
	if(!SSticker.HasRoundStarted())
		var/time_left = SSticker.GetTimeLeft()
		global_data["start"] = time_left > 0 ? round(time_left / 10) : (time_left == -10 ? "DELAYED" : "SOON")
		global_data["players"] = SSticker.totalPlayers

/// Status: the round, their ahelp and question (help_window.dm), then what their mob says about itself (get_status_tab_items())
/datum/controller/subsystem/statpanels/proc/set_status_tab(client/target)
	if(!global_data)
		make_global_data()
	var/list/info = global_data.Copy()
	info["ping"] = list(round(target.lastping, 1), round(target.avgping, 1))
	if(istype(target.mob, /mob/dead)) // the lobby and ghosts were always told the mode
		info["mode"] = SSticker.hide_mode ? "Secret" : "[GLOB.master_mode]"
	if(info["start"] && target.holder)
		info["ready"] = SSticker.totalPlayersReady
	var/list/mine = target.mob?.get_status_tab_items() || list()
	target.stat_panel.send_message("update_stat", list("round" = info, "help" = help_status_lines(target), "items" = mine))

/datum/controller/subsystem/statpanels/proc/set_MC_tab(client/target)
	if(!mc_data)
		generate_mc_data()
	var/turf/eye_turf = get_turf(target.eye)
	var/list/payload = list("mc" = mc_data, "loc" = COORD(eye_turf))
	var/open = target.stat_panel.mc_detail
	if(open)
		for(var/datum/controller/subsystem/sub_system as anything in Master?.subsystems)
			if("[sub_system.type]" == open)
				payload["detail"] = mc_detail(sub_system)
				break
	target.stat_panel.send_message("update_mc", payload)

/// The row an admin opened on the MC tab: type, ms a second over the last MC_HISTORY_LENGTH seconds, wait (ds), priority, fires,
/// next fire in (ds), last fire ago (ds), init order, the flags that change how it's run
/datum/controller/subsystem/statpanels/proc/mc_detail(datum/controller/subsystem/sub_system)
	var/list/flag_names = list()
	if(sub_system.flags & SS_TICKER)
		flag_names += "ticker"
	if(sub_system.flags & SS_BACKGROUND)
		flag_names += "background"
	if(sub_system.flags & SS_NO_TICK_CHECK)
		flag_names += "no tick check"
	if(sub_system.flags & SS_KEEP_TIMING)
		flag_names += "keep timing"
	if(sub_system.flags & SS_POST_FIRE_TIMING)
		flag_names += "post-fire timing"
	if(sub_system.idle_check)
		flag_names += "idle check"
	var/firing = !(sub_system.flags & SS_NO_FIRE) && sub_system.can_fire
	return list("[sub_system.type]", sub_system.mc_ms_history || list(), sub_system.wait, sub_system.priority, sub_system.times_fired,
		firing ? max(0, sub_system.next_fire - world.time) : null, sub_system.last_fire ? world.time - sub_system.last_fire : null,
		sub_system.init_order, jointext(flag_names, ", "))

/datum/controller/subsystem/statpanels/proc/sample_mc_history()
	var/list/now = list(round(world.cpu, 0.1), round(world.map_cpu, 0.1), round(SStime_track.time_dilation_current, 0.1))
	for(var/i in 1 to 3)
		var/list/series = mc_history[i]
		series += now[i]
		if(length(series) > MC_HISTORY_LENGTH)
			series.Cut(1, 2)
	// Each subsystem's ms in the second just gone, from what the MC has counted it running (total_ms)
	var/now_real = REALTIMEOFDAY
	var/seconds = mc_last_sample ? (now_real - mc_last_sample) / 10 : 0
	mc_last_sample = now_real
	for(var/datum/controller/subsystem/sub_system as anything in Master?.subsystems)
		if(sub_system.flags & SS_NO_FIRE)
			continue
		var/ms = sub_system.total_ms - sub_system.mc_last_total_ms
		sub_system.mc_last_total_ms = sub_system.total_ms
		if(seconds <= 0) // the first sample, or over midnight
			continue
		if(!sub_system.mc_ms_history)
			sub_system.mc_ms_history = list()
		var/list/series = sub_system.mc_ms_history
		series += round(ms / seconds, 0.01)
		if(length(series) > MC_HISTORY_LENGTH)
			series.Cut(1, 2)

/// The MC tab: numbers rather than lines of text, so the panel can lay them out, sort the subsystems and draw the history.
/// A subsystem is a list, not keyed, to keep the message small (it goes to each admin on the tab every second):
/// name, state letter, cost ms, tick %, overrun %, ticks a run, its own text, ref, status, type, wait (ds).
/// Status: "" fires as usual, "nofire" never fires (SS_NO_FIRE), "off" turned off (can_fire), "asleep" its fire() hasn't come
/// back (the watchdog warned), or a number: taken offline by the watchdog, back on in that many seconds (0: until an admin).
/datum/controller/subsystem/statpanels/proc/generate_mc_data()
	var/ticks_so_far = world.time / world.tick_lag
	mc_data = list(
		"cpu" = round(world.cpu, 0.1),
		"map_cpu" = round(world.map_cpu, 0.1),
		"tidi" = round(SStime_track.time_dilation_current, 0.1),
		"tidi_avg" = list(round(SStime_track.time_dilation_avg_fast, 0.1), round(SStime_track.time_dilation_avg, 0.1), round(SStime_track.time_dilation_avg_slow, 0.1)),
		"drift" = round(Master?.tickdrift, 1),
		"drift_pct" = ticks_so_far ? round(Master?.tickdrift / ticks_so_far * 100, 0.1) : 0,
		"fps" = world.fps,
		"tick" = round(ticks_so_far),
		"time" = world.time,
		"instances" = length(world.contents),
		"history" = mc_history,
		"globals" = REF(GLOB),
		"config" = REF(config),
		"cameras" = list(length(GLOB.cameranet.cameras), length(GLOB.cameranet.chunks), REF(GLOB.cameranet)),
	)
	if(Master)
		mc_data["mc"] = list(Master.processing, Master.iteration, round(Master.current_ticklimit, 0.1), REF(Master))
	if(Failsafe)
		mc_data["failsafe"] = list(Failsafe.defcon, Failsafe.processing_interval, Failsafe.master_iteration, REF(Failsafe))
	if(MCWatchdog) // hippie (mc_watchdog.dm)
		var/ago = MCWatchdog.freeze_count ? round((world.time - MCWatchdog.last_freeze_time) / 600) : null
		mc_data["watchdog"] = list(MCWatchdog.freeze_count, MCWatchdog.lag_count, MCWatchdog.last_freeze_secs, ago, MCWatchdog.profiling_for ? 1 : 0, REF(MCWatchdog))
	var/list/subsystems = list()
	for(var/datum/controller/subsystem/sub_system as anything in Master?.subsystems)
		sub_system.stat_entry()
		var/status = ""
		if(sub_system.flags & SS_NO_FIRE)
			status = "nofire"
		else if(sub_system.watchdog_offline)
			status = sub_system.watchdog_offline > 0 ? max(1, round((sub_system.watchdog_offline - world.time) / 10)) : 0
		else if(!sub_system.can_fire)
			status = "off"
		else if(sub_system.asleep_warned)
			status = "asleep"
		subsystems[++subsystems.len] = list(sub_system.name, trim(sub_system.state_letter()), round(sub_system.cost, 0.01), round(sub_system.tick_usage, 0.1), round(sub_system.tick_overrun, 0.1), round(sub_system.ticks, 0.1), "[sub_system.stat_extra]", REF(sub_system), status, "[sub_system.type]", sub_system.wait)
	mc_data["subsystems"] = subsystems

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

#undef MC_HISTORY_LENGTH
