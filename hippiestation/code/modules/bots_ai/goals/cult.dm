// The blood cult (bot-cult=N on a Bot Shift, or bot_spawn_cult()): crew bots with the game's own cultist datum, growing the cult the way
// players do it:
//
//  - An Offer rune somewhere quiet in maintenance, scribed in the scribe's own blood (the dagger's scribe_rune() delay and damage; its menu
//    takes a client, so the choice is made here).
//  - Two of them for each conversion. One waits beside the rune. The other finds somebody on their own, stuns them with blood magic (the
//    stun spell's flash, paralysis and silence) and shackles them (the shackles spell's cult cuffs), drags them to the rune and onto it,
//    and invokes it with the first beside it: the rune does the rest (runes.dm).
//  - The sacrifice the Geometer asks for (the cult's first objective, somebody it can't convert: Security or a head) the same way, once
//    there are three of them: the rune won't take that one with fewer chanting.
//  - Nine of them and the sacrifice made: the leader draws Nar'Sie's rune where the veil is weak and the rest stand on it to call the
//    Geometer (below).
//  - In between they keep their jobs and their mouths shut. A convert who's a bot joins in.

#define BOT_CULT_OP_TIMEOUT (3 MINUTES)
/// Between one conversion and the next.
#define BOT_CULT_OP_GAP (2 MINUTES)
/// Nobody else this close, for somebody to count as on their own.
#define BOT_CULT_ALONE 6

/datum/bot_cult
	/// The game's own cult team, for everybody made a cultist here to share.
	var/datum/team/cult/antag_team
	var/list/members = list()
	var/obj/effect/rune/convert/rune
	var/datum/weakref/victim_ref
	var/datum/bot_brain/stunner
	var/datum/bot_brain/helper
	/// The third pair of hands a sacrifice needs.
	var/datum/bot_brain/helper2
	var/sacrificing = FALSE
	var/op_started = 0
	var/next_op = 0
	var/converted = 0

GLOBAL_DATUM(bot_cult, /datum/bot_cult)

/datum/bot_brain
	var/bot_cultist = FALSE
	var/cult_gather_retry_at = 0

/proc/bot_spawn_cult(count)
	if(!GLOB.bot_cult)
		GLOB.bot_cult = new
	var/made = 0
	for(var/datum/bot_brain/B as anything in shuffle(GLOB.bot_brains.Copy()))
		if(made >= count)
			break
		var/mob/living/carbon/human/H = B.owner
		if(QDELETED(H) || H.stat == DEAD || !H.mind || B.bot_traitor || B.op_team || B.bot_wizard || B.bot_cultist || !is_station_level(H.z))
			continue
		var/role = B.work_role()
		if((role in GLOB.security_positions) || (role in GLOB.command_positions) || HAS_TRAIT(H, TRAIT_MINDSHIELD))
			continue
		var/datum/antagonist/cult/C = new
		C.give_equipment = TRUE //the dagger and the runed metal, as the cult game mode hands out
		if(H.mind.add_antag_datum(C, GLOB.bot_cult.antag_team))
			GLOB.bot_cult.antag_team = C.cult_team
			made++
	log_game("BOT CULT: [made] cultists")
	return made

/// Anybody who becomes a cultist, from the start or off the rune: a bot one joins the bot cult.
/datum/antagonist/cult/on_gain()
	. = ..()
	var/mob/living/carbon/human/H = owner?.current
	if(!istype(H) || !H.bot_brain)
		return
	if(!GLOB.bot_cult)
		GLOB.bot_cult = new
	H.bot_brain.bot_cultist = TRUE
	H.bot_brain.duties = null //worked out once and kept: this time there's one more (bot_duties.dm)
	GLOB.bot_cult.members |= H.bot_brain
	log_game("BOT CULT: [H] is a cultist now")

/datum/bot_cult/proc/living()
	. = list()
	for(var/datum/bot_brain/B as anything in members)
		if(!QDELETED(B) && !QDELETED(B.owner) && B.owner.stat != DEAD && iscultist(B.owner))
			. += B

