// Playstyles in a round: what the traits in bot_personality.dm come to.
//
//  - Eyes open (look_round_the_room()). Syndicate gear out in the open, or the Captain's ID on somebody who shouldn't have it, gets
//    called in. Somebody lying dead can harden whoever finds them.
//  - A fight won against somebody Security wants isn't the end of it. They're held down until Security gets there, and cuffed if
//    the bot has anything to cuff them with (/datum/bot_goal/hold_for_security). Nobody finishes anybody off (bot_law.dm).
//  - The powergamer, the hunter and the paranoid each go after their own kit (/datum/bot_duty/stock_up): the best gear going, what
//    it takes to bring somebody in, or what it takes to live through it.
//  - The antag hunter drops what it's doing for a name on the radio (/datum/bot_duty/hunt_valids).

/// The longest it sits on somebody waiting for Security.
#define BOT_HOLD_TIME (2 MINUTES)
/// How old a sighting can be and still be worth going after.
#define BOT_HUNT_SIGHTING (3 MINUTES)
/// Before it looks again for something it couldn't get.
#define BOT_KIT_REST (5 MINUTES)

/// What each kind likes to have on it, the first thing first. Whatever it can get by the door: break-ins are another matter.
GLOBAL_LIST_INIT(bot_style_kits, list(
	BOT_STYLE_ROBUST = list(
		/obj/item/storage/firstaid/regular,
		/obj/item/crowbar,
		/obj/item/assembly/flash/handheld,
	),
	BOT_STYLE_POWERGAMER = list(
		/obj/item/clothing/gloves/color/yellow,
		/obj/item/storage/belt/utility,
		/obj/item/crowbar,
		/obj/item/flashlight,
		/obj/item/clothing/mask/gas,
		/obj/item/storage/firstaid/regular,
		/obj/item/assembly/flash/handheld,
	),
	BOT_STYLE_HUNTER = list(
		/obj/item/crowbar,
		/obj/item/assembly/flash/handheld,
		/obj/item/restraints/handcuffs,
		/obj/item/flashlight,
	),
	BOT_STYLE_PARANOID = list(
		/obj/item/storage/firstaid/regular,
		/obj/item/crowbar,
		/obj/item/assembly/flash/handheld,
		/obj/item/flashlight,
	),
))

/datum/bot_brain
	/// Bodies it's already taken in, as weakrefs.
	var/list/bodies_seen
	/// Kit it went looking for -> when it's worth looking again.
	var/list/kit_rests
	/// When it can next use its flash.
	var/next_flash_time = 0

/// Whatever's on them, out in the open, that nobody on the crew has any reason to have.
/proc/bot_contraband_on(mob/living/carbon/human/H)
	for(var/obj/item/I in H.held_items)
		if(is_type_in_typecache(I, GLOB.bot_contraband))
			return I
	if(H.wear_suit && is_type_in_typecache(H.wear_suit, GLOB.bot_contraband))
		return H.wear_suit
	if(H.head && is_type_in_typecache(H.head, GLOB.bot_contraband))
		return H.head
	return null

/// Whether it's got something to hit with, on it or in its hand.
/datum/bot_brain/proc/has_a_weapon()
	return owner.get_active_held_item()?.force >= BOT_COMBAT_WEAPON_FORCE || !!find_carried_tool(/obj/item/storage/toolbox) || !!find_carried_tool(/obj/item/crowbar)

// ---------------------------------------------------------------------------------------------
// Eyes open
// ---------------------------------------------------------------------------------------------

