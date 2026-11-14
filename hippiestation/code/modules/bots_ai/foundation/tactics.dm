// The tactics library (the plan's foundation/tactics.dm, M2): what a room offers against somebody, by skill. Tier 1 is for anybody when it
// happens to fit, tier 2 for a robust player (BOT_SKILL_MID), tier 3 apex, set up on purpose.
//
// The fuel tank (the user's case, 2026-11-13: "a fuel tank, dragging it, pushing it into a player, backing off and shooting it, dealing an
// easy stunning blow"). A shot that does brute or burn sets one off (fueltank/bullet_act(), reagent_dispenser.dm): explosion(0, 1, 5,
// flame_range = 5), a heavy blast on the tiles beside it and a light one and flames five out. A laser or a bullet does; a disabler or a
// taser doesn't.
//  - Tier 2, in a fight (try_tank_shot()): the one it's fighting is stood beside a tank, it's out of the blast itself with a clear line to
//    the tank: it shoots the tank, not them.
//  - Tier 3, a killing (tank_opener): an apex traitor with the gun for it, a tank near its mark: it fetches the tank, drags it up to them,
//    steps aside so the tank comes on to the tile beside them, lets go, backs off out of the blast where it can see the tank, and shoots it.
//    Then it finishes them (the strike step after).
// Who may: an antagonist, whoever's about; anybody else only against somebody it's in a fight to the end with (fight_is_serious()), and
// only with nobody else in the blast.

/// How far from its mark a tank is worth fetching
#define BOT_TANK_FETCH 7

/// A fuel tank with fuel in it within `range` of A, the nearest
/proc/bot_fuel_tank_near(atom/A, range)
	var/obj/structure/reagent_dispensers/fueltank/best
	for(var/obj/structure/reagent_dispensers/fueltank/T in range(range, A))
		if(QDELETED(T) || !T.reagents?.has_reagent(/datum/reagent/fuel, 10))
			continue
		if(!best || get_dist(T, A) < get_dist(best, A))
			best = T
	return best

/// Whether a shot of this kind sets off a fuel tank (fueltank/bullet_act())
/proc/bot_projectile_pops_tanks(projectile_type)
	if(!ispath(projectile_type, /obj/item/projectile))
		return FALSE
	var/obj/item/projectile/P = projectile_type
	return !initial(P.nodamage) && initial(P.damage) > 0 && (initial(P.damage_type) == BRUTE || initial(P.damage_type) == BURN)

/// The setting of G that sets off a tank, with the charge for it: an energy gun's index into ammo_type, 0 for a loaded ballistic gun whose
/// round will; null for none.
/proc/bot_tank_setting(obj/item/gun/G)
	var/obj/item/gun/energy/E = G
	if(istype(E))
		if(!E.cell)
			return null
		for(var/i in 1 to length(E.ammo_type))
			var/obj/item/ammo_casing/energy/shot = E.ammo_type[i]
			if(istype(shot) && E.cell.charge >= shot.e_cost && bot_projectile_pops_tanks(shot.projectile_type))
				return i
		return null
	var/obj/item/gun/ballistic/B = G
	if(istype(B) && B.can_shoot())
		var/obj/item/ammo_casing/C = B.chambered
		if(!C?.BB && B.magazine && length(B.magazine.stored_ammo))
			C = B.magazine.stored_ammo[1]
		return (C && bot_projectile_pops_tanks(C.projectile_type)) ? 0 : null
	return null

/// A gun on it that would set off a tank, or null
/datum/bot_brain/proc/tank_gun()
	for(var/obj/item/gun/G in owner.GetAllContents())
		if(!isnull(bot_tank_setting(G)))
			return G
	return null

/// Nothing a shot from `from` to A would stop on: walls, people, anything dense but a table.
/proc/bot_clear_line(turf/from, atom/A, atom/movable/ignore)
	var/turf/to_turf = get_turf(A)
	if(!from || !to_turf)
		return FALSE
	for(var/turf/T in getline(from, to_turf))
		if(T == from || T == to_turf)
			continue
		if(T.density)
			return FALSE
		for(var/atom/movable/AM in T)
			if(AM == ignore) //whoever's asking, from where it stands now: it won't be there once it's moved
				continue
			if(isliving(AM) || (AM.density && !istype(AM, /obj/structure/table)))
				return FALSE
	return TRUE

