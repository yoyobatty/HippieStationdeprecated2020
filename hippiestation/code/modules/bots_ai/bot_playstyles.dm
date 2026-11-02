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
		if(H.stat != CONSCIOUS || H.handcuffed || greytider || world.time < next_sighting_call || bot_is_officer(H) || bot_means_well(H))
			continue
		var/datum/bot_wanted/W = bot_get_wanted_entry(H)
		if(W?.severity >= BOT_CRIME_MAJOR)
			continue
		var/obj/item/thing = bot_contraband_on(H)
		if(thing)
			next_sighting_call = world.time + 1 MINUTES
			saw_something_on(H, "Possession of Dangerous Equipment", "has got [thing.name]", BOT_CRIME_MAJOR)
		else if(get_dist(owner, H) <= 3 && bot_has_stolen_captains_id(H)) //close enough to read the card
			next_sighting_call = world.time + 1 MINUTES
			saw_something_on(H, "Grand Larceny", "has the Captain's ID", BOT_CRIME_MURDER)

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
	if(hardened || H.bot_executed || istype(get_area(H), /area/medical/morgue))
		return
	var/datum/weakref/ref = WEAKREF(H)
	if(ref in bodies_seen)
		return
	LAZYADD(bodies_seen, ref)
	if(prob(40))
		harden("found [H] dead")

// ---------------------------------------------------------------------------------------------
// Holding somebody for Security
// ---------------------------------------------------------------------------------------------

/// A fight's over and they're down: if Security wants them, somebody had better still be there when it comes.
/datum/bot_brain/proc/after_the_fight(mob/living/foe)
	var/mob/living/carbon/human/H = foe
	if(!istype(H) || H.stat == DEAD || is_security_job() || greytider || !bot_is_wanted(H) || !is_subdued(H))
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
		if(gym_run && get_area(H) != get_area(owner))
			continue //somebody else's arena
		best = H
		best_at = W.last_seen_at
	return best

/datum/bot_duty/hunt_valids
	name = "hunting somebody down"
	tier = BOT_DUTY_URGENT
	priority = 25
	interval_min = 40
	interval_max = 90

/datum/bot_duty/hunt_valids/applies_to(datum/bot_brain/bot)
	return bot.playstyle == BOT_STYLE_HUNTER && !bot.is_security_job()

/datum/bot_duty/hunt_valids/try_start(datum/bot_brain/bot)
	if(!length(GLOB.bot_security_wanted) || !bot.has_a_weapon())
		return FALSE
	var/mob/living/carbon/human/mark = bot.find_quarry()
	if(!mark)
		return FALSE
	var/datum/bot_wanted/W = bot_get_wanted_entry(mark)
	if(!bot.can_walk_lawfully_to(W.last_seen) || !bot.assign_goal(new /datum/bot_goal/hunt(W.last_seen)))
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

/datum/bot_goal/hunt/New(turf/T)
	. = ..()
	last_seen = T

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