/// A look at who's in the room, every few seconds (keep_an_eye_out(), bot_witness.dm).
/datum/bot_brain/proc/look_round_the_room()
	for(var/mob/living/carbon/human/H in view(6, owner))
		if(H == owner)
			continue
		if(H.stat == DEAD)
			note_body(H)
			continue
		if(H.stat != CONSCIOUS || H.handcuffed || greytider || bot_is_officer(H) || bot_is_the_captain(H) || bot_means_well(H))
			continue
		var/obj/item/thing = bot_contraband_on(H)
		if(thing && !is_security_job() && menaced_by(H, thing))
			return
		if(world.time < next_sighting_call)
			continue
		var/datum/bot_wanted/W = bot_get_wanted_entry(H)
		if(W?.severity >= BOT_CRIME_MAJOR)
			continue
		if(thing)
			next_sighting_call = world.time + 1 MINUTES
			if(is_security_job())
				saw_something_on(H, bot_contraband_crime(thing), "has got [thing.name]", BOT_CRIME_MAJOR)
			else
				saw_contraband(H, thing)
		else if(get_dist(owner, H) <= 3 && bot_has_stolen_captains_id(H)) //close enough to read the card
			next_sighting_call = world.time + 1 MINUTES
			saw_something_on(H, "Grand Larceny", "has the Captain's ID", BOT_CRIME_MURDER)
	pocket_loose_contraband()

// ---------------------------------------------------------------------------------------------
// A traitor's kit in sight
// ---------------------------------------------------------------------------------------------
// The user's rulings (2026-11-10, after playing: they picked an energy sword up off the floor and a Science bot called Security on
// them on the spot): nobody but Security runs to Security over seeing it. Word gets round, the more so the more the bot talks, and
// it acts itself only if they come at it with it (menaced_by()) or go for it (on_attacked(), bot_brain.dm). Security, and the kinds
// that would want one, pick up a traitor's kit they find lying about and keep it.

/datum/bot_brain
	/// weakref of somebody it saw with a traitor's kit -> list(how far off they were last look, whether it's called it in)
	var/list/contraband_seen
	/// A traitor's kit it saw lying loose at its last glance (glance_at_items()), as a weakref
	var/datum/weakref/loose_contraband

/// Out and ready to use: an energy sword lit, a gun or a grenade in hand. An emag or a suit is no threat to anybody stood there.
/proc/bot_item_out(obj/item/I)
	if(istype(I, /obj/item/melee/transforming))
		var/obj/item/melee/transforming/T = I
		return T.active
	return istype(I, /obj/item/gun) || istype(I, /obj/item/grenade)

/// Somebody who isn't Security seeing it: the news goes round (bot_news(), bot_chatter.dm), and by its nature it says so on the
/// radio, to whoever's about, or nothing. The radio line is a heads-up, not a call: Security answers "help" and "security"
/// (on_heard_security_call()), and an officer goes by what it sees.
/datum/bot_brain/proc/saw_contraband(mob/living/carbon/human/H, obj/item/thing)
	var/who = H.name == "Unknown" ? "Somebody" : H.name
	var/where = get_area_name(H, TRUE)
	bot_news("[who] was seen with \a [thing] in [where]", H)
	learn_fact(BOT_FACT_CONTRABAND, H, null, where, "[thing.name]") //bot_memory.dm: it passes it on, or not, by who it is
	bot_tally("traitor kit seen")
	if(playstyle == BOT_STYLE_HUNTER || playstyle == BOT_STYLE_PARANOID || hardened)
		bot_log(src, "saw [H] with [thing] in [where] - saying so on the radio")
		bot_say(owner, ";Heads up, [who]'s walking about with \a [thing] in [where].")
		return
	for(var/mob/living/carbon/human/other in view(5, owner))
		if(other != owner && other != H && other.stat == CONSCIOUS)
			if(prob(sociability * 70))
				bot_log(src, "saw [H] with [thing] in [where] - saying so to [other]")
				owner.face_atom(other)
				bot_say(owner, pick("Is that \a [thing]? Where'd [who] get that?", "Uh. [who]'s got \a [thing].", "Anyone else see what [who]'s carrying?"))
				return
			break
	bot_log(src, "saw [H] with [thing] in [where] - keeping it to itself")