/// Anybody but `except` and itself in reach of the blast
/datum/bot_brain/proc/tank_bystanders(obj/structure/reagent_dispensers/fueltank/tank, mob/living/except)
	. = 0
	for(var/mob/living/carbon/human/H in range(bot_tank_clear(tank) - 1, tank))
		if(H != owner && H != except && H.stat != DEAD)
			.++

/// Whether it would set off a tank by somebody (above).
/datum/bot_brain/proc/tank_play_allowed(mob/living/target, obj/structure/reagent_dispensers/fueltank/tank)
	if(owner.mind && length(owner.mind.antag_datums))
		return TRUE
	return fight_is_serious(target) && !tank_bystanders(tank, target)

/// A shot at the tank with G, its setting changed to one that sets it off first. TRUE if it fired.
/datum/bot_brain/proc/shoot_tank(obj/structure/reagent_dispensers/fueltank/tank, obj/item/gun/G, mob/living/by)
	if(QDELETED(tank) || !G || world.time < next_taser_time)
		return FALSE
	var/setting = bot_tank_setting(G)
	if(isnull(setting) || !bot_clear_line(get_turf(owner), tank) || !ready_in_hand(G))
		return FALSE
	var/obj/item/gun/energy/E = G
	if(istype(E) && setting && E.select != setting)
		for(var/i in 1 to length(E.ammo_type))
			if(E.select == setting)
				break
			E.select_fire(owner)
	owner.a_intent = INTENT_HARM
	owner.face_atom(tank)
	owner.changeNext_move(CLICK_CD_RANGE)
	next_taser_time = world.time + max(CLICK_CD_RANGE, G.fire_delay) + 5
	bot_log(src, "TACTIC: firing [G] at [tank][by ? " beside [by]" : ""] (dist [get_dist(owner, tank)])")
	INVOKE_ASYNC(G, TYPE_PROC_REF(/obj/item/gun, afterattack), tank, owner, FALSE, null)
	return TRUE

// ---------------------------------------------------------------------------------------------
// Tier 2: in a fight
// ---------------------------------------------------------------------------------------------

/// From handle_combat() (bot_brain.dm): the one it's fighting is stood by a tank, and it's clear of the blast with a line to the tank.
/datum/bot_brain/proc/try_tank_shot(mob/living/foe)
	if(!foe || !isturf(foe.loc) || !skill_at_least(BOT_SKILL_MID))
		return FALSE
	var/obj/structure/reagent_dispensers/fueltank/tank = bot_fuel_tank_near(foe, 1)
	if(!tank)
		return FALSE
	var/dist = get_dist(owner, tank)
	if(dist < bot_tank_clear(tank) || dist > BOT_SIGHT_RANGE || !tank_play_allowed(foe, tank))
		return FALSE
	var/obj/item/gun/G = tank_gun()
	if(!G || !shoot_tank(tank, G, foe))
		return FALSE
	bot_tally("shot a fuel tank beside somebody")
	return TRUE

// ---------------------------------------------------------------------------------------------
// Tier 3: setting one up for a killing
// ---------------------------------------------------------------------------------------------

/// Before the strike in a traitor's killing (goals/traitor.dm, goals/robust.dm)
/datum/bot_goal/traitor_kill/get_strategies(datum/bot_brain/bot)
	. = ..()
	bot_add_tank_opener(.)

/datum/bot_goal/traitor_kill/robust/get_strategies(datum/bot_brain/bot)
	. = ..()
	bot_add_tank_opener(.)

/// Before a robust killer's walk up to its mark (close_in), so a mark in a room with one way out can be waited for outside it; before the
/// strike for one that stalks (it waits for nobody to be watching first).
/proc/bot_add_tank_opener(list/strategies)
	for(var/datum/bot_strategy/S in strategies)
		for(var/i in 1 to length(S.steps))
			if(istype(S.steps[i], /datum/bot_step/paced/close_in) || istype(S.steps[i], /datum/bot_step/paced/strike))
				S.steps.Insert(i, new /datum/bot_step/paced/tank_opener())
				break

