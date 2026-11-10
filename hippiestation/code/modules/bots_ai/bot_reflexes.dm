// Reflexes - what a bot does about somebody's hands on it, short of a blow (those go to on_attacked(), bot_brain.dm).
//
// A griefing player grabbed or shoved bots 27 times in one round and not one of them so much as struggled: an aggressive
// grab counts as incapacitated(), so process() stopped dead, and everything short of a punch was left out of what a bot
// noticed at all. Now:
//
//  - Whatever is holding it, it fights off the way a player does, with the Resist button: a grip, cuffs, legcuffs, a
//    locker somebody shoved it in. Not an officer's grip or cuffs, unless it's on the wrong side of the law.
//  - Everything else that can be done to a person with their hands - shoves, disarms, being stripped or tabled, a needle
//    from somebody who isn't a doctor - makes it angrier with whoever did it. A word first, a shove back next, and past a
//    limit that depends on its temper, a fight. The anger fades if they leave it alone.
//  - Whatever gets knocked out of its hand it picks straight back up.

/// One point of anger wears off in this long.
#define BOT_GRUDGE_FADE (40 SECONDS)
/// Anger at which a bot of middling temper shoves back, and at which it starts a fight (handling_limit()).
#define BOT_GRUDGE_SHOVE 3
#define BOT_GRUDGE_FIGHT 6
/// How long a hand on its arm is put up with before it's shaken off.
#define BOT_GRIP_PATIENCE (4 SECONDS)
/// Cuffed by an officer and then left there: how long before it sees about getting out of them.
#define BOT_CUFFED_PATIENCE (2 MINUTES)
/// How long something knocked out of its hand is worth going back for.
#define BOT_KNOCKED_ITEM_MEMORY (30 SECONDS)

/// Off with boot param bot-reflexes=off: the control runs for gym/scenarios_griefing.dm.
GLOBAL_VAR_INIT(bot_reflexes_off, world.params["bot-reflexes"] == "off")

/// What each kind of handling is worth in anger, by log_combat()'s verb. The first match counts, so the longer verb goes
/// first. Nothing here is a blow: those are bot_violent_combat_verbs (goals/security_patrol.dm). A grab goes by its grip.
GLOBAL_LIST_INIT(bot_handling_verbs, list(
	"attempted to disarm" = 1,
	"disarmed" = 2,
	"pushed over" = 3,
	"pushed" = 2,
	"shoved" = 2,
	"grabbed" = 1,
	"stripped" = 5,
	"places" = 3,
	"attempted to handcuff" = 3,
	"attempted to inject" = 3,
	"injected" = 4,
	"sprayed" = 3,
	"splashed" = 3,
	"fed" = 2,
	"shaken" = 0,
	"CPRed" = 0,
))

GLOBAL_LIST_INIT(bot_shoved_lines, list(
	"Hey, quit it!",
	"Watch it!",
	"Do you mind?",
	"Keep your hands to yourself.",
	"What's your problem?",
	"Oi!",
	"Back off, will you?",
))

GLOBAL_LIST_INIT(bot_grabbed_lines, list(
	"Get off me!",
	"Let go!",
	"Hands off!",
	"Get your hands off me!",
	"Let go of me!",
))

GLOBAL_LIST_INIT(bot_robbed_lines, list(
	"Hey, that's mine!",
	"Give that back!",
	"Thief!",
	"Stop, that's mine!",
))

GLOBAL_LIST_INIT(bot_needled_lines, list(
	"What did you just put in me?!",
	"What was that?!",
	"Get that away from me!",
	"Are you even a doctor?!",
))

GLOBAL_LIST_INIT(bot_poked_lines, list(
	"Yes?",
	"Hm?",
	"What's up?",
	"Can I help you?",
	"Hey.",
))

GLOBAL_LIST_INIT(bot_overpoked_lines, list(
	"Stop poking me.",
	"Can I help you with something, or...?",
	"Personal space, please.",
	"Alright, that's enough.",
))

/datum/bot_brain
	/// Weakref to somebody -> how angry with them it was, last time that changed. Read through grudge_with().
	var/list/grudges
	/// Weakref to somebody -> when that was.
	var/list/grudge_times
	/// When it can next press Resist.
	var/next_struggle_time = 0
	/// When the hold it's in began.
	var/held_since = 0
	/// When the cuffs it's in went on, and whether it was an officer who put them there.
	var/cuffed_since = 0
	var/cuffed_lawfully = FALSE
	/// What was just knocked out of its hands, as weakrefs, and when.
	var/list/knocked_away
	var/knocked_away_at = 0
	/// What was in its hands the last time it could use them, as weakrefs, and whether it's been put down since.
	var/list/hands_were
	var/floored = FALSE
	/// Friendly pokes in a row, for telling somebody to stop.
	var/pokes = 0
	var/last_poked = 0

