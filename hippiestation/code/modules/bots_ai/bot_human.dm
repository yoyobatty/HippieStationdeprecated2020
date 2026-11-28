// Human-like action primitives. Everything a bot does with its hands should go through these, so
// it looks like a person doing it rather than an engine call:
//
//  - human_pause(): clicks come at a human rhythm - a short reaction/aim delay when switching to a
//    new thing, and never faster than a person can click. Measured before this existed: 9 hand
//    drill head swaps in 2.5s, and a hardsuit, mask, magboots and tank grabbed within 2ms.
//  - ready_in_hand(): the tool goes into the ACTIVE hand before it's used, the way a player has to
//    draw it off the belt first. Measured before: the jaws of life used 28 times without ever
//    leaving the belt.
//  - use_tool_on(): a help-intent click with a tool (crowbar/jaws on a door, tank on a canister) -
//    the same click that routes to try_to_crowbar()/attackby() for a player.
//  - face_atom() is called by use_atom()/use_item_on() before every interaction; a player's click
//    always turns them toward what they click.
//
// Telemetry (bot_telemetry.dm) and the Bot Gym report where bots still don't meet these rules.

// The pace itself (between clicks, and turning to a different thing) is in foundation/human_limits.dm, by skill.

/datum/bot_brain
	var/next_click_time = 0
	/// Weak so a clicked thing that then gets destroyed (a smashed window, a squashed mouse) can still be
	/// garbage collected - only ever compared, never used.
	var/datum/weakref/last_click_target
	/// While human_pause() is waiting to click, the bot is reaching for something - handle_wander()
	/// doesn't set off somewhere new until then. A time, not a flag, so it can never get left on.
	var/mid_click_until = 0

/// Waits until a human could plausibly make the next click on `target`. Sleeps - only call from
/// code that can (goal steps, obstruction clearing, pickups), never from pathfinding checks.
/datum/bot_brain/proc/human_pause(atom/target)
	var/wait = next_click_time - world.time
	var/datum/weakref/target_ref = WEAKREF(target)
	if(target_ref != last_click_target)
		wait = max(wait, 0) + reaction_delay() //foundation/human_limits.dm
	if(wait > 0)
		mid_click_until = world.time + wait
		sleep(wait)
	last_click_target = target_ref
	next_click_time = world.time + click_interval()

/// A beat between two inputs of the hands: something put away or set down to make room, and the next thing taken, or the thing drawn and
/// the click it's for. Each is an input of a player's own (a key, a click on the bag, a click on the thing), and a person doesn't make two in
/// one instant: telemetry had a drop and a pickup in the same tick about a thousand times a shift, and the item drawn off a belt or out of a
/// bag clicked on a door in the same one. Sleeps, like human_pause().
/datum/bot_brain/proc/hand_beat()
	var/wait = hand_beat_length()
	mid_click_until = world.time + wait
	sleep(wait)
	next_click_time = max(next_click_time, world.time + click_interval())

/// How long a beat is, in ds: 0.2-0.4 s for an apex bot, 0.3-0.6 s below. For a step that waits it out itself (wait_for).
/datum/bot_brain/proc/hand_beat_length()
	return is_apex() ? rand(2, 4) : rand(3, 6)

/// How many things are in its hands.
/datum/bot_brain/proc/held_item_count()
	. = 0
	for(var/obj/item/held in owner.held_items)
		.++