/// Coming at it with it out: within a couple of tiles, and closer than at its last look. Then it calls Security, once, and gets
/// away, unless it has the nerve and something to hit back with.
/datum/bot_brain/proc/menaced_by(mob/living/carbon/human/H, obj/item/thing)
	var/datum/weakref/ref = WEAKREF(H)
	var/dist = get_dist(owner, H)
	var/list/seen = LAZYACCESS(contraband_seen, ref)
	var/was = seen ? seen[1] : INFINITY
	var/list/now = list(dist, seen ? seen[2] : FALSE)
	LAZYSET(contraband_seen, ref, now)
	if(dist > 2 || dist >= was || !bot_item_out(thing))
		return FALSE
	bot_log(src, "[H] came at me with [thing] out")
	if(!now[2])
		now[2] = TRUE
		call_it_in(H, bot_contraband_crime(thing), "came at me with \a [thing]", BOT_CRIME_MAJOR)
	if(nerve < 0.7 || !has_a_weapon())
		run_from(H, "[H] came at me with [thing]")
	return TRUE

/// Who picks up a traitor's kit found lying about and keeps it: Security, and the kinds that would want one.
/datum/bot_brain/proc/keeps_found_contraband()
	return is_security_job() || greytider || (playstyle in list(BOT_STYLE_POWERGAMER, BOT_STYLE_HUNTER, BOT_STYLE_PARANOID, BOT_STYLE_ROBUST))

/datum/bot_brain/proc/pocket_loose_contraband()
	var/obj/item/I = loose_contraband?.resolve()
	loose_contraband = null
	if(!I || state != BOT_STATE_WANDER || !isturf(I.loc) || I.anchored || !keeps_found_contraband())
		return
	if(LAZYACCESS(contraband_rests, WEAKREF(I)) > world.time)
		return //tried, and couldn't get it or keep it: an emag seen through the Brig's glass was gone for every five seconds
	if(!hand_free_for_pickup())
		return //both hands full: 22 of 29 that went for it and didn't get it
	assign_goal(new /datum/bot_goal/pocket_contraband(I))

/datum/bot_brain
	/// weakref of a traitor's kit it went for and didn't get -> when it might again
	var/list/contraband_rests

/datum/bot_goal/pocket_contraband
	lawful = TRUE
	exclusive = TRUE
	doing = "picking something up"
	var/obj/item/found

/datum/bot_goal/pocket_contraband/New(obj/item/I)
	. = ..()
	found = I

/datum/bot_goal/pocket_contraband/resolve_target(datum/bot_brain/bot)
	if(!found)
		for(var/obj/item/I in view(BOT_SIGHT_RANGE, bot.owner))
			if(GLOB.bot_contraband[I.type] && isturf(I.loc))
				found = I
				break
	if(!QDELETED(found) && isturf(found.loc) && found.z == bot.owner.z && get_dist(bot.owner, found) <= BOT_SIGHT_RANGE + 3 && !bot.taken_by_another(found))
		target = found

/datum/bot_goal/pocket_contraband/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.contraband_rests, WEAKREF(target), world.time + 5 MINUTES)

/datum/bot_goal/pocket_contraband/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/pocket_contraband/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/pocket_contraband())
	return list(S)

