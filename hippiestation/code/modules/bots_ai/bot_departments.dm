// Departments: whose room it is, who's let in, and what the staff do about it.
//
//  - Every department knows its own blast doors and shutters (bot_panels()): what each button works, and what that's for. Doors onto
//    space are kept shut as a matter of good practice, in Engineering and the heads' offices. With a threat about, the staff drop their
//    department's lockdown and shutters, and lift them once it's over. The Bridge shuts when the round's gone bad anywhere. Security
//    keeps the armory shut as a matter of routine. An intruder who won't leave can be shut in until Security gets there. Xenobiology
//    seals up when a slime gets out. How keen a bot is on any of it is its strictness, or being paranoid.
//  - Engineering gets broken into for its gloves, by greytiders and powergamers, and role-hoppers who've got a use for them
//    (/datum/bot_goal/tide/raid). Hacking a door leaves it bolted open. Breaking in isn't valid: the staff order them out and call it
//    in, and only Security lays a hand on them. Nobody but the engineers goes near the engine, and they take it very badly when
//    somebody does: one call and they go and stand over it.
//  - A department with a door bolted open is an open department. That's the raiders' doing, or the staff's: the easygoing ones in Science
//    and Medical do it themselves. The crew wander in to use the place. The strict ones put the door right and throw everybody out.

#define BOT_PANEL_SPACE "space"
#define BOT_PANEL_LOCKDOWN "lockdown"
#define BOT_PANEL_SHUTTERS "shutters"
#define BOT_PANEL_CONTAINMENT "containment"
/// How old a sighting of somebody dangerous can be and still be a reason to keep the doors shut.
#define BOT_THREAT_MEMORY (2 MINUTES)
/// The longest anybody's kept shut in for Security.
#define BOT_TRAP_LENGTH (3 MINUTES)
/// The least time between one working of a set of doors and the next. A captain flapped their office shutters for a quarter of an hour
/// as one suspect after another came and went on the records.
#define BOT_PANEL_REST (90 SECONDS)
/// How long engineers stay stood over the engine.
#define BOT_ENGINE_WATCH (45 SECONDS)
/// How long into the round before anybody starts breaking in.
#define BOT_RAID_SETTLE_IN (6 MINUTES)
/// Between one look at which departments are open and the next.
#define BOT_OPEN_DEPT_REFRESH (30 SECONDS)
/// Strictness below which a department's staff don't mind who's in it, and at which they'd rather it was locked.
#define BOT_EASYGOING 0.3
#define BOT_STRICT 0.6

/// Who a room belongs to, past whether it's staff-only (bot_staff_of(), bot_witness.dm). Checked with istype, so the first match.
GLOBAL_LIST_INIT(bot_department_areas, list(
	/area/engine = "engineering",
	/area/storage/tech = "engineering",
	/area/medical = "medical",
	/area/science = "science",
	/area/ai_monitored/security = "security",
	/area/security = "security",
	/area/bridge = "command",
	/area/crew_quarters/heads = "command",
	/area/quartermaster = "supply",
))

/// Words in a button's name that mean it's nothing to do with this: the buttons that vent, launch, load, or are there for the machinery.
GLOBAL_LIST_INIT(bot_panel_leave_alone, list("vent", "loading", "conveyor", "disposal", "mech bay", "experimentor", "justice", "transfer",
	"execution", "storage", "cell ", "test chamber", "cargo", "gateway", "commissary", "teleport", "ai ", "construction", "auxiliary",
	"labor", "nanite", "custodial", "blast door control a", "blast door control b", "blast door control c", "radiation", "chamber shutters"))

/// Rooms a trespasser would really have to answer for.
GLOBAL_LIST_INIT(bot_high_security_areas, typecacheof(list(/area/bridge, /area/crew_quarters/heads, /area/ai_monitored, /area/security)))
GLOBAL_LIST_INIT(bot_dangerous_areas, typecacheof(list(/area/engine, /area/science/mixing, /area/science/xenobiology)))

/// What's bolted open: department -> one of the doors.
GLOBAL_LIST_EMPTY(bot_open_departments)
GLOBAL_VAR_INIT(bot_open_departments_at, 0)

/mob/living/carbon/human
	/// When they last forced a door, for what the charge is (bot_trespass_charge()).
	var/bot_broke_in_at = 0

/datum/bot_brain
	/// When the engine was last reported in danger, and whether it's been looked at.
	var/engine_alarm_at = 0
	/// When it'll next think about propping a door open or putting one right.
	var/next_door_work = 0

/proc/bot_department_of(area/A)
	var/area/bot_gym/arena = A
	if(istype(arena))
		return arena.department
	for(var/area_type in GLOB.bot_department_areas)
		if(istype(A, area_type))
			return GLOB.bot_department_areas[area_type]
	return null

/proc/bot_positions_of(department)
	switch(department)
		if("engineering")
			return GLOB.engineering_positions
		if("medical")
			return GLOB.medical_positions
		if("science")
			return GLOB.science_positions
		if("security")
			return GLOB.security_positions
		if("command")
			return GLOB.command_positions
		if("supply")
			return GLOB.supply_positions
	return list()