/proc/bot_is_officer(mob/living/L)
	return L?.mind?.assigned_role in GLOB.security_positions

/// Up to something right now, that the crew would stop if they saw it.
/datum/bot_brain/proc/up_to_no_good()
	if(world.time < trouble_until || gone_loud()) //goals/robust.dm
		return TRUE
	for(var/datum/bot_goal/goal in list(current_goal, suspended_goal))
		if(istype(goal, /datum/bot_goal/tide) || istype(goal, /datum/bot_goal/traitor_kill))
			return TRUE
	return FALSE

/// Takes on security rather than going quietly: a traitor, or somebody in the middle of a riot.
/datum/bot_brain/proc/resists_arrest()
	//operatives, wizards and cultists weren't here: five operatives with submachine guns stood still for Security's tasers and cuffs
	return greytider || is_changeling || op_team || bot_wizard || bot_cultist || !!owner.mind?.has_antag_datum(/datum/antagonist/traitor) || !!rev_datum()

/// Whether this bot is the kind that's only ever hands-on for a good reason: bots go at each other all shift, in a doctor's
/// or an officer's way of doing things, and it mustn't start fights over that.
/proc/bot_means_well(mob/living/L)
	var/mob/living/carbon/human/H = L
	return istype(H) && H.bot_brain && !H.bot_brain.up_to_no_good()

// ---------------------------------------------------------------------------------------------
// The Resist button
// ---------------------------------------------------------------------------------------------

/// Pressed from process(), ahead of the incapacitated() check that would otherwise leave a held bot doing nothing at all.
/datum/bot_brain/proc/mind_being_held()
	if(!owner.pulledby)
		held_since = 0
	if(!owner.handcuffed)
		cuffed_since = 0
		cuffed_lawfully = FALSE
	else if(!cuffed_since)
		cuffed_since = world.time
	if(GLOB.bot_reflexes_off || world.time < next_struggle_time)
		return FALSE
	var/atom/holding = what_holds_me()
	if(!holding || !owner.can_resist())
		return FALSE
	next_struggle_time = world.time + CLICK_CD_RESIST + rand(0, 8)
	// What takes real time, a player leaves running: pressing it again would only start over.
	var/obj/item/restraints/cuffs = holding
	var/obj/structure/closet/locker = holding
	if(istype(cuffs))
		next_struggle_time = world.time + cuffs.breakouttime + 20
	else if(istype(locker) && (locker.welded || locker.locked))
		next_struggle_time = world.time + locker.breakout_time + 20
	bot_log(src, "struggling against [holding]")
	bot_tally("struggles")
	telemetry_event("struggle", list("against" = "[holding]"))
	var/obj/O = holding
	if(istype(O) && !istype(O, /obj/structure/closet) && !isitem(O))
		INVOKE_ASYNC(O, TYPE_PROC_REF(/atom, relaymove), owner, pick(GLOB.cardinals)) //a bin or a morgue tray is left the way a player leaves it: by walking
	INVOKE_ASYNC(owner, TYPE_VERB_REF(/mob/living, resist))
	return TRUE

/// The thing it would be pressing Resist against, or null.
/datum/bot_brain/proc/what_holds_me()
	var/mob/living/holder = owner.pulledby
	if(holder && unwelcome_grip(holder))
		return holder
	if(owner.legcuffed)
		return owner.legcuffed
	if(owner.handcuffed && should_slip_cuffs())
		return owner.handcuffed
	if(isobj(owner.loc) && bot_should_leave(owner.loc))
		return owner.loc
	return null

/datum/bot_brain/proc/unwelcome_grip(mob/living/holder)
	if(bot_means_well(holder))
		return FALSE
	if(bot_is_officer(holder) && !resists_arrest())
		return FALSE
	if(holder.grab_state >= GRAB_AGGRESSIVE)
		return TRUE
	if(!held_since)
		held_since = world.time
	// Being helped along when it's hurt, or just a tug on the arm. Nobody stands for it for long.
	if(owner.health < owner.maxHealth * 0.5 && (holder.mind?.assigned_role in GLOB.medical_positions))
		return FALSE
	return world.time >= held_since + BOT_GRIP_PATIENCE

/// Handcuffs. A greytider or a traitor starts on them straight away, and so does anybody put in them by somebody with no
/// right to. An ordinary crewmember waits to be taken to the brig, unless nobody comes.
/datum/bot_brain/proc/should_slip_cuffs()
	if(resists_arrest() || !cuffed_lawfully)
		return TRUE
	return world.time >= cuffed_since + BOT_CUFFED_PATIENCE && !owner.pulledby

