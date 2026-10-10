#define BOT_STATE_WANDER "wander"
#define BOT_STATE_COMBAT "combat"
#define BOT_STATE_GOAL "goal"
#define BOT_STATE_ARREST "arrest" //Hippie. Security bots only - see handle_arrest() (goals/security_patrol.dm).
/// How long a bot keeps looking for someone it's fighting after losing sight of them
#define BOT_COMBAT_LOST_TIMEOUT 150
/// How long without being hit before a bot decides the fight's over
#define BOT_COMBAT_CALM_DOWN 80
/// How far a bot sees (the default client view radius) - see can_see_target()
#define BOT_SIGHT_RANGE 7

/mob/living/carbon/human
	var/datum/bot_brain/bot_brain

/datum/bot_brain
	var/mob/living/carbon/human/owner
	var/state = BOT_STATE_WANDER
	var/mob/living/attacker
	var/next_wander_time = 0
	var/next_chat_time = 0
	var/next_reaction_time = 0
	var/next_emote_time = 0
	var/hangout_until = 0
	/// When the bot will next think about buying something from a vending machine it's standing near.
	var/next_snack_time = 0
	/// The machine a stroll in progress is heading for, see try_vend_snack().
	var/datum/weakref/snack_vendor
	var/wander_retry_count = 0
	var/list/area/failed_areas //area -> world.time it's worth retrying again
	var/next_personal_objective_time = 0
	var/next_medical_check_time = 0 //Hippie. Paces try_medical_round() (goals/treat_patient.dm) the same way personal objectives are paced below.
	var/next_engineering_check_time = 0 //Hippie. Paces try_engineering_round() (goals/setup_tesla_engine.dm).
	var/next_atmos_check_time = 0 //Hippie. Paces try_atmos_round() (goals/setup_atmospherics.dm).
	var/next_contamination_check_time = 0 //Hippie. Paces try_contamination_round() (goals/respond_to_contamination.dm).
	var/next_fire_check_time = 0 //Hippie. Paces try_fire_response_round() (goals/respond_to_fire.dm).
	var/next_refill_check_time = 0 //Hippie. Paces try_refill_internals_round() (goals/refill_internals.dm).
	var/next_self_heal_check_time = 0 //Hippie. Paces try_self_heal_round() (goals/self_heal.dm).
	var/next_eva_check_time = 0 //Hippie. Paces try_eva_gearing_round() (goals/gear_up_eva.dm).
	// See tank_needs_refill() (goals/refill_internals.dm) - the highest pressure seen on
	// the CURRENT internals tank (last_seen_internals_tank), reset whenever the tank
	// itself changes.
	var/obj/item/tank/internals/last_seen_internals_tank
	var/internals_tank_max_pressure_seen = 0
	/// Weakref to an internals tank a cut-short refill left in a canister; try_retrieve_stranded_tank() goes back for it
	var/datum/weakref/stranded_refill_tank
	// See continue_goal_chain()/run_goal_chain_link() below - TRUE for the brief window
	// between a chained goal ending (goal_succeeded(), bot_goals.dm - which resets state
	// to BOT_STATE_WANDER synchronously) and its scheduled continuation actually running
	// one tick later. handle_wander() bows out entirely while this is set, so none of
	// its OWN checks (a fire it can see, a contamination alarm, EVA re-gearing, its own
	// tank running low, ...) can win the race and steal the goal slot the continuation
	// was about to claim.
	var/goal_chain_pending = FALSE
	// Paces consolidate_id_into_pda() (bot_items.dm) - now run for every bot regardless
	// of state/goal, not just as one step inside acquire_captains_id's ensure_tools.
	// Every crew-member bot that happens to be carrying both its own ID and its own PDA
	// (the common case - most jobs spawn with both) should tuck the card away the same
	// way, not just the one specific bot mid-hack on the captain's office.
	var/next_id_consolidation_check_time = 0
	// Combat by sight - see handle_combat()/can_see_target()
	var/combat_last_seen = 0
	var/turf/combat_last_seen_turf
	var/turf/combat_path_turf
	var/last_hit_by_attacker = 0
	// When this bot last radioed security about being attacked (see bot_call_security(), goals/security_patrol.dm)
	var/next_assault_report_time = 0

/datum/bot_brain/New(mob/living/carbon/human/new_owner)
	. = ..()
	owner = new_owner
	owner.bot_brain = src
	next_chat_time = world.time + rand(50, 150)
	next_personal_objective_time = world.time + rand(600, 1800)
	START_PROCESSING(SSprocessing, src)
	if(owner.buckled)
		owner.buckled.unbuckle_mob(owner, force = TRUE)

	// See triggerAlarm()/cancelAlarm() (goals/respond_to_contamination.dm) - registers
	// unconditionally rather than only for atmos-response jobs, since a bot's assigned
	// role can't change after spawn anyway and the handler itself already checks
	// is_atmos_response_job() before doing anything - simpler to just always be in the
	// list than to track add/remove around a value that never changes.
	GLOB.atmos_alert_bots += src
	register_security()

	// create_mob_hud() (code/_onclick/hud/hud.dm) is only ever called from Login() and
	// refuses to run without a client ("if(!client || hud_used) return") - since a bot
	// never logs in, hud_used stays permanently null, which silently breaks anyone
	// trying to Observe it: observer.dm's observe() gates the whole HUD-display branch
	// on `mob_eye.hud_used` being set, so admins/ghosts could see a bot's camera view
	// move but never its inventory/HUD overlay. Build the HUD directly, bypassing the
	// client check, since a bot absolutely can be the target of a real client's view.
	if(!owner.hud_used)
		owner.hud_used = new owner.hud_type(owner)
		owner.update_sight()
		SEND_SIGNAL(owner, COMSIG_MOB_HUD_CREATED)

