// The AI keeping watch (overnight 2026-11-10). The user's brief: the AI should be the station's watchdog and caretaker. It had doors,
// wanted people on camera, and bodies on the crew monitor. Now it also does what a player AI does from the core between requests:
//  - Fires and holes in the hull, from its alarms and cameras: called out on the common channel so engineers hear where, and the nearest
//    engineering cyborg sent.
//  - Power: the station's reserves running down, to Engineering.
//  - Fights on camera: whoever started it named to Security, who are sent there.
//  - Its upload and core: anybody in there who shouldn't be, to Security.
//  - The shuttle: a crew dying with nobody left in Command to call it, called from the core.
// Subverted with a law naming somebody to go for, it bolts them in wherever it sees them, and doesn't open a door for them again.

/// Between rounds of the alarms.
#define BOT_AI_WATCH_GAP (6 SECONDS)
/// Before the same thing is called out again.
#define BOT_AI_REPEAT (3 MINUTES)

/datum/bot_silicon/ai
	var/next_watch = 0
	/// Key ("fire|area", "breach|turf", "power", "fight|a>b", "intruder|mob") -> when it can be called out again.
	var/list/called_about
	/// When the crew first looked done for, and nobody had called the shuttle.
	var/decimated_since = 0
	/// Rooms it's called a hull breach in, until they're patched.
	var/list/breached_called

/datum/bot_silicon/ai/think()
	. = ..()
	if(world.time < next_watch || QDELETED(owner) || owner.stat != CONSCIOUS)
		return
	next_watch = world.time + BOT_AI_WATCH_GAP
	if(subverted())
		hunt_law_targets()
		return
	watch_operatives() || watch_fires() || watch_breaches() || watch_fights() || watch_crit() || watch_core() || watch_power()
	watch_shuttle()

/// Somebody in critical condition on the crew monitor (suit sensors set to vitals or better): Medical told where, and a request made that
/// the doctors answer (bot_requests.dm). It only reported the bodies before.
/datum/bot_silicon/ai/proc/watch_crit()
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.stat == DEAD || H.health > H.crit_threshold || !H.mind?.assigned_role)
			continue
		var/obj/item/clothing/under/U = H.w_uniform
		var/turf/T = get_turf(H)
		if(!istype(U) || U.sensor_mode < SENSOR_VITALS || !T || !is_station_level(T.z) || bot_in_medbay(H) || !fresh("crit|[REF(H)]"))
			continue
		note("crew monitor: [H] critical in [get_area_name(T, TRUE)]")
		say_it(":m [H.real_name] is critical[U.sensor_mode >= SENSOR_COORDS ? " in [get_area_name(T, TRUE)]" : ""].")
		var/datum/bot_request_kind/medical/M = locate() in GLOB.bot_request_kinds
		if(M && !bot_open_request_from(H, M))
			bot_offer_request(bot_new_request(M, H, FREQ_MEDICAL, H))
		return TRUE
	return FALSE

/// Somebody in a Syndicate suit on the cameras: Security told where, and the first officer free puts it on the record, which makes them
/// kill on sight (bot_is_fair_game()). A player AI calls operatives out the moment it sees them.
/datum/bot_silicon/ai/proc/watch_operatives()
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.stat == DEAD || !bot_in_syndicate_suit(H)) //goals/security_tactics.dm
			continue
		var/turf/T = get_turf(H)
		if(!T || !is_station_level(T.z) || !bot_camera_sees(T) || !fresh("op|[REF(H)]"))
			continue
		note("Syndicate suit on camera: [H] in [get_area_name(T, TRUE)]")
		say_it(":s Syndicate operative in [get_area_name(T, TRUE)]! [H.name].")
		var/datum/bot_wanted/W = bot_get_wanted_entry(H)
		if(!W || !(W.crime in GLOB.bot_antag_crimes))
			for(var/datum/bot_brain/B as anything in GLOB.bot_security_brains)
				if(!QDELETED(B.owner) && B.owner.stat == CONSCIOUS)
					B.file_crime(H, "Sabotage", "In a Syndicate suit, seen by the AI in [get_area_name(T, TRUE)].", BOT_CRIME_MAJOR)
					break
		else
			W.last_seen = T
			W.last_seen_at = world.time
		bot_dispatch_security(T, H.name)
		return TRUE
	return FALSE