/// Gets I into the active hand, drawing it from the belt/backpack/pocket or picking it up, using a
/// free hand when there is one instead of stowing things unnecessarily. Returns TRUE on success.
/// paced: from code that can sleep (use_item_on()), a hand emptied to make room is an input of its own and the draw is the next, a beat later
/// (hand_beat()).
/datum/bot_brain/proc/ready_in_hand(obj/item/I, paced = FALSE)
	if(!I || QDELETED(I))
		return FALSE
	if(owner.get_active_held_item() == I)
		return TRUE
	if(owner.get_inactive_held_item() == I)
		owner.swap_hand()
		return owner.get_active_held_item() == I
	// Something the bot isn't carrying can only be taken up from within arm's reach. Without this a doctor
	// storing medicine it had left by the chem master "drew" each patch into its hand from three tiles away.
	var/atom/holder = I.loc
	while(holder && holder != owner && !isturf(holder))
		holder = holder.loc
	if(holder != owner && get_dist(owner, get_turf(I)) > 1)
		bot_log_verbose(src, "ready_in_hand: [I] isn't on me and is out of reach")
		return FALSE
	// Something it's wearing comes off into the hand: put_in_hands() on a worn item leaves it in its slot as well, worn and held at once.
	// Picking up a space suit had the game put it straight on (stow_item()), and getting it ready to wear left it in both places.
	if(holder == owner && I.loc == owner && !(I in owner.held_items) && !owner.temporarilyRemoveItemFromInventory(I))
		return FALSE
	use_a_working_hand()
	var/held_before = paced ? held_item_count() : 0
	if(owner.get_active_held_item() && !owner.get_inactive_held_item() && other_hand_works())
		owner.swap_hand() //the other hand is free - use it rather than putting something away
	if(owner.get_active_held_item())
		stow_item(owner.get_active_held_item())
	if(owner.get_active_held_item())
		free_hand_for(I) //last resort: the verified stow-or-set-down path
	if(paced && held_item_count() < held_before)
		hand_beat()
		holder = QDELETED(I) ? null : I.loc
		while(holder && holder != owner && !isturf(holder))
			holder = holder.loc
		if(QDELETED(I) || (holder != owner && get_dist(owner, get_turf(I)) > 1))
			return FALSE //gone, or out of reach by now
	if(!owner.put_in_active_hand(I))
		if(!owner.put_in_hands(I))
			return FALSE
		if(owner.get_active_held_item() != I)
			owner.swap_hand()
	LAZYREMOVE(set_down_items, I) //taken up again: it's not something set down for a moment any more (bot_items.dm)
	return owner.get_active_held_item() == I

/datum/bot_brain
	/// After a tool it couldn't take in passing, when it next tries (grab_passing_tools(), bot_items.dm).
	var/next_passing_grab = 0

/// Whether it has a hand that works with nothing in it.
/datum/bot_brain/proc/hand_free_for_pickup()
	for(var/i in 1 to length(owner.held_items))
		if(!owner.held_items[i] && owner.has_hand_for_held_index(i))
			return TRUE
	return FALSE

/// Whether the hand that isn't active can hold anything: an arm that's been lost, or hurt past use, can't (has_hand_for_held_index()).
/datum/bot_brain/proc/other_hand_works()
	return owner.has_hand_for_held_index(owner.get_inactive_hand_index())

/// The active hand on one that works, if it's on one that doesn't. swap_hand() goes to a hand that isn't there as readily as one that
/// is, and a scientist who'd lost an arm to the experimentor's fireball, switched to it to eat, held a tank transfer valve in the
/// other for the last forty minutes of the shift: everything it went to pick up after that "wouldn't go in its hand" (22 times),
/// and every job that needed a part was given up. A player whose hand isn't there switches back. FALSE with no hand that works.
/datum/bot_brain/proc/use_a_working_hand()
	if(owner.has_active_hand())
		return TRUE
	for(var/i in 1 to length(owner.held_items))
		if(owner.has_hand_for_held_index(i))
			owner.swap_hand(i)
			return owner.has_active_hand()
	return FALSE

/// Puts a held item away - an equipment slot, the belt, backpack or pocket storage - never on the
/// floor and never back into a hand. Returns TRUE if it left the hands.
/datum/bot_brain/proc/put_away(obj/item/I, allow_equip = TRUE)
	if(!I || QDELETED(owner) || !(I in owner.held_items))
		return FALSE
	if(allow_equip && bot_stows_by_wearing(I) && owner.equip_to_appropriate_slot(I)) //bot_items.dm
		return TRUE
	for(var/obj/item/storage/S in list(owner.get_item_by_slot(ITEM_SLOT_BELT), owner.get_item_by_slot(ITEM_SLOT_BACK), owner.get_item_by_slot(ITEM_SLOT_DEX_STORAGE)))
		if(S && SEND_SIGNAL(S, COMSIG_TRY_STORAGE_INSERT, I, owner))
			return TRUE
	for(var/obj/item/storage/S in owner.held_items) //e.g. wirecutters back into the toolbox in the other hand
		if(S != I && SEND_SIGNAL(S, COMSIG_TRY_STORAGE_INSERT, I, owner))
			return TRUE
	return FALSE