/datum/bot_brain/Destroy()
	STOP_PROCESSING(SSprocessing, src)
	stop_pursuit()
	GLOB.atmos_alert_bots -= src
	GLOB.bot_security_brains -= src
	arrest_suspect = null
	if(owner && owner.bot_brain == src)
		owner.bot_brain = null
	owner = null
	attacker = null
	return ..()

/datum/bot_brain/process(delta_time)
	if(QDELETED(owner))
		return PROCESS_KILL
	if(gym_scripted && state == BOT_STATE_WANDER)
		// Bot Gym bot between goals - it only does what its scenario asks (gym/bot_gym.dm). It still sees to its
		// own tank's valve, the way it still breathes: that isn't an errand (goals/refill_internals.dm).
		if(world.time >= next_air_check_time && owner.stat != DEAD && !owner.incapacitated())
			next_air_check_time = world.time + 10
			manage_internals()
		return
	if(owner.stat == DEAD)
		// Not PROCESS_KILL: a bot brought back with the defibrillator (goals/treat_patient.dm) has to pick up where it
		// left off, and nothing would ever start its brain again - it stood where it was revived for the rest of the
		// shift. Dead, this costs a comparison a second. What it was in the middle of dies with it.
		if(state != BOT_STATE_WANDER || current_goal || pursuing_kind)
			if(state == BOT_STATE_ARREST)
				end_arrest("died")
			drop_goals("died")
			attacker = null
			state_before_combat = null
			state = BOT_STATE_WANDER
		return
	if(owner.incapacitated())
		return
	if(try_escape_pool())
		return

	// Its own air before anything else, whatever state it's in (goals/refill_internals.dm): the tank's valve
	// open only where the air isn't breathable, and back inside for a refill before it runs out.
	if(world.time >= next_air_check_time)
		next_air_check_time = world.time + 10
		try
			mind_air_supply()
		catch(var/exception/air_error)
			bot_log_exception(src, "mind_air_supply", air_error)

	// TEMPORARY diagnostic wrap: an unexplained "Cannot execute 1.Copy()" (and an
	// intermittent "Cannot execute null.incapacitated()") has shown up in server logs
	// with no stack trace and no site in this module that visibly matches. Catching
	// here narrows it down decisively - if it's coming from bot code, this will name
	// exactly which proc and bot; if it keeps happening with this catch never firing,
	// it's proven to be unrelated to bot_brain entirely. Remove once resolved.
	// An officer on an errand still has eyes: someone wanted walking past gets picked up (goals/security_patrol.dm).
	if(state == BOT_STATE_GOAL && world.time >= next_security_check_time && is_security_job() && !istype(current_goal, /datum/bot_goal/brig_prisoner))
		next_security_check_time = world.time + rand(10, 20)
		try_spot_wanted()

	// Shut in somewhere its ID doesn't open (bot_requests.dm): a look every minute or so, and a call for somebody
	// to come and get the door.
	if(world.time >= next_shut_in_look)
		next_shut_in_look = world.time + rand(400, 700)
		try
			maybe_ask_to_be_let_out()
		catch(var/exception/shut_in_error)
			bot_log_exception(src, "maybe_ask_to_be_let_out", shut_in_error)

	// A light in the dark (goals/solars.dm): every few seconds, whatever else is going on.
	if(world.time >= next_light_check)
		try
			mind_the_dark()
		catch(var/exception/light_error)
			bot_log_exception(src, "mind_the_dark", light_error)

	// Some duties don't wait for the errand in hand to finish (bot_duties.dm).
	if(state == BOT_STATE_GOAL && world.time >= next_duty_interrupt_time)
		next_duty_interrupt_time = world.time + 20
		try
			check_duty_interrupts()
		catch(var/exception/duty_error)
			bot_log_exception(src, "check_duty_interrupts", duty_error)

	try
		switch(state)
			if(BOT_STATE_COMBAT)
				handle_combat()
			if(BOT_STATE_GOAL)
				handle_goal()
			if(BOT_STATE_ARREST)
				handle_arrest()
			else
				handle_wander()
	catch(var/exception/e)
		message_admins("<span class='danger'>BOT AI EXCEPTION</span> [ADMIN_FLW(owner)] [owner] in [state]: [e]")
		log_runtime("BOT AI EXCEPTION ([owner], state=[state]): [e] at [e.file]:[e.line]")
		GLOB.bot_shift?.note_bot_exception("BOT AI EXCEPTION ([owner], state=[state]): [e] at [e.file]:[e.line]") //gym/bot_shift.dm

	handle_idle_chat()

	// Independent of state (wander/goal/combat) and never suspends anything - unlike
	// the goal-driven checks in handle_wander() (medical/EVA/engineering rounds), this
	// is a one-shot piece of housekeeping a real crewmember does once early on and
	// otherwise ignores, not something worth interrupting a goal for. consolidate_id_
	// into_pda() itself already no-ops instantly (a single locate() check) whenever
	// there's nothing to do, so calling it broadly here is cheap.
	if(world.time >= next_id_consolidation_check_time)
		next_id_consolidation_check_time = world.time + rand(150, 400)
		consolidate_id_into_pda()

/datum/bot_brain/proc/disengage_combat(reason)
	bot_log(src, "disengaging from [attacker]: [reason]")
	attacker = null
	combat_last_seen_turf = null
	stop_pursuit()
	state = state_before_combat || BOT_STATE_WANDER
	state_before_combat = null
	owner.a_intent = INTENT_HELP
	if(state == BOT_STATE_GOAL)
		resume_goal()

/// What something is inside of, all the way out to whatever's actually sitting on a turf (a locker, a crate, a mech...)
/proc/bot_outermost_holder(atom/movable/A)
	while(A?.loc && !isturf(A.loc))
		A = A.loc
	return A