/// The department a bot works for. A head's is their own, the Bridge being everybody's.
/datum/bot_brain/proc/my_departments()
	. = list()
	var/role = work_role()
	for(var/department in list("engineering", "medical", "science", "security", "command", "supply"))
		if(role in bot_positions_of(department))
			. += department

/// What being here without leave comes to, for somebody who's forced their way in or hasn't.
/proc/bot_trespass_charge(area/A, broke_in)
	if(is_type_in_typecache(A, GLOB.bot_high_security_areas))
		return broke_in ? "Breaking into a High Security Area" : "Trespassing in a High Security Area"
	if(is_type_in_typecache(A, GLOB.bot_dangerous_areas))
		return broke_in ? "Breaking into a Dangerous Area" : "Trespassing in a Dangerous Area"
	return broke_in ? "Breaking and Entering" : "Trespassing"

// ---------------------------------------------------------------------------------------------
// Blast doors and shutters
// ---------------------------------------------------------------------------------------------

/// One set of doors on one id, and the buttons that work them.
/datum/bot_panel
	var/id
	var/name
	var/kind
	var/department
	var/list/buttons = list()
	var/list/doors = list()
	/// Whether they stand open in the normal way of things.
	var/open_normally = FALSE
	/// Shut because of something that's going on, and so to be opened again.
	var/shut_for_threat = FALSE
	/// Somebody shut in by this, as a weakref, and when.
	var/datum/weakref/holding
	var/holding_since = 0
	/// When these doors last moved.
	var/last_worked = -BOT_PANEL_REST

/datum/bot_panel/proc/is_shut()
	for(var/obj/machinery/door/poddoor/D as anything in doors)
		if(!QDELETED(D))
			return D.density
	return FALSE

/datum/bot_panel/proc/moving()
	for(var/obj/machinery/door/poddoor/D as anything in doors)
		if(!QDELETED(D) && D.operating)
			return TRUE
	return FALSE

/// A working button of this set that this bot's ID works.
/datum/bot_panel/proc/button_for(datum/bot_brain/bot)
	for(var/obj/machinery/button/door/B as anything in buttons)
		if(!QDELETED(B) && B.z == bot.owner.z && !B.panel_open && !(B.stat & (NOPOWER|BROKEN)) && B.allowed(bot.owner) && !bot.taken_by_another(B))
			return B
	return null

/proc/bot_panel_kind(name, faces_space)
	var/lower = lowertext(name)
	for(var/word in GLOB.bot_panel_leave_alone)
		if(findtext(lower, word))
			return null
	if(findtext(lower, "containment"))
		return BOT_PANEL_CONTAINMENT
	if(faces_space)
		return BOT_PANEL_SPACE
	if(findtext(lower, "lockdown") || findtext(lower, "biohazard") || findtext(lower, "blast"))
		return BOT_PANEL_LOCKDOWN
	if(findtext(lower, "shutter") || findtext(lower, "privacy"))
		return BOT_PANEL_SHUTTERS
	return null

/// id -> panel. What one remembers has to outlast a button being added. A global, not a static in bot_panels(), so a door or a button
/// that's destroyed can take itself off (below): a panel only lists its parts again when the count of buttons changes, so a blown-up
/// blast door stayed on its panel, out of sight of the hunt for what held it (statics aren't anywhere it looks), and was a hard delete.
GLOBAL_LIST_EMPTY(bot_panels_known)

/proc/bot_forget_door_part(obj/machinery/part)
	for(var/id in GLOB.bot_panels_known)
		var/datum/bot_panel/P = GLOB.bot_panels_known[id]
		P.doors -= part
		P.buttons -= part
	for(var/id in GLOB.bot_door_button_cache) //bot_doors.dm
		var/list/buttons = GLOB.bot_door_button_cache[id]
		buttons -= part

/obj/machinery/door/poddoor/Destroy()
	bot_forget_door_part(src)
	return ..()

/obj/machinery/button/door/Destroy()
	bot_forget_door_part(src)
	return ..()