/// Whoever draws the rune and plans the conversions: the first of them still about.
/datum/bot_cult/proc/leader()
	var/list/alive = living()
	return length(alive) ? alive[1] : null

/// The conversion in hand, if it's still going; otherwise it's dropped.
/datum/bot_cult/proc/check_op()
	if(sacrificing && sac_objective()?.check_completion()) //the rune gibs them: there's nobody left to check on
		log_game("BOT CULT: the sacrifice is made")
		end_op()
		return
	var/mob/living/carbon/human/V = victim_ref?.resolve()
	if(!V)
		return
	if((V.stat == DEAD && !sacrificing) || iscultist(V) || world.time > op_started + BOT_CULT_OP_TIMEOUT || !(stunner in living()) || !(helper in living()) || (sacrificing && !(helper2 in living())))
		if(iscultist(V))
			converted++
			log_game("BOT CULT: [V] converted ([converted] so far)")
		else
			log_game("BOT CULT: dropped [V][sacrificing ? " (the sacrifice)" : ""]: dead [V.stat == DEAD], timed out [world.time > op_started + BOT_CULT_OP_TIMEOUT], taker [stunner in living()], waiter [helper in living()]")
		end_op()

/datum/bot_cult/proc/end_op()
	if(stunner?.owner?.pulling)
		stunner.owner.stop_pulling()
	victim_ref = null
	stunner = null
	helper = null
	helper2 = null
	sacrificing = FALSE
	next_op = world.time + BOT_CULT_OP_GAP

/datum/bot_cult/proc/sac_objective()
	RETURN_TYPE(/datum/objective/sacrifice)
	for(var/datum/objective/sacrifice/S in antag_team?.objectives)
		return S

/// Nobody else this close to them.
/proc/bot_cult_alone(mob/living/carbon/human/H)
	for(var/mob/living/carbon/human/other in view(BOT_CULT_ALONE, H))
		if(other != H && other.stat == CONSCIOUS && !iscultist(other))
			return FALSE
	return TRUE

/// The one the Geometer asked for, on their own: the nearest of them takes them and two more wait at the rune.
/datum/bot_cult/proc/plan_sacrifice(list/alive)
	var/datum/objective/sacrifice/S = sac_objective()
	var/mob/living/carbon/human/H = S?.target?.current
	if(!S || S.check_completion() || !istype(H) || H.stat == DEAD || iscultist(H) || H.z != rune.z || is_convertable_to_cult(H, antag_team) || !bot_cult_alone(H))
		return FALSE //one they could convert gets converted by the rune instead, and the objective's still undone
	var/datum/bot_brain/taker
	for(var/datum/bot_brain/B as anything in alive)
		if(!taker || get_dist(B.owner, H) < get_dist(taker.owner, H))
			taker = B
	var/list/rest = alive - taker
	var/datum/bot_brain/first
	var/datum/bot_brain/second
	for(var/datum/bot_brain/B as anything in rest)
		if(!first || get_dist(B.owner, rune) < get_dist(first.owner, rune))
			second = first
			first = B
		else if(!second || get_dist(B.owner, rune) < get_dist(second.owner, rune))
			second = B
	if(!taker || !first || !second || get_dist(taker.owner, H) > 60)
		return FALSE
	victim_ref = WEAKREF(H)
	stunner = taker
	helper = first
	helper2 = second
	sacrificing = TRUE
	op_started = world.time
	log_game("BOT CULT: going for the sacrifice, [H]: [stunner.owner] takes them, [helper.owner] and [helper2.owner] wait at the rune")
	return TRUE