// ---------------------------------------------------------------------------------------------
// Hands between jobs
// ---------------------------------------------------------------------------------------------

/datum/bot_brain
	/// When it next sees to what's in its hands between jobs (tidy_hands()): a moment after a job ends or something's picked up.
	var/tidy_hands_at = 0
	/// What it had no room for and kept in hand anyway (a toolbox, a weapon): weakref -> when to try again, so it isn't tried every second.
	var/list/kept_in_hand
	/// What it had no room for and no use for, and left where it stood: weakref -> until when it isn't picked up again (is_useful_item()).
	var/list/let_go_of
	/// A Bot Gym bot leaves its hands alone between goals unless its scenario is about that.
	var/gym_tidies_hands = FALSE

/// Between jobs, what's in its hands goes back on the belt, in the bag or a pocket, a thing at a time, the way a player presses E or clicks
/// the bag once the job's done: they walk about with their hands empty. Nothing did this, and the Turing judge (tools/bot_gym/turing.py)
/// found the hands the biggest tell: something in a hand for 68-73% of a bot's time between jobs against 42-44% of the player's, and the
/// other hand full 58-65% of it against 30% (held_report.py, batch night1122b_after and two of the player's rounds). Screwdrivers,
/// handcuffs, gas masks, firesuits and a desk lamp went round on strolls for minutes, one for half an hour. What won't fit stays in hand
/// if it's worth keeping (a tool, a weapon, cuffs, a kit, a drink); clothing it isn't wearing and bulky odds and ends are left where it
/// stands. TRUE while it's putting something away.
/datum/bot_brain/proc/tidy_hands()
	if(world.time < tidy_hands_at || world.time < mid_click_until || state != BOT_STATE_WANDER || current_goal || goal_chain_pending)
		return FALSE
	if(!owner.get_active_held_item() && !owner.get_inactive_held_item())
		return FALSE
	if(owner.stat != CONSCIOUS || owner.incapacitated() || owner.handcuffed || gone_loud()) //wanted, it keeps a weapon to hand (stay_armed())
		return FALSE
	var/obj/item/I = next_to_tidy()
	if(!I)
		tidy_hands_at = world.time + 10 SECONDS
		return FALSE
	tidy_hands_at = world.time + hand_beat_length() + 5 //the next one after this one's beat
	INVOKE_ASYNC(src, PROC_REF(tidy_away), I) //it pauses like a person does: process() can't wait on it
	return TRUE

/// The next thing in its hands to see to between jobs, or null if everything there is meant to be held.
/datum/bot_brain/proc/next_to_tidy()
	for(var/obj/item/I in owner.held_items)
		if((I.item_flags & ABSTRACT) || HAS_TRAIT(I, TRAIT_NODROP)) //the other half of something two-handed, an arm blade
			continue
		if(istype(I, /obj/item/twohanded))
			var/obj/item/twohanded/T = I
			if(T.wielded)
				continue
		if(istype(I, /obj/item/flashlight))
			var/obj/item/flashlight/F = I
			// Lighting its way, in the dark (goals/solars.dm). Not in the light: a desk lamp is on from the start (flashlight.dm), and kept
			// for being lit, lamps were carried twice as long between jobs as before this (4.2% of the time, batch hands1128_after).
			if(F.on && in_the_dark())
				continue
		if(istype(I, /obj/item/clothing/head/mob_holder)) //a pet in its arms isn't put in the bag
			continue
		var/datum/weakref/ref = WEAKREF(I)
		if(LAZYACCESS(kept_in_hand, ref) > world.time)
			continue
		return I
	return null

