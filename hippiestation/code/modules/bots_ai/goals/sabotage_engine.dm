// The engine let loose (goals/sabotage.dm). Which engine is the map's:
//
//  - the tesla (Hippie Station): its emitters switched off and the particle accelerator turned all the way up. The field has about
//    seventy seconds in it with the emitters gone, and a ball fed harder grows faster once it's out.
//  - the supermatter (the rest): the pumps and filters on its cooling loop switched off, so the crystal cooks in its own heat.
//    Only the ones it can get to: Box Station's one pump outside the crystal's radiation is between the chamber's two doors, and
//    the saboteurs that picked it gave up on it in the same tick, three times each, every shift. The rest of Box's loop is in among
//    the radiation of a crystal at full power (six tiles out), where nobody goes without a radiation suit (bot_hazards.dm): the
//    saboteur gets one out of Engineering's radiation closets and puts it on first.
//
// The crew's side was there already, and this is what it's for: engineers drop everything when the tesla's emitters go down
// (engine_alarm, setup_tesla_engine.dm) and put the supermatter's loop back as they find it (the supermatter duty walks its
// checklist again, setup_supermatter.dm). A loose ball everybody keeps clear of (bot_hazards.dm). Whether the engineers get there
// in time is the round's business.

/datum/bot_sabotage/engine
	id = "engine"
	name = "the engine let loose"

/datum/bot_sabotage/engine/weight(datum/bot_brain/bot)
	if(!length(bot.engine_sabotage_targets()))
		return 0
	return (bot.work_role() in list("Station Engineer", "Chief Engineer", "Atmospheric Technician")) ? 5 : 1

/datum/bot_sabotage/engine/start(datum/bot_brain/bot)
	var/list/targets = bot.engine_sabotage_targets()
	return length(targets) ? bot.assign_goal(new /datum/bot_goal/sabotage_engine(targets, src)) : FALSE

/// What there is to switch off on the station's running engine, and the accelerator to turn up: nothing if it isn't running.
/datum/bot_brain/proc/engine_sabotage_targets()
	. = list()
	var/turf/site = bot_caged_tesla_site() //setup_tesla_engine.dm
	if(site)
		for(var/obj/machinery/power/emitter/anchored/E as anything in bot_instances_of(/obj/machinery/power/emitter/anchored))
			if(E.active && E.z == site.z && get_dist(E, site) <= 40)
				. += E
		var/obj/machinery/particle_accelerator/control_box/CB = find_pa_console()
		if(CB?.active && CB.strength < CB.strength_upper_limit)
			. += CB
		return
	var/obj/machinery/power/supermatter_crystal/S = station_crystal() //setup_supermatter.dm: null where the tesla's the engine
	if(QDELETED(S) || S.power < 100)
		return
	// Not the ones in among the crystal's radiation: nobody walks in there (bot_hazards.dm), and a saboteur on Box Station tried the pump
	// by the chamber three times with "no path" each time.
	var/list/parts = list()
	var/list/hot = list() //in among the radiation
	for(var/obj/machinery/atmospherics/components/binary/pump/P as anything in bot_instances_of(/obj/machinery/atmospherics/components/binary/pump))
		if(P.on && P.z == S.z && get_dist(S, P) <= 22 && sm_loop_pump(P))
			if(bot_in_crystal_rads(P))
				hot += P
			else
				parts += P
	for(var/obj/machinery/atmospherics/components/trinary/filter/F as anything in bot_instances_of(/obj/machinery/atmospherics/components/trinary/filter))
		if(F.on && F.z == S.z && get_dist(S, F) <= 22 && sm_in_engine_room(F))
			if(bot_in_crystal_rads(F))
				hot += F
			else
				parts += F
	if(length(parts))
		var/obj/item/card/id/id_card = owner.get_idcard(TRUE)
		begin_reach_scope()
		for(var/atom/A as anything in parts)
			var/list/route = bot_path_to(get_turf(A), /turf/proc/bot_weighted_distance, /turf/proc/bot_reachable_permissive, id_card, !can_path_through_space())
			if(length(route) || get_turf(A) == get_turf(owner))
				. += A
		end_reach_scope()
	if(!length(.) && length(hot) && (bot_rad_suited(owner) || find_rad_suit()))
		. = hot //with a radiation suit on (/datum/bot_step/suit_up_for_rads)

