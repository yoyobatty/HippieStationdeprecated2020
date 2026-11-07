// Alerts: what admins want to know the moment it happens, without reading every line of admin chat. The user's tooling plan,
// stage 2 (2026-11-07), for a bigger admin team with new admins. Each alert is a line in admin chat with buttons, a row in the
// Alerts window (tgui-next AdminAlerts.js) where an admin says they're on it, and a message to Discord's admin channel (through
// TGS): every alert, by the user's ruling, unless a +SERVER admin changes it in the window. The rules:
//	Kill       a player killed by one who isn't an antagonist, unless the dead one was: their job, how new, whether both fought
//	Deaths     four or more players dead within two minutes, and where
//	Explosion  a big one on the station, and the last bomb line near it
//	Engine     a singularity or tesla out of its cage; the supermatter past its emergency point
//	Gas        a canister of plasma or another dangerous gas opened into the air
//	Emag       an emag used by someone who isn't an antagonist
//	Ticket     an ahelp waiting three minutes for an answer with admins on
// An admin can mute a kind in their own chat; the window keeps every alert. Most rules read the round log (round_log.dm) as it's
// written, so they sit here and not in the code they watch.

#define ALERTS_KEPT 200

GLOBAL_LIST_INIT(admin_alert_kinds, list(
	"kill" = "Kill",
	"deaths" = "Deaths",
	"boom" = "Explosion",
	"engine" = "Engine",
	"gas" = "Gas",
	"emag" = "Emag",
	"ticket" = "Ticket",
))

/// Where each admin's muted kinds are kept (a check run points it elsewhere)
GLOBAL_VAR_INIT(admin_alert_mutes_path, "data/admin_alert_mutes.json")

/datum/admin_alert
	var/id
	var/kind
	var/time
	var/text
	/// Red if it's bad, amber if it wants a look
	var/bad = FALSE
	var/area_name
	var/x
	var/y
	var/z
	var/datum/weakref/actor
	var/actor_name
	var/actor_ckey
	var/datum/weakref/target
	var/target_name
	var/target_ckey
	var/ticket_id
	/// The same thing again within a while is counted here, not alerted twice
	var/merge_key
	var/count = 1
	/// The admin who said they're on it: their key as shown, and their ckey
	var/handled_by
	var/handled_ckey

SUBSYSTEM_DEF(admin_alerts)
	name = "Admin Alerts"
	wait = 2 SECONDS
	flags = SS_BACKGROUND
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	var/list/alerts = list()
	var/next_id = 0
	/// The round log's last line read
	var/last_log_id = 0
	/// Player deaths lately: list(time, area)
	var/list/recent_deaths = list()
	var/last_deaths_alert = -INFINITY
	var/next_slow_check = 0
	var/engine_alerted = FALSE
	var/supermatter_alerted = FALSE
	/// ticket id = the waiting_since it was alerted for
	var/list/ticket_waits_alerted = list()
	/// ckey = list(kind = TRUE): kinds that admin doesn't get in chat
	var/list/mutes
	/// When Discord's admin channel gets alerts: "always" (the user's ruling, 2026-11-07), "adminless" (no admin on to see them,
	/// as with ahelps) or "never". Admins with +SERVER change it in the Alerts window.
	var/discord_mode = "always"

/datum/controller/subsystem/admin_alerts/Initialize(start_timeofday)
	RegisterSignal(SSdcs, COMSIG_GLOB_EXPLOSION, PROC_REF(on_explosion))
	return ..()

/datum/controller/subsystem/admin_alerts/stat_entry(msg)
	return ..("[alerts.len] alerts")

/datum/controller/subsystem/admin_alerts/fire(resumed)
	read_log()
	if(world.time >= next_slow_check)
		next_slow_check = world.time + 10 SECONDS
		check_engines()
		check_tickets()

/datum/controller/subsystem/admin_alerts/proc/read_log()
	var/list/log = GLOB.round_log
	if(!log.len)
		return
	var/first_id = log[1][RL_ID]
	for(var/i in max(1, last_log_id - first_id + 2) to log.len)
		var/list/entry = log[i]
		last_log_id = entry[RL_ID]
		switch(entry[RL_CAT])
			if("Death")
				saw_death(entry, i)
			if("Admin")
				if(findtext(entry[RL_TEXT], " opened a canister that contains the following at "))
					saw_canister(entry, i)
		if(MC_TICK_CHECK)
			return

