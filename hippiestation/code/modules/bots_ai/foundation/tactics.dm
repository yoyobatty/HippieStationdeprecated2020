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
/proc/bot_clear_line(turf/from, atom/A)
	var/turf/to_turf = get_turf(A)
	if(!from || !to_turf)
		return FALSE
	for(var/turf/T in getline(from, to_turf))
		if(T == from || T == to_turf)
			continue
		if(T.density)
			return FALSE
		for(var/atom/movable/AM in T)
			if(isliving(AM) || (AM.density && !istype(AM, /obj/structure/table)))
				return FALSE
	return TRUE

/// Anybody but `except` and itself in reach of the blast
/datum/bot_brain/proc/tank_bystanders(obj/structure/reagent_dispensers/fueltank/tank, mob/living/except)
	. = 0
	for(var/mob/living/carbon/human/H in range(BOT_TANK_CLEAR - 1, tank))
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
	if(dist < BOT_TANK_CLEAR || dist > BOT_SIGHT_RANGE || !tank_play_allowed(foe, tank))
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

/proc/bot_add_tank_opener(list/strategies)
	for(var/datum/bot_strategy/S in strategies)
		for(var/i in 1 to length(S.steps))
			if(istype(S.steps[i], /datum/bot_step/paced/strike))
				S.steps.Insert(i, new /datum/bot_step/paced/tank_opener())
				break

/// Where to shoot the tank from: floor it can walk to, out of the blast, with a clear line to the tank, the nearest such.
/datum/bot_brain/proc/tank_firing_spot(obj/structure/reagent_dispensers/fueltank/tank)
	var/turf/start = get_turf(owner)
	if(!start)
		return null
	var/list/seen = list()
	seen[start] = TRUE
	var/list/queue = list(start)
	var/at = 1
	while(at <= length(queue) && length(queue) < 400)
		var/turf/T = queue[at++]
		var/dist = get_dist(T, tank)
		if(dist >= BOT_TANK_CLEAR && dist <= BOT_SIGHT_RANGE && bot_clear_line(T, tank))
			return T
		for(var/d in GLOB.cardinals)
			var/turf/next = get_step(T, d)
			if(!next || seen[next] || next.density || isspaceturf(next) || is_blocked_turf(next, TRUE) || bot_turf_is_deadly(next))
				continue
			seen[next] = TRUE
			queue += next
	return null

/// An apex traitor's opener (above). Optional: no gun for it, no tank near its mark, or anything going wrong, and the strike goes ahead.
/datum/bot_step/paced/tank_opener
	max_clicks = 80
	optional = TRUE
	var/obj/structure/reagent_dispensers/fueltank/tank
	var/stage
	var/give_up_at = 0
	var/turf/shoot_from

/datum/bot_step/paced/tank_opener/proc/mark(datum/bot_brain/bot)
	var/datum/bot_goal/traitor_kill/G = bot.current_goal
	return istype(G) ? G.victim() : null

/datum/bot_step/paced/tank_opener/start(datum/bot_brain/bot)
	var/mob/living/V = mark(bot)
	if(!bot.is_apex() || !V || V.stat == DEAD || !isturf(V.loc) || !bot.tank_gun())
		return FALSE
	tank = bot_fuel_tank_near(V, BOT_TANK_FETCH)
	if(!tank || bot.owner.pulling || !bot.can_walk_lawfully_to(tank))
		return FALSE
	stage = "fetch"
	shoot_from = null
	give_up_at = world.time + 45 SECONDS
	bot_log(bot, "TACTIC: going to use [tank] on [V]")
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
			if(get_dist(H, V) <= 1)
				bot.stop_pursuit()
				stage = "place"
				return TRUE
			if(bot.pursue_target != V)
				bot.pursue(V, "follow", force = TRUE)
		if("place")
			// A step to the side, not on to them or back on to the tank: the tank comes on to the tile it stood on, beside them
			var/turf/here = get_turf(H)
			var/turf/aside
			for(var/d in shuffle(GLOB.cardinals.Copy()))
				var/turf/T = get_step(here, d)
				if(T && T != get_turf(V) && T != get_turf(tank) && !T.density && !is_blocked_turf(T, TRUE) && !bot_turf_is_deadly(T))
					aside = T
					break
			if(!aside || !bot.bot_step_towards(aside))
				return quit(bot, "no room to step aside")
			H.stop_pulling()
			if(get_dist(tank, V) > 1)
				return quit(bot, "it didn't end up beside them")
			bot_log(bot, "TACTIC: [tank] is beside [V] - backing off to shoot it")
			stage = "back"
			shoot_from = bot.tank_firing_spot(tank)
			if(!shoot_from)
				return quit(bot, "nowhere to shoot it from out of the blast")
		if("back")
			if(get_dist(V, tank) > 1)
				return quit(bot, "[V] moved away from it")
			if(get_dist(H, tank) >= BOT_TANK_CLEAR && bot_clear_line(get_turf(H), tank))
				bot.stop_pursuit()
				stage = "shoot"
				return TRUE
			if(bot.pursue_target != shoot_from)
				bot.pursue(shoot_from, "follow", force = TRUE)
		if("shoot")
			if(get_dist(V, tank) > 1)
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