/// A radiation suit it has, or one lying about or in a closet it can open, on this level.
/datum/bot_brain/proc/find_rad_suit()
	for(var/obj/item/clothing/suit/radiation/R as anything in bot_instances_of(/obj/item/clothing/suit/radiation))
		var/turf/T = get_turf(R)
		if(QDELETED(R) || !T || T.z != owner.z)
			continue
		if(R.loc == owner || (R in owner.GetAllContents()) || isturf(R.loc))
			return R
		var/obj/structure/closet/C = R.loc
		if(istype(C) && (!C.secure || !C.locked || C.allowed(owner)))
			return R
	return null

/datum/bot_goal/sabotage_engine
	doing = "checking on the engine"
	breaks_in = TRUE
	var/list/parts
	var/datum/bot_sabotage/act
	var/done = 0

/datum/bot_goal/sabotage_engine/New(list/targets, datum/bot_sabotage/A)
	. = ..()
	parts = targets
	act = A

/datum/bot_goal/sabotage_engine/resolve_target(datum/bot_brain/bot)
	for(var/atom/A as anything in parts)
		if(!QDELETED(A))
			target = A
			return

/datum/bot_goal/sabotage_engine/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/sabotage/S = new
	S.steps = list()
	for(var/atom/A as anything in parts)
		if(!QDELETED(A) && bot_in_crystal_rads(A) && !bot_rad_suited(bot.owner))
			S.steps += new /datum/bot_step/suit_up_for_rads()
			break
	for(var/atom/A as anything in parts)
		if(QDELETED(A))
			continue
		var/datum/bot_step/move_to/to_part = new
		to_part.step_target = A
		S.steps += list(to_part, new /datum/bot_step/paced/sabotage_switch_off(src, A))
	return list(S)

/datum/bot_goal/sabotage_engine/on_success(datum/bot_brain/bot)
	if(!done)
		return
	bot.sabotage_finished(act, get_area_name(bot.owner, TRUE))
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, assign_goal), new /datum/bot_goal/lay_low()))

/// At one of them: nobody looking, and it's off (or the accelerator's up).
/datum/bot_step/paced/sabotage_switch_off
	max_clicks = 40
	var/datum/bot_goal/sabotage_engine/goal
	var/atom/part
	var/waiting_since = 0
	var/switched = FALSE

/datum/bot_step/paced/sabotage_switch_off/New(datum/bot_goal/sabotage_engine/G, atom/A)
	. = ..()
	goal = G
	part = A

/datum/bot_step/paced/sabotage_switch_off/start(datum/bot_brain/bot)
	waiting_since = world.time
	return TRUE

/datum/bot_step/paced/sabotage_switch_off/do_click(datum/bot_brain/bot)
	if(switched || QDELETED(part) || !bot.owner.Adjacent(part))
		return FALSE
	if(!bot.sabotage_unwatched(waiting_since))
		wait_for = 10
		return TRUE
	bot.human_pause(part)
	bot.telemetry_ui_action(part, "sabotage")
	if(istype(part, /obj/machinery/power/emitter))
		var/obj/machinery/power/emitter/E = part
		E.active = FALSE
		E.update_icon()
	else if(istype(part, /obj/machinery/particle_accelerator/control_box))
		var/obj/machinery/particle_accelerator/control_box/CB = part
		while(CB.strength < CB.strength_upper_limit)
			CB.add_strength()
	else if(istype(part, /obj/machinery/atmospherics/components/binary/pump))
		var/obj/machinery/atmospherics/components/binary/pump/P = part
		P.on = FALSE
		P.update_icon()
		P.investigate_log("was turned off by [key_name(bot.owner)] (bot saboteur)", INVESTIGATE_ATMOS)
	else if(istype(part, /obj/machinery/atmospherics/components/trinary/filter))
		var/obj/machinery/atmospherics/components/trinary/filter/F = part
		F.on = FALSE
		F.update_icon()
		F.investigate_log("was turned off by [key_name(bot.owner)] (bot saboteur)", INVESTIGATE_ATMOS)
	switched = TRUE
	goal.done++
	bot_log(bot, "SABOTAGE: [istype(part, /obj/machinery/particle_accelerator/control_box) ? "turned [part] all the way up" : "switched off [part]"]")
	log_game("BOT SABOTAGE: [key_name(bot.owner)] sabotaged [part] at [AREACOORD(part)]")
	bot_witness_sabotage(bot.owner, "is messing with the engine")
	return FALSE