/// Whether this bot can see T right now, the way a person would: T is in view, or T is inside something in view that
/// the bot watched them get into a moment ago (last_seen_turf/last_seen_time are from its last sighting of them).
/// Never "sees" someone through a locker door it didn't see them climb behind.
/datum/bot_brain/proc/can_see_target(mob/living/T, turf/last_seen_turf, last_seen_time)
	var/turf/their_turf = get_turf(T) // not T.z - anything inside a locker has no coordinates of its own
	if(QDELETED(T) || !their_turf || their_turf.z != owner.z || is_blind(owner))
		return FALSE
	var/atom/movable/outer = bot_outermost_holder(T)
	var/list/seen = view(BOT_SIGHT_RANGE, owner)
	if(outer == T)
		return (T in seen)
	if(!(outer in seen))
		return FALSE
	return last_seen_turf && world.time - last_seen_time <= 30 && get_dist(get_turf(outer), last_seen_turf) <= 1

/datum/bot_brain/proc/handle_combat()
	if(QDELETED(attacker) || attacker.stat == DEAD)
		disengage_combat("they're down")
		return
	// Crew fight to stop an attack, not to finish someone: once they're cuffed or out cold, it's over.
	var/mob/living/carbon/restrained = attacker
	if(attacker.stat != CONSCIOUS || (istype(restrained) && restrained.handcuffed))
		disengage_combat(attacker.stat != CONSCIOUS ? "they're down" : "they're restrained")
		return
	// Self-defense ends when the threat does: they've stopped hitting us, so we stop too.
	if(world.time - last_hit_by_attacker > BOT_COMBAT_CALM_DOWN)
		disengage_combat("they've stopped fighting")
		return
	// Fights are fought by sight, not by knowing where everyone is: lose them and it's off to where they were last
	// seen, then give up. (This used to chase anyone within 12 tiles through walls, and punch them through locker doors.)
	var/visible = can_see_target(attacker, combat_last_seen_turf, combat_last_seen)
	if(visible)
		combat_last_seen = world.time
		combat_last_seen_turf = get_turf(attacker)
	else if(world.time - combat_last_seen > BOT_COMBAT_LOST_TIMEOUT)
		disengage_combat("lost sight of them")
		return
	if(visible && get_dist(owner, attacker) > 12)
		disengage_combat("they got away")
		return

	if(!visible)
		var/turf/last_turf = combat_last_seen_turf
		if(last_turf && get_turf(owner) != last_turf)
			combat_chase(last_turf)
		return

	// Watched them climb into a locker or crate: get it open (or bash it, locked or welded), don't punch through the door.
	if(!isturf(attacker.loc))
		var/atom/movable/hideout = bot_outermost_holder(attacker)
		if(!owner.Adjacent(hideout))
			combat_chase(hideout)
			return
		stop_pursuit()
		owner.changeNext_move(CLICK_CD_MELEE)
		var/obj/structure/closet/C = hideout
		if(istype(C) && !C.opened && C.can_open(owner))
			bot_log(src, "opening [C] to get at [attacker]")
			use_atom(C)
			return
		var/obj/item/weapon = owner.get_active_held_item()
		if(weapon && weapon.force > 0)
			use_item_on(weapon, hideout, harm = TRUE)
		else
			owner.a_intent = INTENT_HARM
			owner.UnarmedAttack(hideout, TRUE)
		bot_log(src, "bashing [hideout] - [attacker] is hiding in it")
		return

	// A botanist reaches for what it grew first - a death nettle up close, an acid melon or a
	// primed combustible lemon from range (goals/botany_projects.dm).
	if(try_botany_weapon(attacker))
		if(owner.Adjacent(attacker))
			try_combat_sidestep(attacker)
		return
	if(owner.Adjacent(attacker))
		stop_pursuit()
		owner.a_intent = pick_combat_intent(attacker)
		owner.changeNext_move(CLICK_CD_MELEE)
		owner.UnarmedAttack(attacker, TRUE)
		bot_log(src, "attacking [attacker] ([owner.a_intent])")
		try_combat_sidestep(attacker)
	else
		owner.a_intent = INTENT_HARM
		combat_chase(attacker)

/// Chase something, re-pathing only once it's moved off where the current path leads (same as arrests,
/// goals/security_patrol.dm) - this used to run a fresh pathfind every second of every fight.
/datum/bot_brain/proc/combat_chase(atom/target)
	var/turf/target_turf = get_turf(target)
	if(!target_turf)
		return
	if(pursuing_kind == "combat" && pursue_target == target && combat_path_turf && get_dist(combat_path_turf, target_turf) <= 1)
		return
	combat_path_turf = target_turf
	pursue(target, "combat", force = TRUE)

// Mostly harm, but sometimes goes for a disarm instead if the attacker is holding
// something - matching how a real player alternates intents mid-fight rather than
// mindlessly punching regardless of whether the target is armed.
/datum/bot_brain/proc/pick_combat_intent(mob/living/target)
	if(target.get_active_held_item() && prob(30))
		return INTENT_DISARM
	return INTENT_HARM

// Steps to a different tile still adjacent to the target after attacking, instead of
// standing still and trading blows on the same tile - makes the bot a harder target to
// reliably hit/line up attacks against, same as a real player circle-strafing in melee.
/datum/bot_brain/proc/try_combat_sidestep(mob/living/target)
	if(!prob(45))
		return
	var/turf/owner_turf = get_turf(owner)
	var/turf/target_turf = get_turf(target)
	if(!owner_turf || !target_turf)
		return
	var/list/candidates = list()
	for(var/d in GLOB.alldirs)
		var/turf/candidate = get_step(target_turf, d)
		if(!candidate || candidate == owner_turf || candidate == target_turf)
			continue
		if(candidate.density || isspaceturf(candidate) || !istype(candidate, /turf/open))
			continue
		if(get_dist(owner_turf, candidate) > 1) //must be reachable in a single step from here
			continue
		var/blocked = FALSE
		for(var/atom/movable/AM in candidate)
			if(AM.density)
				blocked = TRUE
				break
		if(blocked)
			continue
		candidates += candidate
	if(!candidates.len)
		return
	step_towards(owner, pick(candidates))