////////////////////
// The rules
////////////////////

/datum/controller/subsystem/admin_alerts/proc/saw_death(list/entry, index)
	if(!entry[RL_CKEY])
		return
	var/datum/weakref/victim_ref = entry[RL_REF]
	var/mob/living/victim = victim_ref?.resolve()
	var/turf/where = entry[RL_Z] ? locate(entry[RL_X], entry[RL_Y], entry[RL_Z]) : null
	// many dead at once
	recent_deaths += list(list(entry[RL_TIME], entry[RL_AREA] || "somewhere"))
	while(recent_deaths.len && recent_deaths[1][1] < world.time - 2 MINUTES)
		recent_deaths.Cut(1, 2)
	if(recent_deaths.len >= 4 && world.time > last_deaths_alert + 5 MINUTES)
		last_deaths_alert = world.time
		var/list/areas = list()
		for(var/list/death in recent_deaths)
			areas[death[2]]++
		var/list/bits = list()
		for(var/area_name in areas)
			bits += areas[area_name] > 1 ? "[area_name] x[areas[area_name]]" : area_name
		raise("deaths", "[recent_deaths.len] players dead in 2 min: [english_list(bits)]", TRUE, where)
	// a kill by someone who isn't an antagonist
	var/list/kill = killing_blow(entry, index)
	if(!kill || !kill[RL_CKEY])
		return
	var/datum/weakref/killer_ref = kill[RL_REF]
	var/mob/living/killer = killer_ref?.resolve()
	if(!killer || admin_antag_text(killer) || (victim && admin_antag_text(victim)))
		return
	var/list/bits = list()
	var/killer_job = killer.mind?.assigned_role
	if(killer_job in GLOB.security_positions)
		bits += "Security"
	if(killer.is_bot_crew())
		bits += "bot"
	var/list/seen = SSbans.seen[kill[RL_CKEY]]
	if(seen && text2num(seen["first"]))
		var/days = round((world.realtime - text2num(seen["first"])) / 864000)
		if(days < 7)
			bits += "first seen [days < 1 ? "today" : "[days] d ago"]"
	if(fought_back(entry, index, killer_ref, kill[RL_CKEY]))
		bits += "both fought"
	var/victim_job = victim?.mind?.assigned_role
	var/text = "[kill[RL_NAME]] ([kill[RL_CKEY]][killer_job ? ", [killer_job]" : ""]) killed [entry[RL_NAME]] ([entry[RL_CKEY]][victim_job ? ", [victim_job]" : ""]) in [entry[RL_AREA] || "somewhere"]"
	if(bits.len)
		text += " - [jointext(bits, ", ")]"
	raise("kill", text, TRUE, where, killer, victim, "kill:[kill[RL_CKEY]]")

/// The last hit on the dead one before they died, by someone else, within 90 seconds
/datum/controller/subsystem/admin_alerts/proc/killing_blow(list/death, index)
	var/datum/weakref/victim_ref = death[RL_REF]
	var/victim_ckey = death[RL_CKEY]
	var/since = death[RL_TIME] - 90 SECONDS
	var/list/log = GLOB.round_log
	for(var/i in index - 1 to max(1, index - 3000) step -1)
		var/list/entry = log[i]
		if(entry[RL_TIME] < since)
			break
		if(entry[RL_CAT] != "Attack" || entry[RL_REF] == victim_ref)
			continue
		if((victim_ref && entry[RL_TREF] == victim_ref) || (victim_ckey && entry[RL_TCKEY] == victim_ckey))
			return entry

/// Whether the dead one hit their killer too in the two minutes before
/datum/controller/subsystem/admin_alerts/proc/fought_back(list/death, index, datum/weakref/killer_ref, killer_ckey)
	var/datum/weakref/victim_ref = death[RL_REF]
	var/since = death[RL_TIME] - 2 MINUTES
	var/list/log = GLOB.round_log
	for(var/i in index - 1 to max(1, index - 3000) step -1)
		var/list/entry = log[i]
		if(entry[RL_TIME] < since)
			break
		if(entry[RL_CAT] == "Attack" && entry[RL_REF] == victim_ref && (entry[RL_TREF] == killer_ref || (killer_ckey && entry[RL_TCKEY] == killer_ckey)))
			return TRUE
	return FALSE