/// Where to shoot the tank from: floor it can walk to, out of the blast (bot_tank_clear(), meta_book.dm), with a clear line to the tank.
/// The casing's fragments carry past the blast, so the further the better, as far as it can see: a tile further off is worth four of walking.
/datum/bot_brain/proc/tank_firing_spot(obj/structure/reagent_dispensers/fueltank/tank)
	var/turf/start = get_turf(owner)
	if(!start)
		return null
	var/clear = bot_tank_clear(tank)
	if(clear > BOT_SIGHT_RANGE)
		return null //a small sealed room: no shooting it from anywhere it could see it from
	var/list/seen = list()
	seen[start] = 0
	var/list/queue = list(start)
	var/at = 1
	var/turf/best
	var/best_score
	while(at <= length(queue) && length(queue) < 400)
		var/turf/T = queue[at++]
		var/walk = seen[T]
		var/dist = get_dist(T, tank)
		if(dist >= clear && dist <= BOT_SIGHT_RANGE && bot_clear_line(T, tank))
			var/score = dist * 4 - walk
			if(!best || score > best_score)
				best = T
				best_score = score
		for(var/d in GLOB.cardinals)
			var/turf/next = get_step(T, d)
			if(!next || !isnull(seen[next]) || next.density || isspaceturf(next) || is_blocked_turf(next, TRUE) || bot_turf_is_deadly(next))
				continue
			seen[next] = walk + 1
			queue += next
	return best

/// An apex traitor's opener (above). Optional: no gun for it, no tank near its mark, or anything going wrong, and the strike goes ahead.
/datum/bot_step/paced/tank_opener
	max_clicks = 80
	optional = TRUE
	var/obj/structure/reagent_dispensers/fueltank/tank
	var/stage
	var/give_up_at = 0
	var/turf/shoot_from
	/// Waiting for them at the only way out of where they are (bot_only_way_out()), the tank parked here, rather than taking it to them
	var/ambush = FALSE
	var/turf/park

/datum/bot_step/paced/tank_opener/proc/mark(datum/bot_brain/bot)
	var/datum/bot_goal/traitor_kill/G = bot.current_goal
	return istype(G) ? G.victim() : null

/datum/bot_step/paced/tank_opener/start(datum/bot_brain/bot)
	var/mob/living/V = mark(bot)
	if(!bot.is_apex() || !V || V.stat == DEAD || !isturf(V.loc) || !bot.tank_gun())
		return FALSE
	ambush = FALSE
	park = null
	tank = null
	var/list/exit = bot_only_way_out(V)
	if(exit && !exit[3][get_turf(bot.owner)])
		park = bot_tank_parking(exit[1], exit[2])
		tank = park ? bot_fuel_tank_near(exit[2], 10) : null
		ambush = !!tank
	if(!ambush)
		tank = bot_fuel_tank_near(V, BOT_TANK_FETCH)
	if(!tank || bot.owner.pulling || !bot.can_walk_lawfully_to(tank))
		return FALSE
	stage = "fetch"
	shoot_from = null
	give_up_at = world.time + (ambush ? 90 SECONDS : 45 SECONDS)
	bot_log(bot, ambush ? "TACTIC: going to park [tank] at the way out of where [V] is" : "TACTIC: going to use [tank] on [V]")
	return TRUE

/// Ends the opener, saying why: the strike goes ahead either way
/datum/bot_step/paced/tank_opener/proc/quit(datum/bot_brain/bot, why)
	bot_log(bot, "TACTIC: leaving the tank ([why])")
	return FALSE