/// Every set of doors that's anybody's business, worked out once.
/proc/bot_panels()
	var/static/list/panels
	var/static/buttons_seen = 0
	var/list/known = GLOB.bot_panels_known
	var/list/all_buttons = bot_instances_of(/obj/machinery/button/door)
	if(panels && buttons_seen == length(all_buttons) && !GLOB.bot_gym_running)
		return panels
	buttons_seen = length(all_buttons)
	panels = list()
	var/list/by_id = list()
	for(var/obj/machinery/button/door/B as anything in all_buttons)
		if(QDELETED(B) || B.normaldoorcontrol || !B.id)
			continue
		var/datum/bot_panel/P = by_id["[B.id]"]
		if(!P)
			P = known["[B.id]"]
			if(!P)
				P = new
				P.id = B.id
				P.name = B.name
				known["[B.id]"] = P
			P.buttons = list()
			P.doors = list()
			by_id["[B.id]"] = P
		P.buttons += B
	for(var/obj/machinery/door/poddoor/D as anything in bot_instances_of(/obj/machinery/door/poddoor))
		var/datum/bot_panel/P = by_id["[D.id]"]
		if(P && !QDELETED(D))
			P.doors += D
	for(var/id in by_id)
		var/datum/bot_panel/P = by_id[id]
		if(!length(P.doors))
			continue
		var/faces_space = FALSE
		for(var/obj/machinery/door/poddoor/D as anything in P.doors)
			P.open_normally = P.open_normally || !D.density
			P.department = P.department || bot_department_of(get_area(D))
			for(var/direction in GLOB.cardinals)
				faces_space = faces_space || isspaceturf(get_step(D, direction))
		P.kind = bot_panel_kind(P.name, faces_space)
		// Engineering's plain shutters are part of the engine, there to take a beam or a blast. Nobody drops those for a visitor.
		if(P.kind == BOT_PANEL_SHUTTERS && P.department == "engineering")
			P.kind = null
		if(P.kind && P.department)
			panels += P
	return panels

/// The panels of the departments this bot works in.
/datum/bot_brain/proc/my_panels()
	. = list()
	var/list/mine = my_departments()
	if(!length(mine))
		return
	for(var/datum/bot_panel/P as anything in bot_panels())
		if(P.department in mine)
			. += P

/// Somebody dangerous, seen lately in one of these departments, or anywhere at all for a null list. Null if there's nobody.
/datum/bot_brain/proc/threat_in(list/departments)
	for(var/datum/weakref/ref as anything in GLOB.bot_security_wanted)
		var/mob/living/carbon/human/H = ref.resolve()
		var/datum/bot_wanted/W = GLOB.bot_security_wanted[ref]
		if(!H || H.stat == DEAD || H.handcuffed || W.severity < BOT_CRIME_MAJOR || !W.last_seen || world.time > W.last_seen_at + BOT_THREAT_MEMORY)
			continue
		if(gym_run && get_area(W.last_seen) != get_area(owner))
			continue //somebody else's arena
		if(!departments || (bot_department_of(get_area(W.last_seen)) in departments))
			return H
	return null

/// A slime outside the pens, where this bot can see it.
/datum/bot_brain/proc/sees_loose_slime()
	for(var/mob/living/simple_animal/slime/S in view(BOT_SIGHT_RANGE, owner))
		if(S.stat != DEAD && !GLOB.bot_hazard_turfs[get_turf(S)])
			return TRUE
	return FALSE

/// What this bot thinks of these doors: TRUE shut, FALSE open, null nothing either way.
/datum/bot_brain/proc/panel_opinion(datum/bot_panel/P, mob/living/threat)
	var/keen = strictness >= 0.5 || is_paranoid()
	switch(P.kind)
		if(BOT_PANEL_SPACE)
			return keen ? TRUE : null //good practice
		if(BOT_PANEL_CONTAINMENT)
			if(sees_loose_slime())
				return TRUE
			return P.shut_for_threat ? FALSE : null
	if(!P.open_normally)
		return null
	var/datum/weakref/ref = P.holding
	if(ref)
		var/mob/living/carbon/human/H = ref.resolve()
		if(H && !H.handcuffed && H.stat != DEAD && world.time < P.holding_since + BOT_TRAP_LENGTH && !officer_in_sight())
			return TRUE
		P.holding = null
		return FALSE
	if(threat)
		// A suit at large: the heads and the Warden drop them whatever their nature.
		if(bot_in_nanosuit(threat) && ((work_role() in GLOB.command_positions) || work_role() == "Warden"))
			return TRUE
		return keen ? TRUE : null
	// The armory's a matter of routine, and that's the Warden's.
	if(P.department == "security" && work_role() == "Warden" && istype(get_area(P.doors[1]), /area/ai_monitored/security/armory))
		return TRUE
	return P.shut_for_threat ? FALSE : null

/datum/bot_brain/proc/officer_in_sight()
	for(var/mob/living/carbon/human/H in view(BOT_SIGHT_RANGE, owner))
		if(H != owner && H.stat == CONSCIOUS && bot_is_officer(H))
			return TRUE
	return FALSE

/// The first of its doors that isn't how it thinks it should be, and that it can do something about.
/datum/bot_brain/proc/panel_wanting_attention()
	var/list/panels = my_panels()
	if(!length(panels))
		return null
	var/list/mine = my_departments()
	var/mob/living/here = threat_in(mine)
	// The Bridge shuts for trouble anywhere, and the Brig and the armory for somebody in a nanosuit anywhere (the user's ruling, 2026-11-04).
	var/mob/living/anywhere = (("command" in mine) || ("security" in mine)) ? threat_in(null) : null
	for(var/datum/bot_panel/P as anything in panels)
		if(world.time < P.last_worked + BOT_PANEL_REST)
			continue
		var/mob/living/threat = here
		if(P.kind == BOT_PANEL_LOCKDOWN && (P.department == "command" || (P.department == "security" && bot_in_nanosuit(anywhere))))
			threat = anywhere
		if(threat && bot_armory_authorised() && P.department == "security" && istype(get_area(P.doors[1]), /area/ai_monitored/security/armory))
			threat = null //red alert: the armory opens for the officers to arm up (goals/security_tactics.dm)
		var/shut = panel_opinion(P, threat)
		if(isnull(shut) || shut == P.is_shut() || P.moving())
			continue
		var/obj/machinery/button/door/B = P.button_for(src)
		if(B && can_walk_lawfully_to(B))
			return P
	return null