/// "key/(Name) opened a canister that contains the following at Area (x, y, z):", then a "Plasma: 1875 moles." line for each gas
/datum/controller/subsystem/admin_alerts/proc/saw_canister(list/entry, index)
	var/static/regex/opened = new(@"^(.*) opened a canister that contains the following at (.*) \((\d+), (\d+), (\d+)\):$")
	var/static/regex/gas_line = new(@"^(.+): ([\d.]+) moles\.$")
	if(!opened.Find(entry[RL_TEXT]))
		return
	var/turf/where = locate(text2num(opened.group[3]), text2num(opened.group[4]), text2num(opened.group[5]))
	if(!where || !is_station_level(where.z))
		return
	var/list/gases = list()
	var/list/log = GLOB.round_log
	for(var/i in index + 1 to min(log.len, index + 8))
		var/list/next = log[i]
		if(!gas_line.Find(next[RL_TEXT]))
			break
		gases += "[gas_line.group[1]] [round(text2num(gas_line.group[2]))] mol"
	if(!gases.len)
		return
	var/who = replacetext(opened.group[1], "\[DC\]", "") // key_name() marks a key with no client (a bot, someone gone)
	var/slash = findtext(who, "/")
	var/who_ckey = ckey(slash ? copytext(who, 1, slash) : who)
	var/mob/M = mob_of_ckey(who_ckey)
	var/antag = admin_antag_text(M)
	raise("gas", "[who][antag ? " ([antag])" : ""] opened a canister into the air in [opened.group[2]]: [english_list(gases)]", !antag, where, M, null, "gas:[who_ckey]")

/datum/controller/subsystem/admin_alerts/proc/on_explosion(datum/source, turf/epicenter, devastation_range, heavy_impact_range, light_impact_range, took, orig_dev_range, orig_heavy_range, orig_light_range)
	SIGNAL_HANDLER
	if(!epicenter || !is_station_level(epicenter.z))
		return
	if(orig_dev_range < 1 && orig_heavy_range < 3)
		return
	var/area/A = get_area(epicenter)
	// the last bomb line near it: who set it
	var/list/bomber
	var/since = world.time - 3 MINUTES
	var/list/log = GLOB.round_log
	for(var/i in log.len to max(1, log.len - 3000) step -1)
		var/list/entry = log[i]
		if(entry[RL_TIME] < since)
			break
		if(entry[RL_CAT] != "Bomb" || !entry[RL_Z])
			continue
		if(entry[RL_AREA] == A.name || (entry[RL_Z] == epicenter.z && abs(entry[RL_X] - epicenter.x) <= 15 && abs(entry[RL_Y] - epicenter.y) <= 15))
			bomber = entry
			break
	var/datum/weakref/bomber_ref = bomber ? bomber[RL_REF] : null
	var/text = "Explosion ([orig_dev_range], [orig_heavy_range], [orig_light_range]) in [A.name]"
	if(bomber)
		text += ", last bomb line by [bomber[RL_NAME]][bomber[RL_CKEY] ? " ([bomber[RL_CKEY]])" : ""]: [bomber[RL_TEXT]]"
	INVOKE_ASYNC(src, PROC_REF(raise), "boom", text, orig_dev_range >= 2, epicenter, bomber_ref?.resolve(), null, "boom:[A.name]", 30 SECONDS) // redrawing windows can sleep

/datum/controller/subsystem/admin_alerts/proc/check_engines()
	var/obj/singularity/S = bot_loose_engine()
	if(S && !engine_alerted)
		engine_alerted = TRUE
		raise("engine", "[istype(S, /obj/singularity/energy_ball) ? "Tesla" : "Singularity"] loose in [get_area_name(S, TRUE)]", TRUE, S)
	else if(!S)
		engine_alerted = FALSE
	var/obj/machinery/power/supermatter_crystal/crystal = GLOB.main_supermatter_engine
	if(QDELETED(crystal))
		supermatter_alerted = FALSE
		return
	if(crystal.damage >= crystal.emergency_point && !supermatter_alerted)
		supermatter_alerted = TRUE
		raise("engine", "Supermatter at [round(crystal.get_integrity())]% integrity in [get_area_name(crystal, TRUE)]", TRUE, crystal)
	else if(crystal.damage < crystal.emergency_point * 0.8)
		supermatter_alerted = FALSE