/datum/bot_step/paced/tank_opener/do_click(datum/bot_brain/bot)
	var/mob/living/V = mark(bot)
	if(stage == "done")
		return FALSE
	if(!V || V.stat == DEAD || !isturf(V.loc))
		return quit(bot, "no mark to use it on")
	if(QDELETED(tank))
		return quit(bot, "the tank's gone")
	if(world.time > give_up_at)
		return quit(bot, "taking too long")
	var/mob/living/carbon/human/H = bot.owner
	wait_for = 3
	switch(stage)
		if("fetch")
			if(H.pulling == tank)
				stage = "drag"
				return TRUE
			if(!H.Adjacent(tank))
				if(bot.pursue_target != tank)
					bot.pursue(tank, "follow", force = TRUE)
				return TRUE
			bot.stop_pursuit()
			bot.human_pause(tank)
			H.start_pulling(tank)
			if(H.pulling != tank)
				return quit(bot, "couldn't get hold of it")
			stage = "drag"
		if("drag")
			if(H.pulling != tank)
				return quit(bot, "lost hold of it on the way")
			if(ambush ? get_turf(H) == park : get_dist(H, V) <= 1)
				bot.stop_pursuit()
				stage = "place"
				return TRUE
			var/atom/drag_to = ambush ? park : V
			if(bot.pursue_target != drag_to)
				bot.pursue(drag_to, "follow", force = TRUE)
		if("place")
			// A step to the side, not on to them or back on to the tank: the tank comes on to the tile it stood on, beside them
			var/turf/here = get_turf(H)
			var/turf/aside
			for(var/d in shuffle(GLOB.cardinals.Copy()))
				var/turf/T = get_step(here, d)
				if(T && T != get_turf(V) && T != get_turf(tank) && !T.density && !is_blocked_turf(T, TRUE) && !bot_turf_is_deadly(T) && !(locate(/obj/machinery/door) in T))
					aside = T
					break
			if(!aside || !bot.bot_step_towards(aside))
				return quit(bot, "no room to step aside")
			H.stop_pulling()
			if(ambush ? get_turf(tank) != park : get_dist(tank, V) > 1)
				return quit(bot, "it didn't end up [ambush ? "where it was going" : "beside them"]")
			bot_log(bot, ambush ? "TACTIC: [tank] is parked at the way out - waiting for [V] out of the blast" : "TACTIC: [tank] is beside [V] - backing off to shoot it")
			stage = "back"
			shoot_from = bot.tank_firing_spot(tank)
			if(!shoot_from)
				return quit(bot, "nowhere to shoot it from out of the blast")
		if("back")
			if(!ambush && get_dist(V, tank) > 1)
				return quit(bot, "[V] moved away from it")
			if((get_turf(H) == shoot_from || get_dist(H, tank) >= max(bot_tank_clear(tank), get_dist(shoot_from, tank))) && bot_clear_line(get_turf(H), tank))
				bot.stop_pursuit()
				stage = ambush ? "wait" : "shoot"
				return TRUE
			if(bot.pursue_target != shoot_from)
				bot.pursue(shoot_from, "follow", force = TRUE)
		if("wait")
			// For them to come out past it: still, facing it, the gun ready
			H.face_atom(tank)
			if(get_dist(V, tank) <= 1)
				stage = "shoot"
				wait_for = bot.perception_delay()
			return TRUE
		if("shoot")
			if(get_dist(V, tank) > 1)
				if(ambush)
					stage = "wait"
					return TRUE
				return quit(bot, "[V] moved away from it")
			if(bot.shoot_tank(tank, bot.tank_gun(), V))
				bot_tally("set off a fuel tank by somebody")
				stage = "done"
				wait_for = 10
	return TRUE

/datum/bot_step/paced/tank_opener/finish(datum/bot_brain/bot)
	bot.stop_pursuit()
	if(!QDELETED(tank) && bot.owner.pulling == tank)
		bot.owner.stop_pulling()
	tank = null
	return GOAL_STEP_SUCCESS

#undef BOT_TANK_FETCH

// ---------------------------------------------------------------------------------------------
// Tier 2: welding a door shut behind it
// ---------------------------------------------------------------------------------------------
// Running from somebody dangerous, through a door, a welder on it with the fuel for it: it welds the door shut behind it, as a player being
// chased with a welder does, and whoever's after it has to cut through or go round. Only with them well back (five tiles or out of sight):
// the weld takes four seconds, stood at the door.

/datum/bot_brain
	/// The tile of the door it last walked through (close_airlock_behind(), bot_items.dm), and when
	var/turf/door_passed
	var/door_passed_at = 0
	var/welded_behind_at = 0

/datum/bot_brain/proc/note_door_passed(turf/T)
	if(T && (locate(/obj/machinery/door/airlock) in T))
		door_passed = T
		door_passed_at = world.time
		if(istype(current_goal, /datum/bot_goal/run_from))
			fled_through = T //try_barricade(), below
			fled_through_at = world.time