/// Somebody on their own, who the rune would take, and the two cultists nearest them.
/datum/bot_cult/proc/plan_op()
	var/list/alive = living()
	if(length(alive) < 2 || QDELETED(rune))
		return
	if(length(alive) >= 3 && plan_sacrifice(alive))
		return
	var/datum/bot_brain/first = alive[1]
	var/datum/antagonist/cult/C = first.owner.mind.has_antag_datum(/datum/antagonist/cult, TRUE)
	var/mob/living/carbon/human/best
	var/datum/bot_brain/best_stunner
	var/best_dist
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.stat != CONSCIOUS || iscultist(H) || H.z != rune.z || !H.mind || !is_convertable_to_cult(H, C?.cult_team))
			continue
		var/role = H.bot_brain ? H.bot_brain.work_role() : H.mind.assigned_role
		if((role in GLOB.security_positions) || (role in GLOB.command_positions))
			continue
		if(!bot_cult_alone(H))
			continue
		for(var/datum/bot_brain/B as anything in alive)
			var/dist = get_dist(B.owner, H)
			if(!best || dist < best_dist)
				best = H
				best_stunner = B
				best_dist = dist
	if(!best || best_dist > 60)
		return
	victim_ref = WEAKREF(best)
	stunner = best_stunner
	var/helper_dist
	for(var/datum/bot_brain/B as anything in alive)
		if(B == stunner)
			continue
		var/dist = get_dist(B.owner, rune)
		if(!helper || dist < helper_dist)
			helper = B
			helper_dist = dist
	op_started = world.time
	log_game("BOT CULT: going for [best]: [stunner.owner] takes them, [helper.owner] waits at the rune")

/datum/bot_duty/cult
	name = "the Geometer's work"
	tier = BOT_DUTY_URGENT
	interrupts = TRUE
	priority = 7
	interval_min = 20
	interval_max = 50

/datum/bot_duty/cult/applies_to(datum/bot_brain/bot)
	return bot.bot_cultist

/datum/bot_duty/cult/try_start(datum/bot_brain/bot)
	return bot.cult_business()

/// One with a part in what's going on now drops whatever it's doing for it. Only a bot with nothing on looked: a botanist sent to take the
/// sacrifice watered trays the whole three minutes, six times over.
/datum/bot_duty/cult/should_interrupt(datum/bot_brain/bot)
	var/datum/bot_cult/C = GLOB.bot_cult
	var/static/list/cult_goals = typecacheof(list(/datum/bot_goal/cult_take, /datum/bot_goal/cult_wait, /datum/bot_goal/cult_summon, /datum/bot_goal/cult_gather, /datum/bot_goal/cult_scribe))
	if(!C || cult_goals[bot.current_goal?.type] || cult_goals[bot.suspended_goal?.type]) //suspended: off for the tools to hack a door on the way, say
		return FALSE
	if(C.victim_ref)
		return bot == C.stunner || bot == C.helper || bot == C.helper2
	if(!QDELETED(C.big_rune))
		return !C.big_rune.used
	return bot == (C.summoner || C.leader()) && C.ready_to_summon() && world.time >= C.next_summon_try

/// Beside the rune for the one being brought, or with them on it for the others: it stays there. Back to wandering in between, it walked
/// off from the rune a moment after getting there, and was never beside it with the victim on it and the rest there too: the
/// conversion ran out of time three times out of four.
/datum/bot_duty/cult/keep_holding(datum/bot_brain/bot)
	var/datum/bot_cult/C = GLOB.bot_cult
	if(C && !QDELETED(C.big_rune))
		return !bot.owner.incapacitated() && C.on_big_rune(bot)
	if(!C || QDELETED(C.rune) || !C.victim_ref?.resolve() || bot.owner.incapacitated() || !bot.owner.Adjacent(C.rune))
		return FALSE
	return bot == C.helper || bot == C.helper2 || bot == C.stunner

/// Waiting by the rune: held there (keep_holding() above).
/datum/bot_brain/proc/cult_hold()
	holding_duty = bot_duty_of(/datum/bot_duty/cult)
	return TRUE