/// What a person with no room for it leaves where they stand rather than carry about: clothing they aren't wearing, a desk lamp, other
/// bulky odds and ends. Not a tool, a weapon, cuffs, a kit, a bag, anything with something in it, or what a job's about.
/datum/bot_brain/proc/leaves_behind(obj/item/I)
	// A desk lamp hits like a weapon (force 10: worth_going_back_for()), and bots take one up to arm themselves (acquire_item_type), but
	// nobody carries a lamp about once the trouble's over.
	if(istype(I, /obj/item/flashlight/lamp))
		return TRUE
	if(worth_going_back_for(I) || bot_keeps_in_hand(I) || traitor_keeps_hold_of(I) || istype(I, /obj/item/storage) || I.reagents?.total_volume)
		return FALSE
	return istype(I, /obj/item/clothing) || I.w_class >= WEIGHT_CLASS_BULKY

/// Puts one thing away between jobs: an input of its own (a key, a click on the bag), a beat after the last.
/datum/bot_brain/proc/tidy_away(obj/item/I)
	hand_beat()
	if(QDELETED(owner) || QDELETED(I) || !(I in owner.held_items) || state != BOT_STATE_WANDER || current_goal || owner.incapacitated())
		return
	if(istype(I, /obj/item/weldingtool))
		var/obj/item/weldingtool/W = I
		if(W.isOn() && toggle_in_hand(W)) //off before it goes on the belt
			hand_beat()
			if(QDELETED(owner) || QDELETED(I) || !(I in owner.held_items))
				return
	// Clothing goes in the bag, not on: a firesuit picked up in passing isn't something to dress in for a stroll. A desk lamp goes
	// down, not on the belt, where it fits as a flashlight does (slot_flags) and nobody would clip one.
	if(!istype(I, /obj/item/flashlight/lamp) && put_away(I, allow_equip = !istype(I, /obj/item/clothing)))
		bot_log(src, "put [I] away")
		bot_tally("put away between jobs")
		return
	if(!leaves_behind(I))
		LAZYSET(kept_in_hand, WEAKREF(I), world.time + 2 MINUTES) //no room: it carries it, and looks again in a while
		return
	bot_log(src, "no room for [I] - leaving it here")
	bot_tally("left behind between jobs")
	owner.dropItemToGround(I)
	LAZYSET(let_go_of, WEAKREF(I), world.time + 30 MINUTES)

/// Whether it left I behind between jobs not long ago (tidy_away()): a stroll doesn't pick it straight back up.
/datum/bot_brain/proc/let_go_recently(obj/item/I)
	if(!let_go_of)
		return FALSE
	var/until = let_go_of[WEAKREF(I)]
	return until && until > world.time

/// A player's help-intent click on `target` with `tool` in hand - crowbar or jaws of life on a door
/// (door/attackby() -> try_to_crowbar()), a tank on a canister, and so on.
/datum/bot_brain/proc/use_tool_on(obj/item/tool, atom/target)
	var/old_intent = owner.a_intent
	owner.a_intent = INTENT_HELP
	. = use_item_on(tool, target)
	if(!QDELETED(owner)) //gibbed while it was at it: the pauses in use_item_on() let the body go, and its brain let go of it ("Cannot modify null.a_intent", gen1116)
		owner.a_intent = old_intent

/// Turns an item in hand on or off (welder, baton, extinguisher safety) the way a player does:
/// in the active hand, then use it in hand.
/datum/bot_brain/proc/toggle_in_hand(obj/item/I)
	if(!ready_in_hand(I))
		return FALSE
	human_pause(I)
	if(!ready_in_hand(I)) //the pause sleeps, and a fight doesn't wait: an officer's baton could be back on the belt by now
		return FALSE
	telemetry_shortcut("attack_self", I, null)
	I.attack_self(owner)
	return TRUE

// ---------------------------------------------------------------------------------------------
// Walking and idling
// ---------------------------------------------------------------------------------------------

/// Quick 0.2s re-tries after a step fails (a door finishing its animation) before the 1s stuck logic.
#define BOT_QUICK_STEP_RETRIES 5

/datum/bot_brain
	var/quick_step_retries = 0
	var/next_fidget_time = 0
	/// When it next looks round at somebody or turns about while stood waiting (idle_fidget()).
	var/next_look_round_time = 0