/// From do_step_next_node() (bot_movement.dm), before the next step. Sleeps while it welds. TRUE if it welded the door.
/datum/bot_brain/proc/weld_shut_behind()
	if(!door_passed)
		return FALSE
	var/turf/T = door_passed
	door_passed = null
	if(world.time > door_passed_at + 2 SECONDS || (welded_behind_at && world.time < welded_behind_at + 30 SECONDS) || !skill_at_least(BOT_SKILL_MID))
		return FALSE
	var/datum/bot_goal/run_from/R = current_goal
	if(!istype(R) || state != BOT_STATE_GOAL)
		return FALSE
	var/mob/living/foe = R.foe_ref?.resolve()
	if(!isliving(foe) || foe.stat != CONSCIOUS || !(outmatched_by(foe) || fight_is_serious(foe)))
		return FALSE
	if(foe.z == owner.z && get_dist(owner, foe) < 5 && (foe in view(BOT_SIGHT_RANGE, owner)))
		return FALSE //no time
	var/obj/machinery/door/airlock/A = locate() in T
	var/obj/item/weldingtool/W = find_carried_tool(/obj/item/weldingtool)
	if(!A || A.welded || !owner.Adjacent(A) || !W || W.get_fuel() < 5 || (locate(/mob/living) in T))
		return FALSE
	// Not an airlock to space: welded behind it from outside it's the way back in gone (one ran out of Atmospherics' and welded it, Bot
	// Shift found4)
	if(istype(A, /obj/machinery/door/airlock/external) || bot_turf_borders_space(get_turf(owner)) || bot_turf_borders_space(T))
		return FALSE
	welded_behind_at = world.time
	bot_log(src, "TACTIC: welding [A] shut behind me - [foe] is after me")
	if(!A.density)
		INVOKE_ASYNC(A, TYPE_PROC_REF(/obj/machinery/door, close))
		for(var/i in 1 to 8)
			sleep(2)
			if(A.density && !A.operating)
				break
	if(!A.density || A.operating || QDELETED(owner))
		return FALSE
	equip_welding_eye_protection()
	if(!W.isOn())
		toggle_in_hand(W)
	if(!W.isOn())
		return FALSE
	use_item_on(W, A, TRUE) //harm intent: on help intent an airlock takes a welder for a repair (try_unweld(), bot_breach.dm)
	if(W.isOn())
		toggle_in_hand(W)
	if(!A.welded)
		return FALSE
	bot_tally("welded a door shut behind it")
	return TRUE

// ---------------------------------------------------------------------------------------------
// Tier 2: barricading the door behind it
// ---------------------------------------------------------------------------------------------
// Run from somebody dangerous through a door into a room, and got there with them out of sight: a robust bot drags a locker or a crate
// across the inside of the doorway and stands behind it. Whoever comes through the door after it has a locker in their face and a person
// behind it to push against.

/datum/bot_brain
	/// The tile of the door it last ran through (note_door_passed() while running), and when
	var/turf/fled_through
	var/fled_through_at = 0

/datum/bot_goal/run_from/on_success(datum/bot_brain/bot)
	. = ..()
	if(!istype(src, /datum/bot_goal/run_from/gas))
		addtimer(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, try_barricade), foe_ref), 5)

/// The barricade, a moment after it's got where it was running to: TRUE if it's started on one.
/datum/bot_brain/proc/try_barricade(datum/weakref/foe_ref)
	if(QDELETED(owner) || owner.incapacitated() || state != BOT_STATE_WANDER || current_goal || !skill_at_least(BOT_SKILL_MID))
		return FALSE
	if(!fled_through || world.time > fled_through_at + 30 SECONDS)
		return FALSE
	var/mob/living/foe = foe_ref?.resolve()
	if(foe && foe.z == owner.z && (foe in view(BOT_SIGHT_RANGE, owner)))
		return FALSE //they're right there: no time
	var/turf/door_turf = fled_through
	var/area/inside = get_area(owner)
	// The tile just inside the door, and the one behind it
	var/turf/inner
	var/turf/behind
	for(var/d in GLOB.cardinals)
		var/turf/T = get_step(door_turf, d)
		var/turf/B = T && get_step(T, d)
		if(!T || !B || get_area(T) != inside || T.density || B.density || is_blocked_turf(T, TRUE) || is_blocked_turf(B, TRUE))
			continue
		inner = T
		behind = B
		break
	if(!inner)
		return FALSE
	var/obj/structure/barricade_with
	for(var/obj/structure/S in range(5, owner))
		if(S.density && get_area(S) == inside && bot_can_pull(S, owner) && bot_movable_obstacle(S, owner) && !bot_movable_volatile(S))
			if(!barricade_with || get_dist(S, owner) < get_dist(barricade_with, owner))
				barricade_with = S
	if(!barricade_with)
		return FALSE
	fled_through = null
	bot_log(src, "TACTIC: dragging [barricade_with] across the door I came in by")
	return assign_goal(new /datum/bot_goal/barricade(barricade_with, inner, behind))

/datum/bot_goal/barricade
	lawful = TRUE
	exclusive = TRUE
	doing = "barricading a door"
	var/turf/inner
	var/turf/behind

/datum/bot_goal/barricade/New(obj/structure/S, turf/in_turf, turf/behind_turf)
	. = ..()
	target = S
	inner = in_turf
	behind = behind_turf