/datum/controller/subsystem/admin_alerts/proc/check_tickets()
	var/list/counts = get_admin_counts()
	var/list/present = counts["present"]
	if(!present.len) // with nobody on, the ahelp went to Discord already
		return
	for(var/datum/admin_help/AH in GLOB.ahelp_tickets.active_tickets)
		if(!AH.waiting_since || world.time - AH.waiting_since < 3 MINUTES || ticket_waits_alerted["[AH.id]"] == AH.waiting_since)
			continue
		ticket_waits_alerted["[AH.id]"] = AH.waiting_since
		var/datum/admin_alert/alert = raise("ticket", "Ticket #[AH.id] ([AH.initiator_key_name]) waiting [ticket_ago_text(world.time - AH.waiting_since)][AH.claimed_key ? ", claimed by [AH.claimed_key]" : ", unclaimed"]: [AH.name]", FALSE, null, AH.initiator?.mob)
		alert.ticket_id = AH.id

/datum/controller/subsystem/admin_alerts/proc/saw_emag(mob/user, atom/target)
	if(!user?.ckey || admin_antag_text(user))
		return
	var/job = user.mind?.assigned_role
	raise("emag", "[user.real_name || user.name] ([user.ckey][job ? ", [job]" : ""]) used an emag on [target] and isn't an antagonist", TRUE, user, user, target, "emag:[user.ckey]")

/obj/item/card/emag/afterattack(atom/target, mob/user, proximity)
	. = ..()
	if(target && user && (proximity || !prox_check))
		SSadmin_alerts.saw_emag(user, target)

////////////////////
// Raising one
////////////////////

/datum/controller/subsystem/admin_alerts/proc/raise(kind, text, bad, atom/where, atom/actor, atom/target, merge_key, merge_window = 2 MINUTES)
	if(merge_key)
		for(var/i in alerts.len to max(1, alerts.len - 30) step -1)
			var/datum/admin_alert/old = alerts[i]
			if(old.merge_key == merge_key && world.time - old.time < merge_window)
				old.count++
				old.time = world.time
				old.text = copytext_char("[old.text] / [text]", 1, 600)
				alerts_changed()
				return old
	var/datum/admin_alert/A = new
	A.id = ++next_id
	A.kind = kind
	A.time = world.time
	A.text = text
	A.bad = bad
	A.merge_key = merge_key
	var/turf/T = get_turf(where || actor)
	if(T)
		A.x = T.x
		A.y = T.y
		A.z = T.z
		var/area/place = T.loc
		A.area_name = place.name
	if(istype(actor))
		A.actor = WEAKREF(actor)
		A.actor_name = ismob(actor) ? (actor:real_name || actor.name) : actor.name
		A.actor_ckey = ismob(actor) ? actor:ckey : null
	if(istype(target))
		A.target = WEAKREF(target)
		A.target_name = ismob(target) ? (target:real_name || target.name) : target.name
		A.target_ckey = ismob(target) ? target:ckey : null
	alerts += A
	if(alerts.len > ALERTS_KEPT)
		alerts.Cut(1, 2)
	log_admin_private("ALERT ([GLOB.admin_alert_kinds[kind]]): [text]")
	announce(A)
	alerts_changed()
	return A

/datum/controller/subsystem/admin_alerts/proc/announce(datum/admin_alert/A)
	var/list/links = list()
	if(A.z)
		links += "(<a href='?_src_=holder;[HrefToken(TRUE)];adminplayerobservecoodjump=1;X=[A.x];Y=[A.y];Z=[A.z]'>JMP</a>)"
	var/mob/M = A.actor?.resolve()
	if(ismob(M))
		links += ADMIN_FLW(M)
		if(M.ckey)
			links += ADMIN_SEARCHLOGS(M)
	links += "(<a href='?_src_=holder;[HrefToken(TRUE)];adminalerts=[A.id]'>ALERTS</a>)"
	var/line = "<span class='adminnotice'><b><font color='[A.bad ? "#e05050" : "#e8a33c"]'>ALERT</font> [GLOB.admin_alert_kinds[A.kind]]:</b> [html_encode(A.text)] [jointext(links, " ")]</span>"
	load_mutes()
	for(var/client/X in GLOB.admins)
		var/list/muted = mutes[X.ckey]
		if(muted && muted[A.kind])
			continue
		to_chat(X, line, confidential = TRUE)
	if(discord_mode == "never")
		return
	if(discord_mode == "adminless")
		var/list/counts = get_admin_counts()
		var/list/present = counts["present"]
		if(present.len)
			return
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(send2irc), "Alert", "[GLOB.admin_alert_kinds[A.kind]]: [A.text]")

