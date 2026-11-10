// The admins' live dashboard (the user's rulings, 2026-11-09): a web page any browser can open, a phone too, served by a small web
// server inside the game's process (tools/dashboard, hippie_dashboard.dll / libhippie_dashboard.so) on its own port. Admins only,
// through a personal link the Dashboard Link verb makes (a token good for 12 hours, no passwords); read only. It shows the station map
// live (crew and bots moving, antags marked, fires, air alarms, rooms with no power, bodies), server health (tick load, CPU, what
// each subsystem costs, the native engines), everyone on the crew (job, health, where, what each bot is doing) and an alerts feed
// (deaths, explosions with their blame, new ahelps, the admin alerts).
//
// Config: DASHBOARD_PORT (0, the default, is off), DASHBOARD_LOCAL_ONLY (this machine only), DASHBOARD_URL (the address to put in
// the links, if not http://<the server's address>:<port>). World param dashboard-port=<port> turns it on for a test run.
// SSdashboard only builds what a page is showing while one is open (dashboard_clients()). Included after the bot AI (its states)
// and the admin alerts (raise()).

/datum/config_entry/number/dashboard_port	// the admins' dashboard's web port; 0 is off (admin/dashboard.dm)
	config_entry_value = 0
	min_val = 0
	max_val = 65535
	protection = CONFIG_ENTRY_LOCKED

/datum/config_entry/flag/dashboard_local_only	// only this machine can open the dashboard (admin/dashboard.dm)
	protection = CONFIG_ENTRY_LOCKED

/datum/config_entry/string/dashboard_url	// the dashboard's address for the links, if not http://<server address>:<port>
	protection = CONFIG_ENTRY_LOCKED

#define DASHBOARD_LIB (world.system_type == UNIX ? "./libhippie_dashboard.so" : "hippie_dashboard")
#define DASHBOARD_LIB_FILE (world.system_type == UNIX ? "./libhippie_dashboard.so" : "hippie_dashboard.dll")
/// How long a link is good for
#define DASHBOARD_LINK_HOURS 12

SUBSYSTEM_DEF(dashboard)
	name = "Dashboard"
	wait = 5
	init_order = INIT_ORDER_DEFAULT - 5
	runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT
	var/port = 0
	/// "on", or why not
	var/status = "off"
	var/fires = 0
	/// Pages open at the last look
	var/clients = 0
	/// subsystem name -> times_fired at the last health push
	var/list/fired_before = list()
	/// When the station's walls were last sent
	var/static_sent_at = -INFINITY
	var/static_building = FALSE

/datum/controller/subsystem/dashboard/Initialize(start_timeofday)
	port = text2num(world.params["dashboard-port"]) || CONFIG_GET(number/dashboard_port)
	if(!port)
		status = "off (DASHBOARD_PORT)"
		can_fire = FALSE
		return ..()
	if(!fexists(DASHBOARD_LIB_FILE))
		status = "off: no [DASHBOARD_LIB_FILE]"
		can_fire = FALSE
		log_world("Dashboard: [status]")
		return ..()
	var/result
	try
		result = call_ext(DASHBOARD_LIB, "dashboard_start")("[port]", CONFIG_GET(flag/dashboard_local_only) ? "local" : "all")
	catch(var/exception/E)
		result = "error: [E.name]"
	if(!findtext(result, "ok", 1, 3))
		status = "off: [result]"
		can_fire = FALSE
		log_world("Dashboard: [status]")
		return ..()
	status = "on, port [port]"
	log_world("Dashboard: [status] ([result])")
	RegisterSignal(SSdcs, COMSIG_GLOB_EXPLOSION, PROC_REF(explosion_alert))
	return ..()

/datum/controller/subsystem/dashboard/stat_entry(msg)
	return ..("[status], [clients] open")

/datum/controller/subsystem/dashboard/proc/send(channel, list/data)
	call_ext(DASHBOARD_LIB, "dashboard_push")(channel, json_encode(data))