/datum/bot_step/paced/sabotage_switch_off/finish(datum/bot_brain/bot)
	return GOAL_STEP_SUCCESS //one it couldn't get at doesn't stop it going on to the next

/// Into a radiation suit before going in among a running crystal's radiation: fetched from a radiation closet if it hasn't one.
/datum/bot_step/suit_up_for_rads
	var/fetched = FALSE

/datum/bot_step/suit_up_for_rads/execute(datum/bot_brain/bot)
	if(bot_rad_suited(bot.owner))
		return GOAL_STEP_SUCCESS
	var/obj/item/clothing/suit/radiation/R = locate() in bot.owner.GetAllContents()
	if(R)
		if(!bot.wear(R, ITEM_SLOT_OCLOTHING))
			return GOAL_STEP_FAIL
		var/obj/item/clothing/head/radiation/hood = locate() in bot.owner.GetAllContents()
		if(hood)
			bot.wear(hood, ITEM_SLOT_HEAD)
		bot_log(bot, "suited up against the crystal's radiation")
		return bot_rad_suited(bot.owner) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
	if(fetched)
		return GOAL_STEP_FAIL
	fetched = TRUE
	var/datum/bot_goal/acquire_item_type/fetch = new
	fetch.item_type = /obj/item/clothing/suit/radiation
	return bot.suspend_goal_for(fetch) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

// --- Out of its cage ---

/// When somebody last called in an engine that's got loose.
GLOBAL_VAR_INIT(bot_engine_loose_called, 0)

/// A tesla ball out of its cage (bot_caged_tesla_site(), setup_tesla_engine.dm), or a singularity nowhere near a running field: what a
/// delaminating crystal can leave behind. Not the little balls that orbit a big one.
/proc/bot_loose_engine()
	for(var/obj/singularity/S as anything in GLOB.singularities)
		if(QDELETED(S) || !(is_station_level(S.z) || is_reserved_level(S.z))) //reserved: the Bot Gym's arenas
			continue
		if(istype(S, /obj/singularity/energy_ball))
			var/obj/singularity/energy_ball/ball = S
			if(ball.miniball)
				continue
			var/turf/site = GLOB.bot_tesla_site
			if(site && site.z == S.z && get_dist(S, site) <= 10)
				continue
			return S
		var/caged = FALSE
		for(var/obj/machinery/field/generator/G in range(10, S))
			if(G.active == 2) //FG_ONLINE
				caged = TRUE
				break
		if(!caged)
			return S
	return null

/// Whoever's in sight of it calls it in on the common channel, once in a while: everybody keeps clear of it (bot_hazards.dm), and
/// a head who hears it calls the shuttle (call_shuttle.dm). A loose tesla wrecked the station with nobody saying a word, and the
/// shuttle came when the shift was up.
/proc/bot_notice_loose_engine()
	if(GLOB.bot_engine_loose_called && world.time < GLOB.bot_engine_loose_called + 5 MINUTES)
		return
	var/obj/singularity/S = bot_loose_engine()
	if(!S)
		return
	for(var/mob/living/carbon/human/H in hearers(9, S))
		var/datum/bot_brain/B = H.bot_brain
		if(!B || B.saboteur || H.stat != CONSCIOUS || H.incapacitated())
			continue
		GLOB.bot_engine_loose_called = world.time
		var/what = istype(S, /obj/singularity/energy_ball) ? "tesla" : "singularity"
		bot_say(H, pick(";The [what]'s loose! It's in [get_area_name(S, TRUE)], keep away from it!", ";[uppertext(what)]'S OUT! [get_area_name(S, TRUE)]! Get clear!"))
		bot_tally("loose engine called in")
		bot_log(B, "called in the loose [what] in [get_area_name(S, TRUE)]")
		log_game("BOT ENGINE: [key_name(H)] called in the loose [what] at [AREACOORD(S)]")
		return