// Shared by every "goal succeeded, immediately move on to the next one" chain
// (continue_engineering_round() and friends, one per goal-file) - see goal_chain_
// pending's declaration above for why this needs to exist at all. end_goal() (bot_
// goals.dm) resets state to BOT_STATE_WANDER synchronously the instant a goal ends, but
// assign_goal() refuses to start a NEW one until state genuinely reads WANDER (it won't
// accept a call made from inside the still-finishing old goal) - so every one of these
// chains has always needed a 1-tick-deferred addtimer to let that reset land first.
// Confirmed in-game as a real, visible bug: an engineer bot that had just lit the first
// tesla emitter got pulled away mid-checklist (wandered off, then came back and
// finished the rest) by something else grabbing that exact gap before its own
// continuation ever got to run - and along the way, one emitter ended up skipped
// entirely for a while. Setting this flag right before scheduling the continuation, and
// having handle_wander() bow out entirely while it's set, gives the scheduled
// continuation first claim on the very next tick instead of racing it.
/datum/bot_brain/proc/continue_goal_chain(datum/callback/cb)
	// Something of its own has become pressing - it's properly hungry (goals/eat_and_drink.dm). The work doesn't
	// chain straight on into more work: handle_wander() gets a look in, and comes back to the job after.
	if(has_pressing_need())
		return
	goal_chain_pending = TRUE
	addtimer(CALLBACK(src, PROC_REF(run_goal_chain_link), cb), 1)

/datum/bot_brain/proc/run_goal_chain_link(datum/callback/cb)
	goal_chain_pending = FALSE
	cb.Invoke()