/datum/controller/subsystem/dashboard/fire(resumed)
	fires++
	clients = text2num(call_ext(DASHBOARD_LIB, "dashboard_clients")())
	if(fires % 2 == 0)
		note_subsystem_costs() //kept up whether or not anybody's looking, so the first figures a page gets are a second's worth
	if(!clients)
		return
	if(world.time - static_sent_at > 5 MINUTES && !static_building)
		static_building = TRUE
		INVOKE_ASYNC(src, PROC_REF(send_station))
	send("map_live", map_live())
	if(fires % 2 == 0)
		send("health", health())
	if(fires % 4 == 0)
		send("crew", crew())

// ---------------------------------------------------------------------------------------------
// Server health, once a second
// ---------------------------------------------------------------------------------------------

/datum/controller/subsystem/dashboard
	/// subsystem name -> ms it cost the last second
	var/list/subsystem_ms = list()

/datum/controller/subsystem/dashboard/proc/note_subsystem_costs()
	for(var/datum/controller/subsystem/SS as anything in Master.subsystems)
		var/fired = SS.times_fired - fired_before[SS.name]
		fired_before[SS.name] = SS.times_fired
		subsystem_ms[SS.name] = fired > 0 ? fired * SS.cost : 0

/datum/controller/subsystem/dashboard/proc/health()
	var/list/subsystems = list()
	for(var/name in subsystem_ms)
		if(subsystem_ms[name] >= 0.05)
			subsystems += list(list(name, round(subsystem_ms[name], 0.1)))
	sortTim(subsystems, GLOBAL_PROC_REF(cmp_dashboard_cost))
	if(length(subsystems) > 12)
		subsystems.Cut(13)
	var/alive = 0
	for(var/mob/living/carbon/human/H in GLOB.mob_living_list)
		if(H.stat != DEAD && H.mind?.assigned_role)
			alive++
	. = list(
		"round" = GLOB.round_id ? "#[GLOB.round_id]" : "local",
		"time" = dashboard_shift_time(),
		"players" = length(GLOB.clients),
		"bots" = length(GLOB.bot_brains),
		"alive" = alive,
		"tick" = list("usage" = round(world.cpu, 0.1), "cpu" = round(world.cpu, 0.1), "map_cpu" = round(world.map_cpu, 0.1), "dilation" = round(SStime_track.time_dilation_avg, 0.1)),
		"subsystems" = subsystems,
		"engines" = list(
			"Path engine" = GLOB.path_engine_status,
			"Atmos" = SSair.tile_engine ? "tile engine" : "LINDA",
			"Lighting" = SSlighting.native ? "native ([SSlighting.native_status])" : "DM",
			"Explosions" = GLOB.explosion_shape_mode == "line" ? "straight line" : (GLOB.explosion_shape_native == FALSE ? "shaped, in DM" : "shaped, native"),
		),
		"server" = list(
			"Map" = SSmapping.config?.map_name,
			"BYOND" = "[world.byond_version].[world.byond_build] on [world.system_type == UNIX ? "Linux" : "Windows"]",
			"Ticks a second" = "[round(world.fps)]",
			"Atoms" = "[length(world.contents)]",
			"Timers" = "[length(SStimer.timer_id_dict)]",
		),
	)

/proc/cmp_dashboard_cost(list/a, list/b)
	return b[2] - a[2]

// ---------------------------------------------------------------------------------------------
// The station map: the walls every five minutes, what moves twice a second
// ---------------------------------------------------------------------------------------------

/// What a tile is drawn as on the page: space, wall, reinforced wall, floor, door, window
/proc/dashboard_tile(turf/T)
	if(isspaceturf(T))
		return " "
	if(T.density)
		return istype(T, /turf/closed/wall/r_wall) ? "R" : "#"
	for(var/obj/O in T)
		if(istype(O, /obj/machinery/door))
			return "D"
		if(istype(O, /obj/structure/window) || istype(O, /obj/structure/grille))
			return "W"
	return "."

/datum/controller/subsystem/dashboard/proc/send_station()
	var/list/levels = list()
	for(var/z in SSmapping.levels_by_trait(ZTRAIT_STATION))
		var/list/rows = list()
		for(var/y in 1 to world.maxy)
			var/list/row = new(world.maxx)
			for(var/x in 1 to world.maxx)
				row[x] = dashboard_tile(locate(x, y, z))
			rows += row.Join("")
			CHECK_TICK
		levels += list(list("z" = z, "name" = length(SSmapping.levels_by_trait(ZTRAIT_STATION)) > 1 ? "Deck [z]" : "Station", "w" = world.maxx, "h" = world.maxy, "tiles" = rows.Join("")))
	send("map_static", list("levels" = levels))
	static_sent_at = world.time
	static_building = FALSE