/// How long to linger after arriving somewhere while wandering. People hang around where there's
/// someone to talk to or somewhere to sit; they don't stand frozen on an empty tile for 20 seconds
/// (telemetry recorded a 17s freeze in the middle of Engineering).
/datum/bot_brain/proc/wander_dwell_time()
	for(var/mob/living/carbon/human/H in view(4, owner))
		if(H != owner && H.stat == CONSCIOUS)
			return rand(80, 250)
	if(locate(/obj/structure/chair) in range(2, owner))
		return rand(60, 180)
	if(locate(/obj/structure/table) in range(1, owner))
		return rand(40, 120)
	return rand(10, 40)

/// Small signs of life while waiting: look at whoever's nearby or at the door, and never loiter
/// in a doorway.
/datum/bot_brain/proc/idle_fidget()
	if(world.time < next_fidget_time || owner.incapacitated() || owner.buckled)
		return
	next_fidget_time = world.time + rand(15, 50)
	if(swat_passing_mice())
		return
	var/turf/here = get_turf(owner)
	if(here && (locate(/obj/machinery/door) in here))
		var/datum/weather/rad_storm/storm = bot_rad_storm(here.z) //goals/rad_storm.dm
		for(var/turf/open/T in get_adjacent_open_turfs(here))
			// In a radiation storm, not out of the doorway into it, nor on to whoever's sheltering just inside: that swaps them into the
			// doorway, and they step off it next. Put on a maintenance door's tile by the next one in, an officer stepped off it on the
			// hallway side and ran back in for shelter, twenty times in one storm (bugs1112base run1). The doorway itself is mostly cover.
			if(storm && (!is_type_in_list(T.loc, storm.protected_areas) || (locate(/mob/living/carbon/human) in T)))
				continue
			if(!T.density && !(locate(/obj/machinery/door) in T) && !is_blocked_turf(T, TRUE))
				step_to(owner, T)
				return
	// A look round every few seconds, not every one or two: a player stood waiting turns to something when it moves or speaks. The
	// Turing judge had bots turning on the spot in 10% of their still seconds against the player's 4% (turing.py slice, 2026-11-28).
	if(world.time < next_look_round_time)
		return
	next_look_round_time = world.time + rand(40, 120)
	var/list/interesting = list()
	for(var/mob/living/carbon/human/H in view(5, owner))
		if(H != owner && H.stat == CONSCIOUS)
			interesting += H
	if(!length(interesting))
		for(var/obj/machinery/door/D in view(4, owner))
			interesting += D
	if(length(interesting) && prob(70))
		owner.face_atom(pick(interesting))
	else if(prob(15))
		owner.setDir(pick(GLOB.cardinals))

// ---------------------------------------------------------------------------------------------
// Walking like a person
// ---------------------------------------------------------------------------------------------
// A person walking somewhere stops for a moment now and then (a look round, at the PDA, at who's about) and runs a step past a corner
// before turning back into it; a bot ran its route tile after tile at full speed. The Turing judge found it in the windows where both
// were mostly on the move (turing.py slice --calm --where "move_frac > 0.6", 2026-11-28): moving stretches of 5.75 s for the player
// against 9 s for bots, 6 brief stops a minute against 4, and the way reversed from one second to the next 20% of the time against 9%.

/// Out of a hundred: how often a turn after a straight run is taken a step late (corner_overshoot()).
#define BOT_OVERSHOOT_CHANCE 15

/datum/bot_brain
	/// Steps to go on a walk before it next stops for a moment (walk_pause()).
	var/steps_to_pause = 0
	/// The way its last step went, and how many in a row went that way (corner_overshoot()).
	var/last_step_dir = 0
	var/straight_steps = 0
	/// Its own BOT_OVERSHOOT_CHANCE, for a gym scenario to set.
	var/overshoot_chance = BOT_OVERSHOOT_CHANCE
	/// A Bot Gym bot walks straight through unless its scenario is about this.
	var/gym_walks_like_people = FALSE