/datum/bot_goal/barricade/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/staged())
	return list(S)

/datum/bot_goal/barricade/staged_work(datum/bot_brain/bot, datum/bot_step/staged/step)
	var/obj/structure/S = target
	var/mob/living/carbon/human/H = bot.owner
	if(QDELETED(S) || ++step.actions > 60)
		return GOAL_STEP_FAIL
	if(get_turf(S) == inner)
		if(H.pulling == S)
			H.stop_pulling()
		bot.stop_pursuit()
		bot_log(bot, "TACTIC: [S] is across the doorway")
		bot_tally("barricaded a door")
		return GOAL_STEP_SUCCESS
	if(H.pulling != S)
		if(!H.Adjacent(S))
			if(bot.pursue_target != S)
				bot.pursue(S, "follow", force = TRUE)
			return step.again(bot, 3)
		bot.stop_pursuit()
		bot.human_pause(S)
		H.start_pulling(S)
		if(H.pulling != S)
			return GOAL_STEP_FAIL
		return step.again(bot, 2)
	// In tow: to the tile just inside the door, then a step off it, and it comes on to that tile. Back from the door if the tile behind
	// is free; come in from the room side, though, and what's in tow is on that tile, and walking into it is a push that lets go of it:
	// a step to the side then, and it comes on to the doorway all the same.
	if(get_turf(H) == inner)
		bot.stop_pursuit()
		var/turf/step_to = behind
		if(get_turf(S) == behind || behind.density || is_blocked_turf(behind, TRUE))
			step_to = null
			for(var/d in GLOB.cardinals)
				var/turf/T = get_step(inner, d)
				if(T && T != behind && T != get_turf(S) && get_area(T) == get_area(inner) && !T.density && !is_blocked_turf(T, TRUE) && !(locate(/obj/machinery/door) in T))
					step_to = T
					break
		if(!step_to || !bot.bot_step_towards(step_to))
			return ++step.tries > 4 ? GOAL_STEP_FAIL : step.again(bot, 3)
		return step.again(bot, 2)
	if(bot.pursue_target != inner)
		bot.pursue(inner, "follow", force = TRUE)
	return step.again(bot, 3)

// ---------------------------------------------------------------------------------------------
// Tier 3: the tank at the only way out
// ---------------------------------------------------------------------------------------------
// The opener's other way (tank_opener): its mark in a room with one door, an apex killer doesn't go in after them with a tank in tow. It
// parks the tank beside the outside of that door, backs off out of the blast where it can see the tank, and waits for them to come out
// past it.

/// The one door out of where M is, if there's only one: a flood from it, through anything but doors, walls and windows. list(airlock, tile
/// outside it, the room's tiles), or null.
/proc/bot_only_way_out(mob/living/M)
	var/turf/start = get_turf(M)
	if(!start)
		return null
	var/list/seen = list()
	seen[start] = TRUE
	var/list/queue = list(start)
	var/at = 1
	var/obj/machinery/door/airlock/door
	while(at <= length(queue))
		if(length(queue) > 200)
			return null //not a room, a station
		var/turf/T = queue[at++]
		for(var/d in GLOB.cardinals)
			var/turf/N = get_step(T, d)
			if(!N || seen[N] || N.density)
				continue
			seen[N] = TRUE
			var/obj/machinery/door/airlock/A = locate() in N
			if(A)
				if(door && door != A)
					return null //two ways out
				door = A
				continue
			var/blocked = FALSE
			for(var/obj/O in N)
				if(O.density && (istype(O, /obj/structure/window) || istype(O, /obj/structure/grille) || istype(O, /obj/machinery/door)))
					blocked = TRUE
					break
			if(!blocked)
				queue += N
	if(!door)
		return null
	for(var/d in GLOB.cardinals)
		var/turf/out = get_step(door, d)
		if(out && !seen[out] && !out.density)
			return list(door, out, seen)
	return null

/// Where to park the tank: beside the tile outside the door, not on the way through it.
/proc/bot_tank_parking(obj/machinery/door/airlock/door, turf/out)
	for(var/d in GLOB.cardinals)
		var/turf/P = get_step(out, d)
		if(!P || P == get_turf(door) || P.density || is_blocked_turf(P, TRUE) || get_step(door, get_dir(door, out)) == P)
			continue
		if(get_dir(out, P) == get_dir(door, out))
			continue //straight on from the door is where they'll walk
		return P
	return null