/datum/bot_brain/proc/cult_business()
	var/datum/bot_cult/C = GLOB.bot_cult
	if(!C || !iscultist(owner) || owner.incapacitated())
		return FALSE
	C.check_op()
	if(!C.victim_ref && C.ready_to_summon())
		return summon_business(C)
	if(QDELETED(C.rune))
		return src == C.leader() ? assign_goal(new /datum/bot_goal/cult_scribe()) : FALSE
	var/mob/living/carbon/human/V = C.victim_ref?.resolve()
	if(!V)
		if(src != C.leader() || world.time < C.next_op)
			return FALSE
		C.plan_op()
		V = C.victim_ref?.resolve()
		if(!V)
			return FALSE
	if(src == C.helper || src == C.helper2)
		return owner.Adjacent(C.rune) ? cult_hold() : assign_goal(new /datum/bot_goal/cult_wait(C.rune))
	if(src != C.stunner)
		return FALSE
	if(V.loc == C.rune.loc)
		if(!owner.Adjacent(C.rune))
			return assign_goal(new /datum/bot_goal/cult_wait(C.rune))
		if(C.helper?.owner?.Adjacent(C.rune) && (!C.sacrificing || C.helper2?.owner?.Adjacent(C.rune)))
			human_pause(C.rune)
			telemetry_clicked(C.rune)
			usr = owner //the soulstone a sacrifice leaves is made out to whoever clicked (runes.dm)
			C.rune.attack_hand(owner) //it gathers the cultists beside it (can_invoke())
			C.check_op()
			return TRUE
		return cult_hold() //waiting on the others
	return assign_goal(new /datum/bot_goal/cult_take(V, C.rune))

// ---------------------------------------------------------------------------------------------
// The rune
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/cult_scribe
	doing = "looking for somewhere quiet"

/datum/bot_goal/cult_scribe/resolve_target(datum/bot_brain/bot)
	target = GLOB.bot_cult?.rune_spot()

/// Quiet rooms anybody can walk into: maintenance would do for the scribe, but most of a cult can't get in there.
GLOBAL_LIST_INIT(bot_cult_rune_areas, typecacheof(list(/area/crew_quarters/toilet, /area/crew_quarters/dorms, /area/crew_quarters/locker, /area/library, /area/crew_quarters/fitness)))

/// Somewhere quiet that every one of them can walk to, a few tries' worth.
/datum/bot_cult/proc/rune_spot()
	var/list/alive = living()
	if(!length(alive))
		return null
	var/datum/bot_brain/first = alive[1]
	var/list/candidates = list()
	for(var/area/A as anything in GLOB.sortedAreas)
		if(!GLOB.bot_cult_rune_areas[A.type] || A.z != first.owner.z)
			continue
		for(var/turf/open/floor/F in A)
			if(!is_blocked_turf(F, TRUE) && !(locate(/obj/effect/rune) in F))
				candidates += F
	// The leader and two more is all the rune ever needs at once (three for the sacrifice). Every one of them was asked for: a cult of nine
	// never once found a quiet room all nine could walk into, and never drew a rune.
	var/need = min(3, length(alive))
	for(var/i in 1 to 6)
		if(!length(candidates))
			break
		var/turf/T = pick_n_take(candidates)
		if(!first.can_walk_lawfully_to(T))
			continue
		var/can = 1
		for(var/datum/bot_brain/B as anything in alive - first)
			if(can >= need)
				break
			if(B.can_walk_lawfully_to(T))
				can++
		if(can >= need)
			return T
	return null

/datum/bot_goal/cult_scribe/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/cult/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/cult_scribe())
	return list(S)

/datum/bot_strategy/cult/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// The dagger's rite, in the scribe's own blood: the arm cut, the wait, the rune.
/datum/bot_step/paced/cult_scribe
	max_clicks = 3
	var/stage = 0

/datum/bot_step/paced/cult_scribe/start(datum/bot_brain/bot)
	stage = 0
	return TRUE