/// Whether being inside this is something to get out of. The medical machines are where it was put to get better.
/proc/bot_should_leave(obj/O)
	return !(istype(O, /obj/machinery/sleeper) || istype(O, /obj/machinery/atmospherics/components/unary/cryo_cell) || istype(O, /obj/machinery/clonepod) \
		|| istype(O, /obj/machinery/dna_scannernew) || istype(O, /obj/mecha) || istype(O, /obj/vehicle) || istype(O, /obj/machinery/nanite_chamber))

// ---------------------------------------------------------------------------------------------
// Handling
// ---------------------------------------------------------------------------------------------

/// How much of a grudge to go from one reaction to the next: a short fuse gets there in half the anger, a long one in half as much again.
/datum/bot_brain/proc/handling_limit(points)
	return points * (1.5 - temper)

/// Grudge enough to shove over. bot_conversation.dm asks, for insults.
/datum/bot_brain/proc/shove_limit()
	return handling_limit(BOT_GRUDGE_SHOVE)

/datum/bot_brain/proc/grudge_with(mob/living/who)
	var/datum/weakref/ref = WEAKREF(who)
	var/points = LAZYACCESS(grudges, ref)
	if(!points)
		return 0
	return max(0, points - (world.time - grudge_times[ref]) / BOT_GRUDGE_FADE)

/// Sore at them just now: they've been shoving or hitting it. A doctor doesn't go and patch them up (patient_needs_treatment()).
/datum/bot_brain/proc/sore_at(mob/living/who)
	return grudge_with(who) >= BOT_GRUDGE_SHOVE

/datum/bot_brain/proc/add_grudge(mob/living/who, points)
	var/now = grudge_with(who) + points
	var/datum/weakref/ref = WEAKREF(who)
	LAZYSET(grudges, ref, now)
	LAZYSET(grudge_times, ref, world.time)
	return now

/// Called from log_combat() (through bot_security_witness_combat(), goals/security_patrol.dm) for anything done to a person
/// that isn't a blow. Runs inside the other person's click, so it never sleeps.
/// Somebody whose needle is medicine: Medical's crew, or a medical cyborg.
/proc/bot_is_medic(mob/living/user)
	if(user?.mind?.assigned_role in GLOB.medical_positions)
		return TRUE
	var/mob/living/silicon/robot/R = user
	return istype(R) && istype(R.module, /obj/item/robot_module/medical)

/proc/bot_note_handling(mob/living/user, mob/living/carbon/human/target, what_done, atom/object)
	if(!target.bot_brain || !istext(what_done))
		return
	var/lower = lowertext(what_done)
	for(var/handled_verb in GLOB.bot_handling_verbs)
		if(findtext(lower, lowertext(handled_verb)))
			target.bot_brain.on_handled(user, handled_verb, GLOB.bot_handling_verbs[handled_verb], object)
			return

/datum/bot_brain/proc/on_handled(mob/living/user, handled_verb, anger, atom/object)
	if(GLOB.bot_reflexes_off || QDELETED(user) || QDELETED(owner) || owner.stat != CONSCIOUS || bot_means_well(user))
		return
	if(istype(user, /mob/living/simple_animal/bot/medbot))
		return //one hurt roboticist took a medibot's needle badly, and went for it
	if(handled_verb == "grabbed")
		if(!held_since)
			held_since = world.time
		switch(user.grab_state)
			if(GRAB_PASSIVE)
				anger = 1
			if(GRAB_AGGRESSIVE)
				anger = 3
			else //round the neck: that stopped being horseplay
				bot_record_aggression(user, owner)
				on_attacked(user, "strangled", object)
				return
	if(!anger)
		addtimer(CALLBACK(src, PROC_REF(answer_touch), WEAKREF(user), handled_verb), rand(5, 12))
		return
	if(bot_is_officer(user) && !resists_arrest())
		return //being searched, moved along or held down by security: on_attacked() has the protesting
	// A doctor's needle in somebody hurt is the doctor doing their job, whatever it looks like to the patient.
	// A medical cyborg's hypospray too: a janitor fighting a traitor took one for an attack, beat the cyborg, and was booked for it (2026-11-10).
	if((handled_verb in list("injected", "attempted to inject", "sprayed", "splashed", "fed")) && owner.health < owner.maxHealth * 0.75 && bot_is_medic(user))
		return
	add_grudge(user, anger)
	addtimer(CALLBACK(src, PROC_REF(answer_handling), WEAKREF(user), handled_verb, object), rand(3, 8))