/datum/bot_duty/blast_doors
	name = "seeing to the blast doors"
	tier = BOT_DUTY_URGENT
	priority = 18
	interval_min = 150
	interval_max = 300

/datum/bot_duty/blast_doors/try_start(datum/bot_brain/bot)
	var/datum/bot_panel/P = bot.panel_wanting_attention()
	return P ? bot.assign_goal(new /datum/bot_goal/work_panel(P)) : FALSE

/datum/bot_goal/work_panel
	lawful = TRUE
	exclusive = TRUE
	doing = "seeing to the blast doors"
	var/datum/bot_panel/panel

/datum/bot_goal/work_panel/New(datum/bot_panel/P)
	. = ..()
	panel = P

/datum/bot_goal/work_panel/resolve_target(datum/bot_brain/bot)
	target = panel.button_for(bot)

/datum/bot_goal/work_panel/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/work_panel(panel))
	return list(S)

/datum/bot_step/paced/work_panel
	max_clicks = 3
	var/datum/bot_panel/panel
	var/shutting = FALSE

/datum/bot_step/paced/work_panel/New(datum/bot_panel/P)
	. = ..()
	panel = P

/datum/bot_step/paced/work_panel/start(datum/bot_brain/bot)
	shutting = !panel.is_shut()
	return bot.owner.Adjacent(bot.current_goal?.target)

/datum/bot_step/paced/work_panel/do_click(datum/bot_brain/bot)
	var/obj/machinery/button/door/B = bot.current_goal?.target
	if(QDELETED(B) || !bot.owner.Adjacent(B) || panel.is_shut() == shutting)
		return FALSE
	if(panel.moving())
		wait_for = 5
		return TRUE
	bot.press_door_button(B)
	wait_for = 12
	clicks++
	return TRUE

/datum/bot_step/paced/work_panel/finish(datum/bot_brain/bot)
	if(panel.is_shut() != shutting)
		return GOAL_STEP_FAIL
	panel.shut_for_threat = shutting && panel.kind != BOT_PANEL_SPACE
	panel.last_worked = world.time
	bot_log(bot, "[shutting ? "shut" : "opened"] [panel.name]")
	bot_tally(shutting ? "doors shut" : "doors opened")
	if(panel.kind == BOT_PANEL_LOCKDOWN)
		bot_say(bot.owner, shutting ? ";[panel.name]: going down." : ";[panel.name]: lifted.")
	return GOAL_STEP_SUCCESS

/// Somebody who won't leave, and shutters within reach: they can wait for Security in here.
/datum/bot_brain/proc/shut_them_in(mob/living/carbon/human/H)
	if(strictness < 0.5 && !is_paranoid())
		return FALSE
	var/area/there = get_area(H)
	for(var/datum/bot_panel/P as anything in my_panels())
		if(P.is_shut() || P.moving() || !P.open_normally || (P.kind != BOT_PANEL_LOCKDOWN && P.kind != BOT_PANEL_SHUTTERS))
			continue
		var/obj/machinery/door/poddoor/D = P.doors[1]
		if(get_area(D) != there && get_dist(D, H) > 6)
			continue
		var/obj/machinery/button/door/B = P.button_for(src)
		if(!B || get_dist(owner, B) > 10 || !can_walk_lawfully_to(B))
			continue
		P.holding = WEAKREF(H)
		P.holding_since = world.time
		if(assign_goal(new /datum/bot_goal/work_panel(P)))
			bot_tally("shut somebody in")
			return TRUE
		P.holding = null
	return FALSE

// ---------------------------------------------------------------------------------------------
// The engine
// ---------------------------------------------------------------------------------------------

/// Whether somebody being here is somebody near the engine. Engineers aren't having it.
/proc/bot_near_the_engine(atom/A)
	var/area/where = get_area(A)
	return istype(where, /area/engine) && !istype(where, /area/engine/break_room) && !istype(where, /area/engine/atmos)

/// Word goes round the engineers: the first thing any of them does is go and look at the engine.
/proc/bot_sound_engine_alarm()
	bot_news("somebody's been messing about near the engine")
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(B.work_role() in GLOB.engineering_positions)
			B.engine_alarm_at = world.time

/datum/bot_duty/check_the_engine
	name = "checking on the engine"
	tier = BOT_DUTY_URGENT
	priority = 22
	interval_min = 30
	interval_max = 80