/datum/bot_brain/proc/handle_wander()
	if(goal_chain_pending)
		return
	// Mid-reach for something (human_pause(), bot_human.dm): finish that before strolling off. The pause
	// sleeps while this keeps ticking, and a bot that started its next wander leg in the middle of one
	// picked the item up from wherever it had walked to.
	if(world.time < mid_click_until)
		return

	// Whatever can't wait for anything below - the shuttle is leaving, the room is on fire (bot_duties.dm).
	if(run_duties(BOT_DUTY_URGENT))
		if(owner.buckled && state == BOT_STATE_GOAL) //up and off - unless the duty is to stay sat (aboard the shuttle)
			owner.buckled.unbuckle_mob(owner, force = TRUE)
		return

	// Waiting somewhere on purpose - at departures for the shuttle, say (bot_duties.dm). Nothing below gets a look in
	// until whatever it's waiting for says the wait is over.
	if(holding_duty)
		if(holding_duty.keep_holding(src))
			idle_fidget()
			return
		holding_duty = null

	// Security: spotting someone wanted in plain sight is checked first and on a short
	// cadence (1-2s, not the 5-15s of the rounds below) - a suspect walking past is gone
	// by the time a slower poll comes around. Witnessed crimes don't wait for this at
	// all; they interrupt immediately via bot_security_witness_combat()
	// (goals/security_patrol.dm). No-ops instantly for every non-security job.
	if(world.time >= next_security_check_time)
		next_security_check_time = world.time + rand(10, 20)
		if(try_security_round())
			if(owner.buckled)
				owner.buckled.unbuckle_mob(owner, force = TRUE)
			return

	// Urgent patient care pre-empts everything else opportunistic - hanging out in a
	// chair, or mid-walk to an ordinary wander destination. This used to sit BELOW the
	// buckled/pursuing_kind gates below, which meant a doctor sitting down to "hang out"
	// (try_sit_down(), can buckle for up to 45s) or already mid-stroll to its next
	// wander spot would never even check on a crit patient until that unrelated
	// business finished - a real doctor doesn't finish their coffee break while someone
	// dies on the floor. assign_goal() (called via try_medical_round()) already cancels
	// any in-progress ordinary wander pursuit on its own.
	// Engineers kit up with insulated gloves (and the CE's cloak) as a priority - goals/engineer_gear.dm
	if(world.time >= next_engineer_gear_check_time)
		next_engineer_gear_check_time = world.time + rand(300, 600) //retry every 30-60s if it couldn't finish
		if(try_engineer_gear_round())
			if(owner.buckled)
				owner.buckled.unbuckle_mob(owner, force = TRUE)
			return

	if(world.time >= next_cable_check_time)
		next_cable_check_time = world.time + rand(50, 150)
		if(try_cable_repair_round()) //goals/repair_cables.dm
			if(owner.buckled)
				owner.buckled.unbuckle_mob(owner, force = TRUE)
			return

	if(world.time >= next_medical_check_time)
		next_medical_check_time = world.time + rand(50, 150)
		if(try_medical_round())
			if(owner.buckled)
				owner.buckled.unbuckle_mob(owner, force = TRUE)
			return

	// Engineers/Atmos Techs get dressed for space BEFORE any of the tesla-engine work
	// below - checked first so gearing up always wins over resuming the tesla checklist.
	if(world.time >= next_eva_check_time)
		next_eva_check_time = world.time + rand(50, 150)
		if(try_eva_gearing_round())
			if(owner.buckled)
				owner.buckled.unbuckle_mob(owner, force = TRUE)
			return

	// Own air supply next - checked ahead of fire/contamination response for the same
	// "insure their own safety first" reasoning the fire-fighting priority order already
	// follows (respond_to_fire.dm's header comment): no point sending a bot into another
	// firefight on a tank that's about to run dry. safe_to_refill_tank()/tank_needs_
	// refill() (goals/refill_internals.dm) both gate this so it only actually fires when
	// genuinely low AND somewhere safe to swap tanks.
	if(world.time >= next_refill_check_time)
		next_refill_check_time = world.time + rand(50, 150)
		if(try_refill_internals_round())
			if(owner.buckled)
				owner.buckled.unbuckle_mob(owner, force = TRUE)
			return

	// Own injuries next, same "own well-being first" tier as EVA gearing/internals just
	// above - every job checks this, not just medical (goals/self_heal.dm), since a hurt
	// engineer bandaging itself is exactly as normal as a hurt doctor doing the same.
	// Below EVA gearing/air supply (a punctured suit matters more than a scrape) but above
	// reacting to hazards - a bot that's already hurt stabilizes itself before rushing
	// into another fire.
	if(world.time >= next_self_heal_check_time)
		next_self_heal_check_time = world.time + rand(50, 150)
		if(try_self_heal_round())
			if(owner.buckled)
				owner.buckled.unbuckle_mob(owner, force = TRUE)
			return

	// Immediate, untimed reaction to whatever the bot can actually SEE right now -
	// can_see_active_fire()/can_see_atmos_hazard() (goals/respond_to_fire.dm/goals/
	// respond_to_contamination.dm) check the bot's current view() every single tick,
	// with no next_*_check_time pacing at all, so a bot standing right next to a fire
	// or a visible plasma cloud reacts the same tick it notices - not on the normal
	// 5-15s poll cadence below, the same way a real crew member doesn't wait out a
	// schedule before reacting to flames in front of them. The timed/radio-pushed
	// checks further down stay as-is for hazards the bot ISN'T currently looking at.
	if(is_fire_response_job() && can_see_active_fire())
		if(try_fire_response_round())
			if(owner.buckled)
				owner.buckled.unbuckle_mob(owner, force = TRUE)
			return
	if(is_atmos_response_job() && can_see_atmos_hazard())
		if(try_contamination_round())
			if(owner.buckled)
				owner.buckled.unbuckle_mob(owner, force = TRUE)
			return

	// Lower priority than seeing the actual hazard directly (above) - a console just
	// points the bot toward something it can't necessarily see yet (goals/check_alert_
	// console.dm). Still untimed/checked every tick, same "reacts to what's observable
	// right now" reasoning.
	if(is_fire_response_job() && can_see_alerted_console())
		if(try_check_alert_console_round())
			if(owner.buckled)
				owner.buckled.unbuckle_mob(owner, force = TRUE)
			return

	// Active fire response (goals/respond_to_fire.dm) - checked ahead of the contamination
	// response right below it: a live fire is the more immediate danger of the two (risk
	// of spreading/breaching the hull) and gets first look each cycle. Still behind EVA
	// gearing, same reasoning as the contamination check. This is the timed/poll-based
	// fallback for hazards the bot can't currently see (a radio push was missed, or
	// something's happening elsewhere on the station) - see the untimed check just above.
	if(world.time >= next_fire_check_time)
		next_fire_check_time = world.time + rand(50, 150)
		if(try_fire_response_round())
			if(owner.buckled)
				owner.buckled.unbuckle_mob(owner, force = TRUE)
			return

	// Active hazard response (goals/respond_to_contamination.dm) - checked ahead of both
	// the tesla engine and the atmos pump room, same "don't finish routine chores before
	// dealing with a live emergency" reasoning as the medical check above. Still behind
	// EVA gearing (a bot without its hardsuit/mask on has no business walking toward a
	// plasma-contaminated room to begin with).
	if(world.time >= next_contamination_check_time)
		next_contamination_check_time = world.time + rand(50, 150)
		if(try_contamination_round())
			if(owner.buckled)
				owner.buckled.unbuckle_mob(owner, force = TRUE)
			return

	// Same idea for engineers and the Tesla engine setup (goals/setup_tesla_engine.dm) -
	// no reason to wait out a chair-sitting or an unrelated wander stroll before getting
	// back to assembling the particle accelerator.
	if(world.time >= next_engineering_check_time)
		next_engineering_check_time = world.time + rand(50, 150)
		if(try_engineering_round())
			if(owner.buckled)
				owner.buckled.unbuckle_mob(owner, force = TRUE)
			return

	// Same idea again for Atmospheric Technicians and the pump room (goals/
	// setup_atmospherics.dm).
	if(world.time >= next_atmos_check_time)
		next_atmos_check_time = world.time + rand(50, 150)
		if(try_atmos_round())
			if(owner.buckled)
				owner.buckled.unbuckle_mob(owner, force = TRUE)
			return

	// Botanists keep the hydroponics bay going (goals/tend_hydroponics.dm).
	if(world.time >= next_botany_check_time)
		next_botany_check_time = world.time + rand(50, 150)
		if(try_botany_round())
			if(owner.buckled)
				owner.buckled.unbuckle_mob(owner, force = TRUE)
			return

	// The day job of everyone whose work isn't one of the rounds above (bot_duties.dm).
	if(run_duties(BOT_DUTY_WORK))
		if(owner.buckled && state == BOT_STATE_GOAL)
			owner.buckled.unbuckle_mob(owner, force = TRUE)
		return

	if(owner.buckled)
		if(world.time < hangout_until)
			return
		owner.buckled.unbuckle_mob(owner, force = TRUE)

	if(pursuing_kind)
		return
	if(world.time < next_wander_time)
		idle_fidget() //bot_human.dm - look around / get out of doorways instead of standing frozen
		return

	// Auto-retry the captain's-ID goal once its give-up cooldown has passed, instead of
	// requiring an admin to manually re-click the debug verb every single time. Reverting
	// pick_reachable()'s "walk up to a locked door anyway" last-resort fallback
	// (goals/acquire_tool.dm) means this goal now gives up more readily when nothing is
	// currently reachable - this is the other half of that trade-off: ordinary wandering
	// below (find_item_goal()) opportunistically gathers tools crossed along the way in
	// the meantime, same as a real person just keeping an eye out, and then the goal gets
	// another shot once some time has passed instead of the bot just sitting idle
	// forever. goal_giveup_time itself was already being set on every give-up
	// (give_up_goal(), bot_goals.dm) but nothing ever read it before this.
	if(goal_giveup_time && world.time >= goal_giveup_time)
		goal_giveup_time = 0
		if(assign_goal(new /datum/bot_goal/acquire_captains_id()))
			return

	// Free time: something to do instead of another stroll (bot_duties.dm).
	if(run_duties(BOT_DUTY_LEISURE))
		return

	if(prob(30) && try_vend_snack())
		return
	if(world.time >= next_emote_time && prob(20))
		next_emote_time = world.time + rand(150, 400)
		owner.emote(pick(GLOB.bot_idle_emotes))

	if(world.time >= next_personal_objective_time)
		next_personal_objective_time = world.time + rand(3000, 6000) //5-10min real-time between attempts, success or not
		if(prob(15) && try_personal_objective())
			return

	if(prob(25))
		var/atom/goal = find_item_goal()
		if(goal)
			next_wander_time = world.time + rand(10, 30)
			bot_log(src, "going for [goal] @ [bot_coord(get_turf(goal))] ([get_area_name(goal)])")
			pursue(goal, istype(goal, /obj/structure/closet) ? "locker" : "item")
			return

	begin_wander_pick()