/// Someone friendly tapped it on the shoulder, or brought it round.
/datum/bot_brain/proc/answer_touch(datum/weakref/who, handled_verb)
	var/mob/living/user = who?.resolve()
	if(!user || QDELETED(owner) || owner.stat != CONSCIOUS || state == BOT_STATE_COMBAT)
		return
	if(handled_verb == "CPRed")
		return
	pokes = world.time < last_poked + 20 SECONDS ? pokes + 1 : 1
	last_poked = world.time
	if(world.time < next_reaction_time)
		return
	next_reaction_time = world.time + 40
	owner.face_atom(user)
	if(pokes >= 4)
		add_grudge(user, 1)
		bot_say(owner, pick(GLOB.bot_overpoked_lines))
	else if(prob(30 + 50 * sociability))
		bot_say(owner, pick(GLOB.bot_poked_lines))

/// A moment later, the way it takes a person a moment: a word, a shove back, or that's enough.
/datum/bot_brain/proc/answer_handling(datum/weakref/who, handled_verb, atom/object)
	var/mob/living/user = who?.resolve()
	if(!user || QDELETED(owner) || owner.stat != CONSCIOUS)
		return
	if(state == BOT_STATE_COMBAT && attacker == user)
		last_hit_by_attacker = world.time //still at it: so's the fight
		return
	var/grudge = grudge_with(user)
	if(grudge >= handling_limit(BOT_GRUDGE_FIGHT))
		had_enough_of(user, handled_verb, object)
		return
	if(grudge >= handling_limit(BOT_GRUDGE_SHOVE) && shove_back(user))
		return
	tell_off(user, handled_verb)

/datum/bot_brain/proc/tell_off(mob/living/user, handled_verb)
	if(owner.incapacitated(ignore_grab = TRUE) || world.time < next_reaction_time)
		return
	next_reaction_time = world.time + 30
	if(!pursuing_kind)
		owner.face_atom(user)
	var/list/lines = GLOB.bot_shoved_lines
	switch(handled_verb)
		if("grabbed")
			lines = GLOB.bot_grabbed_lines
		if("stripped")
			lines = GLOB.bot_robbed_lines
		if("injected", "attempted to inject", "sprayed", "splashed", "fed")
			lines = GLOB.bot_needled_lines
	bot_say(owner, pick(lines))
	bot_log(src, "telling [user] off ([handled_verb])")
	bot_tally("told off")

/// A disarm-intent click back at them: what they did to it. FALSE if they're out of reach, or it's in no state to.
/datum/bot_brain/proc/shove_back(mob/living/user)
	if(!owner.Adjacent(user) || owner.incapacitated() || owner.next_move > world.time)
		return FALSE
	stop_pursuit_for_a_moment()
	owner.face_atom(user)
	owner.changeNext_move(CLICK_CD_MELEE)
	var/old_intent = owner.a_intent
	owner.a_intent = INTENT_DISARM
	telemetry_clicked(user)
	owner.UnarmedAttack(user, TRUE)
	owner.a_intent = old_intent
	bot_log(src, "shoving [user] back")
	bot_tally("shoves back")
	if(world.time >= next_reaction_time && prob(60))
		next_reaction_time = world.time + 30
		bot_say(owner, pick(GLOB.bot_combat_lines))
	return TRUE

/// A shove isn't worth abandoning a walk for: it's only got to be standing still to do it, and the walk picks itself up.
/datum/bot_brain/proc/stop_pursuit_for_a_moment()
	stand_still_until = max(stand_still_until, world.time + CLICK_CD_MELEE)

/datum/bot_brain/proc/had_enough_of(mob/living/user, handled_verb, atom/object)
	bot_log(src, "had enough of [user] ([handled_verb])")
	bot_tally("lost their temper")
	bot_record_aggression(user, owner) //they started it, whatever a witness sees next
	if(is_security_job() && ishuman(user) && !bot_is_officer(user))
		file_crime(user, "Assaulting an Officer", "Wouldn't keep their hands off [owner.real_name] in [get_area_name(owner, TRUE)].", BOT_CRIME_MINOR)
	on_attacked(user, handled_verb, object)

// ---------------------------------------------------------------------------------------------
// Things knocked out of its hand
// ---------------------------------------------------------------------------------------------

/// From species/disarm(), when a disarm knocks something out of this bot's hand.
/datum/bot_brain/proc/on_knocked_from_hand(obj/item/I)
	if(GLOB.bot_reflexes_off || !I)
		return
	LAZYADD(knocked_away, WEAKREF(I))
	knocked_away_at = world.time