/datum/bot_duty/check_the_engine/applies_to(datum/bot_brain/bot)
	return bot.work_role() in GLOB.engineering_positions

/// When an engineer next goes and has a look at the running tesla, on its rounds.
GLOBAL_VAR_INIT(bot_next_engine_look, 0)

/datum/bot_duty/check_the_engine/try_start(datum/bot_brain/bot)
	var/turf/tesla = bot_caged_tesla_site() //goals/setup_tesla_engine.dm
	// A lit supermatter's looked in on as well, at its cooling loop: a saboteur switching the pumps off one by one is caught at it by
	// an engineer who's there (bot_witness_sabotage()), and nothing else saves the crystal (the user's ruling, 2026-11-07).
	var/obj/machinery/power/supermatter_crystal/crystal = tesla ? null : bot.station_crystal() //goals/setup_supermatter.dm
	if(crystal && crystal.power < 100)
		crystal = null
	var/on_rounds = FALSE
	if(!bot.engine_alarm_at || world.time > bot.engine_alarm_at + 2 MINUTES)
		// Now and then one goes and looks at a running tesla anyway: an emitter somebody's switched off is seen, not known
		// (bot_emitter_trouble()), and in a Bot Shift nobody went near one in the five minutes a saboteur's field took to fail.
		if((!tesla && !crystal) || bot.saboteur || world.time < GLOB.bot_next_engine_look || !prob(25))
			return FALSE
		on_rounds = TRUE
	bot.engine_alarm_at = 0
	if(crystal)
		var/obj/machinery/atmospherics/components/binary/pump/loop_pump
		for(var/obj/machinery/atmospherics/components/binary/pump/P as anything in bot_instances_of(/obj/machinery/atmospherics/components/binary/pump))
			if(P.z != crystal.z || get_dist(crystal, P) > 22 || !bot.sm_loop_pump(P) || bot_in_crystal_rads(P))
				continue
			if(!loop_pump || get_dist(bot.owner, P) < get_dist(bot.owner, loop_pump))
				loop_pump = P
		if(!loop_pump || !bot.can_walk_lawfully_to(loop_pump) || !bot.assign_goal(new /datum/bot_goal/stand_over_engine(loop_pump)))
			if(on_rounds)
				GLOB.bot_next_engine_look = world.time + 30 SECONDS
			return FALSE
		if(on_rounds)
			GLOB.bot_next_engine_look = world.time + rand(3 MINUTES, 6 MINUTES)
		bot_tally("engine checked")
		return TRUE
	var/obj/machinery/power/emitter/nearest
	for(var/obj/machinery/power/emitter/E as anything in bot_instances_of(/obj/machinery/power/emitter))
		// The engine's own, welded down by it: the nearest was as often as not a spare in Secure Storage behind a sealed door, the walk
		// there failed, and with the next look put off each time no engineer looked in on a running tesla in three shifts.
		if(tesla && (E.z != tesla.z || get_dist(E, tesla) > 40 || !istype(E, /obj/machinery/power/emitter/anchored) || E.state != 2)) //BOT_ENGINE_LOCAL_REACH; EMITTER_WELDED
			continue
		if(E.z == bot.owner.z && (!nearest || get_dist(bot.owner, E) < get_dist(bot.owner, nearest)))
			nearest = E
	if(!nearest || !bot.can_walk_lawfully_to(nearest) || !bot.assign_goal(new /datum/bot_goal/stand_over_engine(nearest)))
		if(on_rounds)
			GLOB.bot_next_engine_look = world.time + 30 SECONDS //somebody else, shortly
		return FALSE
	if(on_rounds)
		GLOB.bot_next_engine_look = world.time + rand(3 MINUTES, 6 MINUTES)
	bot_tally("engine checked")
	return TRUE

/// Over there, and it stays until it's happy.
/datum/bot_goal/stand_over_engine
	lawful = TRUE
	doing = "keeping an eye on the engine"

/datum/bot_goal/stand_over_engine/New(atom/A)
	. = ..()
	target = A

/datum/bot_goal/stand_over_engine/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/stand_over_engine/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/watch_engine())
	return list(S)

/datum/bot_step/paced/watch_engine
	var/ends_at = 0

/datum/bot_step/paced/watch_engine/start(datum/bot_brain/bot)
	ends_at = world.time + BOT_ENGINE_WATCH
	return TRUE

/datum/bot_step/paced/watch_engine/do_click(datum/bot_brain/bot)
	if(world.time > ends_at)
		return FALSE
	bot.idle_fidget()
	wait_for = 20
	return TRUE

/datum/bot_step/paced/watch_engine/finish(datum/bot_brain/bot)
	bot_say(bot.owner, pick(":e Engine's fine. Nobody's touched it.", ":e All good at the engine. Keep people out of here.", ":e Nothing's been touched down here."))
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// Break-ins
// ---------------------------------------------------------------------------------------------