/datum/bot_brain/proc/on_pursuit_finished(kind, atom/target, success)
	switch(kind)
		if("wander")
			// A stroll over to a vending machine (try_vend_snack()): buy on arrival; if the way was barred, never mind.
			var/obj/machinery/vending/vendor = snack_vendor?.resolve()
			snack_vendor = null
			if(vendor)
				if(success)
					buy_snack(vendor)
				next_wander_time = world.time + wander_dwell_time()
			else if(success)
				if(!try_sit_down())
					next_wander_time = world.time + wander_dwell_time()
			else
				var/area/AR = get_area(target)
				if(AR)
					LAZYSET(failed_areas, AR, world.time + rand(1800, 3600))
				bot_log(src, "couldn't reach [target] @ [bot_coord(get_turf(target))] in [AR], avoiding it for a while[last_path_fail_reason ? " ([last_path_fail_reason])" : ""]")
				try_next_wander_candidate()
		if("item")
			if(success)
				try_pickup_target(target)
			else
				bot_log(src, "couldn't reach item [target] @ [bot_coord(get_turf(target))][last_path_fail_reason ? " ([last_path_fail_reason])" : ""]")
				try_next_wander_candidate()
		if("locker")
			if(success)
				try_open_locker(target)
			else
				bot_log(src, "couldn't reach locker [target] @ [bot_coord(get_turf(target))][last_path_fail_reason ? " ([last_path_fail_reason])" : ""]")
				try_next_wander_candidate()
		if("goal")
			on_goal_pursuit_finished(target, success)
		if("arrest")
			if(!success)
				on_arrest_pursuit_failed() //goals/security_patrol.dm - success needs nothing, handle_arrest() takes it from there next tick

/datum/bot_brain/proc/try_sit_down()
	if(!prob(40))
		return FALSE
	var/obj/structure/chair/C = locate(/obj/structure/chair) in get_turf(owner)
	if(!C || C.has_buckled_mobs())
		return FALSE
	if(!C.buckle_mob(owner))
		return FALSE
	hangout_until = world.time + rand(150, 450)
	bot_log(src, "sitting down in [get_area_name(owner)]")
	return TRUE

/datum/bot_brain/proc/begin_wander_pick()
	snack_vendor = null
	next_wander_time = world.time + rand(10, 30) //spacing only - how long to linger is decided on arrival (wander_dwell_time())
	wander_retry_count = 12
	try_next_wander_candidate()

/datum/bot_brain/proc/try_next_wander_candidate()
	if(wander_retry_count <= 0)
		next_wander_time = world.time + rand(20, 40) //every candidate failed - try again shortly rather than freezing
		return
	wander_retry_count--
	var/turf/T = prob(65) ? pick_poi_destination() : pick_local_destination()
	if(!T)
		T = pick_local_destination()
	if(!T)
		try_next_wander_candidate()
		return
	bot_log(src, "wandering to [T] @ [bot_coord(T)] ([get_area_name(T)])")
	pursue(T, "wander")

// T.density is the TURF's own density, which stays FALSE even when a dense structure
// (table, rack, counter, ...) sits on top of it - so a plain T.density check let wander
// destination-picking freely send a bot climbing onto a table or bumping into a rack
// for no reason, something a real person wouldn't casually do unless actually headed
// somewhere that requires it (over the bar counter, into a kitchen prep area, etc).
// The one exception: if the bot is already standing on a table, stepping onto an
// adjacent table tile is ordinary movement (table/CanPass()'s "already on a table"
// exception, see bot_items.dm's clear_one_blocker()), so that's still fair game.
/datum/bot_brain/proc/is_wanderable_turf(turf/T)
	if(!T || T.density || isspaceturf(T) || !istype(T, /turf/open) || istype(T, /turf/open/pool)) //nobody strolls into the pool (bot_steps_into_pool())
		return FALSE
	// Shuttles (the arrivals shuttle especially, but any of them - cargo, mining, escape,
	// custom, ...) dock and undock on their own schedule, independent of anything a bot
	// is doing. Confirmed as a real, dangerous bug in-game: an idly wandering bot ended
	// up on the arrivals shuttle, opened what looked like an ordinary airlock in its
	// path, and got exposed to space through it - a shuttle's own hull doors aren't
	// necessarily safe to open the instant it's docked (alignment, transit timing, ...)
	// the way a normal station airlock is, and nothing about ordinary wandering has any
	// business being on a shuttle at all in the first place. Goal-driven pursuits
	// (move_to) aren't affected by this - no current goal ever targets anything aboard a
	// shuttle, so this only needed to stop undirected wandering from picking one.
	if(istype(get_area(T), /area/shuttle))
		return FALSE
	for(var/obj/structure/S in T)
		if(!S.density)
			continue
		if(istype(S, /obj/structure/table) && (locate(/obj/structure/table) in get_turf(owner)))
			continue
		return FALSE
	return TRUE