/datum/bot_strategy/pocket_contraband/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/datum/bot_step/pocket_contraband/execute(datum/bot_brain/bot)
	var/obj/item/I = bot.current_goal?.target
	if(!istype(I) || QDELETED(I) || !isturf(I.loc))
		bot_log(bot, "[I] isn't lying there any more")
		return GOAL_STEP_FAIL
	bot.human_pause(I)
	if(QDELETED(I) || !isturf(I.loc))
		bot_log(bot, "[I] went before it got it")
		return GOAL_STEP_FAIL
	if(!bot.stow_item(I))
		bot_log(bot, "couldn't take [I]: [bot.owner.handcuffed ? "cuffed" : (bot.hand_free_for_pickup() ? "it wouldn't come" : "hands full")]")
		return GOAL_STEP_FAIL
	bot_log(bot, "kept [I], found lying about")
	bot_tally("traitor kit kept")
	bot_say(bot.owner, bot.is_security_job() ? pick("Confiscated.", "I'll be holding on to this.", "Evidence.") : pick("Finders keepers.", "Ooh. Mine now.", "Don't mind if I do."))
	return GOAL_STEP_SUCCESS

/datum/bot_brain/proc/saw_something_on(mob/living/carbon/human/H, crime, details, severity)
	owner.face_atom(H)
	if(is_security_job())
		file_crime(H, crime, "[capitalize(details)] in [get_area_name(H, TRUE)].", severity)
		bot_say(owner, ":s [crime], [get_area_name(H, TRUE)] - suspect [H.name]. Responding.")
		begin_arrest(H)
		return
	call_it_in(H, crime, details, severity)

/// Somebody lying dead, the first time it comes across them. It doesn't take everybody the same way.
/datum/bot_brain/proc/note_body(mob/living/carbon/human/H)
	if(H.bot_executed || istype(get_area(H), /area/medical/morgue))
		return
	var/datum/weakref/ref = WEAKREF(H)
	if(ref in bodies_seen)
		return
	LAZYADD(bodies_seen, ref)
	bot_news("[H.real_name] turned up dead in [get_area_name(H, TRUE)]", H)
	learn_fact(BOT_FACT_DIED, null, H, get_area_name(H, TRUE)) //bot_memory.dm
	if(!hardened && prob(40))
		harden("found [H] dead")
	see_to_body(H)

// ---------------------------------------------------------------------------------------------
// A body found (the user's Captain round, 2026-11-13, round-17.21.40): Lee Montague lay dead in Fore Maintenance, in the hole a fuel tank
// had blown in the floor, for nine minutes. An atmospheric technician and an engineer walked past her, "found Lee Montague dead", and
// went on with what they were doing: nobody said a word, and nobody brought her out. People do one or both: say where on the radio, and
// drag the body to Medbay for the doctors (the cloner, or the morgue).
// ---------------------------------------------------------------------------------------------

/// Bodies somebody's said on the radio they've found: weakref -> when. Once between everybody, not by each who walks past.
GLOBAL_LIST_EMPTY(bot_bodies_reported)

/datum/bot_brain
	/// Not off with another body before this
	var/next_body_carry = 0
	/// Added to the chance it brings a body out (a Bot Gym scenario makes it certain)
	var/body_carry_bias = 0

/// Said where it is, and taken it to Medbay if it's free to and the sort to.
/datum/bot_brain/proc/see_to_body(mob/living/carbon/human/H)
	if(bot_in_medbay(H) || bot_traitor || op_team || bot_wizard || gone_loud() || owner.incapacitated() || owner.handcuffed)
		return
	if(state == BOT_STATE_COMBAT || state == BOT_STATE_ARREST || H.pulledby || H.buckled || !isturf(H.loc))
		return
	var/datum/weakref/W = WEAKREF(H)
	var/where = get_area_name(H, TRUE)
	if((!(W in GLOB.bot_bodies_reported) || world.time > GLOB.bot_bodies_reported[W] + 5 MINUTES) && prob(60 + sociability * 40))
		GLOB.bot_bodies_reported[W] = world.time
		bot_log(src, "found [H] dead in [where] - saying so")
		bot_tally("bodies reported")
		if(!gym_scripted)
			say_after_typing(pick(";Body in [where]. Looks like [H.first_name()].", ";Medical, there's a body in [where]. [H.real_name].", ";Found [H.first_name()] dead in [where].", ";There's somebody dead in [where]."))
	if(world.time < next_body_carry || !prob(25 + diligence * 50 + (is_medical_job() ? 30 : 0) + body_carry_bias))
		return
	if(state == BOT_STATE_GOAL && !(current_goal && bot_goal_can_wait(current_goal))) //goals/carry_casualty.dm
		return
	var/turf/spot = medbay_drop_spot() //goals/security_medevac.dm
	if(!spot || taken_by_another(H) || in_bad_air(H) || !can_walk_lawfully_to(H))
		return
	if(state == BOT_STATE_GOAL)
		drop_goals("bringing [H]'s body out")
	if(assign_goal(new /datum/bot_goal/carry_casualty/body(H, spot)))
		next_body_carry = world.time + 5 MINUTES
		bot_log(src, "taking [H]'s body to Medbay")

/// A body to Medbay's door, for the doctors: the cloner, or the morgue (clone_body, goals/cloning.dm, takes it from there).
/datum/bot_goal/carry_casualty/body
	doing = "bringing a body to Medbay"

/datum/bot_goal/carry_casualty/body/resolve_target(datum/bot_brain/bot)
	var/mob/living/carbon/human/H = target
	if(QDELETED(H) || H.stat != DEAD || !isturf(H.loc) || !drop_spot || bot_in_medbay(H))
		target = null

/datum/bot_goal/carry_casualty/body/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/escort/S = new(drop_spot)
	var/datum/bot_step/move_to/to_medbay = new
	to_medbay.step_target = drop_spot
	// A body's taken hold of as the Chaplain does it (goals/civilians.dm): no medipen for the dead
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/take_hold_of_body(), to_medbay, new /datum/bot_step/set_casualty_down())
	return list(S)