/// What's worth breaking in for. Gloves come first: with those a bot can get in anywhere else.
GLOBAL_LIST_INIT(bot_raid_wishlist, list(
	/obj/item/clothing/gloves/color/yellow,
	/obj/item/storage/belt/utility,
	/obj/item/clothing/mask/gas,
))

/datum/bot_goal/tide/raid
	doing = "on an errand"
	var/item_type

/datum/bot_goal/tide/raid/New(wanted)
	. = ..()
	item_type = wanted

/// The nearest one of these that isn't on somebody: the thing itself, or the locker it's in.
/datum/bot_goal/tide/raid/resolve_target(datum/bot_brain/bot)
	bot.glance_at_items()
	var/atom/movable/best
	var/best_dist
	for(var/obj/item/I as anything in bot_instances_of(item_type))
		var/atom/movable/holder = bot_outermost_holder(I)
		if(QDELETED(I) || ismob(holder) || !isturf(holder.loc) || holder.z != bot.owner.z || !bot.knows_of(I)) //what it knows of (bot_knowledge.dm)
			continue
		if(bot.gym_run && get_area(holder) != get_area(bot.owner) && !istype(get_area(holder), /area/bot_gym))
			continue
		// A locked locker takes a fire axe, and no raider stops to go and get one. What's on the tables is what goes missing.
		var/obj/structure/closet/C = holder
		if(istype(C) && C.locked && !C.allowed(bot.owner))
			continue
		var/dist = get_dist(bot.owner, holder)
		if(!best || dist < best_dist)
			best = holder
			best_dist = dist
	target = best

/datum/bot_goal/tide/raid/get_strategies(datum/bot_brain/bot)
	if(istype(target, item_type))
		return list(new /datum/bot_strategy/raid_grab(item_type))
	return list(new /datum/bot_strategy/raid_locker(item_type))

/datum/bot_strategy/raid_grab/New()
	. = ..()
	steps = list(new /datum/bot_step/ensure_raid_tools(), new /datum/bot_step/move_to(), new /datum/bot_step/pickup_item())

/datum/bot_strategy/raid_grab/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_strategy/raid_locker/New(item_type)
	. = ..()
	steps = list(new /datum/bot_step/ensure_raid_tools(), new /datum/bot_step/move_to(), new /datum/bot_step/interact(), new /datum/bot_step/pickup_from_target(item_type))

/datum/bot_strategy/raid_locker/is_feasible(datum/bot_brain/bot)
	return TRUE

/// A screwdriver and a multitool for the door, from wherever anybody can get them.
/datum/bot_step/ensure_raid_tools
	var/list/tried = list()
	/// The job is the door's wires and nothing else, so without both tools there's no going over. A raid goes on without: the door
	/// may open to its ID, or stand open already. A chemist with neither tool, and none it knew of to fetch, walked to Virology's
	/// airlock to bolt it open and stood there: 50 trips to a door in twelve shifts.
	var/must_have = FALSE

/datum/bot_step/ensure_raid_tools/New(needs_both = FALSE)
	. = ..()
	must_have = needs_both

/datum/bot_step/ensure_raid_tools/execute(datum/bot_brain/bot)
	for(var/needed in list(/obj/item/screwdriver, /obj/item/multitool))
		if(bot.find_carried_tool(needed) || (needed in tried))
			continue
		tried += needed
		var/datum/bot_goal/acquire_item_type/fetch = new()
		fetch.item_type = needed
		fetch.lawful = TRUE
		if(bot.suspend_goal_for(fetch))
			return GOAL_STEP_PENDING
	if(must_have && !(bot.find_carried_tool(/obj/item/multitool) && bot.find_or_transform_tool(/obj/item/screwdriver)))
		bot_log(bot, "no screwdriver and multitool to be had for [bot.current_goal?.target] - leaving the door alone")
		return GOAL_STEP_FAIL
	return GOAL_STEP_SUCCESS

/datum/bot_goal/tide/raid/on_success(datum/bot_brain/bot)
	..()
	bot_log(bot, "got the [item_type] by breaking in")
	bot_tally("raids")
	bot.things_looted++
	if(ispath(item_type, /obj/item/clothing/gloves/color/yellow))
		bot.equip_insulated_gloves()
	if(prob(40))
		bot_say(bot.owner, pick("Nobody was using these.", "Finders keepers.", "Don't mind me.", "Worth it."))

/datum/bot_duty/raid
	name = "helping itself"
	priority = 38
	interval_min = 900
	interval_max = 2400

/datum/bot_duty/raid/applies_to(datum/bot_brain/bot)
	return bot.greytider || bot.playstyle == BOT_STYLE_POWERGAMER || bot.playstyle == BOT_STYLE_HOPPER