/datum/bot_step/paced/cult_scribe/do_click(datum/bot_brain/bot)
	var/mob/living/carbon/human/H = bot.owner
	var/turf/T = get_turf(H)
	var/obj/item/melee/cultblade/dagger/D = locate() in H.GetAllContents()
	if(!D || !isopenturf(T) || (locate(/obj/effect/rune) in T) || !GLOB.bot_cult)
		return FALSE
	switch(stage++)
		if(0)
			if(!bot.ready_in_hand(D))
				return FALSE
			H.visible_message("<span class='warning'>[H] cuts open [H.p_their()] arm and begins writing in [H.p_their()] own blood!</span>")
			var/obj/effect/rune/convert/kind = /obj/effect/rune/convert
			H.apply_damage(initial(kind.scribe_damage), BRUTE, pick(BODY_ZONE_L_ARM, BODY_ZONE_R_ARM))
			wait_for = initial(kind.scribe_delay)
			return TRUE
		if(1)
			GLOB.bot_cult.rune = new /obj/effect/rune/convert(T)
			log_game("BOT CULT: [H] scribed an Offer rune at [AREACOORD(T)]")
			bot.put_away(D)
	return FALSE

/datum/bot_step/paced/cult_scribe/finish(datum/bot_brain/bot)
	return !QDELETED(GLOB.bot_cult?.rune) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// Beside the rune, to make up the numbers.
/datum/bot_goal/cult_wait
	doing = "waiting"
	var/obj/effect/rune/rune

/datum/bot_goal/cult_wait/New(obj/effect/rune/R)
	. = ..()
	rune = R

/datum/bot_goal/cult_wait/resolve_target(datum/bot_brain/bot)
	target = QDELETED(rune) ? null : rune

/datum/bot_goal/cult_wait/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/cult/S = new
	S.steps = list(new /datum/bot_step/move_to())
	return list(S)

// ---------------------------------------------------------------------------------------------
// Taking somebody
// ---------------------------------------------------------------------------------------------

/// Up to them, the stun and the shackles, then dragged to the rune and onto it.
/datum/bot_goal/cult_take
	doing = "on an errand"
	var/obj/effect/rune/rune

/datum/bot_goal/cult_take/New(mob/living/carbon/human/V, obj/effect/rune/R)
	. = ..()
	target = V
	rune = R

/datum/bot_goal/cult_take/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target) || QDELETED(rune))
		target = null

/datum/bot_goal/cult_take/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/cult/S = new
	var/datum/bot_step/move_to/to_rune = new
	to_rune.step_target = rune
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/cult_stun(), new /datum/bot_step/grab_patient(), to_rune, new /datum/bot_step/cult_place())
	return list(S)

/datum/bot_goal/cult_take/on_give_up(datum/bot_brain/bot)
	bot.owner.stop_pulling()

/datum/bot_goal/cult_wait/on_success(datum/bot_brain/bot)
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, cult_business)), TRUE) //there: held, or the words if they're all in place

/datum/bot_goal/cult_take/on_success(datum/bot_brain/bot)
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, cult_business)), TRUE) //on the rune: the words, before they can get up

/// What the stun spell's hand does to whoever it touches (blood_magic.dm), then what the shackles spell does.
/datum/bot_step/cult_stun/execute(datum/bot_brain/bot)
	var/mob/living/carbon/human/V = bot.current_goal?.target
	var/mob/living/carbon/human/H = bot.owner
	if(!istype(V) || QDELETED(V) || V.stat == DEAD || !H.Adjacent(V))
		return GOAL_STEP_FAIL
	if(V.IsParalyzed() && V.handcuffed)
		return GOAL_STEP_SUCCESS
	bot.human_pause(V)
	H.face_atom(V)
	H.say("Fuu ma'jin!", forced = "cult invocation")
	H.visible_message("<span class='warning'>[H] holds up [H.p_their()] hand, which explodes in a flash of red light!</span>")
	log_combat(H, V, "used a cult spell on", "Stun", "")
	V.Paralyze(160)
	V.flash_act(1, 1)
	V.silent += 6
	V.stuttering += 15
	V.cultslurring += 15
	V.Jitter(15)
	if(!V.handcuffed)
		var/obj/item/restraints/handcuffs/energy/cult/used/shackles = new(V)
		V.handcuffed = shackles
		V.update_handcuffed()
		log_combat(H, V, "shackled", "", "")
	return GOAL_STEP_SUCCESS