/datum/bot_goal/carry_casualty/body/on_success(datum/bot_brain/bot)
	var/mob/living/carbon/human/H = target
	if(istype(H) && !bot.gym_scripted)
		bot.say_after_typing(pick(";Medbay, I've left [H.first_name()]'s body at your door.", ";Brought [H.real_name] to Medbay. Dead, for the cloner if they can.", ";[H.first_name()]'s body is at Medbay's door."))

// ---------------------------------------------------------------------------------------------
// Holding somebody for Security
// ---------------------------------------------------------------------------------------------

/// A fight's over and they're down: if Security wants them, somebody had better still be there when it comes.
/datum/bot_brain/proc/after_the_fight(mob/living/foe)
	var/mob/living/carbon/human/H = foe
	if(!istype(H) || H.stat == DEAD || is_security_job() || greytider || !bot_is_wanted(H) || !is_subdued(H))
		return
	if(gone_loud()) //an operative, say: Security's the last people it wants
		return
	if(bot_shuttle_boarding()) //nobody's coming for them now, and it was this that left two people sat on somebody at the shuttle's own doors
		return
	if(state == BOT_STATE_GOAL)
		if(istype(current_goal, /datum/bot_goal/treat_patient) || istype(current_goal, /datum/bot_goal/evacuate))
			return
		drop_goals("keeping hold of [H]")
	if(state == BOT_STATE_WANDER)
		assign_goal(new /datum/bot_goal/hold_for_security(H))

/datum/bot_goal/hold_for_security
	lawful = TRUE
	doing = "keeping hold of somebody for Security"
	var/mob/living/carbon/human/captive

/datum/bot_goal/hold_for_security/New(mob/living/carbon/human/H)
	. = ..()
	captive = H

/datum/bot_goal/hold_for_security/resolve_target(datum/bot_brain/bot)
	if(!QDELETED(captive) && captive.stat != DEAD)
		target = captive

/datum/bot_goal/hold_for_security/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/hold_down())
	return list(S)

/// Keeps them on the floor with a shove whenever they get up, and tells Security where they are.
/datum/bot_step/paced/hold_down
	max_clicks = 60
	var/ends_at = 0
	var/next_call = 0

/datum/bot_step/paced/hold_down/start(datum/bot_brain/bot)
	ends_at = world.time + BOT_HOLD_TIME
	next_call = 0
	return TRUE