/// Walked to in a hurry: no stops to look round on the way, and no step past a corner.
GLOBAL_LIST_INIT(bot_hurried_goals, typecacheof(list(
	/datum/bot_goal/run_from,
	/datum/bot_goal/respond_to_call,
	/datum/bot_goal/answer_call,
	/datum/bot_goal/treat_patient,
	/datum/bot_goal/escort_to_sleeper,
	/datum/bot_goal/fight_fire,
	/datum/bot_goal/evacuate,
	/datum/bot_goal/shelter_from_storm,
	/datum/bot_goal/seek_air,
	/datum/bot_goal/seek_medbay_healing,
	/datum/bot_goal/search_for,
	/datum/bot_goal/hunt,
	/datum/bot_goal/traitor_kill,
	/datum/bot_goal/hide_in_locker,
)))

/// Out for a stroll or on an everyday errand with nothing to hurry for: where walk_pause() and corner_overshoot() apply. Not running from
/// anybody or to anybody, not in bad air or a fight, not hauling, walking carefully, floating or wanted.
/datum/bot_brain/proc/walking_at_ease()
	if(gym_run && !gym_walks_like_people)
		return FALSE
	if((state != BOT_STATE_WANDER && state != BOT_STATE_GOAL) || (pursuing_kind != "wander" && pursuing_kind != "goal"))
		return FALSE
	if((urgency_override >= 0 ? urgency_override : urgency_known) != BOT_URGENCY_CALM || attacker || gone_loud())
		return FALSE
	if(owner.pulling || owner.pulledby || owner.buckled || owner.m_intent == MOVE_INTENT_WALK || !owner.has_gravity())
		return FALSE
	if(current_goal && (current_goal.never_rests || current_goal.braves_bad_air || current_goal.holds_for_calls || is_type_in_typecache(current_goal, GLOB.bot_hurried_goals)))
		return FALSE
	return TRUE

/// Deciseconds more before the next step (do_step_next_node(), bot_movement.dm): every 40-120 steps of a walk at its ease, a moment stood
/// still (1-2 s), looking at whoever's about. Not in a doorway or right in front of a door: a step more and it's through.
/datum/bot_brain/proc/walk_pause(turf/next_node)
	if(steps_to_pause <= 0)
		steps_to_pause = rand(40, 120)
		return 0
	if(--steps_to_pause > 0)
		return 0
	steps_to_pause = rand(40, 120)
	if(!walking_at_ease())
		return 0
	var/turf/here = get_turf(owner)
	if(!here || (locate(/obj/machinery/door) in here) || (next_node && (locate(/obj/machinery/door) in next_node)))
		steps_to_pause = rand(2, 4)
		return 0
	var/list/people = list()
	for(var/mob/living/carbon/human/H in view(5, owner))
		if(H != owner && H.stat == CONSCIOUS)
			people += H
	if(length(people) && prob(60))
		owner.face_atom(pick(people))
	bot_tally("stopped a moment on a walk")
	. = rand(10, 20)
	bot_log_verbose(src, "stopping a moment on the way ([. / 10] s)")