/// Flags on a person, the page's: 1 antagonist, 2 dead, 4 bot, 8 player
/proc/dashboard_flags(mob/living/M)
	. = 0
	if(length(M.mind?.antag_datums))
		. |= 1
	if(M.stat == DEAD)
		. |= 2
	var/mob/living/carbon/human/H = M
	if(istype(H) && H.bot_brain)
		. |= 4
	if(M.client)
		. |= 8

/proc/dashboard_antag_names(mob/living/M)
	var/list/names = list()
	for(var/datum/antagonist/A as anything in M.mind?.antag_datums)
		names += A.name
	return names.Join(", ")

/datum/controller/subsystem/dashboard/proc/map_live()
	var/list/station = SSmapping.levels_by_trait(ZTRAIT_STATION)
	var/list/mobs = list()
	for(var/mob/living/M as anything in GLOB.mob_living_list)
		if(!ishuman(M) && !issilicon(M))
			continue
		var/turf/T = get_turf(M)
		if(!T || !(T.z in station))
			continue
		mobs += list(list(T.x, T.y, T.z, dashboard_flags(M), M.real_name || M.name, dashboard_antag_names(M)))
	var/list/fires = list()
	for(var/obj/effect/hotspot/H as anything in SSair.hotspots)
		if(length(fires) >= 400)
			break
		if(H.z in station)
			fires += list(list(H.x, H.y, H.z))
	var/list/alarms = list()
	for(var/obj/machinery/airalarm/A as anything in bot_instances_of(/obj/machinery/airalarm))
		if(A.danger_level >= 2 && (A.z in station))
			alarms += list(list(A.x, A.y, A.z))
	var/list/unpowered = list()
	for(var/obj/machinery/power/apc/P as anything in bot_instances_of(/obj/machinery/power/apc))
		if((P.z in station) && P.area && !P.area.power_equip)
			unpowered += list(list(P.x, P.y, P.z))
	return list("mobs" = mobs, "fires" = fires, "alarms" = alarms, "unpowered" = unpowered)

// ---------------------------------------------------------------------------------------------
// The crew, every two seconds
// ---------------------------------------------------------------------------------------------

/datum/controller/subsystem/dashboard/proc/crew()
	. = list()
	for(var/mob/living/M as anything in GLOB.mob_living_list)
		if(!M.mind?.assigned_role || !(ishuman(M) || issilicon(M)))
			continue
		var/area/where = get_area(M)
		var/doing
		var/mob/living/carbon/human/H = M
		if(istype(H) && H.bot_brain)
			doing = H.bot_brain.dashboard_doing()
		else if(M.client)
			doing = M.client.is_afk() ? "player, away" : "player"
		else
			doing = M.stat == DEAD ? "" : "no one at the keys"
		var/health = M.maxHealth > HEALTH_THRESHOLD_DEAD ? round(100 * (M.health - HEALTH_THRESHOLD_DEAD) / (M.maxHealth - HEALTH_THRESHOLD_DEAD)) : 0
		. += list(list(
			"n" = M.real_name || M.name,
			"j" = M.mind.assigned_role,
			"h" = clamp(health, 0, 100),
			"a" = where ? where.name : "",
			"s" = doing,
			"f" = dashboard_flags(M),
			"t" = dashboard_antag_names(M),
		))

/// What a bot is up to, in a few words
/datum/bot_brain/proc/dashboard_doing()
	if(QDELETED(owner) || owner.stat == DEAD)
		return ""
	switch(state)
		if(BOT_STATE_COMBAT)
			return "fighting[attacker ? " [attacker]" : ""]"
		if(BOT_STATE_ARREST)
			return "arresting [arrest_suspect]"
	if(current_goal)
		if(current_goal.doing)
			return current_goal.doing
		var/datum/bot_goal/acquire_item_type/fetch = current_goal
		if(istype(fetch) && fetch.item_type)
			var/obj/item/kind = fetch.item_type
			return "getting [bot_some(initial(kind.name))]"
		var/datum/bot_goal/acquire_tool/tool = current_goal
		if(istype(tool))
			var/obj/item/kind = tool.needed_tool_type
			return kind ? "getting [bot_some(initial(kind.name))]" : "getting tools"
		return replacetext(replacetext("[current_goal.type]", "/datum/bot_goal/", ""), "_", " ")
	return pursuing_kind ? "on the move" : "idle"