// Area-name substring keywords per job - matched case-insensitively against
// GLOB.teleportlocs' keys (real area names, see Space_Station_13_areas.dm) rather than
// needing every /area subtype tagged with a formal department field. A real crew member
// spends most of their time near their own workplace, not roaming the whole station
// with equal odds of ending up in the chapel or the bar - pick_poi_destination() below
// uses this to bias wander destinations toward "home turf" most of the time while still
// leaving room to wander off occasionally, same as a real person taking a break.
GLOBAL_LIST_INIT(bot_department_keywords, list(
	"Chief Engineer" = list("Engineering", "Atmospherics", "Solar", "Supermatter", "Gravity Generator"),
	"Station Engineer" = list("Engineering", "Atmospherics", "Solar", "Supermatter", "Gravity Generator"),
	"Atmospheric Technician" = list("Atmospherics", "Engineering", "Solar"),
	"Chief Medical Officer" = list("Medbay", "Medical", "Surgery", "Virology", "Chemistry", "Morgue", "Genetics", "Cloning", "Cryogenics"),
	"Medical Doctor" = list("Medbay", "Medical", "Surgery", "Virology", "Chemistry", "Morgue", "Genetics", "Cloning", "Cryogenics"),
	"Chemist" = list("Chemistry", "Apothecary"), //not "Medbay" - too broad a substring, matched unrelated areas like "Security Post - Medbay" instead of the actual lab
	"Geneticist" = list("Genetics", "Cloning", "Medbay"),
	"Virologist" = list("Virology", "Medbay"),
	"Research Director" = list("Science", "Research", "Robotics", "Toxins", "Xenobiology"),
	"Scientist" = list("Science", "Research", "Toxins", "Xenobiology"),
	"Roboticist" = list("Robotics", "Mech Bay", "Science"),
	"Head of Security" = list("Security", "Brig", "Detective", "Armory", "Courtroom", "Warden"),
	"Warden" = list("Security", "Brig", "Armory"),
	"Detective" = list("Detective", "Security", "Brig"),
	"Security Officer" = list("Security", "Brig", "Hallway"), //"Hallway" = patrolling the public halls, where most crime actually gets witnessed
	"Quartermaster" = list("Cargo", "Quartermaster", "Warehouse", "Mining"),
	"Cargo Technician" = list("Cargo", "Quartermaster", "Warehouse"),
	"Shaft Miner" = list("Mining"),
	"Bartender" = list("Bar", "Kitchen", "Cafeteria"),
	"Cook" = list("Kitchen", "Cafeteria"),
	"Botanist" = list("Hydroponics", "Garden"),
	"Head of Personnel" = list("Head of Personnel", "Bridge", "Dormitories"),
	"Captain" = list("Bridge", "Captain"),
	"Clown" = list("Clown", "Theatre", "Hallway", "Bar"),
	"Mime" = list("Mime", "Theatre", "Hallway", "Bar"),
	"Chaplain" = list("Chapel"),
	"Curator" = list("Library"),
	"Lawyer" = list("Law Office", "Courtroom", "Brig"),
	"Janitor" = list("Custodial", "Hallway"),
))

// Public hallway/common-area keywords - where a job in bot_maintenance_averse_jobs
// below is allowed to wander once it steps outside its own department.
GLOBAL_LIST_INIT(bot_common_area_keywords, list(
	"Hallway", "Dormitories", "Cafeteria", "Lounge", "Atrium", "Locker Room",
))

// Jobs that have no business being found in maintenance tunnels - a doctor wandering
// off from medbay should end up in the cafeteria or a public hallway, not crawling
// through electrical maintenance. Every area name in this codebase that's actually a
// maintenance tunnel literally contains "Maintenance" (Space_Station_13_areas.dm), so
// excluding that substring is enough without needing a separate area-type check.
GLOBAL_LIST_INIT(bot_maintenance_averse_jobs, list("Medical Doctor", "Chief Medical Officer"))

// Picks an area biased toward the bot's job's own department most of the time (see
// GLOB.bot_department_keywords above). The rest of the time (or for jobs with no
// mapped department, like Assistant/Clown), maintenance-averse jobs are kept to public
// hallways/common areas instead of anywhere on the station; everyone else still falls
// back to a fully random area, same as before.
/datum/bot_brain/proc/pick_department_biased_area()
	var/role = owner.mind?.assigned_role
	var/list/keywords = GLOB.bot_department_keywords[role]
	if(keywords && length(keywords) && prob(75))
		var/list/matches = list()
		for(var/area_name in GLOB.teleportlocs)
			for(var/keyword in keywords)
				if(findtext(area_name, keyword))
					matches += GLOB.teleportlocs[area_name]
					break
		if(matches.len)
			return pick(matches)

	if(role in GLOB.bot_maintenance_averse_jobs)
		var/list/common = list()
		for(var/area_name in GLOB.teleportlocs)
			if(findtext(area_name, "Maintenance"))
				continue
			for(var/keyword in GLOB.bot_common_area_keywords)
				if(findtext(area_name, keyword))
					common += GLOB.teleportlocs[area_name]
					break
		if(common.len)
			return pick(common)

	return GLOB.teleportlocs[pick(GLOB.teleportlocs)]