/datum/bot_silicon/ai/proc/fresh(key)
	if(LAZYACCESS(called_about, key) > world.time)
		return FALSE
	LAZYSET(called_about, key, world.time + BOT_AI_REPEAT)
	return TRUE

/datum/bot_silicon/ai/proc/watch_fires()
	var/list/seen = list()
	for(var/obj/effect/hotspot/H as anything in SSair.hotspots)
		var/turf/T = get_turf(H)
		if(!T || !is_station_level(T.z) || bot_fire_meant_to_burn(T)) //goals/respond_to_fire.dm
			continue
		var/area/A = get_area(T)
		if(!A || seen[A])
			continue
		seen[A] = TRUE
		if(!A.fire && !bot_camera_sees(T)) //its fire alarm, or a camera on it
			continue
		if(!fresh("fire|[REF(A)]"))
			continue
		note("fire in [A.name]")
		say_it(";Fire in [A.name].")
		send_engi_borg(T)
		return TRUE
	return FALSE

/// Each breached room once, while it stays breached, a few to a line: in a meteor round (n1_sil_meteor) it called each of thirty rooms
/// every three minutes, ten times over.
/datum/bot_silicon/ai/proc/watch_breaches()
	var/list/open_now = list() //area -> a hole in it
	for(var/turf/T as anything in GLOB.bot_hull_breaches)
		if(!istype(T, /turf/open/space) || !is_station_level(T.z))
			continue
		var/area/A = get_area(T)
		if(A && !open_now[A])
			open_now[A] = T
	for(var/area/A as anything in breached_called)
		if(!open_now[A])
			breached_called -= A //patched: a new hole there is news again
	var/list/new_rooms = list()
	var/turf/first
	for(var/area/A as anything in open_now)
		if(A in breached_called)
			continue
		LAZYADD(breached_called, A)
		new_rooms += A.name
		first = first || open_now[A]
	if(!length(new_rooms))
		return FALSE
	note("hull breach in [english_list(new_rooms)]")
	if(length(new_rooms) > 3)
		say_it(";Hull breaches in [english_list(new_rooms.Copy(1, 4))] and [length(new_rooms) - 3] more. Engineering, please respond.")
	else
		say_it(";Hull breach in [english_list(new_rooms)]. Engineering, please respond.")
	send_engi_borg(first)
	return TRUE

/// The nearest engineering cyborg with nothing better to do goes.
/datum/bot_silicon/ai/proc/send_engi_borg(turf/T)
	var/datum/bot_silicon/borg/best
	for(var/datum/bot_silicon/borg/B in GLOB.bot_silicons)
		var/mob/living/silicon/robot/R = B.owner
		if(!istype(R) || R.stat != CONSCIOUS || R.z != T.z || R.module.type != /obj/item/robot_module/engineering || B.master_ref || B.charger_ref)
			continue
		if(B.heading_for && !B.wandering && !B.patrol_spot)
			continue //at a job of its own
		if(!best || get_dist(R, T) < get_dist(best.owner, T))
			best = B
	if(!best)
		return
	var/turf/spot = istype(T, /turf/open/space) ? bot_hull_standing_spot(T) : T
	if(spot && best.go_to(spot, istype(T, /turf/open/space) ? 0 : 3))
		best.wandering = TRUE //looks for the work when it's in sight of it
		best.next_job_look = world.time
		say_it(":b [best.owner.name], [get_area_name(T, TRUE)].")

/// A fight on its cameras: whoever started on somebody, if it's not Security at work or somebody fighting a known antagonist.
/datum/bot_silicon/ai/proc/watch_fights()
	for(var/key in GLOB.bot_recent_aggression)
		if(world.time - GLOB.bot_recent_aggression[key] > 10 SECONDS)
			continue
		var/split = findtext(key, ">")
		var/mob/living/carbon/human/attacker = locate(copytext(key, 1, split))
		var/mob/living/carbon/human/victim = locate(copytext(key, split + 1))
		if(!istype(attacker) || !istype(victim) || attacker.stat == DEAD || !is_station_level(attacker.z))
			continue
		if((attacker.mind?.assigned_role in GLOB.security_positions) || bot_is_fair_game(victim))
			continue
		var/their_first = GLOB.bot_recent_aggression["[REF(victim)]>[REF(attacker)]"]
		if(their_first && their_first < GLOB.bot_recent_aggression[key])
			continue //the other one started it: that one's call comes up under its own key
		var/turf/T = get_turf(attacker)
		if(!bot_camera_sees(T))
			continue
		if(!fresh("fight|[REF(attacker)]"))
			continue
		note("on camera: [attacker] attacking [victim]")
		say_it(":s [attacker.name] is attacking [victim.name] in [get_area_name(T, TRUE)].")
		bot_dispatch_security(T, attacker.name) //goals/security_tactics.dm
		return TRUE
	return FALSE