/// While it has the use of its hands. Being put on the floor drops whatever's in them, and nothing says so but the state of
/// its hands when it gets up.
/// A slime on its head: pulled at until it comes off, which is a click on it with an empty hand (slime attack_hand()). Left alone
/// it eats you, slowly, and you go on about your day until you fall over.
/datum/bot_brain/proc/mind_slime()
	for(var/mob/living/simple_animal/slime/S in owner.buckled_mobs)
		if(owner.next_move > world.time)
			return
		bot_log(src, "wrestling [S] off me")
		owner.changeNext_move(CLICK_CD_MELEE)
		make_hand_free()
		S.attack_hand(owner)
		return

/datum/bot_brain/proc/mind_hands()
	if(!owner.has_active_hand())
		use_a_working_hand() //bot_human.dm: an arm lost or hurt past use, and the other one used
	mind_slime()
	mind_fauna() //goals/mining.dm
	if(armed_bomb)
		mind_armed_bomb() //goals/toxins.dm
	if(length(GLOB.bot_ticking_bombs))
		mind_ticking_bombs() //goals/sabotage_bomb.dm
	if(length(GLOB.hostile_machines))
		mind_armed_drones() //goals/circuit_drones.dm
	if(floored)
		floored = FALSE
		if(!GLOB.bot_reflexes_off)
			for(var/datum/weakref/ref in hands_were) //typed: an item mid-delete has no weakref (WEAKREF() of it is null)
				var/obj/item/I = ref.resolve()
				if(I && isturf(I.loc))
					LAZYADD(knocked_away, ref)
					knocked_away_at = world.time
	hands_were = list()
	for(var/obj/item/I in owner.held_items)
		var/datum/weakref/held = WEAKREF(I)
		if(held)
			hands_were += held
	if(knocked_away && gym_scripted && state == BOT_STATE_WANDER)
		try_recover_knocked_item() //otherwise after the reflexes in process(), where walking back for it holds everything else up

/datum/bot_brain/proc/try_recover_knocked_item()
	if(world.time > knocked_away_at + BOT_KNOCKED_ITEM_MEMORY)
		knocked_away = null
		return FALSE
	var/datum/weakref/ref = knocked_away[1]
	var/obj/item/I = ref.resolve()
	if(!I)
		LAZYREMOVE(knocked_away, ref)
		return FALSE
	if(!isturf(I.loc))
		LAZYREMOVE(knocked_away, ref)
		var/mob/living/thief = bot_outermost_holder(I)
		if(isliving(thief) && thief != owner && !bot_means_well(thief))
			add_grudge(thief, 3)
			addtimer(CALLBACK(src, PROC_REF(answer_handling), WEAKREF(thief), "stripped"), rand(3, 8))
		return FALSE
	if(owner.next_move > world.time)
		return FALSE
	if(!owner.Adjacent(I))
		// A weapon or a tool a step or three off goes back in the hand before anything else: an officer knocked flat by a nanosuit got up,
		// went on with the arrest four tiles away, and left his energy gun on the floor where he fell. Anything less, or further, is let be.
		if(get_dist(owner, I) > 3 || !worth_going_back_for(I) || owner.buckled || owner.pulledby || !(I in view(3, owner)))
			return FALSE
		if(pursuing_kind != "follow" || pursue_target != I)
			pursue(I, "follow", force = TRUE)
		return TRUE
	if(pursue_target == I)
		stop_pursuit()
	LAZYREMOVE(knocked_away, ref)
	bot_log(src, "picking [I] back up")
	bot_tally("picked back up")
	INVOKE_ASYNC(src, PROC_REF(take_back), I)
	return TRUE

/// Worth a step or three back for, with somebody at it: a weapon, cuffs, a tool, an ID, the RPED, what the job's about.
/datum/bot_brain/proc/worth_going_back_for(obj/item/I)
	return istype(I, /obj/item/gun) || istype(I, /obj/item/melee) || I.force >= 10 || istype(I, /obj/item/restraints) || istype(I, /obj/item/card/id) || istype(I, /obj/item/storage/part_replacer) || is_tool_or_toolbox(I) || I == current_goal?.target

/datum/bot_brain/proc/take_back(obj/item/I)
	if(try_pickup_target(I) && state == BOT_STATE_COMBAT)
		ready_in_hand(I)

#undef BOT_GRUDGE_FADE
#undef BOT_GRUDGE_SHOVE
#undef BOT_GRUDGE_FIGHT
#undef BOT_GRIP_PATIENCE
#undef BOT_CUFFED_PATIENCE
#undef BOT_KNOCKED_ITEM_MEMORY
