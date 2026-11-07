// Xenobiology's slimes let out (goals/sabotage.dm). From the management console, the way the lab's run anyway (goals/xenobiology.dm):
// the slimes picked up out of their pens and put down by the lab's door, and the door swiped open with the emag so it stays that way.
// A hungry slime out of its pen goes for the nearest person, and a slime that's fed splits.
//
// The crew's side. Everybody keeps clear of a loose slime already (bot_hazards.dm). Now somebody who sees one out of the lab calls it in,
// and Security goes and puts the ones it's been told about down, from as far off as a gun reaches.

/// How many it lets out at most.
#define BOT_SLIMES_LET_OUT 6
/// Between one call about loose slimes and the next, station-wide.
#define BOT_SLIME_CALL_GAP (1 MINUTES)

/// Area -> when slimes were last reported loose in it.
GLOBAL_LIST_EMPTY(bot_loose_slime_reports)
GLOBAL_VAR_INIT(bot_next_slime_call, 0)

/datum/bot_sabotage/slimes
	id = "slimes"
	name = "the slimes let out"

/datum/bot_sabotage/slimes/weight(datum/bot_brain/bot)
	if(!(bot.work_role() in list("Scientist", "Research Director")))
		return 0
	if(!bot.find_xeno_console() || length(bot.lab_slimes()) < 2)
		return 0
	return 4

/datum/bot_sabotage/slimes/start(datum/bot_brain/bot)
	var/obj/machinery/computer/camera_advanced/xenobio/X = bot.find_xeno_console()
	var/obj/machinery/door/airlock/exit = bot.xeno_exit_door(X)
	if(!X || !exit)
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/sabotage_slimes(X, exit, src))

/// The lab's way out to the rest of the station: an airlock with the lab on one side and somewhere else on the other.
/datum/bot_brain/proc/xeno_exit_door(obj/machinery/computer/camera_advanced/xenobio/X)
	var/area/lab = get_area(X)
	if(!lab)
		return null
	var/obj/machinery/door/airlock/best
	var/best_dist
	for(var/obj/machinery/door/airlock/A as anything in bot_instances_of(/obj/machinery/door/airlock))
		if(QDELETED(A) || A.z != X.z || get_dist(A, X) > 30 || A.welded)
			continue
		var/inside = FALSE
		var/outside = FALSE
		for(var/d in GLOB.cardinals)
			var/turf/T = get_step(A, d)
			if(!T || T.density)
				continue
			if(T.loc == lab)
				inside = TRUE
			else if(!istype(T.loc, /area/science/xenobiology))
				outside = TRUE
		if(!inside || !outside)
			continue
		var/dist = get_dist(A, X)
		if(!best || dist < best_dist)
			best = A
			best_dist = dist
	return best

/datum/bot_goal/sabotage_slimes
	doing = "working the slime pens"
	breaks_in = TRUE
	var/obj/machinery/computer/camera_advanced/xenobio/console
	var/obj/machinery/door/airlock/exit
	var/datum/bot_sabotage/act
	var/let_out = 0

/datum/bot_goal/sabotage_slimes/New(obj/machinery/computer/camera_advanced/xenobio/X, obj/machinery/door/airlock/A, datum/bot_sabotage/S)
	. = ..()
	console = X
	exit = A
	act = S

/datum/bot_goal/sabotage_slimes/resolve_target(datum/bot_brain/bot)
	if(!QDELETED(console) && !QDELETED(exit))
		target = bot.spot_beside(console) || console

/datum/bot_goal/sabotage_slimes/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/sabotage/S = new
	var/datum/bot_step/move_to/to_door = new
	to_door.step_target = exit
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/sabotage_release_slimes(src), to_door, new /datum/bot_step/sabotage_open_lab(src))
	return list(S)

/datum/bot_goal/sabotage_slimes/on_success(datum/bot_brain/bot)
	bot.sabotage_finished(act, get_area_name(console, TRUE))
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, assign_goal), new /datum/bot_goal/lay_low()))

/// In the chair: a slime a click out of its pen and down by the door, until they're all out or there are six of them.
/datum/bot_step/paced/sabotage_release_slimes
	max_clicks = 40
	var/datum/bot_goal/sabotage_slimes/goal
	var/waiting_since = 0

/datum/bot_step/paced/sabotage_release_slimes/New(datum/bot_goal/sabotage_slimes/G)
	. = ..()
	goal = G