/// Now and then, on a walk at its ease, a turn after four or more steps the same way is taken a step late: on past the corner, then back
/// to it and round. Routes cut corners (a diagonal step), so there the corner is the tile the route cuts past, and the step past is beyond
/// it. The tiles to walk before the route goes on, or null. Only open floor in the same room with nobody on it, and not at a door, where
/// a person slows for it anyway.
/datum/bot_brain/proc/corner_overshoot(turf/next_node)
	if(straight_steps < 4 || !(last_step_dir in GLOB.cardinals) || !next_node || length(current_path) < 2 || current_path[1] != next_node)
		return null
	var/turf/here = get_turf(owner)
	if(!here || next_node.z != here.z)
		return null
	var/turn_dir = get_dir(here, next_node)
	var/turf/corner
	if(turn_dir == turn(last_step_dir, 90) || turn_dir == turn(last_step_dir, -90))
		corner = here //a square turn, here
	else if(turn_dir == turn(last_step_dir, 45) || turn_dir == turn(last_step_dir, -45))
		corner = get_step(here, last_step_dir) //a cut corner: round from the tile it cuts past
	else
		return null
	if(!prob(overshoot_chance) || !walking_at_ease())
		return null
	var/turf/past = get_step(corner, last_step_dir)
	for(var/turf/T in list(corner, past))
		if(T == here)
			continue
		if(!istype(T, /turf/open) || get_area(T) != get_area(here) || !is_wanderable_turf(T) || is_blocked_turf(T, TRUE) || (locate(/mob/living) in T) || (locate(/obj/machinery/door) in T))
			return null
	if((locate(/obj/machinery/door) in here) || (locate(/obj/machinery/door) in next_node))
		return null
	if((corner != here && here.LinkBlockedWithAccess(corner, owner, null)) || corner.LinkBlockedWithAccess(past, owner, null))
		return null
	if(corner == here)
		return list(past, here)
	// From the corner, the route's next tile is a straight step round
	if(get_dist(corner, next_node) != 1 || !(get_dir(corner, next_node) in GLOB.cardinals) || corner.LinkBlockedWithAccess(next_node, owner, null))
		return null
	return list(corner, past, corner)

/// Taking something off to put something else on: the old item goes into the bag (through a free
/// hand, like a player), and only onto the floor if there's truly nowhere to put it. Telemetry
/// caught bots dropping their shoes and hard hat on the floor when suiting up.
/datum/bot_brain/proc/swap_out_worn(obj/item/current, obj/item/replacement)
	if(!current || current == replacement)
		return
	if(!owner.temporarilyRemoveItemFromInventory(current))
		return
	if(owner.put_in_hands(current) && put_away(current, allow_equip = FALSE)) //into the bag - not straight back onto the body
		return
	if(current in owner.held_items)
		owner.dropItemToGround(current)
	else
		current.forceMove(owner.drop_location())

// ---------------------------------------------------------------------------------------------
// Pests
// ---------------------------------------------------------------------------------------------

/datum/bot_brain
	var/next_mouse_swat_time = 0

/// Squash a mouse within reach, the way crew do in passing - mice chew through power cables
/// (goals/repair_cables.dm). A harm-intent click with whatever is in hand, or a punch.
/datum/bot_brain/proc/swat_passing_mice()
	if(world.time < next_mouse_swat_time || state == BOT_STATE_COMBAT)
		return FALSE
	for(var/mob/living/simple_animal/mouse/M in range(1, owner))
		if(M.stat == DEAD || istype(M, /mob/living/simple_animal/mouse/brown/Tom) || !isturf(M.loc))
			continue
		// Asked once there's a mouse in reach: it was asked first, on every step every bot takes, a dozen proc calls to hear "no".
		if(owner.incapacitated())
			return FALSE
		next_mouse_swat_time = world.time + CLICK_CD_MELEE
		human_pause(M)
		if(QDELETED(owner) || QDELETED(M) || M.stat == DEAD || !owner.Adjacent(M)) //the pause sleeps: the body can go in it
			return FALSE
		owner.face_atom(M)
		var/old_intent = owner.a_intent
		owner.a_intent = INTENT_HARM
		var/obj/item/W = owner.get_active_held_item()
		var/swings = 0
		// Keep at it for a few clicks like a person would - a punch can miss or not quite kill it.
		while(swings < 4 && !QDELETED(M) && M.stat != DEAD && owner.Adjacent(M) && !owner.incapacitated())
			if(swings)
				human_pause(M)
			owner.face_atom(M)
			if(W && W.force > 0 && !(W.item_flags & NOBLUDGEON))
				W.melee_attack_chain(owner, M)
			else
				owner.UnarmedAttack(M, TRUE)
			swings++
		if(QDELETED(owner))
			return FALSE //gibbed mid-swat
		owner.a_intent = old_intent
		owner.changeNext_move(CLICK_CD_MELEE)
		telemetry_event("swat_mouse", list("with" = W ? "[W]" : "hands", "swings" = swings, "killed" = M.stat == DEAD))
		if(M.stat == DEAD)
			bot_log(src, "squashed [M]")
		return TRUE
	return FALSE