/datum/bot_duty/raid/try_start(datum/bot_brain/bot)
	if(!bot_mischief_allowed() || bot.owner.handcuffed || bot.is_in_active_cell(bot.owner))
		return FALSE
	if(!bot.gym_run && world.time < SSticker.round_start_time + BOT_RAID_SETTLE_IN)
		return FALSE
	var/list/wishlist = bot.playstyle == BOT_STYLE_HOPPER ? list(GLOB.bot_raid_wishlist[1]) : GLOB.bot_raid_wishlist
	for(var/item_type in wishlist)
		if(bot.find_carried_tool(item_type) || istype(bot.owner.gloves, item_type))
			continue
		return bot.assign_goal(new /datum/bot_goal/tide/raid(item_type))
	return FALSE

// ---------------------------------------------------------------------------------------------
// Open departments
// ---------------------------------------------------------------------------------------------

/// A look round for doors standing bolted open, which is what an open department comes to.
/proc/bot_refresh_open_departments()
	if(world.time < GLOB.bot_open_departments_at)
		return
	GLOB.bot_open_departments_at = world.time + BOT_OPEN_DEPT_REFRESH
	GLOB.bot_open_departments = list()
	for(var/obj/machinery/door/airlock/A as anything in bot_instances_of(/obj/machinery/door/airlock))
		if(QDELETED(A) || A.density || !A.locked)
			continue
		var/department = bot_department_of(get_area(A))
		if(department && department != "security" && department != "command")
			GLOB.bot_open_departments[department] = A

/// A way in from outside: an airlock of this department with somewhere that isn't the department on the other side of it.
/datum/bot_brain/proc/find_front_door(department)
	var/obj/machinery/door/airlock/best
	for(var/obj/machinery/door/airlock/A as anything in bot_instances_of(/obj/machinery/door/airlock))
		if(QDELETED(A) || A.z != owner.z || !A.density || A.locked || A.welded || !A.hasPower() || A.security_level || !A.requiresID())
			continue
		if(istype(A, /obj/machinery/door/airlock/external) || bot_department_of(get_area(A)) != department)
			continue
		var/outside = FALSE
		for(var/direction in GLOB.cardinals)
			var/turf/T = get_step(A, direction)
			if(!isopenturf(T))
				continue
			var/area/there = get_area(T)
			if(istype(there, /area/hallway))
				outside = TRUE
		if(outside && (!best || get_dist(owner, A) < get_dist(owner, best)) && A.allowed(owner))
			best = A
	return best

/// The easygoing staff of Science and Medical, now and then: the door bolted open, for anybody who wants to come in.
/datum/bot_duty/open_up
	name = "opening up the department"
	priority = 12
	interval_min = 1800
	interval_max = 4800

/datum/bot_duty/open_up/applies_to(datum/bot_brain/bot)
	var/job = bot.work_role()
	return bot.strictness < BOT_EASYGOING && ((job in GLOB.science_positions) || (job in GLOB.medical_positions)) && !(job in GLOB.command_positions)

/datum/bot_duty/open_up/try_start(datum/bot_brain/bot)
	if(!bot_mischief_allowed() || !prob(40) || world.time < bot.next_door_work)
		return FALSE
	bot_refresh_open_departments()
	var/department = (bot.work_role() in GLOB.science_positions) ? "science" : "medical"
	if(GLOB.bot_open_departments[department])
		return FALSE
	var/obj/machinery/door/airlock/A = bot.find_front_door(department)
	if(!A)
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/set_door(A, TRUE))

/// The strict ones, when it's their department with its door stood open.
/datum/bot_duty/close_up
	name = "putting the door right"
	priority = 13
	interval_min = 200
	interval_max = 500

/datum/bot_duty/close_up/applies_to(datum/bot_brain/bot)
	return bot.strictness >= BOT_STRICT && !bot.is_security_job()

/datum/bot_duty/close_up/try_start(datum/bot_brain/bot)
	if(world.time < bot.next_door_work)
		return FALSE
	bot_refresh_open_departments()
	if(!length(GLOB.bot_open_departments))
		return FALSE
	for(var/department in bot.my_departments())
		var/obj/machinery/door/airlock/A = GLOB.bot_open_departments[department]
		if(!QDELETED(A) && A.locked && !A.density && bot.can_walk_lawfully_to(A))
			return bot.assign_goal(new /datum/bot_goal/set_door(A, FALSE))
	return FALSE

/// Tools from wherever, over to the door, and the wires: bolted open, or back to how it should be.
/datum/bot_goal/set_door
	lawful = TRUE
	exclusive = TRUE
	doing = "doing something to a door"
	var/opening = FALSE

/datum/bot_goal/set_door/New(obj/machinery/door/airlock/A, want_open)
	. = ..()
	target = A
	opening = want_open

/datum/bot_goal/set_door/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/set_door/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/ensure_raid_tools(TRUE), new /datum/bot_step/move_to(), new /datum/bot_step/paced/set_door(opening))
	return list(S)

/// No tools to be had, or the wires are live: that's the end of that idea for a while.
/datum/bot_goal/set_door/on_give_up(datum/bot_brain/bot)
	bot.next_door_work = world.time + 5 MINUTES

/datum/bot_step/paced/set_door
	max_clicks = 3
	var/opening = FALSE
	var/done = FALSE

/datum/bot_step/paced/set_door/New(want_open)
	. = ..()
	opening = want_open