// ---------------------------------------------------------------------------------------------
// The alerts feed
// ---------------------------------------------------------------------------------------------

/proc/dashboard_alert(kind, text)
	if(!SSdashboard?.can_fire)
		return
	call_ext(DASHBOARD_LIB, "dashboard_event")(json_encode(list("t" = dashboard_shift_time(), "k" = kind, "m" = text)))

/// The shift so far, h:mm:ss, or "lobby"
/proc/dashboard_shift_time()
	if(!SSticker.round_start_time)
		return "lobby"
	var/seconds = round((world.time - SSticker.round_start_time) / 10)
	return "[round(seconds / 3600)]:[add_leading("[round(seconds / 60) % 60]", 2, "0")]:[add_leading("[seconds % 60]", 2, "0")]"

/mob/living/carbon/human/death(gibbed)
	var/was_alive = stat != DEAD
	. = ..()
	if(was_alive && stat == DEAD && mind?.assigned_role)
		dashboard_alert("death", "[real_name] ([mind.assigned_role]) died in [get_area_name(src, TRUE)][lastattacker ? ", last hit by [lastattacker]" : ""]")

/datum/controller/subsystem/admin_alerts/raise(kind, text, bad, atom/where, atom/actor, atom/target, merge_key, merge_window = 2 MINUTES, chat_links)
	. = ..()
	dashboard_alert("admin", "[kind]: [text]")

/datum/admin_help/New(msg, client/C, is_bwoink)
	. = ..()
	dashboard_alert("ahelp", "#[id] [is_bwoink ? "to" : "from"] [C?.key]: [msg]")

/datum/controller/subsystem/dashboard/proc/explosion_alert(datum/source, turf/epicenter, devastation_range, heavy_impact_range, light_impact_range)
	SIGNAL_HANDLER
	var/blame = length(GLOB.bombers) ? GLOB.bombers[length(GLOB.bombers)] : ""
	var/cause = findtext(blame, "Cause: ") ? copytext(blame, findtext(blame, "Cause: ") + 7, findtext(blame, ". Suspects")) : ""
	dashboard_alert("explosion", "([devastation_range], [heavy_impact_range], [light_impact_range]) in [get_area_name(epicenter, TRUE)][cause ? ": [cause]" : ""]")

// ---------------------------------------------------------------------------------------------
// The link
// ---------------------------------------------------------------------------------------------

/client/add_admin_verbs()
	. = ..()
	if(holder && (holder.rank.rights & R_ADMIN))
		verbs += /client/proc/cmd_dashboard_link

/client/remove_admin_verbs()
	. = ..()
	verbs.Remove(/client/proc/cmd_dashboard_link)

/client/proc/cmd_dashboard_link()
	set name = "Dashboard Link"
	set category = "Admin"
	if(!check_rights(R_ADMIN))
		return
	if(!SSdashboard.can_fire)
		to_chat(src, "<span class='warning'>Dashboard [SSdashboard.status].</span>", confidential = TRUE)
		return
	var/token = call_ext(DASHBOARD_LIB, "dashboard_token")(ckey, "[DASHBOARD_LINK_HOURS * 3600]")
	var/base = CONFIG_GET(string/dashboard_url) || "http://[world.internet_address || "127.0.0.1"]:[SSdashboard.port]"
	var/url = "[base]/?t=[token]"
	to_chat(src, "<span class='adminnotice'>Your dashboard link, good for [DASHBOARD_LINK_HOURS] hours and for you alone: <a href='[url]'>[url]</a></span>", confidential = TRUE)
	src << link(url)
	log_admin("[key_name(src)] made a dashboard link")

#undef DASHBOARD_LINK_HOURS