/// Next to the rune with them in tow: a click on the rune's tile pulls them onto it.
/datum/bot_step/cult_place/execute(datum/bot_brain/bot)
	var/datum/bot_goal/cult_take/G = bot.current_goal
	var/mob/living/carbon/human/V = G?.target
	var/mob/living/carbon/human/H = bot.owner
	if(!istype(G) || QDELETED(G.rune) || !istype(V) || H.pulling != V)
		return GOAL_STEP_FAIL
	var/turf/T = get_turf(G.rune)
	for(var/i in 1 to 3)
		if(V.loc == T)
			break
		bot.human_pause(T)
		H.Move_Pulled(T)
	H.stop_pulling()
	return V.loc == T ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// The Geometer
// ---------------------------------------------------------------------------------------------
// What the dagger does for Nar'Sie's rune (scribe_rune(), ritual.dm), its menu and its "are you sure" both being a client's: one of the
// summoning spots the objective names, the station told, a shield of blood round the one drawing it, forty damage and fifty seconds.
// Then the nine of them on it, a tile each, and the words.

/datum/bot_cult
	var/obj/effect/rune/narsie/big_rune
	var/turf/summon_spot
	/// Whichever of them can walk to the spot on its own card: it draws the rune and stands in the middle of it.
	var/datum/bot_brain/summoner
	var/next_summon_try = 0
	var/summon_announced = FALSE
	var/summon_nowhere_noted = FALSE
	/// Until when the summoner is in the middle of drawing it.
	var/drawing_until = 0

/datum/bot_cult/proc/summon_objective()
	for(var/datum/objective/eldergod/O in antag_team?.objectives)
		return O

/// Nine of them, the sacrifice made, and the Geometer not here yet.
/datum/bot_cult/proc/ready_to_summon()
	var/datum/objective/eldergod/O = summon_objective()
	if(!O || O.check_completion() || length(living()) < 9)
		return FALSE
	var/datum/objective/sacrifice/S = sac_objective()
	return !S || S.check_completion()

/// Where it can go: clear floor for the one drawing it, and the eight round it somewhere to stand for the rest, the rune being three tiles
/// across - a table will do, they climb up. Clear floor all round was more than a kitchen, an office or the armory ever has: two rounds
/// in three found nowhere in any of the three spots.
/proc/bot_summon_ground(turf/T)
	if(!T || !is_station_level(T.z) || !isopenturf(T) || isspaceturf(T) || is_blocked_turf(T, TRUE) || (locate(/obj/effect/rune) in T))
		return FALSE
	var/area/A = get_area(T)
	if(!A?.blob_allowed)
		return FALSE
	for(var/turf/U in range(1, T))
		if(!isopenturf(U) || isspaceturf(U) || U.density || istype(U, /turf/open/pool)) //the water's no place to stand nine of them, and a rune drawn by it vanished five times over (cause not found)
			return FALSE
		for(var/obj/O in U)
			if(!O.density)
				continue
			var/obj/structure/S = O
			if(!istype(S) || !S.climbable)
				return FALSE
	return TRUE

/// Ground for the rune in each of the summoning spots, and of the cultists nearest each, one who can walk there on its own card: that one
/// draws it. With the leader's card alone there was often nowhere at all. When none of them can, the nearest to the nearest spot breaks
/// in, the way players do: a hacked door gets bolted open (bot_doors.dm), so the rest follow it in. A few route checks, a minute apart at
/// most.
/datum/bot_cult/proc/pick_summoner()
	summoner = null
	summon_spot = null
	var/datum/objective/eldergod/O = summon_objective()
	var/list/alive = living()
	var/list/grounds = list()
	for(var/area/A in O?.summon_spots)
		var/looked = 0
		for(var/turf/open/floor/T in A)
			if(++looked > 400)
				break
			if(bot_summon_ground(T))
				grounds += T
				break
	for(var/turf/T as anything in grounds)
		var/list/by_distance = list()
		for(var/datum/bot_brain/B as anything in alive)
			by_distance[B] = get_dist(B.owner, T)
		sortTim(by_distance, associative = TRUE) //nearest first
		var/asked = 0
		for(var/datum/bot_brain/B as anything in by_distance)
			if(++asked > 3)
				break
			if(B.can_walk_lawfully_to(T))
				summoner = B
				summon_spot = T
				return TRUE
	var/best_dist
	for(var/turf/T as anything in grounds)
		for(var/datum/bot_brain/B as anything in alive)
			if(B.owner.z == T.z && (isnull(best_dist) || get_dist(B.owner, T) < best_dist))
				best_dist = get_dist(B.owner, T)
				summoner = B
				summon_spot = T
	if(summoner)
		log_game("BOT CULT: no way in to [get_area(summon_spot)] on any of their cards: [summoner.owner] breaks in")
		return TRUE
	if(!summon_nowhere_noted)
		summon_nowhere_noted = TRUE
		log_game("BOT CULT: nowhere to call the Geometer: none of the [length(O?.summon_spots)] spots ([english_list(O?.summon_spots)]) has room")
	return FALSE