/datum/bot_step/paced/set_door/start(datum/bot_brain/bot)
	done = FALSE
	return !!bot.find_carried_tool(/obj/item/multitool) && !!bot.find_or_transform_tool(/obj/item/screwdriver)

/datum/bot_step/paced/set_door/do_click(datum/bot_brain/bot)
	var/obj/machinery/door/airlock/A = bot.current_goal?.target
	if(QDELETED(A) || !bot.owner.Adjacent(A))
		return FALSE
	if(opening)
		done = bot.try_hack_door(A)
	else
		done = bot.put_door_right(A)
	if(done && A.panel_open)
		var/obj/item/screwdriver/driver = bot.find_or_transform_tool(/obj/item/screwdriver)
		if(driver)
			bot.use_item_on(driver, A)
	return FALSE

/datum/bot_step/paced/set_door/finish(datum/bot_brain/bot)
	if(!done)
		return GOAL_STEP_FAIL
	GLOB.bot_open_departments_at = 0
	bot_tally(opening ? "departments opened" : "departments shut")
	bot_log(bot, opening ? "bolted [bot.current_goal?.target] open" : "put [bot.current_goal?.target] right")
	if(opening)
		bot_say(bot.owner, pick(";Door's open, come and help yourselves.", ";We're open, anybody who wants anything.", ";Open department, come on in."))
	else
		bot_say(bot.owner, pick("There. Stay out.", "Who keeps doing this?", ";Department's closed. Everybody who doesn't work here, out."))
	return GOAL_STEP_SUCCESS

/// Bolts up, and the door shut: the same panel a hacker went in by.
/datum/bot_brain/proc/put_door_right(obj/machinery/door/airlock/A)
	var/obj/item/screwdriver/driver = find_or_transform_tool(/obj/item/screwdriver)
	var/obj/item/multitool/tool = find_carried_tool(/obj/item/multitool)
	if(!driver || !tool)
		return FALSE
	equip_insulated_gloves()
	if(!A.panel_open)
		use_item_on(driver, A)
	if(!A.panel_open)
		return FALSE
	free_hand_for(tool)
	if(owner.get_active_held_item() != tool && !owner.put_in_hands(tool))
		return FALSE
	owner.visible_message("<span class='notice'>[owner] pulses [A]'s wires with [tool].</span>")
	if(!do_after(owner, 20, target = A))
		return FALSE
	if(A.locked)
		A.wires.pulse(WIRE_BOLTS, owner)
	A.close()
	stow_or_drop(tool)
	recover_set_down_items()
	return !A.locked

/// Crew with nothing better to do, and a department standing open.
/datum/bot_duty/visit_open_department
	name = "having a look round an open department"
	tier = BOT_DUTY_LEISURE
	interval_min = 1800
	interval_max = 4800

/datum/bot_duty/visit_open_department/try_start(datum/bot_brain/bot)
	bot_refresh_open_departments()
	var/list/open = GLOB.bot_open_departments - bot.my_departments()
	if(!length(open))
		return FALSE
	var/department = pick(open)
	var/obj/machinery/door/airlock/A = GLOB.bot_open_departments[department]
	if(QDELETED(A) || !bot.can_walk_lawfully_to(A))
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/visit_department(A))

/// In by the open door, a look around, and anything worth having on the way past.
/datum/bot_goal/visit_department
	lawful = TRUE
	doing = "having a look around"

/datum/bot_goal/visit_department/New(atom/A)
	. = ..()
	target = A

/datum/bot_goal/visit_department/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/visit_department/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/look_around_department())
	return list(S)

/datum/bot_step/paced/look_around_department
	max_clicks = 4
	optional = TRUE

/datum/bot_step/paced/look_around_department/start(datum/bot_brain/bot)
	bot_tally("open department visits")
	return TRUE

/datum/bot_step/paced/look_around_department/do_click(datum/bot_brain/bot)
	var/obj/machinery/door/airlock/A = bot.current_goal?.target
	if(QDELETED(A))
		return FALSE
	var/turf/inside
	for(var/turf/open/T in view(5, A))
		if(bot_department_of(get_area(T)) == bot_department_of(get_area(A)) && !is_blocked_turf(T, TRUE))
			inside = T
			if(prob(25))
				break
	if(inside && !bot.pursuing_kind)
		bot.pursue(inside, "wander")
	bot.pocket_something()
	wait_for = 40
	clicks++
	return TRUE

#undef BOT_PANEL_SPACE
#undef BOT_PANEL_LOCKDOWN
#undef BOT_PANEL_SHUTTERS
#undef BOT_PANEL_CONTAINMENT
#undef BOT_THREAT_MEMORY
#undef BOT_PANEL_REST
#undef BOT_TRAP_LENGTH
#undef BOT_ENGINE_WATCH
#undef BOT_RAID_SETTLE_IN
#undef BOT_OPEN_DEPT_REFRESH
#undef BOT_EASYGOING
#undef BOT_STRICT