/datum/controller/subsystem/admin_alerts/proc/alerts_changed()
	for(var/datum/admin_alerts_window/W in GLOB.admin_alerts_windows)
		if(!W.owner)
			qdel(W)
			continue
		SStgui.update_uis(W)

/datum/controller/subsystem/admin_alerts/proc/load_mutes()
	if(mutes)
		return
	mutes = list()
	if(!fexists(GLOB.admin_alert_mutes_path))
		return
	var/list/loaded
	try
		loaded = json_decode(file2text(GLOB.admin_alert_mutes_path))
	catch
		loaded = null
	if(islist(loaded))
		for(var/admin_ckey in loaded)
			var/list/kinds = list()
			for(var/kind in loaded[admin_ckey])
				kinds[kind] = TRUE
			mutes[admin_ckey] = kinds
	return

/datum/controller/subsystem/admin_alerts/proc/toggle_mute(admin_ckey, kind)
	load_mutes()
	var/list/kinds = mutes[admin_ckey] || list()
	if(kinds[kind])
		kinds -= kind
	else
		kinds[kind] = TRUE
	mutes[admin_ckey] = kinds
	var/list/saved = list()
	for(var/someone in mutes)
		var/list/theirs = mutes[someone]
		if(theirs.len)
			var/list/names = list()
			for(var/k in theirs)
				names += k
			saved[someone] = names
	fdel(GLOB.admin_alert_mutes_path)
	text2file(json_encode(saved), GLOB.admin_alert_mutes_path)

/datum/controller/subsystem/admin_alerts/proc/get_alert(id)
	for(var/datum/admin_alert/A in alerts)
		if(A.id == id)
			return A

////////////////////
// The window
////////////////////

GLOBAL_LIST_EMPTY(admin_alerts_windows)

/client/var/datum/admin_alerts_window/admin_alerts_window

/client/proc/cmd_admin_alerts()
	set name = "Alerts"
	set category = "Admin"
	set desc = "Kills, mass deaths, explosions, loose engines, gas, emags and waiting tickets this round."
	if(!check_rights(R_ADMIN))
		return
	open_admin_alerts()

/client/proc/open_admin_alerts(alert_id)
	if(!holder)
		return
	if(!admin_alerts_window)
		admin_alerts_window = new
		admin_alerts_window.owner = src
	if(alert_id)
		admin_alerts_window.picked_id = alert_id
	admin_alerts_window.ui_interact(mob)

/datum/admin_alerts_window
	var/client/owner
	/// The alert a chat line's ALERTS link opened it on
	var/picked_id
	/// Only these kinds listed, or all
	var/list/shown_kinds = list()

/datum/admin_alerts_window/New()
	GLOB.admin_alerts_windows += src

/datum/admin_alerts_window/Destroy()
	GLOB.admin_alerts_windows -= src
	owner = null
	return ..()

/datum/admin_alerts_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.admin_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "admin_alerts", "Alerts", 860, 600, master_ui, state)
		ui.open()