/// On it, as far as the words go: anywhere in the three tiles across (can_invoke(), runes.dm).
/datum/bot_cult/proc/on_big_rune(datum/bot_brain/B)
	return !QDELETED(big_rune) && get_dist(B.owner, big_rune) <= 1 && B.owner.z == big_rune.z

/// The one who drew it in the middle; everybody else whichever tile round it is free and nearest. A tile each, handed out in turn, left
/// those given one with a table on it stopping beside it and trying again, hundreds of times.
/datum/bot_cult/proc/gather_tile(datum/bot_brain/B)
	if(QDELETED(big_rune))
		return null
	var/turf/center = get_turf(big_rune)
	if(B == summoner)
		return center
	var/turf/best
	for(var/turf/T in range(1, center))
		if(T == center || (locate(/mob/living) in T))
			continue
		if(!best || get_dist(B.owner, T) < get_dist(B.owner, best))
			best = T
	return best

/datum/bot_brain/proc/summon_business(datum/bot_cult/C)
	if(QDELETED(C.big_rune))
		if(world.time < C.next_summon_try || (world.time < C.drawing_until && (C.summoner in C.living())))
			return FALSE //the shield of blood round the one drawing it fails the ground check: a second of them went off to draw another
		if(!(C.summoner in C.living()) || !bot_summon_ground(C.summon_spot))
			if(src != C.leader())
				return FALSE //the rest keep their heads down until it's drawn
			if(!C.pick_summoner())
				C.next_summon_try = world.time + 1 MINUTES
				return FALSE
		return src == C.summoner ? assign_goal(new /datum/bot_goal/cult_summon()) : FALSE
	if(!C.on_big_rune(src))
		if(world.time < cult_gather_retry_at)
			return FALSE
		cult_gather_retry_at = world.time + 5 SECONDS
		return assign_goal(new /datum/bot_goal/cult_gather())
	if((src == C.summoner || !(C.summoner in C.living())) && !C.big_rune.used)
		var/list/invokers = C.big_rune.can_invoke(owner)
		if(length(invokers) >= C.big_rune.req_cultists)
			log_game("BOT CULT: the Geometer is called, [length(invokers)] of them chanting")
			human_pause(C.big_rune)
			telemetry_clicked(C.big_rune)
			usr = owner
			C.big_rune.attack_hand(owner)
			return TRUE
	return cult_hold()

/datum/bot_goal/cult_summon
	doing = "drawing something"

/datum/bot_goal/cult_summon/resolve_target(datum/bot_brain/bot)
	var/datum/bot_cult/C = GLOB.bot_cult
	if(!C)
		return
	target = (bot == C.summoner && bot_summon_ground(C.summon_spot)) ? C.summon_spot : null

/datum/bot_goal/cult_summon/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/cult/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/cult_summon())
	return list(S)

/datum/bot_goal/cult_summon/on_give_up(datum/bot_brain/bot)
	var/datum/bot_cult/C = GLOB.bot_cult
	if(C)
		C.next_summon_try = world.time + 1 MINUTES
		C.summon_spot = null

/datum/bot_goal/cult_summon/on_success(datum/bot_brain/bot)
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, cult_business)), TRUE)

