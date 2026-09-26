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

#define BOT_CLICK_INTERVAL_MIN 4 //deciseconds between clicks, like a person clicking steadily
#define BOT_CLICK_INTERVAL_MAX 7
#define BOT_REACTION_MIN 1 //extra delay when turning to a different thing
#define BOT_REACTION_MAX 3

/datum/bot_brain
	var/next_click_time = 0
	/// Weak so a clicked thing that then gets destroyed (a smashed window, a squashed mouse) can still be
	/// garbage collected - only ever compared, never used.
	var/datum/weakref/last_click_target

/// Waits until a human could plausibly make the next click on `target`. Sleeps - only call from
/// code that can (goal steps, obstruction clearing, pickups), never from pathfinding checks.
/datum/bot_brain/proc/human_pause(atom/target)
	var/wait = next_click_time - world.time
	var/datum/weakref/target_ref = WEAKREF(target)
	if(target_ref != last_click_target)
		wait = max(wait, 0) + rand(BOT_REACTION_MIN, BOT_REACTION_MAX)
	if(wait > 0)
		sleep(wait)
	last_click_target = target_ref
	next_click_time = world.time + rand(BOT_CLICK_INTERVAL_MIN, BOT_CLICK_INTERVAL_MAX)

/// Gets I into the active hand, drawing it from the belt/backpack/pocket or picking it up, using a
/// free hand when there is one instead of stowing things unnecessarily. Returns TRUE on success.
/datum/bot_brain/proc/ready_in_hand(obj/item/I)
	if(!I || QDELETED(I))
		return FALSE
	if(owner.get_active_held_item() == I)
		return TRUE
	if(owner.get_inactive_held_item() == I)
		owner.swap_hand()
		return owner.get_active_held_item() == I
	if(owner.get_active_held_item() && !owner.get_inactive_held_item())
		owner.swap_hand() //the other hand is free - use it rather than putting something away
	if(owner.get_active_held_item())
		stow_item(owner.get_active_held_item())
	if(owner.get_active_held_item())
		free_hand_for(I) //last resort: the verified stow-or-set-down path
	if(!owner.put_in_active_hand(I))
		if(!owner.put_in_hands(I))
			return FALSE
		if(owner.get_active_held_item() != I)
			owner.swap_hand()
	return owner.get_active_held_item() == I

/// Puts a held item away - an equipment slot, the belt, backpack or pocket storage - never on the
/// floor and never back into a hand. Returns TRUE if it left the hands.
/datum/bot_brain/proc/put_away(obj/item/I, allow_equip = TRUE)
	if(!I || !(I in owner.held_items))
		return FALSE
	if(allow_equip && owner.equip_to_appropriate_slot(I))
		return TRUE
	for(var/obj/item/storage/S in list(owner.get_item_by_slot(ITEM_SLOT_BELT), owner.get_item_by_slot(ITEM_SLOT_BACK), owner.get_item_by_slot(ITEM_SLOT_DEX_STORAGE)))
		if(S && SEND_SIGNAL(S, COMSIG_TRY_STORAGE_INSERT, I, owner))
			return TRUE
	for(var/obj/item/storage/S in owner.held_items) //e.g. wirecutters back into the toolbox in the other hand
		if(S != I && SEND_SIGNAL(S, COMSIG_TRY_STORAGE_INSERT, I, owner))
			return TRUE
	return FALSE

/// A player's help-intent click on `target` with `tool` in hand - crowbar or jaws of life on a door
/// (door/attackby() -> try_to_crowbar()), a tank on a canister, and so on.
/datum/bot_brain/proc/use_tool_on(obj/item/tool, atom/target)
	var/old_intent = owner.a_intent
	owner.a_intent = INTENT_HELP
	. = use_item_on(tool, target)
	owner.a_intent = old_intent

/// Turns an item in hand on or off (welder, baton, extinguisher safety) the way a player does:
/// in the active hand, then use it in hand.
/datum/bot_brain/proc/toggle_in_hand(obj/item/I)
	if(!ready_in_hand(I))
		return FALSE
	human_pause(I)
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
		for(var/turf/open/T in get_adjacent_open_turfs(here))
			if(!T.density && !(locate(/obj/machinery/door) in T) && !is_blocked_turf(T, TRUE))
				step_to(owner, T)
				return
	var/list/interesting = list()
	for(var/mob/living/carbon/human/H in view(5, owner))
		if(H != owner && H.stat == CONSCIOUS)
			interesting += H
	if(!length(interesting))
		for(var/obj/machinery/door/D in view(4, owner))
			interesting += D
	if(length(interesting) && prob(70))
		owner.face_atom(pick(interesting))
	else if(prob(40))
		owner.setDir(pick(GLOB.cardinals))

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
	if(world.time < next_mouse_swat_time || owner.incapacitated() || state == BOT_STATE_COMBAT)
		return FALSE
	for(var/mob/living/simple_animal/mouse/M in range(1, owner))
		if(M.stat == DEAD || istype(M, /mob/living/simple_animal/mouse/brown/Tom) || !isturf(M.loc))
			continue
		next_mouse_swat_time = world.time + CLICK_CD_MELEE
		human_pause(M)
		if(QDELETED(M) || M.stat == DEAD || !owner.Adjacent(M))
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
		owner.a_intent = old_intent
		owner.changeNext_move(CLICK_CD_MELEE)
		telemetry_event("swat_mouse", list("with" = W ? "[W]" : "hands", "swings" = swings, "killed" = M.stat == DEAD))
		if(M.stat == DEAD)
			bot_log(src, "squashed [M]")
		return TRUE
	return FALSE