/datum/bot_step/paced/hold_down/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/hold_for_security/G = bot.current_goal
	var/mob/living/carbon/human/C = G?.captive
	if(QDELETED(C) || C.stat == DEAD || world.time > ends_at || C.pulledby)
		return FALSE
	if(!bot.owner.Adjacent(C))
		if(get_dist(bot.owner, C) > 3)
			return FALSE //got away: it's a chase now, and that's Security's
		if(bot.pursuing_kind != "follow" || bot.pursue_target != C)
			bot.pursue(C, "follow", force = TRUE)
		wait_for = 8
		return TRUE
	bot.stop_pursuit()
	if(!C.handcuffed)
		var/obj/item/restraints/handcuffs/cuffs = bot.find_restraints()
		if(cuffs)
			bot_log(bot, "cuffing [C] for Security")
			bot.use_item_on(cuffs, C)
			wait_for = 10
			return TRUE
		if(!bot.is_subdued(C))
			bot.shove_back(C)
			wait_for = CLICK_CD_MELEE
			return TRUE
	if(world.time >= next_call)
		next_call = world.time + 40 SECONDS
		if(C.health <= 0)
			bot_say(bot.owner, ";Medical, [C.name] is in a bad way in [get_area_name(bot.owner, TRUE)]. Hurry!")
		bot_say(bot.owner, ";[C.name] is down in [get_area_name(bot.owner, TRUE)], I've got them. Security, come and get them!")
		bot_log(bot, "called Security to come and get [C]")
		bot_tally("held for Security")
	wait_for = 15
	return TRUE

// ---------------------------------------------------------------------------------------------
// Stocking up
// ---------------------------------------------------------------------------------------------

/// What this bot likes to have on it.
/datum/bot_brain/proc/my_kit()
	. = list()
	if(playstyle == BOT_STYLE_NORMAL || playstyle == BOT_STYLE_HOPPER)
		if(hardened)
			. += GLOB.bot_style_kits[BOT_STYLE_PARANOID]
	else
		. += GLOB.bot_style_kits[playstyle]
	var/list/chems = chem_wishlist() //goals/chem_lab.dm
	if(chems?["knockout"])
		. += /obj/item/gun/syringe

/datum/bot_duty/stock_up
	name = "stocking up"
	priority = 15
	interval_min = 300
	interval_max = 600

/datum/bot_duty/stock_up/applies_to(datum/bot_brain/bot)
	return !bot.is_security_job()

/datum/bot_duty/stock_up/try_start(datum/bot_brain/bot)
	var/list/kit = bot.my_kit()
	for(var/item_type in kit)
		if(bot.find_carried_tool(item_type) || LAZYACCESS(bot.kit_rests, item_type) > world.time)
			continue
		LAZYSET(bot.kit_rests, item_type, world.time + BOT_KIT_REST)
		var/datum/bot_goal/acquire_item_type/goal = new()
		goal.item_type = item_type
		goal.lawful = TRUE
		if(bot.assign_goal(goal))
			bot_log(bot, "stocking up: after [item_type]")
			bot_tally("stocking up")
			return TRUE
	return FALSE

/// The flash out of the kit, in the face, up close: it buys a second to get away, or to get the cuffs on.
/datum/bot_brain/proc/try_flash(mob/living/target)
	if(world.time < next_flash_time || !owner.Adjacent(target))
		return FALSE
	var/obj/item/assembly/flash/handheld/F = find_carried_tool(/obj/item/assembly/flash/handheld)
	if(!F || F.burnt_out || !ready_in_hand(F))
		return FALSE
	next_flash_time = world.time + 12 SECONDS
	bot_log(src, "flashing [target]")
	owner.a_intent = INTENT_HELP
	use_item_on(F, target)
	return TRUE

// ---------------------------------------------------------------------------------------------
// The hunt
// ---------------------------------------------------------------------------------------------

/// The latest name on the radio worth going after, that there's a recent sighting of.
/datum/bot_brain/proc/find_quarry()
	var/mob/living/carbon/human/best
	var/best_at = 0
	for(var/datum/weakref/ref as anything in GLOB.bot_security_wanted)
		var/mob/living/carbon/human/H = ref.resolve()
		var/datum/bot_wanted/W = GLOB.bot_security_wanted[ref]
		if(!H || H == owner || W.severity < BOT_CRIME_MAJOR || !W.last_seen || world.time > W.last_seen_at + BOT_HUNT_SIGHTING)
			continue
		if(H.stat == DEAD || H.handcuffed || W.last_seen.z != owner.z || is_in_active_cell(H) || W.last_seen_at <= best_at)
			continue
		// Down already, or in a sleeper or a locker: nothing to hunt. And not the same sighting twice: a hunter got there, found nobody,
		// and went back to the same spot 22 times in one shift, the wanted man lying in crit in Medbay.
		if(H.stat != CONSCIOUS || !isturf(H.loc) || LAZYACCESS(hunted_sightings, REF(H)) == W.last_seen_at)
			continue
		if(bot_too_dangerous(H) && !find_usable_gun())
			continue //a nanosuit or a gun isn't gone after with a toolbox: that's Security's, geared up (goals/security_tactics.dm)
		if(gym_run && get_area(H) != get_area(owner))
			continue //somebody else's arena
		best = H
		best_at = W.last_seen_at
	return best