/datum/bot_step/paced/cult_summon
	max_clicks = 3
	var/stage = 0
	var/turf/spot
	var/list/shields

/datum/bot_step/paced/cult_summon/start(datum/bot_brain/bot)
	stage = 0
	spot = get_turf(bot.owner)
	var/datum/objective/eldergod/O = GLOB.bot_cult?.summon_objective()
	return O && (get_area(spot) in O.summon_spots) && bot_summon_ground(spot) && (locate(/obj/item/melee/cultblade/dagger) in bot.owner.GetAllContents())

/datum/bot_step/paced/cult_summon/do_click(datum/bot_brain/bot)
	var/mob/living/carbon/human/H = bot.owner
	var/datum/bot_cult/C = GLOB.bot_cult
	var/obj/item/melee/cultblade/dagger/D = locate() in H.GetAllContents()
	switch(stage++)
		if(0)
			if(!D || !C || !bot.ready_in_hand(D))
				return FALSE
			var/area/A = get_area(spot)
			priority_announce("Figments from an eldritch god are being summoned by [H] into [A.map_name] from an unknown dimension. Disrupt the ritual at all costs!","Central Command Higher Dimensional Affairs", 'hippiestation/sound/pyko/spanomalies.ogg') // hippie -- pykoai
			C.summon_announced = TRUE
			shields = list()
			for(var/turf/T in spiral_range_turfs(1, H, 1))
				var/obj/structure/emergency_shield/sanguine/N = new(T)
				QDEL_IN(N, 70 SECONDS) //if this is cut short and finish() never comes
				shields += N
			H.visible_message("<span class='warning'>[H] cuts open [H.p_their()] arm and begins writing in [H.p_their()] own blood!</span>")
			var/obj/effect/rune/narsie/kind = /obj/effect/rune/narsie
			H.apply_damage(initial(kind.scribe_damage), BRUTE, pick(BODY_ZONE_L_ARM, BODY_ZONE_R_ARM))
			started_narsie_summon()
			log_game("BOT CULT: [H] is drawing Nar'Sie's rune in [A]")
			wait_for = initial(kind.scribe_delay)
			C.drawing_until = world.time + wait_for + 10 SECONDS
			return TRUE
		if(1)
			for(var/obj/structure/emergency_shield/sanguine/S as anything in shields)
				if(!QDELETED(S))
					qdel(S)
			shields = null
			if(C)
				C.drawing_until = 0
			if(!D || !C || H.incapacitated() || get_turf(H) != spot || (locate(/obj/effect/rune) in spot)) //do_after()'s checks
				failed_narsie_summon()
				log_game("BOT CULT: the drawing of Nar'Sie's rune was cut short")
				return FALSE
			H.visible_message("<span class='warning'>[H] creates a strange circle in [H.p_their()] own blood.</span>")
			var/obj/effect/rune/narsie/R = new(spot)
			R.add_mob_blood(H)
			C.big_rune = R
			log_game("BOT CULT: Nar'Sie's rune is drawn")
			return FALSE
	return FALSE

/datum/bot_step/paced/cult_summon/finish(datum/bot_brain/bot)
	for(var/obj/structure/emergency_shield/sanguine/S as anything in shields)
		if(!QDELETED(S))
			qdel(S)
	shields = null
	return QDELETED(GLOB.bot_cult?.big_rune) ? GOAL_STEP_FAIL : GOAL_STEP_SUCCESS

/// Onto its own tile of the big rune.
/datum/bot_goal/cult_gather
	doing = "on an errand"

/datum/bot_goal/cult_gather/resolve_target(datum/bot_brain/bot)
	target = GLOB.bot_cult?.gather_tile(bot)

/datum/bot_goal/cult_gather/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/cult/S = new
	S.steps = list(new /datum/bot_step/move_to())
	return list(S)

/datum/bot_goal/cult_gather/on_success(datum/bot_brain/bot)
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, cult_business)), TRUE)

#undef BOT_CULT_OP_TIMEOUT
#undef BOT_CULT_OP_GAP
#undef BOT_CULT_ALONE