/// Its own rooms: anybody in the upload or the core who isn't Command, or the cyborgs' and its own.
/datum/bot_silicon/ai/proc/watch_core()
	for(var/area_type in list(/area/ai_monitored/turret_protected/ai_upload, /area/ai_monitored/turret_protected/ai))
		var/area/A = GLOB.areas_by_type[area_type]
		if(!A)
			continue
		for(var/mob/living/carbon/human/H in A)
			if(H.stat == DEAD || (H.mind?.assigned_role in GLOB.command_positions) || (H.mind?.assigned_role == "Research Director"))
				continue
			if(!fresh("intruder|[REF(H)]"))
				continue
			note("[H] in [A.name]")
			say_it(":s [H.name] is in [A.name] without clearance.")
			bot_dispatch_security(get_turf(H), H.name)
			return TRUE
	return FALSE

/datum/bot_silicon/ai/proc/watch_power()
	var/power = bot_smes_percent(owner.z) //bot_chatter.dm
	if(isnull(power) || power >= 15 || !fresh("power"))
		return FALSE
	note("power reserves at [power]%")
	say_it(":e Power reserves at [power] percent. Engineering, check the engine.")
	return TRUE

/// A crew more than a third dead and nobody calling the shuttle: after a few minutes, it calls it itself, as an AI can from the core.
/datum/bot_silicon/ai/proc/watch_shuttle()
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	if(!E || E.mode != SHUTTLE_IDLE || bot_shift_end_time() == -1 || !bot_crew_decimated()) //goals/call_shuttle.dm
		decimated_since = 0
		return
	if(!decimated_since)
		decimated_since = world.time
		return
	if(world.time < decimated_since + 4 MINUTES)
		return
	decimated_since = world.time + 5 MINUTES //not every look, if it doesn't go
	note("calling the shuttle: a third of the crew dead and nobody's called it")
	SSshuttle.requestEvac(owner, "Heavy casualties. Crew evacuation required.")
	if(E.mode == SHUTTLE_CALL)
		say_it(";I've called the shuttle. Get to Departures.")

/// Subverted: whoever its laws name, bolted in where the cameras see them.
/datum/bot_silicon/ai/proc/hunt_law_targets()
	for(var/mob/living/carbon/human/H in bot_law_targets(owner)) //goals/silicon_work.dm
		var/turf/T = get_turf(H)
		if(!T || !is_station_level(T.z) || !bot_camera_sees(T) || !fresh("hunt|[REF(H)]|[REF(get_area(T))]"))
			continue
		var/list/bolted = bolt_room(get_area(T), T)
		note("its laws name [H]: bolted [length(bolted)] doors round them in [get_area_name(T, TRUE)]")
		if(length(bolted))
			addtimer(CALLBACK(src, PROC_REF(lift_lockdown), bolted, get_area(T)), 2 MINUTES)
		return

/// Every door it can work on the edge of `A`, shut and bolted. The doors.
/datum/bot_silicon/ai/proc/bolt_room(area/A, turf/near)
	. = list()
	for(var/obj/machinery/door/airlock/D in range(12, near))
		if(D.locked || !D.canAIControl(owner))
			continue
		var/on_the_edge = get_area(D) == A
		if(!on_the_edge)
			for(var/turf/T in get_adjacent_open_turfs(D))
				if(get_area(T) == A)
					on_the_edge = TRUE
					break
		if(!on_the_edge)
			continue
		if(D.density)
			D.bolt()
		else
			INVOKE_ASYNC(src, PROC_REF(close_and_bolt), D)
		. += D

#undef BOT_AI_WATCH_GAP
#undef BOT_AI_REPEAT