/datum/bot_brain/proc/pick_poi_destination()
	if(!length(GLOB.teleportlocs))
		return null
	var/area/AR = pick_department_biased_area()
	if(!AR)
		return null
	var/cooldown = LAZYACCESS(failed_areas, AR)
	if(cooldown && world.time < cooldown)
		return null //recently unreachable - pick_local_destination() covers this wander cycle instead
	var/list/candidates = list()
	var/list/chair_candidates = list()
	for(var/turf/T in AR)
		if(!is_wanderable_turf(T))
			continue
		candidates += T
		if(locate(/obj/structure/chair) in T)
			chair_candidates += T
	if(chair_candidates.len && prob(50))
		return pick(chair_candidates)
	if(!candidates.len)
		return null
	return pick(candidates)

/datum/bot_brain/proc/pick_local_destination()
	for(var/turf/candidate in shuffle(orange(6, get_turf(owner))))
		if(!is_wanderable_turf(candidate))
			continue
		return candidate
	return null

/// Between strolls, with a vending machine a couple of steps away: go and buy something from it. This
/// used to make the product appear on the machine's tile and take it from wherever the bot stood, for
/// free - telemetry recorded every one as an item picked up from two tiles away. Returns TRUE if the
/// bot is now on its way to (or at) the machine.
/datum/bot_brain/proc/try_vend_snack()
	if(world.time < next_snack_time)
		return FALSE
	var/obj/machinery/vending/V = locate(/obj/machinery/vending) in oview(2, owner)
	if(!V || V.panel_open || (V.stat & (BROKEN|NOPOWER)))
		return FALSE
	next_snack_time = world.time + rand(600, 1800) //one trip to the machine every so often, whether or not it sells anything
	if(owner.Adjacent(V))
		INVOKE_ASYNC(src, PROC_REF(buy_snack), V) //it pauses like a person does; handle_wander() can't wait on it
		return TRUE
	var/turf/open/spot
	for(var/turf/open/T in get_adjacent_open_turfs(V))
		if(!is_blocked_turf(T, TRUE) && (!spot || get_dist(owner, T) < get_dist(owner, spot)))
			spot = T
	if(!spot)
		return FALSE
	// Walked as a stroll, so the same rules apply as to any other: nothing gets hacked or broken to reach a snack
	snack_vendor = WEAKREF(V)
	next_wander_time = world.time + rand(10, 30)
	pursue(spot, "wander")
	return TRUE

/// At the machine: press the vend button and pay like anyone else (vend_from(), goals/tend_hydroponics.dm),
/// then take the thing out of the tray.
/datum/bot_brain/proc/buy_snack(obj/machinery/vending/V)
	if(QDELETED(V) || !owner.Adjacent(V))
		return FALSE
	var/list/available = list()
	for(var/datum/data/vending_product/R in V.product_records)
		if(R.amount > 0 && R.product_path)
			available += R
	if(!length(available))
		return FALSE
	var/datum/data/vending_product/chosen = pick(available)
	var/obj/item/bought = vend_from(V, chosen.product_path)
	if(!bought || !try_pickup_target(bought))
		return FALSE
	bot_log(src, "bought [bought] from [V]")
	return TRUE

/// Someone hurt this bot. what_done is log_combat()'s verb ("punched", "attacked", "shot"...), fed from
/// bot_notice_combat() (goals/security_patrol.dm) - every kind of attack, fists and bites and bullets included.
/datum/bot_brain/proc/on_attacked(mob/living/user, what_done, atom/object)
	if(!user || user == owner || QDELETED(owner) || owner.stat == DEAD)
		return
	// A law-abiding crewmember doesn't fight the officer arresting them - they protest.
	if(!is_security_job() && (user.mind?.assigned_role in GLOB.security_positions))
		if(world.time >= next_reaction_time)
			next_reaction_time = world.time + 100
			bot_say(owner, pick("What did I do?!", "Hey, I didn't do anything!", "Okay, okay! I'm not resisting!", "This is a mistake!"))
		return
	// Security bots arrest their attacker (stun + cuff + brig) rather than trading
	// punches - the witness hook files the actual "Assaulting an Officer" charge a tick
	// later and begin_arrest() upgrades to it. Animals, and other security (not a crime
	// this module judges), still get ordinary combat below.
	if(is_security_job() && ishuman(user) && !(user.mind?.assigned_role in GLOB.security_positions))
		if(begin_arrest(user))
			return
	combat_last_seen = world.time
	combat_last_seen_turf = get_turf(user)
	last_hit_by_attacker = world.time
	if(state == BOT_STATE_COMBAT && attacker == user)
		return // already fighting them - every further hit used to re-shout and restart the chase
	bot_log(src, "attacked by [user] ([what_done || "hit"]), engaging")
	if(state != BOT_STATE_COMBAT)
		state_before_combat = state
	attacker = user
	combat_path_turf = null
	state = BOT_STATE_COMBAT
	stop_pursuit()
	if(owner.buckled)
		owner.buckled.unbuckle_mob(owner, force = TRUE)
	hangout_until = 0
	if(ishuman(user))
		bot_call_security(user, what_done, object) //goals/security_patrol.dm - a victim radios it in, it doesn't just fight back
	if(prob(60))
		bot_say(owner, pick(GLOB.bot_combat_lines))

/mob/living/carbon/human/Hear(message, atom/movable/speaker, message_language, raw_message, radio_freq, list/spans, message_mode)
	. = ..()
	if(bot_brain && speaker)
		bot_brain.on_heard_security_call(speaker, raw_message, radio_freq) //goals/security_patrol.dm
		bot_brain.on_heard_speech(speaker, raw_message, radio_freq) //bot_chatter.dm

/mob/living/carbon/human/Destroy()
	if(bot_brain)
		GLOB.bot_crew_members -= src
		QDEL_NULL(bot_brain)
	return ..()