/datum/bot_step/paced/sabotage_release_slimes/start(datum/bot_brain/bot)
	waiting_since = world.time
	return !QDELETED(goal.console) && bot.owner.Adjacent(goal.console)

/datum/bot_step/paced/sabotage_release_slimes/do_click(datum/bot_brain/bot)
	var/obj/machinery/computer/camera_advanced/xenobio/X = goal.console
	if(goal.let_out >= BOT_SLIMES_LET_OUT || QDELETED(X) || !bot.owner.Adjacent(X))
		return FALSE
	if(!goal.let_out && !bot.sabotage_unwatched(waiting_since))
		wait_for = 10
		return TRUE
	// Down by the door, on the lab side, where the console's cameras can see.
	var/list/spots = list()
	for(var/turf/open/T in range(2, goal.exit))
		if(T.loc == get_area(X) && !is_blocked_turf(T, TRUE) && bot_camera_sees(T))
			spots += T
	if(!length(spots))
		return FALSE
	for(var/mob/living/simple_animal/slime/S as anything in bot.lab_slimes())
		if(S.buckled || S.docile || get_dist(S, goal.exit) <= 2)
			continue
		bot.human_pause(X)
		bot.owner.face_atom(X)
		bot.telemetry_ui_action(X, "move slime")
		bot_warp_slime(S, pick(spots)) //xenobiology.dm
		goal.let_out++
		bot_log(bot, "SABOTAGE: moved [S] out of its pen to the lab door")
		return TRUE
	return FALSE

/datum/bot_step/paced/sabotage_release_slimes/finish(datum/bot_brain/bot)
	return goal.let_out ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// The door swiped open, for good.
/datum/bot_step/sabotage_open_lab
	var/datum/bot_goal/sabotage_slimes/goal

/datum/bot_step/sabotage_open_lab/New(datum/bot_goal/sabotage_slimes/G)
	. = ..()
	goal = G

/datum/bot_step/sabotage_open_lab/execute(datum/bot_brain/bot)
	var/obj/machinery/door/airlock/A = goal.exit
	if(QDELETED(A))
		return GOAL_STEP_SUCCESS
	if(!(A.obj_flags & EMAGGED))
		bot.swipe_door(A) //bot_doors.dm
	if(A.density && !A.locked)
		A.open()
	log_game("BOT SABOTAGE: [key_name(bot.owner)] let [goal.let_out] slimes out of [get_area_name(A, TRUE)] at [AREACOORD(A)]")
	bot_witness_sabotage(bot.owner, "is letting the slimes out of Xenobiology")
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// The crew's side: slimes loose, and anything else with teeth (carp, a morph, a space dragon that came in with nobody playing it,
// goals/ghost_roles.dm). Nobody but the creature's victims did anything about any of them.
// ---------------------------------------------------------------------------------------------

/// A slime out of the lab that's not been tamed: what nobody wants about.
/proc/bot_loose_slime(mob/living/simple_animal/slime/S)
	return istype(S) && S.stat != DEAD && !S.docile && !S.ckey && isturf(S.loc) && !istype(get_area(S), /area/science/xenobiology)

/// The animals aboard when the round starts (REF() -> TRUE): the station's pets, some of them hostile kinds on paper (the janitor's
/// lizard, the HoS's tarantula). Called in as loose and set on by Security in a batch, they're nobody's business.
GLOBAL_LIST_EMPTY(bot_resident_animals)

/proc/bot_note_resident_animals()
	for(var/mob/living/simple_animal/M in GLOB.alive_mob_list)
		GLOB.bot_resident_animals[REF(M)] = TRUE

/datum/controller/subsystem/ticker/Initialize(timeofday)
	. = ..()
	OnRoundstart(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_note_resident_animals)))

/// Something hostile loose on the station that nobody's playing: not the station's own animals, not Lavaland's.
/proc/bot_loose_beast(mob/living/simple_animal/hostile/M)
	if(!istype(M) || M.stat == DEAD || M.ckey || !isturf(M.loc) || !(is_station_level(M.z) || istype(get_area(M), /area/bot_gym)) || istype(M, /mob/living/simple_animal/hostile/asteroid))
		return FALSE
	if(GLOB.bot_resident_animals[REF(M)])
		return FALSE
	return !("neutral" in M.faction) && !("station" in M.faction)

/proc/bot_loose_creature(mob/living/simple_animal/M)
	return bot_loose_slime(M) || bot_loose_beast(M)