/datum/bot_brain
	/// REF(somebody wanted) -> the sighting of them it last went to, so it isn't gone to again.
	var/list/hunted_sightings

/datum/bot_duty/hunt_valids
	name = "hunting somebody down"
	tier = BOT_DUTY_URGENT
	priority = 25
	interval_min = 40
	interval_max = 90

/datum/bot_duty/hunt_valids/applies_to(datum/bot_brain/bot)
	return !bot.is_security_job()

/datum/bot_duty/hunt_valids/try_start(datum/bot_brain/bot)
	if(!length(GLOB.bot_security_wanted) || !bot.fights_back_now() || !bot.has_a_weapon()) //goals/robust.dm
		return FALSE
	var/mob/living/carbon/human/mark = bot.find_quarry()
	if(!mark)
		return FALSE
	var/datum/bot_wanted/W = bot_get_wanted_entry(mark)
	LAZYSET(bot.hunted_sightings, REF(mark), W.last_seen_at)
	if(!bot.can_walk_lawfully_to(W.last_seen) || !bot.assign_goal(new /datum/bot_goal/hunt(W.last_seen, mark, W.last_seen_at)))
		return FALSE
	bot_log(bot, "going after [mark], last seen in [get_area_name(W.last_seen, TRUE)]")
	bot_tally("hunts")
	if(prob(40))
		bot_say(bot.owner, pick(";I'm going after [mark.name].", ";On my way. [mark.name]'s mine.", ";Where was [mark.name] last?"))
	return TRUE

/// To where they were last seen. Once they're in sight, the same eyes as anybody's take it from there (look_out_for_trouble(), bot_witness.dm).
/datum/bot_goal/hunt
	lawful = TRUE
	doing = "looking for somebody"
	var/turf/last_seen
	/// Who, and when they were seen there: from the sighting, a search (foundation/hunt.dm)
	var/datum/weakref/mark_ref
	var/seen_at = 0

/datum/bot_goal/hunt/New(turf/T, mob/living/mark, at)
	. = ..()
	last_seen = T
	mark_ref = mark ? WEAKREF(mark) : null
	seen_at = at

/datum/bot_goal/hunt/resolve_target(datum/bot_brain/bot)
	target = last_seen

/datum/bot_goal/hunt/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/move_to())
	return list(S)

// ---------------------------------------------------------------------------------------------
// Serving life
// ---------------------------------------------------------------------------------------------

/// The Prison Wing is all there is: no rounds, no duties, a walk round the room now and then (handle_wander(), bot_brain.dm).
/datum/bot_brain/proc/serve_time()
	if(pursuing_kind || world.time < next_wander_time)
		idle_fidget()
		return
	next_wander_time = world.time + rand(15 SECONDS, 45 SECONDS)
	var/turf/T = bot_prison_spot()
	if(T && get_dist(owner, T) <= 8)
		pursue(T, "wander")

/// For the Bot Shift report: who played how.
/proc/bot_playstyle_report()
	var/list/counts = list()
	var/hardened = 0
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		counts[B.playstyle]++
		if(B.hardened)
			hardened++
	var/list/parts = list()
	for(var/style in counts)
		parts += "[counts[style]] [style]"
	return "[english_list(parts)]; [hardened] hardened during the round"

#undef BOT_HOLD_TIME
#undef BOT_HUNT_SIGHTING
#undef BOT_KIT_REST