/datum/admin_alerts_window/ui_data(mob/user)
	var/list/rows = list()
	var/list/counts = list()
	var/list/alerts = SSadmin_alerts.alerts
	for(var/i in alerts.len to 1 step -1)
		var/datum/admin_alert/A = alerts[i]
		counts[A.kind]++
		if(shown_kinds.len && !shown_kinds[A.kind])
			continue
		var/mob/actor = A.actor?.resolve()
		var/atom/target = A.target?.resolve()
		rows += list(list(
			"id" = A.id,
			"kind" = A.kind,
			"kind_name" = GLOB.admin_alert_kinds[A.kind],
			"time" = log_search_clock(A.time),
			"ago" = ticket_ago_text(world.time - A.time),
			"text" = A.text,
			"bad" = A.bad,
			"count" = A.count,
			"area" = A.area_name,
			"where" = A.z ? "[A.x], [A.y], [A.z]" : null,
			"actor" = A.actor_name,
			"actor_ckey" = A.actor_ckey,
			"actor_here" = !!actor,
			"actor_mob" = ismob(actor),
			"actor_ref" = actor ? REF(actor) : null,
			"target" = A.target_name,
			"target_ckey" = A.target_ckey,
			"target_here" = !!target,
			"target_mob" = ismob(target),
			"target_ref" = target ? REF(target) : null,
			"ticket" = A.ticket_id,
			"handled_by" = A.handled_by,
			"mine" = !!owner && A.handled_ckey == owner.ckey,
			"picked" = A.id == picked_id,
		))
	SSadmin_alerts.load_mutes()
	var/list/muted = SSadmin_alerts.mutes[owner?.ckey] || list()
	var/list/kinds = list()
	for(var/kind in GLOB.admin_alert_kinds)
		kinds += list(list("kind" = kind, "name" = GLOB.admin_alert_kinds[kind], "count" = counts[kind] || 0, "muted" = !!muted[kind], "shown" = !!shown_kinds[kind]))
	return list(
		"alerts" = rows,
		"kinds" = kinds,
		"discord_mode" = SSadmin_alerts.discord_mode,
		"can_set_discord" = !!check_rights_for(owner, R_SERVER),
		"round_time" = log_search_clock(world.time),
	)

/datum/admin_alerts_window/ui_act(action, list/params)
	if(..())
		return
	if(!check_rights(R_ADMIN))
		return
	if(action == "player_menu") // a name's menu (player_menu.dm)
		return player_menu_act(usr, params)
	switch(action)
		if("mute")
			if(GLOB.admin_alert_kinds[params["kind"]])
				SSadmin_alerts.toggle_mute(usr.ckey, params["kind"])
			return TRUE
		if("show")
			var/kind = params["kind"]
			if(!kind)
				shown_kinds = list()
			else if(GLOB.admin_alert_kinds[kind])
				if(shown_kinds[kind])
					shown_kinds -= kind
				else
					shown_kinds[kind] = TRUE
			return TRUE
		if("discord")
			if(!check_rights(R_SERVER))
				return
			if(params["mode"] in list("adminless", "always", "never"))
				SSadmin_alerts.discord_mode = params["mode"]
				log_admin("[key_name(usr)] set Discord alerts to [params["mode"]].")
				message_admins("[key_name_admin(usr)] set Discord alerts to [params["mode"]].")
			return TRUE
	var/datum/admin_alert/A = SSadmin_alerts.get_alert(text2num(params["id"]))
	if(!A)
		return
	picked_id = A.id
	switch(action)
		if("handle")
			if(A.handled_ckey == usr.ckey)
				A.handled_by = null
				A.handled_ckey = null
				message_admins("[key_name_admin(usr)] is no longer on alert #[A.id].")
			else
				A.handled_by = usr.client.key
				A.handled_ckey = usr.ckey
				message_admins("[key_name_admin(usr)] is on it: [html_encode(A.text)]")
			SSadmin_alerts.alerts_changed()
			return TRUE
		if("jmp")
			if(A.z)
				usr.client.jumptocoord(A.x, A.y, A.z)
		if("ticket")
			if(A.ticket_id)
				usr.client.open_tickets(A.ticket_id)
		if("logs")
			usr.client.open_log_search(A.actor_ckey || A.actor_name)
		if("t_logs")
			usr.client.open_log_search(A.target_ckey || A.target_name)
		if("profile")
			if(A.actor_ckey)
				usr.client.open_player_profile(A.actor_ckey)
		if("t_profile")
			if(A.target_ckey)
				usr.client.open_player_profile(A.target_ckey)
		if("pp", "vv", "flw", "t_pp", "t_vv", "t_flw")
			var/datum/weakref/W = findtext(action, "t_") == 1 ? A.target : A.actor
			var/atom/thing = W?.resolve()
			if(!thing)
				return
			switch(replacetext(action, "t_", ""))
				if("pp")
					if(ismob(thing))
						usr.client.holder.show_player_panel(thing)
				if("vv")
					usr.client.debug_variables(thing)
				if("flw")
					if(ismovable(thing) && (isobserver(usr) || usr.client.admin_ghost()))
						var/mob/dead/observer/ghost = usr.client.mob
						ghost.ManualFollow(thing)
		if("pick")
			return TRUE

#undef ALERTS_KEPT