GLOBAL_VAR_INIT(bot_loose_slime_checked_at, -100)
GLOBAL_VAR_INIT(bot_loose_slime_any, FALSE)

/// Whether there's a slime loose anywhere, looked at every ten seconds at most: every bot's look round asks.
/proc/bot_any_loose_slime()
	if(world.time < GLOB.bot_loose_slime_checked_at + 10 SECONDS)
		return GLOB.bot_loose_slime_any
	GLOB.bot_loose_slime_checked_at = world.time
	GLOB.bot_loose_slime_any = FALSE
	for(var/mob/living/simple_animal/S in GLOB.alive_mob_list)
		if(bot_loose_creature(S))
			GLOB.bot_loose_slime_any = TRUE
			break
	return GLOB.bot_loose_slime_any

/// From the look round (keep_an_eye_out(), bot_witness.dm): one in sight, it says so on the radio, unless somebody just has.
/datum/bot_brain/proc/notice_loose_slimes()
	for(var/mob/living/simple_animal/S in view(BOT_SIGHT_RANGE, owner))
		if(!bot_loose_creature(S))
			continue
		var/area/A = get_area(S)
		GLOB.bot_loose_slime_reports[A] = world.time
		if(world.time >= GLOB.bot_next_slime_call && !gone_loud())
			GLOB.bot_next_slime_call = world.time + BOT_SLIME_CALL_GAP
			if(isslime(S))
				bot_say(owner, pick(";Slimes loose in [A.name]! Security!", ";There's slimes out in [A.name], somebody deal with them!", ";Slime out of Xenobiology, [A.name]! Stay away from it!"), TRUE)
			else
				bot_say(owner, pick(";There's a [S.name] loose in [A.name]! Security!", ";[capitalize(S.name)] in [A.name]! Somebody deal with it!", ";Security, [A.name], there's a [S.name]!"), TRUE)
		return TRUE
	return FALSE

/// Security puts down slimes it's been told are loose: the nearest one in a room somebody's called in the last five minutes.
/datum/bot_duty/loose_slimes
	name = "slimes loose"
	jobs = list("Security Officer", "Warden", "Head of Security")
	tier = BOT_DUTY_URGENT
	priority = 35
	interval_min = 30
	interval_max = 60

/datum/bot_duty/loose_slimes/try_start(datum/bot_brain/bot)
	if(!length(GLOB.bot_loose_slime_reports))
		return FALSE
	var/mob/living/simple_animal/best
	var/best_dist
	for(var/mob/living/simple_animal/S in GLOB.alive_mob_list)
		if(!bot_loose_creature(S) || S.z != bot.owner.z || GLOB.bot_loose_slime_reports[get_area(S)] < world.time - 5 MINUTES || bot.taken_by_another(S))
			continue
		var/dist = get_dist(bot.owner, S)
		if(dist <= 60 && (!best || dist < best_dist))
			best = S
			best_dist = dist
	return best ? bot.assign_goal(new /datum/bot_goal/put_down_slime(best)) : FALSE

/datum/bot_goal/put_down_slime
	doing = "dealing with a loose slime"
	exclusive = TRUE
	never_rests = TRUE

/datum/bot_goal/put_down_slime/New(mob/living/simple_animal/S)
	. = ..()
	target = S

/datum/bot_goal/put_down_slime/resolve_target(datum/bot_brain/bot)
	if(!bot_loose_creature(target))
		target = null

/datum/bot_goal/put_down_slime/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/sabotage/S = new
	S.steps = list(new /datum/bot_step/paced/shoot_slime())
	if(isslime(target) && !bot.slime_gun())
		S.steps.Insert(1, new /datum/bot_step/ensure_extinguisher()) //goals/respond_to_fire.dm: the cabinet in the hall
	return list(S)

/datum/bot_goal/put_down_slime/on_success(datum/bot_brain/bot)
	bot_tally("loose slimes put down")

/// A gun that hurts a slime: anything but a laser or the like, which heals one (slime bullet_act()).
/datum/bot_brain/proc/slime_gun()
	for(var/obj/item/gun/G in owner.GetAllContents(/obj/item/gun))
		if(!G.can_shoot())
			continue
		var/obj/item/ammo_casing/casing = G.chambered
		if(!casing && istype(G, /obj/item/gun/energy))
			var/obj/item/gun/energy/E = G
			casing = E.ammo_type[E.select]
		var/obj/item/projectile/P = casing?.BB
		if(P && P.damage > 0 && P.damage_type == BRUTE)
			return G
	return null

/// Into range and at it until it's dead, from as far off as the thing in hand reaches: water from an extinguisher (a slime takes 15-20
/// a spray, apply_water()), or a gun that does brute. A laser heals them: an officer shot one twelve times and it was the better for it.
/datum/bot_step/paced/shoot_slime
	max_clicks = 60

/datum/bot_step/paced/shoot_slime/do_click(datum/bot_brain/bot)
	var/mob/living/simple_animal/S = bot.current_goal?.target
	if(!istype(S) || QDELETED(S) || S.stat == DEAD)
		return FALSE
	var/dist = get_dist(bot.owner, S)
	// Anything but a slime: a gun on a setting that hurts (a taser's electrodes did nothing to a space dragon: goals/security_tactics.dm's
	// ready_lethal_gun(), or anything firing bullets), or what's in its hand up close.
	if(!isslime(S))
		var/obj/item/gun/lethal = bot.ready_lethal_gun() || bot.slime_gun()
		if(lethal && dist <= BOT_SIGHT_RANGE && bot.has_clear_shot(S) && world.time >= bot.next_taser_time && bot.ready_in_hand(lethal))
			if(bot.pursuing_kind)
				bot.stop_pursuit()
			bot.owner.a_intent = INTENT_HARM
			bot.owner.face_atom(S)
			bot.next_taser_time = world.time + max(CLICK_CD_RANGE, lethal.fire_delay) + 5
			bot_log(bot, "firing [lethal] at [S]")
			INVOKE_ASYNC(lethal, TYPE_PROC_REF(/obj/item/gun, afterattack), S, bot.owner, FALSE, null)
			wait_for = 5
			return TRUE
		if(dist <= 1)
			bot.owner.a_intent = INTENT_HARM
			bot.owner.face_atom(S)
			var/obj/item/held = bot.owner.get_active_held_item()
			if(held && held.force >= 5)
				held.melee_attack_chain(bot.owner, S)
			else
				bot.owner.UnarmedAttack(S)
			wait_for = 8
			return TRUE
		if(bot.pursuing_kind != "follow" || bot.pursue_target != S)
			bot.pursue(S, "follow", force = TRUE)
		wait_for = 5
		return TRUE
	var/obj/item/gun/G = bot.slime_gun()
	if(G && dist <= BOT_SIGHT_RANGE && bot.has_clear_shot(S) && world.time >= bot.next_taser_time && bot.ready_in_hand(G))
		if(bot.pursuing_kind)
			bot.stop_pursuit()
		bot.owner.a_intent = INTENT_HARM
		bot.owner.face_atom(S)
		bot.next_taser_time = world.time + max(CLICK_CD_RANGE, G.fire_delay) + 5
		bot_log(bot, "firing [G] at [S]")
		INVOKE_ASYNC(G, TYPE_PROC_REF(/obj/item/gun, afterattack), S, bot.owner, FALSE, null)
		wait_for = 5
		return TRUE
	var/obj/item/extinguisher/E = bot.find_carried_tool(/obj/item/extinguisher)
	if(E && E.reagents.total_volume >= 1 && dist <= 4 && bot.has_clear_shot(S))
		if(bot.pursuing_kind)
			bot.stop_pursuit()
		if(E.safety)
			bot.toggle_in_hand(E)
		if(bot.owner.get_active_held_item() != E)
			bot.owner.put_in_hands(E)
		bot.owner.face_atom(S)
		E.afterattack(S, bot.owner, 0)
		wait_for = 8
		return TRUE
	if(!G && (!E || E.reagents.total_volume < 1) && dist <= 1)
		bot.owner.a_intent = INTENT_HARM
		bot.owner.UnarmedAttack(S)
		wait_for = 8
		return TRUE
	if(dist > 3 && (bot.pursuing_kind != "follow" || bot.pursue_target != S))
		bot.pursue(S, "follow", force = TRUE)
	wait_for = 5
	return TRUE

/datum/bot_step/paced/shoot_slime/finish(datum/bot_brain/bot)
	var/mob/living/simple_animal/slime/S = bot.current_goal?.target
	return (!istype(S) || QDELETED(S) || S.stat == DEAD) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

#undef BOT_SLIMES_LET_OUT
#undef BOT_SLIME_CALL_GAP
