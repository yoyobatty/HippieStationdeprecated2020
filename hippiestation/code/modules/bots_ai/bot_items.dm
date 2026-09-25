// /obj/item/clothing/gloves/color/yellow specifically (not its fyellow "budget" sibling
// - that one's siemens_coefficient is randomized at Initialize() and often isn't
// actually 0, so it can't be trusted to reliably stop a shock) - see
// equip_insulated_gloves() (below) for why these need to be in the same "go get this"
// machinery as the real hand tools, even though they're not a tool themselves.
#define BOT_TOOL_ITEM_ROOTS list(\
	/obj/item/crowbar,\
	/obj/item/screwdriver,\
	/obj/item/wrench,\
	/obj/item/wirecutters,\
	/obj/item/weldingtool,\
	/obj/item/multitool,\
	/obj/item/clothing/gloves/color/yellow,\
)
GLOBAL_LIST_INIT(bot_tool_items, typecacheof(BOT_TOOL_ITEM_ROOTS))
/// The root types of bot_tool_items, for bot_instances_of() searches (see bot_registry.dm).
GLOBAL_LIST_INIT(bot_tool_item_roots, BOT_TOOL_ITEM_ROOTS)

GLOBAL_LIST_INIT(bot_useful_items, typecacheof(list(
	/obj/item/card/id,
	/obj/item/pda,
	/obj/item/radio,
	/obj/item/clothing,
	/obj/item/reagent_containers/food,
	/obj/item/crowbar,
	/obj/item/screwdriver,
	/obj/item/wrench,
	/obj/item/wirecutters,
	/obj/item/weldingtool,
	/obj/item/multitool,
)))

/datum/bot_brain/proc/use_atom(atom/A)
	if(!A || QDELETED(A) || !owner.Adjacent(A))
		return FALSE
	A.attack_hand(owner)
	return TRUE

// A real player carrying a whole toolkit doesn't hold all 5 tools in two hands - they
// clip a screwdriver to their belt, drop a multitool in a pocket, etc, via
// equip_to_appropriate_slot() (mob.dm), which works directly on an item wherever it
// currently is (ground, hand, anywhere) and doesn't need it to already be held. This
// used to go through put_in_hands() first and then obj/item/proc/equip_to_best_slot()
// (inventory.dm) - but equip_to_best_slot() HARD REFUSES unless the item is already in
// the mob's ACTIVE hand specifically (`if(src != M.get_active_held_item()) return FALSE`
// at the top of it), so calling it on whichever hand put_in_hands() happened to use
// (often the inactive one) silently did nothing. With only 2 hands and no working path
// to belt/pockets/back, a bot could never actually carry more than 2 tools at once - the
// captain's-office hack alone needs 5. Try the real slot-finder FIRST (no hands needed
// at all), and only fall back to a bare hand if every worn storage slot is full too,
// same as a player who's out of pockets just holds the extra tool instead.
/datum/bot_brain/proc/stow_item(obj/item/I)
	if(!I || QDELETED(I))
		return FALSE
	if(owner.equip_to_appropriate_slot(I))
		return TRUE
	// equip_to_appropriate_slot() only WEARS an item into an empty slot - it can't put
	// one into a belt/backpack that's already being worn (mob_can_equip() refuses two
	// things fighting over the same slot). Every tool this AI cares about only declares
	// ITEM_SLOT_BELT as valid (tools.dm), so once anything at all occupies the belt
	// slot, this is the ONLY way a further tool goes anywhere but a hand - a real
	// player drops a loose tool straight into their already-worn toolbelt the same way,
	// they don't take the belt off first. COMSIG_TRY_STORAGE_INSERT (same signal
	// smart_equipbelt(), human/inventory.dm, uses for exactly this) doesn't care where
	// I currently is, so this works whether it's on the ground or already in hand.
	for(var/obj/item/storage/S in list(owner.get_item_by_slot(ITEM_SLOT_BELT), owner.get_item_by_slot(ITEM_SLOT_BACK), owner.get_item_by_slot(ITEM_SLOT_DEX_STORAGE)))
		if(S && SEND_SIGNAL(S, COMSIG_TRY_STORAGE_INSERT, I, owner))
			return TRUE
	return owner.put_in_hands(I)

// Same fix as stow_item()'s comment: equip_to_best_slot() only ever worked on the
// ACTIVE hand, so trying to free up the inactive one by "upgrading" it into a slot
// always failed and just dropped it instead. equip_to_appropriate_slot() has no such
// restriction.
/datum/bot_brain/proc/make_room_for_item()
	var/obj/item/active = owner.get_active_held_item()
	var/obj/item/inactive = owner.get_inactive_held_item()
	if(!active || !inactive)
		return
	if(owner.equip_to_appropriate_slot(inactive))
		return
	// A tool already in hand represents real progress toward whatever goal actually
	// needed it (often gathered at real cost - a whole trip, maybe a door hacked open
	// to get it) - it's worth more than whatever opportunistic item is trying to bump
	// it out to make room (this gets called from ordinary wander pickups too, e.g. a
	// welding mask noticed in passing, completely unrelated to any tool-gathering
	// goal). Leave it in hand rather than dropping it on the ground and forgetting
	// about it; the caller's own pickup just won't have anywhere to go this time,
	// which is the right trade-off - a missed opportunistic pickup costs nothing, a
	// silently-abandoned tool costs the whole trip that gathered it.
	if(is_tool_or_toolbox(inactive))
		return
	owner.dropItemToGround(inactive)

/datum/bot_brain/proc/is_useful_item(obj/item/I)
	return istype(I) && !I.anchored && is_type_in_typecache(I, GLOB.bot_useful_items) && !already_carries_matching_tool(I)

// Floor items first, then storage: an open closet's contents, or a closed closet
// itself (opened on arrival by try_open_locker(), then re-scanned next wander tick).
/datum/bot_brain/proc/find_item_goal()
	for(var/obj/item/I in oview(5, owner))
		if(isturf(I.loc) && is_useful_item(I))
			return I
	for(var/obj/structure/closet/C in oview(6, owner))
		if(QDELETED(C))
			continue
		if(C.opened)
			for(var/obj/item/I in C)
				if(is_useful_item(I))
					return I
		else
			return C
	return null

/datum/bot_brain/proc/try_pickup_target(obj/item/I)
	if(!I || QDELETED(I))
		bot_log_verbose(src, "try_pickup_target: [I] is null or deleted")
		return FALSE
	make_room_for_item()
	if(!stow_item(I))
		bot_log_verbose(src, "try_pickup_target: stow_item([I]) failed - active=[owner.get_active_held_item()], inactive=[owner.get_inactive_held_item()], dist=[get_dist(owner, I)], active_hand_index=[owner.active_hand_index], held_items=[owner.held_items], mobility_pickup=[owner.mobility_flags & MOBILITY_PICKUP], I.loc=[I.loc], I.anchored=[I.anchored], I.item_flags=[I.item_flags]")
		return FALSE
	bot_log(src, "picked up [I]")
	return TRUE

// Item-in-hand-on-atom interaction (emag, brute force, etc.) - melee_attack_chain()
// is the same engine entry point real clicks funnel through, already used by other
// non-player callers in this codebase (telekinesis, cyborgs), so this is precedented
// rather than a novel shortcut - same idea as use_atom() reusing attack_hand().
// harm = TRUE swings in HARM intent: airlocks/closets treat any non-harm click with an
// item as "open/toggle" (door/attackby(), closet/attackby()) and never damage anything,
// so a weapon swing at a door or locker in the default help intent did literally nothing.
/datum/bot_brain/proc/use_item_on(obj/item/I, atom/A, harm = FALSE)
	if(!I || QDELETED(I) || !A || QDELETED(A) || !owner.Adjacent(A))
		return FALSE
	if(owner.get_active_held_item() != I)
		free_hand_for(I)
		if(!owner.put_in_hands(I))
			return FALSE
	var/old_intent = owner.a_intent
	if(harm)
		owner.a_intent = INTENT_HARM
	I.melee_attack_chain(owner, A)
	if(harm)
		owner.a_intent = old_intent
	return TRUE

// Frees up a hand for `needed` (used right before use_item_on() has to pull something
// out of storage - a full toolkit without a toolbelt genuinely doesn't have enough
// hand+pocket+belt capacity to hold everything at once, see stow_item()'s comment) -
// real storage first via stow_item(), and ONLY if that verifiably didn't actually free
// the hand (checked directly, not by trusting stow_item()'s return - see below) does
// this set the item down on the ground as a guaranteed last resort. Different from
// make_room_for_item()'s refusal to ever drop a tool for an UNRELATED opportunistic
// pickup (bot_items.dm) - that guards against losing a tool somewhere it won't get
// recovered; here the bot is standing right at the door mid-task and will pick it back
// up (put_in_hands() doesn't care whether an item's current loc is the ground or a
// pocket) the moment the sequence needs it again.
//
// Why the verification matters: stow_item()'s own last-resort fallback is
// put_in_hands(), which for an item that's ALREADY occupying that exact hand slot with
// nowhere else to go performs a no-op drop-then-immediately-re-hold IN THE SAME HAND
// (put_in_hand(), inventory.dm, unconditionally displaces whatever's already in the
// target hand_index before placing the new item there - here that's the same item)
// and returns TRUE. Trusting that TRUE used to mean "freed" when it actually meant
// "did nothing" - exactly why a bot with a welder and multitool already filling both
// hands (no toolbelt this run) got stuck unable to ever draw the screwdriver it had
// sitting uselessly in a pocket to open a panel.
/datum/bot_brain/proc/free_hand_for(obj/item/needed)
	// A carried fire axe stays in ONE hand (unwielded, so the other hand is free) while a
	// tool is used in the other - it used to be stowed/dropped with everything else, so
	// after each door hack or refuel the axe was on the floor and the bot ran off without
	// it. A wielded axe holds both hands, so let go of the second grip first.
	var/obj/item/twohanded/fireaxe/keep_axe
	if(needed)
		for(var/obj/item/twohanded/fireaxe/F in owner.held_items)
			if(F != needed)
				keep_axe = F
				break
	if(keep_axe && keep_axe.wielded)
		keep_axe.unwield(owner, FALSE)
	var/obj/item/active = owner.get_active_held_item()
	if(active && active != needed && active != keep_axe)
		stow_item(active)
		if(owner.get_active_held_item() == active)
			bot_log(src, "setting [active] down for a moment")
			owner.dropItemToGround(active)
			LAZYADD(set_down_items, active)
	var/obj/item/inactive = owner.get_inactive_held_item()
	if(inactive && inactive != needed && inactive != keep_axe)
		stow_item(inactive)
		if(owner.get_inactive_held_item() == inactive)
			bot_log(src, "setting [inactive] down for a moment")
			owner.dropItemToGround(inactive)
			LAZYADD(set_down_items, inactive)
	// Kept axe sitting in the active hand: swap hands so the needed item lands in the
	// (now empty) active hand, like a real player switching hands.
	if(keep_axe && owner.get_active_held_item() == keep_axe && needed && !(needed in owner.held_items))
		owner.swap_hand(owner.get_inactive_hand_index())

// "Put this away when I'm done with it" version of free_hand_for()'s verified-stow
// pattern - for callers (strip_airlock_security(), try_hack_door()) that want a tool
// off their hands entirely once finished with it, not freed for one specific
// replacement. Same reasoning: stow_item() alone can report success via a no-op
// drop-then-immediately-re-hold when there's genuinely nowhere else for the item to
// go (no toolbelt, pockets already full) - verify it actually left the hand it was in,
// and set it down for real if not, rather than believing a false "it's put away."
/datum/bot_brain/proc/stow_or_drop(obj/item/I)
	if(!I || QDELETED(I))
		return
	var/held_active = (owner.get_active_held_item() == I)
	var/held_inactive = (owner.get_inactive_held_item() == I)
	if(!held_active && !held_inactive)
		return //not in a hand at all - already stowed, or already on the ground
	stow_item(I)
	if(owner.get_active_held_item() == I || owner.get_inactive_held_item() == I)
		bot_log(src, "setting [I] down for a moment")
		owner.dropItemToGround(I)
		LAZYADD(set_down_items, I)

/datum/bot_brain/proc/try_open_locker(obj/structure/closet/C)
	if(QDELETED(C))
		return
	bot_log(src, "opening [C]")
	open_closet(C)

// A click on a LOCKED locker only unlocks it (closet/attack_hand(): toggle() fails, so
// it falls through to togglelock()) - a player just clicks a second time to actually
// open it. Clicking only once left every locked-but-accessible locker (security
// lockers especially) unlocked yet still shut - failing any fetch from it, and when
// wandering (try_open_locker() above), walking off and leaving it unlocked. Returns
// whether the closet ended up open.
/datum/bot_brain/proc/open_closet(obj/structure/closet/C)
	if(C.opened)
		return TRUE
	if(!use_atom(C))
		return FALSE
	if(!C.opened && !C.locked)
		use_atom(C)
	return C.opened

// Doors open via attack_hand()'s access check, so use_atom() (a bare-hand click) is
// correct for them - but attack_hand() on most other dense structures (windows in
// particular) is flavor-only and never actually breaks them (window/attack_hand()
// just "knocks"). Those need force: a held weapon/tool via use_item_on(), or nothing
// happens - no point endlessly bare-hand-knocking something that can't be knocked down.
// A one-line "why" for whatever the bot is currently doing, meant for exactly the kind
// of moment that used to be confusing to watch live - "hacking Chief Engineer's
// wiring" reads as a bot randomly breaking into an unrelated office unless it's
// obvious that office happens to have a screwdriver the captain's-ID hack still needs.
// Reads pursuing_kind/current_goal/suspended_goal (bot_movement.dm/bot_goals.dm) rather
// than needing every call site to work this out itself.
/datum/bot_brain/proc/describe_pursuit_purpose()
	switch(pursuing_kind)
		if("goal")
			if(!current_goal)
				return "pursuing an unspecified goal"
			if(istype(current_goal, /datum/bot_goal/acquire_fireaxe))
				return suspended_goal ? "need a fire axe for [suspended_goal.type]" : "need a fire axe"
			var/datum/bot_goal/acquire_tool/AT = current_goal
			if(istype(AT) && AT.needed_tool_type)
				return suspended_goal ? "need [AT.needed_tool_type] for [suspended_goal.type]" : "need [AT.needed_tool_type]"
			if(istype(AT))
				return suspended_goal ? "fetching tools for [suspended_goal.type]" : "fetching tools"
			return "working toward [current_goal.type]"
		if("wander")
			return "just wandering"
		if("item", "locker")
			return "grabbing something useful while wandering"
		if("combat")
			return "dealing with [attacker]"
	return "no particular reason"

// True if the CURRENT pursuit is an acquire_tool goal chasing a specific tool type the
// bot already carries - most commonly because grab_passing_tools() (bot_movement.dm)
// picked one up in passing en route to the original target, independently of this
// pursuit's own machinery. Without checking this, the bot would keep committing to
// whatever it takes to reach the ORIGINAL target (hacking through a locked door,
// smashing it, all of it) for something it's already got, having no way to notice the
// trip stopped being necessary partway through.
/datum/bot_brain/proc/tool_need_already_satisfied()
	var/datum/bot_goal/acquire_tool/AT = current_goal
	return istype(AT) && AT.needed_tool_type && can_eventually_provide_tool(AT.needed_tool_type)

/datum/bot_brain/proc/clear_one_blocker(obj/O)
	// A containment field (containment_field.dm) is resistance_flags = INDESTRUCTIBLE -
	// no weapon this bot could ever carry does anything to it, so falling through to the
	// generic "smash it" branch below just swings uselessly at an unbreakable object,
	// wasting a full obstruction-check cycle (and risking whatever THAT swing itself
	// might trigger) for something that was never going to budge. This only gets hit at
	// all for a field that appeared AFTER the route was planned (bot_reachable_strict()/
	// bot_reachable_permissive(), bot_pathing_permissive.dm, already keep pre-existing
	// fields out of every route from the start) - a field generator warming up mid-walk
	// elsewhere on the SAME pursuit. Failing immediately routes through
	// handle_blocker_failure() like any other genuinely impassable obstacle, which
	// triggers a real reroute around it instead of standing there uselessly bumping it.
	if(istype(O, /obj/machinery/field))
		bot_log(src, "[O] is an active containment field - nothing I can do but go around it")
		return FALSE
	// A firelock (firedoor.dm) IS an /obj/machinery/door, so without this it fell
	// straight into the generic door branch below - which tries wire-hacking
	// (try_hack_door: pulses WIRE_BOLTS/WIRE_OPEN, airlock-specific wire constants a
	// firedoor's own wire datum doesn't act on) and, failing that, smashing it open with
	// a fire axe - neither of which is how a firedoor actually opens. The real mechanic
	// (desc = "Apply crowbar.") is try_to_crowbar(), which a real player triggers by
	// crowbar-clicking it - confirmed empirically: an engineer bot with a full toolkit
	// but no fire axe stood at a permanently-closed firelock into an intentionally
	// airless engine room "banging on it" (attack_hand()'s only effect on a firedoor)
	// forever, unable to reach 3 of 4 tesla emitters and every tesla coil/grounding rod
	// beyond it.
	var/obj/machinery/door/firedoor/F = O
	if(istype(F))
		if(!F.density)
			return TRUE
		if(F.operating)
			return FALSE
		// Welded: unweld it with a carried welder (bot_breach.dm), or - only when in real
		// danger - break it down. It used to be a flat dead end.
		if(F.welded && !try_unweld(F))
			if(destruction_allowed())
				return try_breach(F)
			return FALSE
		var/obj/item/crowbar/CB = find_or_transform_tool(/obj/item/crowbar)
		if(!CB)
			bot_log(src, "[F] is closed and I don't have a crowbar to pry it open")
			return FALSE
		bot_log(src, "prying [F] open with [CB]")
		F.try_to_crowbar(CB, owner)
		return !F.density
	var/obj/machinery/door/D = O
	if(istype(D))
		if(!D.density)
			return TRUE
		if(tool_need_already_satisfied())
			bot_log(src, "already got what I needed for this trip - no point getting through [D]")
			goal_succeeded()
			return TRUE
		// A welded door no longer has to be smashed or given up on: unweld it first (4s with a
		// carried welder, bot_breach.dm), then the normal open/hack logic below takes over.
		if(D.welded && can_unweld())
			try_unweld(D)
		if(D.locked || D.welded)
			// The door itself is rarely the actual point - it's just whatever happens
			// to be between the bot and wherever it's actually trying to get to (the
			// captain's ID, a tool it's fetching, ...), which is often NOT obvious from
			// "hacking Chief Engineer's wiring" alone. describe_pursuit_purpose() spells
			// out the reason so this reads as a deliberate step toward something, not a
			// bot randomly breaking into an unrelated office.
			if(should_smash_instead(D))
				bot_log(src, "[D] is locked - my welder's low, so I'll smash it with the axe ([describe_pursuit_purpose()])")
				if(try_smash_door(D))
					return TRUE
			bot_log(src, "[D] is locked - hacking it ([describe_pursuit_purpose()])")
			if(try_hack_door(D))
				return TRUE
			return try_smash_door(D)
		bot_log(src, "opening [O]")
		use_atom(O)
		if(!D.density)
			return TRUE
		// A closed, unbolted, unwelded airlock can still refuse to open via a plain
		// attack_hand() click - access denied (req_access, not bolted, so the
		// D.locked check above never caught it). That used to be silently treated as
		// "handled" regardless of whether it actually opened - which meant a bot with
		// no access but the tools to wire-hack the door never even tried, it just
		// stood in front of a still-closed door thinking the job was done. Fall
		// through to the same wire-hacking path a locked door gets instead - and if
		// THAT can't get through either (missing tools, or nothing to strip a
		// security-shielded door with), a strong enough weapon can just smash it open
		// instead, same as a real intruder without an electrician's patience would.
		//
		// Prying (try_pry_door(), below) is tried FIRST, ahead of both - it's the
		// cleanest option when it applies at all (no do_after on an unpowered door, no
		// destruction, no wire-hacking do_afters), so there's no reason to hack or smash
		// a door a crowbar/jaws-of-life can just pop open outright.
		if(try_pry_door(D))
			return TRUE
		if(should_smash_instead(D))
			bot_log(src, "[D] didn't open - my welder's low, so I'll just smash it with the axe ([describe_pursuit_purpose()])")
			if(try_smash_door(D))
				return TRUE
		bot_log(src, "[D] didn't open - access denied, trying to hack it ([describe_pursuit_purpose()])")
		if(try_hack_door(D))
			return TRUE
		return try_smash_door(D)
		// Climbing (tables, racks, ...) is a MouseDrop_T (drag-yourself-onto-it) mechanic,
	// not attack_hand() - call the structure's own climb proc directly rather than
	// trying to simulate the drag. But only if the bot isn't already standing on a
	// climbable structure: /obj/structure/table/Move() (and friends) explicitly lets
	// a mover step off a table tile onto ANY neighbor, dense or not, with no climb
	// needed - so once up, walking across several adjacent tables is just ordinary
	// movement. Climbing again here would be a wasted ~2s do_mob() channel per tile.
	var/obj/structure/S = O
	if(istype(S) && S.climbable)
		if(locate(/obj/structure/table) in get_turf(owner))
			return TRUE
		// Armed: smash the table instead of climbing (a climb stuns and drops everything
		// held). Falls through to climbing if the swing does nothing.
		if(istype(S, /obj/structure/table) && has_strong_weapon() && destruction_allowed()) //calm bots climb instead
			var/obj/item/smasher = owner.get_active_held_item()
			if(!smasher || smasher.force < 20)
				smasher = ready_fireaxe() || smasher
			if(smasher && smasher.force >= 20)
				var/table_integrity = S.obj_integrity
				bot_log(src, "smashing [S] out of the way with [smasher]")
				use_item_on(smasher, S, TRUE)
				if(QDELETED(S) || !S.density || S.obj_integrity < table_integrity)
					return TRUE
				bot_log(src, "[smasher] isn't doing anything to [S] - climbing instead")
		bot_log(src, "climbing over [S]")
		// climb_structure() (structures.dm) stuns the climber for S.climb_stun ticks
		// right after a successful climb - and mob/living/update_mobility() (living.dm)
		// unconditionally calls drop_all_held_items() the instant MOBILITY_USE drops
		// out from a stun, dumping anything in a HAND (not worn - belt/pocket/back
		// items are untouched) straight onto the tile just climbed onto. This is a real
		// engine mechanic (a real player fumbles what's in their hands climbing too),
		// not a bug to route around - but a bot that gathered tools only to leave them
		// behind on a table forever, having no idea it dropped anything, absolutely is
		// one. Recover once the stun (and the MOBILITY_PICKUP it clears) has actually
		// worn off - see recover_dropped_tools().
		// Remember exactly what was in hand - recover_dropped_tools() used to only look for
		// "tool-shaped" items, so a fire axe (not a tool) dropped by the climb stun was
		// simply left behind on the table.
		var/list/held_before = list()
		for(var/obj/item/H in owner.held_items)
			held_before += H
		S.climb_structure(owner)
		// Wait out the climb stun RIGHT HERE and pick everything back up before the bot
		// takes another step. This used to be a delayed timer that gave up if the bot had
		// already wandered off - and the pursuit resumed walking the instant the stun
		// ended, so the timer always found the bot gone and the dropped screwdriver and
		// multitool were simply left on the floor of the captain's office.
		sleep(S.climb_stun + 2)
		var/waited_for_grip = 0
		while(!(owner.mobility_flags & MOBILITY_PICKUP) && waited_for_grip < 30)
			sleep(2)
			waited_for_grip += 2
		recover_dropped_tools(get_turf(owner), held_before)
		return TRUE
	// Anything else physically in the way (window, grille, windoor, machine, crate...): only broken
	// when the bot is in real danger, with the weapon that gets through fastest - carried, lying
	// nearby, or in a wall cabinet. See bot_breach.dm. This used to swing whatever was in hand,
	// calm or not, even when the pairing could never finish the job.
	return try_breach(O)

// A crowbar/jaws-of-life PRIES a door open - no access check, no wire-hacking do_after,
// no destruction - the real mechanic behind a door's "Apply crowbar." desc
// (try_to_crowbar(), door.dm/airlock.dm). An UNPOWERED, unlocked, unwelded airlock opens
// for ANY crowbar almost instantly (try_to_crowbar()'s own fallback for a dead door), but
// a POWERED one only yields to a force_opens = TRUE tool specifically - jaws of life
// (/obj/item/crowbar/power, crowbar.dm), not a plain crowbar - via a ~5s forced pry that
// risks a shock if the door happens to be electrified (same risk a real player takes).
// Locked (bolted) or welded doors refuse a crowbar outright regardless of power or tool
// (try_to_crowbar() bails immediately for both, airlock.dm) - not worth even attempting.
/datum/bot_brain/proc/try_pry_door(obj/machinery/door/D)
	if(D.locked || D.welded)
		return FALSE
	var/obj/item/crowbar/CB
	if(!D.hasPower())
		CB = find_or_transform_tool(/obj/item/crowbar) //dead door - any crowbar will do
	else
		CB = find_or_transform_tool(/obj/item/crowbar/power) //live door - only jaws of life forces it
	if(!CB)
		return FALSE
	bot_log(src, "prying [D] open with [CB] ([describe_pursuit_purpose()])")
	D.try_to_crowbar(CB, owner, CB.force_opens)
	return !D.density

// Bolted/welded airlocks don't open via attack_hand() no matter what access you
// have (airlock/open(): `if(operating || welded || locked) return FALSE`) - the real
// fix is wire-hacking: screwdriver the panel open, then pulse WIRE_BOLTS to unbolt
// and WIRE_OPEN to actually open it. wires.pulse(wire, user) is the same proc the
// real wire-panel UI calls per click, so this is the real hack, not a shortcut - it
// just skips needing to know the (possibly randomized) on-screen wire color/position,
// since pulse() takes the wire constant directly. Welded doors have no wire fix.
/datum/bot_brain/proc/try_hack_door(obj/machinery/door/D)
	if(D.welded)
		bot_log(src, "[D] is welded shut - can't fix that")
		return FALSE
	if(!istype(D, /obj/machinery/door/airlock) || !D.wires)
		bot_log(src, "[D] is locked and I don't know how to hack it")
		return FALSE
	var/obj/machinery/door/airlock/A = D

	// airlock/attackby() (airlock.dm) shocks on ANY interaction with a powered airlock
	// (isElectrified() check right at the top, before any tool-specific logic even
	// runs) - a real electrician puts insulated gloves on before ever touching a live
	// panel, not after getting zapped once. Cheap and harmless if there's nothing to
	// equip or nothing to protect against (unpowered door, or gloves already on).
	equip_insulated_gloves()

	// Command/security-tier airlocks (security_level > 0, set on
	// /obj/machinery/door/airlock/command etc.) armor their wires behind layers of
	// grille/plasteel/metal shielding - the wires aren't reachable at all until that's
	// physically stripped off, in order, each layer with its own specific tool. Do that
	// first if needed; strip_airlock_security() also opens the panel with a screwdriver.
	if(A.security_level)
		if(!strip_airlock_security(A))
			return FALSE

	// find_or_transform_tool(), not find_carried_tool() directly - a screwdriver/power
	// held in its WRENCH form (wrench/power) wouldn't match a plain screwdriver-type
	// locate(), even though it's one attack_self() click away from being one (see
	// GLOB.bot_tool_transform_pairs, bot_items.dm).
	var/obj/item/screwdriver/sd = find_or_transform_tool(/obj/item/screwdriver)
	var/obj/item/multitool/mt = find_carried_tool(/obj/item/multitool)
	if(!sd || !mt)
		bot_log(src, "[A] is locked - need a screwdriver and multitool to hack it")
		return FALSE
	if(!A.panel_open)
		use_item_on(sd, A)
	if(!A.panel_open)
		bot_log(src, "couldn't get [A]'s panel open")
		return FALSE
	bot_log(src, "hacking [A]'s wiring")
	// Actually pick the multitool up and take a moment with it - the wires were pulsed
	// straight from the datum with the multitool never leaving the bot's pocket, so
	// nothing visibly happened and the door just opened.
	free_hand_for(mt)
	if(owner.get_active_held_item() != mt && !owner.put_in_hands(mt))
		bot_log(src, "couldn't get a grip on the multitool")
		return FALSE
	owner.visible_message("<span class='notice'>[owner] pulses [A]'s wires with [mt].</span>", "<span class='notice'>You pulse [A]'s wires with [mt].</span>")
	playsound(A, 'sound/items/screwdriver2.ogg', 40, TRUE)
	if(!do_after(owner, 20, target = A))
		bot_log(src, "got interrupted hacking [A]")
		return FALSE
	// WIRE_BOLTS's pulse handler (datums/wires/airlock.dm) TOGGLES the bolts - `if(!A.
	// locked) A.bolt() else A.unbolt()` - it does NOT unconditionally unbolt. Pulsing
	// it unconditionally here, on a door that was only closed because of a plain
	// access check (locked == FALSE, never actually bolted), WRONGLY engaged the
	// bolts instead - and airlock/open() (airlock.dm) refuses outright whenever
	// `locked` is true (`if(operating || welded || locked) return FALSE`), regardless
	// of the WIRE_OPEN pulse that immediately followed. That's exactly the "shows
	// locked/bolted but the bot walks through anyway" bug: the FIRST hack attempt on
	// an unbolted door accidentally bolted it and failed to open, and only the retry
	// (finding it now genuinely locked) correctly unbolted and opened it - a real
	// state, just reached by a wasted, confusing extra cycle. Only pulse it when the
	// door is ACTUALLY bolted and needs unbolting; never toggle blind.
	if(A.locked)
		A.wires.pulse(WIRE_BOLTS, owner)
	var/was_dense = A.density
	var/was_operating = A.operating
	// Open it through the door's normal open() (what a click on a door with access ends
	// up calling) instead of the WIRE_OPEN pulse handler: the pulse path left the door
	// "operating" with its icon never switched to the opening frames, so it opened with
	// no animation at all. The multitool use itself (held, visible, timed) is unchanged.
	A.open()
	bot_log_verbose(src, "opened [A] ([A.type]): before density=[was_dense] operating=[was_operating]; immediately after: density=[A.density] operating=[A.operating] icon_state=[A.icon_state]")
	// Let the airlock's own open() run its animation/sleeps before doing anything else,
	// and record what actually happened so a "pulsed but nothing visible" report can be
	// checked against real state instead of guessed at.
	sleep(2)
	bot_log_verbose(src, "after open pulse on [A]: was_dense=[was_dense] density=[A.density] operating=[A.operating] locked=[A.locked] powered=[A.hasPower()] open_wire_cut=[A.wires.is_cut(WIRE_OPEN)] emagged=[!!(A.obj_flags & EMAGGED)] icon_state=[A.icon_state]")
	var/waited = 0
	while(A.operating && waited < 20)
		sleep(1)
		waited++
	// Drop the bolts so the door stays open behind us (autoclose can't close a bolted
	// door) - a hacked door that shuts again means hacking it all over again on the way
	// back out, and pulsing WIRE_BOLTS on an OPEN, unbolted door bolts it (the handler
	// toggles).
	if(!A.density && !A.locked && A.hasPower() && !A.wires.is_cut(WIRE_BOLTS))
		bot_log(src, "dropping [A]'s bolts so it stays open")
		A.wires.pulse(WIRE_BOLTS, owner)
	// Screwdriver and multitool are done being useful here - put them away rather
	// than leaving them in hand where they'd contend with (and drop) whatever the
	// NEXT step needs, same reasoning as strip_airlock_security()'s tool handling.
	// stow_or_drop(), not stow_item() directly - see free_hand_for()'s comment for why
	// a bare stow_item() can report success without actually freeing the hand.
	stow_or_drop(sd)
	stow_or_drop(mt)
	recover_set_down_items()
	return TRUE

// A carried welder that's nearly out of fuel - stripping one shielded airlock burns
// roughly 6-8 units, and an empty welder silently blocks every shielded door after it.
/datum/bot_brain/proc/welder_needs_fuel(threshold = 12)
	var/obj/item/weldingtool/W = find_carried_tool(/obj/item/weldingtool)
	return W && W.get_fuel() < threshold

// Hack-vs-smash decision for a door that refused to open. Smashing is only possible when
// the carried weapon clears the door's damage_deflection (the wielded fire axe's 24 beats
// a plain airlock's 21 but never a reinforced one's 30), and it's preferred over the
// hack when the hack would be costly: a shielded airlock's strip burns welding fuel, so
// with the welder low it's better to just axe a smashable door than to trek to a tank.
/datum/bot_brain/proc/should_smash_instead(obj/machinery/door/D)
	if(!has_strong_weapon())
		return FALSE
	var/weapon_force = 24
	var/obj/item/held = owner.get_active_held_item()
	if(held && held.force >= 20)
		weapon_force = held.force
	if(weapon_force < D.damage_deflection)
		return FALSE
	var/obj/machinery/door/airlock/A = D
	if(!istype(A) || !A.wires)
		return TRUE //nothing to hack it with anyway
	if(A.security_level && welder_needs_fuel(12))
		return TRUE
	return FALSE

// True if the bot carries everything strip_airlock_security() needs for shielded airlocks.
// The welder must actually have fuel: a route planned through shielded doors with an
// empty welder is what sent the bot toward the fuel tank THROUGH the Bridge doors it
// couldn't strip.
// can_eventually_provide_tool() (below) for wirecutters/crowbar specifically, not
// find_carried_tool() - they're the SAME physical "jaws of life" tool (crowbar/power
// <-> wirecutters/power, see GLOB.bot_tool_transform_pairs), so the bot can never carry
// both forms at once. Requiring both PRESENT here would be checking for something
// impossible whenever the CE's actual tool is the transforming pair.
/datum/bot_brain/proc/can_strip_security()
	var/obj/item/weldingtool/W = find_carried_tool(/obj/item/weldingtool)
	return can_eventually_provide_tool(/obj/item/screwdriver) && can_eventually_provide_tool(/obj/item/wirecutters) 		&& W && W.get_fuel() >= 6 && can_eventually_provide_tool(/obj/item/crowbar)

// Items free_hand_for()/stow_or_drop() had to set on the ground because there was nowhere
// to stow them (a bulky fire axe won't fit a backpack). Nothing ever went back for them -
// the bot hacked a door with the axe set down beside it, walked off, and later stood at
// the captain's locker "holding nothing". Pick up whatever is still lying within reach.
/datum/bot_brain/proc/recover_set_down_items()
	if(!set_down_items || !set_down_items.len)
		return
	for(var/obj/item/I in set_down_items.Copy())
		if(QDELETED(I) || !isturf(I.loc))
			set_down_items -= I
			continue
		if(get_turf(owner) != I.loc && !owner.Adjacent(I))
			continue
		if(try_pickup_target(I))
			set_down_items -= I
			bot_log(src, "picked [I] back up")
	UNSETEMPTY(set_down_items)
	if(has_strong_weapon())
		ready_fireaxe()

// True if the bot is already holding something that can smash a door/locker (force>=20
// in a hand) or is carrying a fire axe it could wield.
/datum/bot_brain/proc/has_strong_weapon()
	var/obj/item/A = owner.get_active_held_item()
	var/obj/item/B = owner.get_inactive_held_item()
	if((A && A.force >= 20) || (B && B.force >= 20))
		return TRUE
	return !!find_carried_tool(/obj/item/twohanded/fireaxe)

// Gets a carried fire axe into the ACTIVE hand and two-hand wielded (force 24; unwielded
// it's only 5, useless for smashing). wield() (twohanded.dm) needs the other hand empty.
// Anything that stows/holds other tools afterwards (use_item_on() frees hands) can
// unwield it, so callers about to swing call this again rather than assuming it stuck.
// Returns the wielded axe, or null if there's none carried / it couldn't be wielded.
/datum/bot_brain/proc/ready_fireaxe()
	var/obj/item/twohanded/fireaxe/F = find_carried_tool(/obj/item/twohanded/fireaxe)
	if(!F || QDELETED(F))
		return null
	if(F.wielded && owner.get_active_held_item() == F)
		return F
	// Start from a known state: axe unwielded (releases the second grip / offhand item).
	if(F.wielded)
		F.unwield(owner, FALSE)
	// Clear everything ELSE out of the hands one item at a time with the verified
	// stow-or-set-down (stow_or_drop() tracks what it drops so it gets picked up again).
	for(var/obj/item/I in owner.held_items)
		if(I != F && !istype(I, /obj/item/twohanded/offhand))
			stow_or_drop(I)
	// Get the axe itself into a hand. put_in_hand() never clears the slot an item was
	// already equipped in (same trap as the PDA on the belt slot), so take it off first.
	if(!(F in owner.held_items))
		if(F.loc == owner)
			owner.temporarilyRemoveItemFromInventory(F, TRUE)
		if(!owner.put_in_hands(F))
			bot_log_verbose(src, "ready_fireaxe: couldn't get [F] into a hand (loc=[F.loc])")
			return null
	// It has to be in the ACTIVE hand to be swung.
	if(owner.get_active_held_item() != F)
		owner.swap_hand(owner.get_held_index_of_item(F))
	if(owner.get_inactive_held_item() && !istype(owner.get_inactive_held_item(), /obj/item/twohanded/offhand))
		stow_or_drop(owner.get_inactive_held_item())
	if(!F.wielded)
		F.wield(owner)
	if(!F.wielded)
		bot_log_verbose(src, "ready_fireaxe: couldn't wield [F] (active=[owner.get_active_held_item()], inactive=[owner.get_inactive_held_item()], arms=[owner.get_num_arms()])")
	return F.wielded ? F : null

// Last resort for a door that can't be wire-hacked through (no tools, or a
// security-shielded door the bot can't fully strip) - just smash it, the same generic
// verified-progress pattern clear_one_blocker() already uses for windows/other
// obstacles: one swing per call (naturally repeats on the next obstruction check as
// movement retries), only claims success if obj_integrity actually dropped or the door
// gave way, so a weapon that can't hurt it gets routed through handle_blocker_failure()'s
// real blacklist instead of endlessly bashing something that'll never budge. force>=20
// matches brute_force's own threshold for the captain's locker itself (attack_until_
// broken, acquire_captains_id.dm) - a fireaxe and similar are well above that.
/datum/bot_brain/proc/try_smash_door(obj/machinery/door/D)
	var/obj/item/weapon = owner.get_active_held_item() || owner.get_inactive_held_item()
	if(!weapon || weapon.force < 20)
		weapon = ready_fireaxe() || weapon
	if(!weapon || weapon.force < 20)
		bot_log(src, "nothing strong enough in hand to smash [D] (holding [weapon ? weapon : "nothing"])")
		return FALSE
	var/integrity_before = D.obj_integrity
	bot_log(src, "smashing through [D] with [weapon]")
	use_item_on(weapon, D, TRUE)
	if(QDELETED(D) || !D.density || D.obj_integrity < integrity_before)
		stuck_repeat_count = 0
		last_stuck_turf = null
		failed_blocker_count = 0
		return TRUE
	bot_log(src, "[weapon] isn't doing anything to [D]")
	return FALSE

// See clear_one_blocker()'s climb branch: a climb can drop everything held in hand
// (not worn) right onto the tile just climbed onto, via the engine's own
// stun-clears-MOBILITY_USE-clears-held-items chain. Scheduled to fire once climb_stun
// has actually worn off, so MOBILITY_PICKUP is back before trying to pick anything up.
/datum/bot_brain/proc/recover_dropped_tools(turf/where, list/held_before)
	if(!where || QDELETED(owner) || !(owner.mobility_flags & MOBILITY_PICKUP))
		return
	// Only bother if the bot is still there (or right next to it) - if it's already
	// moved on by the time this fires, whatever's on that tile isn't worth a detour;
	// on_stuck_timeout()/try_clear_obstruction() will pick up anything genuinely in the
	// way later, and find_tool_goal() will find it again during ordinary wandering.
	if(get_turf(owner) != where && !owner.Adjacent(where))
		return
	for(var/obj/item/I in where)
		if(!(I in held_before) && !is_tool_or_toolbox(I))
			continue
		if(try_pickup_target(I))
			bot_log(src, "picking [I] back up after climbing")
	// A dropped fire axe comes back unwielded (force 5) - get it back into a two-handed
	// grip so the next door/locker swing isn't wasted.
	if(has_strong_weapon())
		ready_fireaxe()

// Strips a shielded airlock's security layers in the exact order/tool a real player
// needs (code/game/machinery/doors/airlock.dm's attackby() security_level switch):
// wirecutters slice the outer grille, welder burns through each plasteel/metal layer,
// crowbar pries off each sliced layer - alternating welder/crowbar twice for the
// full PLASTEEL tier. wires.pulse() itself doesn't actually check security_level (it's
// only enforced through the UI's attempt_wire_interaction() gate), so this could be
// skipped outright - deliberately not doing that: the goal is a bot that hacks a door
// the way a real player physically would, not one that exploits an engine shortcut.
/datum/bot_brain/proc/strip_airlock_security(obj/machinery/door/airlock/A)
	var/obj/item/weldingtool/wt = find_carried_tool(/obj/item/weldingtool)
	// NOT pre-fetched fixed locals for screwdriver/crowbar/wirecutters, unlike wt above -
	// screwdriver/power and wrench/power are ALSO the same physical tool as each other
	// (just a different pair than crowbar/wirecutters), so the guard below has to ask
	// "could I produce a screwdriver" rather than "do I already have one", and the panel
	// step needs the actual transform performed right before it's used, not assumed from
	// a stale pre-fetch. crowbar/wirecutters themselves are looked up fresh inside the
	// loop instead of as fixed locals - the loop needs to actively SWITCH which form
	// it's in partway through (layers 2/4 need the crowbar head, layer 6 needs the
	// wirecutters head), and a fixed reference grabbed once up front would go stale the
	// instant the tool transforms into the other form (attack_self() qdel()s the old
	// object).
	if(!can_eventually_provide_tool(/obj/item/screwdriver) || !wt || !can_eventually_provide_tool(/obj/item/wirecutters) || !can_eventually_provide_tool(/obj/item/crowbar))
		bot_log(src, "[A]'s wiring is shielded - need a screwdriver, wirecutters, welder and crowbar to strip it")
		return FALSE
	if(!wt.get_fuel())
		bot_log(src, "[A]'s wiring is shielded - my welder is out of fuel")
		return FALSE

	if(!A.panel_open)
		use_item_on(find_or_transform_tool(/obj/item/screwdriver), A)
	if(!A.panel_open)
		bot_log(src, "couldn't get [A]'s panel open")
		return FALSE

	equip_welding_eye_protection()

	// Every TOOL_WELDER branch in attackby() (airlock.dm) gates on tool_start_check(),
	// which requires isOn() - a welder that's still switched off just silently does
	// nothing (no message, no progress, no error) when clicked, which is exactly the
	// "shielding never budges" stall this used to hit. attack_self() is the same
	// toggle a real player's click activates - switch it on once before starting, not
	// before every individual cut, same as a person would. The actual multi-second
	// "wait for it to finish" already happens for free: use_tool() (items.dm) blocks
	// on do_after() internally, so a normal synchronous call here already waits out the
	// full weld before returning - nothing extra needed for that part.
	if(!wt.isOn())
		wt.attack_self(owner)
	if(!wt.isOn())
		bot_log(src, "couldn't get [wt] lit - is it out of fuel?")
		return FALSE

	bot_log(src, "stripping [A]'s security shielding")
	bot_log_verbose(src, "strip_airlock_security: security_level=[A.security_level], panel_open=[A.panel_open], welder fuel=[wt.get_fuel()], gloves=[owner.gloves] (siemens=[owner.gloves ? "[owner.gloves:siemens_coefficient]" : "none"])")
	// airlock.dm's AIRLOCK_SECURITY_* defines are #undef'd at the end of that file (its
	// own convention for every local define), so they're not visible here - these are
	// the same values by their meaning, per that file's attackby() security_level
	// switch and its own comment table: 1=metal(welder), 2=plasteel inner sliced
	// (crowbar), 3=plasteel inner(welder), 4=plasteel outer sliced(crowbar),
	// 5=plasteel outer(welder), 6=plasteel/max security(wirecutters, then repeats
	// down through 5-1 as each layer comes off).
	var/stall_guard = 0
	while(A.security_level && stall_guard < 8)
		stall_guard++
		var/before_level = A.security_level
		var/obj/item/needed
		switch(A.security_level)
			if(1, 3, 5) // metal, or a plasteel layer with its outer slice already cut - weld it
				needed = wt
			if(2, 4) // a plasteel layer already welded through - crowbar the sliced piece off
				needed = find_or_transform_tool(/obj/item/crowbar)
			if(6) // max security - cut the outer grille first
				needed = find_or_transform_tool(/obj/item/wirecutters)
		// This sequence rotates through THREE different tools (weld, pry, cut) across
		// its steps - use_item_on() (bot_items.dm) already frees a hand for whichever
		// one this step actually needs before pulling it out, verifying the hand
		// genuinely came free (real storage, or a real ground-drop as last resort)
		// rather than trusting a stow that silently no-op'd because there was nowhere
		// to put it - see free_hand_for()'s comment for exactly what that used to break.
		use_item_on(needed, A)
		if(A.security_level == before_level)
			// airlock/attackby() (airlock.dm) can also shock on a powered-door
			// interaction (isElectrified() check right at the top, and again
			// specifically for the PLASTEEL grille cut) - a shock that lands stuns the
			// bot, and a stun clears MOBILITY_USE, dropping everything held in hand
			// (living.dm's update_mobility(), same mechanic climbing hits - see
			// recover_dropped_tools()). Insulated gloves (equip_insulated_gloves())
			// should prevent that, but this still checks for it directly rather than
			// assuming - a transient setback like that is worth a retry, not giving up
			// the whole job over one bad tick.
			if(owner.IsStun() || owner.IsKnockdown() || owner.stat != CONSCIOUS)
				bot_log(src, "got knocked around trying to strip [A]'s shielding - will try again")
			else
				bot_log(src, "couldn't strip any more of [A]'s shielding")
			if(wt.isOn())
				wt.attack_self(owner)
			// Put EVERYTHING away, not just the welder - whichever of wt/(the jaws tool,
			// in whichever of its two forms) is currently in hand from this attempt
			// would otherwise sit there and immediately contend with the next tool
			// try_hack_door()'s screwdriver/multitool step needs right after this
			// returns, same hand-contention problem this whole proc already exists to
			// avoid mid-loop. stow_or_drop() (not stow_item() directly) because a bare
			// stow_item() can report "success" without actually freeing anything - see
			// free_hand_for()'s comment for why. Only one of crowbar/wirecutters is ever
			// actually carried at a time now (see the loop above), so only one of these
			// two calls will ever find anything to do.
			stow_or_drop(wt)
			stow_or_drop(find_carried_tool(/obj/item/wirecutters))
			stow_or_drop(find_carried_tool(/obj/item/crowbar))
			return FALSE
	// Switch it back off and put everything away properly when done, same as a real
	// player would rather than walking around with a lit torch (burning fuel for no
	// reason) or a fistful of tools they're finished with - and, critically, a stowed
	// tool (belt/pocket) can't be knocked out of a hand by a LATER stun the way one
	// left sitting in hand could, and won't contend with whatever try_hack_door()'s
	// screwdriver/multitool step needs a free hand for right after this returns.
	if(wt.isOn())
		wt.attack_self(owner)
	stow_or_drop(wt)
	stow_or_drop(find_carried_tool(/obj/item/wirecutters))
	stow_or_drop(find_carried_tool(/obj/item/crowbar))
	if(A.security_level)
		bot_log(src, "giving up stripping [A]'s shielding - taking too many attempts")
		return FALSE
	bot_log(src, "[A]'s shielding is stripped")
	return TRUE

// Equips W into `slot`, displacing whatever's already there first if it isn't W itself.
// equip_to_slot_if_possible() (mob.dm) refuses outright the instant the target slot is
// occupied at all (mob_can_equip() fails) - it never unequips the incumbent, because a
// real click-driven equip always goes hand-first. Every slot this AI puts something
// into can plausibly start occupied already (default job-outfit shoes sitting in FEET
// before magboots, a starting mask, a starting glove, wear_id itself) - silently
// no-opping on ALL of those is exactly what left a bot fully "gathering" EVA gear in
// its logs while its feet stayed in plain shoes the whole time, with is_eva_ready()
// (gear_up_eva.dm) never turning true and no error anywhere to say why. Generalizes the
// one-off pattern equip_insulated_gloves() and wear_pda_in_id_slot() (below) each used
// to reinvent for their own single slot - every equip in this module should go through
// this instead of calling equip_to_slot_if_possible() directly.
/datum/bot_brain/proc/equip_displacing(obj/item/W, slot)
	var/obj/item/current = owner.get_item_by_slot(slot)
	if(current && current != W)
		owner.dropItemToGround(current)
	return owner.equip_to_slot_if_possible(W, slot, FALSE, TRUE, TRUE)

// Frees up the ID slot for the toolbelt fetch onward - not a tool itself, just good
// housekeeping a real crewmember does once, early. /obj/item/pda/GetID() returns
// whatever ID is inserted into it, and get_idcard() (human_helpers.dm) already checks
// wear_id.GetID() as one of its lookup tiers - so a PDA worn in the ID slot with a card
// inside it is already a fully-supported, transparent stand-in everywhere access gets
// checked, no special-casing needed on this AI's end. Paced across two ticks (insert,
// pause, then wear) rather than both in the same instant, matching how every other
// multi-action sequence in this file reads as a person doing one thing at a time
// instead of an instant swap.
/datum/bot_brain/proc/consolidate_id_into_pda()
	var/obj/item/card/id/id_card = owner.get_idcard(TRUE)
	if(!id_card || istype(id_card.loc, /obj/item/pda))
		return FALSE //no card carried, or already done
	var/obj/item/pda/pda = locate(/obj/item/pda) in owner
	if(!pda || pda.id)
		return FALSE //no PDA carried, or its slot's already got a card in it
	bot_log(src, "putting [id_card] into [pda] to save space")
	if(!pda.id_check(owner, id_card))
		return FALSE
	addtimer(CALLBACK(src, PROC_REF(wear_pda_in_id_slot), pda), CLICK_CD_MELEE)
	return TRUE

/datum/bot_brain/proc/wear_pda_in_id_slot(obj/item/pda/pda)
	if(QDELETED(pda) || QDELETED(owner) || !pda.id)
		return //something changed its mind in the meantime (id got pulled back out, etc)
	// The PDA can spawn already worn somewhere else entirely (a pocket, or the belt slot
	// itself depending on loadout) - equip_displacing() below only ever clears the
	// TARGET slot (ID), not wherever the item currently sits, so calling it directly on
	// an already-equipped item would leave it DOUBLE-referenced (e.g. owner.belt AND
	// owner.wear_id both pointing at the same PDA at once) - exactly the "still shows up
	// on the belt slot too" bug. Properly unequip it first unless it's already
	// free-standing in a hand or on the ground.
	if(owner.get_active_held_item() != pda && owner.get_inactive_held_item() != pda && !isturf(pda.loc))
		owner.temporarilyRemoveItemFromInventory(pda)
	// Target ITEM_SLOT_ID specifically rather than equip_to_appropriate_slot() (which
	// tries a whole priority list, and a PDA also declares ITEM_SLOT_BELT valid) - and
	// verify against wear_id directly below rather than trusting a return value, so this
	// can't silently claim success after landing on the belt instead.
	equip_displacing(pda, ITEM_SLOT_ID)
	if(owner.wear_id == pda)
		bot_log(src, "wearing [pda] in my ID slot")
	else
		bot_log(src, "couldn't get [pda] onto my ID slot (currently in [pda.loc] - wear_id is [owner.wear_id])")

// A welder flashes the user's eyes every use (weldingtool.dm's tool_start_check()) -
// a real player wears goggles/a welding mask first. Non-blocking: if the bot isn't
// carrying eye protection, it just welds unprotected rather than giving up the hack.
/datum/bot_brain/proc/equip_welding_eye_protection()
	if(owner.get_eye_protection() > 0)
		return
	var/obj/item/protection = locate(/obj/item/clothing/glasses/welding) in owner
	if(!protection)
		protection = locate(/obj/item/clothing/head/welding) in owner
	if(protection)
		bot_log(src, "putting on [protection] before welding")
		// equip_to_best_slot() (inventory.dm) only works on the mob's ACTIVE held
		// item (same restriction find_carried_tool()'s comment covers) - if these
		// goggles are sitting in a pocket rather than in-hand, that call silently did
		// nothing. equip_to_appropriate_slot() has no such requirement.
		owner.equip_to_appropriate_slot(protection)

// airlock/attackby() (airlock.dm) shocks on ANY interaction with a powered airlock
// before any tool-specific logic even runs (isElectrified() check right at the top),
// and calls it out again specifically when cutting the PLASTEEL layer's grille with
// wirecutters. electrocute_mob() (power.dm) skips the shock entirely if the wearer's
// gloves have siemens_coefficient == 0 - insulated gloves - so put a pair on before any
// hands-on interaction with a locked airlock, exactly like a real electrician would
// before ever touching a live panel. Non-blocking, same philosophy as the welding
// goggles above: if none are carried, it just risks the shock rather than giving up.
/datum/bot_brain/proc/equip_insulated_gloves()
	if(owner.gloves)
		var/obj/item/clothing/gloves/G = owner.gloves
		if(G.siemens_coefficient <= 0)
			return //already wearing something insulated
	var/obj/item/clothing/gloves/color/yellow/gloves = find_carried_tool(/obj/item/clothing/gloves/color/yellow)
	if(!gloves)
		return
	bot_log(src, "putting on [gloves] before touching live wiring")
	equip_displacing(gloves, ITEM_SLOT_GLOVES)

// `locate(type) in owner` only ever searches owner's DIRECT contents - one level. That
// was fine when a tool could only ever end up loose in a hand or worn directly, but
// stow_item() (above) now also deposits tools into a worn toolbelt/backpack via
// COMSIG_TRY_STORAGE_INSERT - one level deeper than owner's own contents - so a tool
// genuinely on the bot, just inside its toolbelt, was invisible to every "do I have X"
// check in this file, ensure_tools (acquire_captains_id.dm), and pick_reachable()
// (goals/acquire_tool.dm). That's what caused a bot to visibly pick up every missing
// tool and then immediately report them all still missing - it wasn't lying, it just
// wasn't looking inside its own belt. Checks owner directly first (the common case,
// no extra cost), then one level into any storage container on the mob.
/datum/bot_brain/proc/find_carried_tool(tool_type)
	var/obj/item/I = locate(tool_type) in owner
	if(I)
		return I
	for(var/obj/item/storage/S in owner)
		I = locate(tool_type) in S
		if(I)
			return I
	return null

// The CE's default "hand drill"/"jaws of life" tools are TRANSFORMING tools, not
// separate physical items - attack_self() on any of these four (the same proc a real
// player's click triggers) deletes it and spawns its PAIR in the user's hand instead
// (confirmed via source: screwdriver/power <-> wrench/power in screwdriver.dm/wrench.dm,
// crowbar/power <-> wirecutters/power in crowbar.dm/wirecutters.dm - each pair cycles
// back and forth). A bot carrying just a screwdriver/power already effectively carries a
// wrench too, one click away - fetching an entirely separate physical wrench while
// already holding the tool that BECOMES one is a wasted trip a real engineer wouldn't
// make.
GLOBAL_LIST_INIT(bot_tool_transform_pairs, list(
	/obj/item/screwdriver/power = /obj/item/wrench/power,
	/obj/item/wrench/power = /obj/item/screwdriver/power,
	/obj/item/crowbar/power = /obj/item/wirecutters/power,
	/obj/item/wirecutters/power = /obj/item/crowbar/power,
))

// Like find_carried_tool(), but if the bot doesn't carry `tool_type` directly, also
// checks whether it carries that type's transform-pair counterpart (see
// GLOB.bot_tool_transform_pairs above) and transforms it via attack_self() first.
/datum/bot_brain/proc/find_or_transform_tool(tool_type)
	var/obj/item/direct = find_carried_tool(tool_type)
	if(direct)
		return direct
	for(var/from_type in GLOB.bot_tool_transform_pairs)
		// ispath(), not != - every real caller passes the plain base type (/obj/item/
		// wrench), while the map's values are the specific /power subtype
		// (/obj/item/wrench/power). A bare equality check between those two never
		// matched, at all, for any caller in this codebase - confirmed in-game as a CE
		// bot stuck permanently looping on assemble_pa_part (ensure_pa_tools kept
		// concluding its hand drill "wasn't" a wrench, sent it after a separate physical
		// one that didn't exist, gave up, and immediately retried forever) and separately
		// fetching a spare wirecutters/wrench it already effectively carried. ispath(A, B)
		// is true when A is B or a SUBTYPE of B, which is what this was always meant to
		// check.
		if(!ispath(GLOB.bot_tool_transform_pairs[from_type], tool_type))
			continue
		var/obj/item/carried = find_carried_tool(from_type)
		if(!carried)
			continue
		// attack_self() spawns the new head on the FLOOR, qdel()s the old one, then
		// put_in_active_hand()s the new one - which silently fails if the active hand is
		// busy (the cable coil still held from wiring the previous PA step, say), leaving
		// the swapped tool on the ground. Confirmed in-game: the CE's hand drill landed on
		// the floor between the PA console's wiring and screwdriver steps, failing the step
		// and making the bot give up and wander off. Get the drill into a hand, with the
		// others cleared, before swapping heads - same verified pattern as use_item_on().
		if(!(carried in owner.held_items))
			free_hand_for(carried)
			if(!owner.put_in_hands(carried))
				bot_log(src, "couldn't get [carried] into a hand to switch heads")
				return null
		else if(owner.get_active_held_item() != carried)
			free_hand_for(carried)
		var/turf/drop_turf = get_turf(owner)
		bot_log(src, "transforming [carried] to switch heads")
		carried.attack_self(owner)
		// `carried` is now deleted - look the result up fresh instead of trusting it.
		var/obj/item/result = find_carried_tool(tool_type)
		if(!result)
			// Belt-and-braces: if the new head still ended up on the floor, pick it back up.
			result = locate(tool_type) in drop_turf
			if(result && owner.put_in_hands(result))
				bot_log(src, "picked the swapped [result] back up off the floor")
			else
				result = null
		return result
	return null

// A pure check, unlike find_or_transform_tool() above - never actually transforms
// anything. Used by pre-checks (ensure_pa_tools, below) that need to know "will I be
// ABLE to produce this tool later" without committing to a specific form yet - a bot
// holding just a screwdriver/power satisfies BOTH the wrench and the screwdriver
// requirement (it's the same physical tool), so a check that required both forms
// PRESENT AT ONCE would be checking for something that can never be true.
/datum/bot_brain/proc/can_eventually_provide_tool(tool_type)
	if(find_carried_tool(tool_type))
		return TRUE
	for(var/from_type in GLOB.bot_tool_transform_pairs)
		// ispath(), not == - see find_or_transform_tool()'s comment above for why a bare
		// equality never actually matched any real caller's plain base type.
		if(ispath(GLOB.bot_tool_transform_pairs[from_type], tool_type) && find_carried_tool(from_type))
			return TRUE
	return FALSE

/datum/bot_brain/proc/is_tool_or_toolbox(obj/item/I)
	return istype(I) && !I.anchored && (istype(I, /obj/item/storage/toolbox) || is_type_in_typecache(I, GLOB.bot_tool_items))

// True if I is a tool type the bot can already produce - one screwdriver is exactly as
// useful as two, so nothing should ever pick up a second. can_eventually_provide_tool(),
// not find_carried_tool(): a CE carrying the jaws of life in crowbar mode already has
// wirecutters one attack_self() away, and the hand drill covers screwdriver AND wrench -
// a plain type lookup missed that and sent the CE after loose wirecutters/wrenches it
// never needed. Wrench is included for the same reason (the drill covers it).
GLOBAL_LIST_INIT(bot_single_copy_tools, list(
	/obj/item/screwdriver,
	/obj/item/wrench,
	/obj/item/wirecutters,
	/obj/item/weldingtool,
	/obj/item/crowbar,
	/obj/item/multitool,
	/obj/item/clothing/gloves/color/yellow,
))

/datum/bot_brain/proc/already_carries_matching_tool(obj/item/I)
	for(var/tool_type in GLOB.bot_single_copy_tools)
		if(istype(I, tool_type))
			return can_eventually_provide_tool(tool_type)
	return FALSE

// Called every tile a goal-driven pursuit (move_to) advances - see bot_movement.dm's
// do_step_next_node(). Grabs a loose tool right next to the bot's path ONLY if it's a
// type the captain's-ID hack still needs and the bot doesn't already have one - this is
// deliberately narrow (not "grab anything useful," that's what ordinary wandering
// already does) so it doesn't turn every goal pursuit into a scavenger hunt, just stops
// the bot marching past the exact thing it's short on because it happened to be in a
// room it was only passing through rather than the one pre-picked target.
//
// Strictly "already adjacent, right now" - this used to also try a single bonus
// step_towards() at something merely within 2 tiles, to catch a tool just off the exact
// path. That step has NO obstruction-awareness at all (unlike every other movement in
// this codebase, which goes through try_clear_obstruction()/climbing logic) - a tool
// sitting on a table, the single most common place for one to be in a tool storage
// room, needs a climb to reach if the bot isn't already on a table, and a bare
// step_towards() just silently fails against that. Since this runs on EVERY successful
// main-path step, and the "still not adjacent" condition never resolved on its own, it
// re-issued that same doomed step_towards() call every single tick forever - the exact
// "walked into tool storage and just stood there with endless footsteps" bug. Catching
// something merely nearby properly would need the same real obstruction-clearing/climb
// handling try_clear_obstruction() already does, not a raw step - not worth the
// complexity for a passing-by nicety, so this stays limited to what's already in reach.
/datum/bot_brain/proc/grab_passing_tools()
	if(state != BOT_STATE_GOAL)
		return
	for(var/obj/item/I in oview(1, owner))
		if(!isturf(I.loc) || I.anchored || istype(I, /obj/item/storage/toolbox))
			continue //don't detour into unpacking a whole box in passing, just loose tools
		if(!owner.Adjacent(I))
			continue
		for(var/tool_type in GLOB.captains_id_required_tools)
			if(!istype(I, tool_type) || can_eventually_provide_tool(tool_type))
				continue
			if(try_pickup_target(I))
				bot_log(src, "grabbed [I] in passing")
			break

// Real security etiquette, not just a courtesy - a solid airlock left open behind a bot
// is exactly what lets an unauthorized tailgater slip through right after it without
// ever badging in themselves. Checked against the tile the bot just LEFT (passed in by
// step_next_node(), bot_movement.dm), not wherever it's standing now, so the door closes
// on an empty tile instead of the bot's own body. Not gated on BOT_STATE_GOAL like
// grab_passing_tools() above - closing up behind yourself is a habit, not just something
// that matters while busy with a specific task.
//
// A PUBLIC glass airlock is the only real exemption - you can already see whoever's
// coming through one, AND it doesn't restrict anything anyway (check_access_list(),
// access.dm: no req_access/req_one_access at all means anyone can walk through
// regardless), so there's genuinely nothing to protect there, and a bot slamming shut
// every glass door on an open public hallway on principle would just be obnoxious. A
// glass airlock that DOES require access still gets closed - being able to see through
// it doesn't stop an unauthorized tailgater from walking through it right behind the
// bot before it shuts, same as a solid one.
//
// Airlocks with cyclelinkeddir set are skipped entirely, glass or not - a cyclelinked
// pair (try_to_activate_door(), airlock.dm - see that override's own comment) already
// closes the OTHER side of the pair the instant the bot opens either one, which is
// exactly this same "don't leave the pair open" job already being done via a different,
// more precise mechanism (it knows which specific door pairs with which). Closing THIS
// door on top of that would just be redundant at best, or race the cyclelink's own
// close at worst.
//
// close() itself (airlock.dm) already refuses to shut on top of anyone still standing
// in the doorway (the safe check, same as a normal autoclose) - no need to duplicate
// that here, just let it handle the "someone's still there" case on its own.
/datum/bot_brain/proc/close_airlock_behind(turf/T)
	if(!T)
		return
	var/obj/machinery/door/airlock/A = locate() in T
	if(!istype(A) || A.density || A.operating || A.welded || A.cyclelinkeddir)
		return
	if(A.glass && !LAZYLEN(A.req_access) && !LAZYLEN(A.req_one_access))
		return //public glass airlock - the one real exemption
	A.close()

// Same shape as find_item_goal() (nearby floor items, then nearby closets), just
// filtered to tools/toolboxes and with a wider radius - this is the "already visible"
// tier of acquire_tool's priority search, see goals/acquire_tool.dm.
/datum/bot_brain/proc/find_tool_goal()
	for(var/obj/item/I in oview(9, owner))
		if(isturf(I.loc) && is_tool_or_toolbox(I) && !already_carries_matching_tool(I))
			return I
	for(var/obj/structure/closet/C in oview(9, owner))
		if(QDELETED(C))
			continue
		// A secure, locked closet needs its OWN access check to open (closets.dm),
		// separate from whatever door leads to the room it's in - no point targeting
		// one the ID card was never going to open regardless of getting there.
		if(C.secure && C.locked && !C.allowed(owner))
			continue
		// A closet's `contents` is a normal BYOND container check - it's readable by
		// code regardless of C.opened (that var only gates what a real PLAYER can see/
		// interact with, not what for(var/x in C) can enumerate) - so check what's
		// actually inside before ever committing to this as a tool source. This used
		// to just return ANY closed closet unconditionally (no way to "peek" without
		// opening it, or so it assumed), which sent the bot on a wasted round trip to
		// whatever closet happened to be nearest regardless of whether it held tools,
		// fire extinguishers, or a change of clothes.
		var/has_tool = FALSE
		for(var/obj/item/I in C)
			// istype(I, /obj/item/storage/toolbox) is deliberately NOT excluded here even
			// though a toolbox itself can't be "a duplicate" - already_carries_matching_
			// tool() only ever matches specific tool types, never toolboxes, so this stays
			// correct without extra casing.
			if(is_tool_or_toolbox(I) && !already_carries_matching_tool(I))
				has_tool = TRUE
				break
		if(!has_tool)
			continue
		if(C.opened)
			for(var/obj/item/I in C)
				if(is_tool_or_toolbox(I) && !already_carries_matching_tool(I))
					return I
		else
			return C
	return null

// Called when clear_one_blocker() had no weapon/tool to act with. While just wandering,
// this is a plain goal swap. While pursuing a real goal (e.g. hacking into the
// captain's office for the spare ID and coming up short on tools), assign_goal() would
// refuse outright (it won't stack a second goal over an active one) - so the current
// goal/strategy/step position is parked in suspended_goal instead, and end_goal()
// (bot_goals.dm) restores and resumes it once the tool-fetch finishes, whether that
// succeeded or gave up. Without this, a goal pursuit that hit a locked door it lacked
// tools for would just stall/fail right there instead of actually going to get them.
// needed_tool_type: the specific tool type the caller already knows is missing (e.g.
// ensure_tools, acquire_captains_id.dm, checks each required type itself before calling
// this) - passed straight through to acquire_tool so it can prioritize a source that
// actually has it (goals/acquire_tool.dm) instead of just "the nearest tool-shaped
// thing," which could easily be a poor-fit toolbox that "succeeds" without solving
// anything. Left null for callers with no specific type in mind (handle_blocker_failure()
// clearing a generic obstruction), which falls back to the old "grab anything useful"
// priority order.
/datum/bot_brain/proc/seek_tool_for_obstacle(needed_tool_type)
	return suspend_goal_for(new /datum/bot_goal/acquire_tool(needed_tool_type))

// Generalized version of the suspend/resume dance above - works for ANY sub-goal, not
// just acquire_tool, so the fireaxe-fetch-for-brute-force flow (ensure_weapon,
// acquire_captains_id.dm) can reuse the exact same stack-of-one suspension instead of
// duplicating it. seek_tool_for_obstacle() above is now just this with an acquire_tool
// sub-goal plugged in - every comment/behavior below applied to it unchanged before this
// refactor.
/datum/bot_brain/proc/suspend_goal_for(datum/bot_goal/sub_goal)
	if(state == BOT_STATE_WANDER)
		return assign_goal(sub_goal)

	if(state != BOT_STATE_GOAL || !current_goal || suspended_goal)
		return FALSE // already mid sub-goal, or nothing sensible to suspend

	goal_suspend_count++
	// This cap exists to stop a genuinely pathological case - the sub-goal itself
	// repeatedly failing on the exact same obstacle the outer goal is also stuck on -
	// not to budget ordinary multi-item gathering. acquire_captains_id alone can
	// legitimately need up to 6 distinct successful fetches (5 tools + a toolbelt), and
	// a real trip often nets fewer than that if a source only had part of what's
	// missing or got blacklisted after a failure - a cap of 3 was hit comfortably
	// before ever finishing a 5-tool set, aborting the whole goal despite steady real
	// progress (see the captains_id_required_tools comment in acquire_captains_id.dm).
	// Every INDIVIDUAL fetch is already bounded on its own terms (acquire_tool's own
	// on_give_up() blacklist, failed_blockers, per-pursuit stuck-timeouts), so this
	// only needs to be high enough to not fire during legitimate multi-item gathering,
	// not tight.
	if(goal_suspend_count > 15)
		bot_log(src, "given up too many times trying to get things for [current_goal.type] - giving up")
		goal_suspend_count = 0
		give_up_goal()
		return TRUE

	suspended_goal = current_goal
	suspended_strategy = current_strategy
	suspended_step_index = current_step_index
	current_goal = null
	current_strategy = null
	current_step_index = 0
	state = BOT_STATE_WANDER

	// assign_goal() can run the sub-goal to completion (or give up on it) synchronously,
	// which resumes the suspended goal and nulls suspended_goal before it returns - read
	// its name first (this was the "Cannot read null.type" exception).
	var/suspended_name = "[suspended_goal.type]"
	if(assign_goal(sub_goal))
		bot_log(src, "need something for [suspended_name] - going to fetch it")
		return TRUE

	// Couldn't even find something to go after - put things back exactly as they were.
	// Nothing was actually suspended (no sub-goal is running, there was nowhere to
	// send it), so this shouldn't cost anything from the budget above either - undo
	// the increment, or an optional fetch that simply found nothing (a toolbelt search
	// on a map with no toolbelt, say) would silently eat into the same limited budget
	// real fetches need.
	goal_suspend_count--
	current_goal = suspended_goal
	current_strategy = suspended_strategy
	current_step_index = suspended_step_index
	suspended_goal = null
	suspended_strategy = null
	suspended_step_index = 0
	state = BOT_STATE_GOAL
	return FALSE

// Getting out of a pool is also a MouseDrop_T mechanic (drag yourself onto an
// adjacent non-pool floor tile) - call it directly on any adjacent dry turf rather
// than needing a ladder specifically, so this works from anywhere in the pool.
/datum/bot_brain/proc/try_escape_pool()
	if(!owner.swimming)
		return FALSE
	for(var/d in GLOB.cardinals)
		var/turf/open/floor/F = get_step(owner, d)
		if(istype(F) && !istype(F, /turf/open/pool))
			bot_log(src, "climbing out of the pool")
			F.MouseDrop_T(owner, owner)
			return TRUE
	return FALSE

// A dense object SOMEWHERE nearby isn't necessarily in the way of anything - a
// non-fulltile ("directional") window only blocks the one direction it faces
// (window/CanPass(): `get_dir(loc, target) == dir` gates its density check), and
// more fundamentally, checking all 4 cardinal neighbors (as this used to) means a
// window on a side the bot has no intention of ever crossing still gets "found."
// The only direction that actually matters is the bot's real next path step - check
// that one specifically, via LinkBlockedWithAccess() (the same real passability check
// the pathfinder itself uses, code/__HELPERS/AStar.dm), not "is anything dense nearby."
/datum/bot_brain/proc/try_clear_obstruction()
	if(!current_path || !current_path.len)
		return FALSE
	var/turf/here = get_turf(owner)
	var/turf/T = current_path[1]
	if(!here || !T)
		return FALSE

	// Doors need checking unconditionally, before the LinkBlockedWithAccess gate below:
	// CanAStarPass() (what LinkBlockedWithAccess relies on) treats an unlocked,
	// accessible, powered airlock as "not blocked" purely because it CAN be opened -
	// that's correct for planning a route through it, but the door is still physically
	// closed and nothing else ever actually opens it. clear_one_blocker() no-ops
	// instantly if the door's already open, so this is safe to call every step.
	for(var/obj/machinery/door/D in T)
		if(D.density)
			bot_log_verbose(src, "obstruction check: door [D] @ [bot_coord(T)] is dense - clearing")
			if(!clear_one_blocker(D))
				return handle_blocker_failure(D)
			return FALSE

	// LinkBlockedWithAccess()/CanAStarPass() (what this used to check) is the
	// PATHFINDER's model of passability, not the real one - a round-trip through this
	// exact bug showed a directional window whose CanAStarPass said "not blocked" for
	// this approach direction, while the real movement engine still refused to let the
	// bot step onto the tile. real_move_blocker() calls the literal procs the movement
	// engine itself uses (CheckExit() on the departure tile's contents, CanPass() on the
	// destination tile's contents, with the same arguments Uncross()/Cross() pass them
	// in code/game/atoms_movable.dm) - so this can't diverge from what actually happens
	// when the bot tries to step there, by construction.
	var/atom/movable/blocker = real_move_blocker(here, T)
	if(!blocker)
		bot_log_verbose(src, "obstruction check: [here] -> [T] @ [bot_coord(T)] - real engine check found nothing blocking, something else stalled movement")
		return FALSE
	bot_log_verbose(src, "obstruction check: [blocker] ([blocker.type]) actually blocks [here] -> [T] @ [bot_coord(T)] - clearing")
	if(istype(blocker, /obj))
		if(!clear_one_blocker(blocker))
			return handle_blocker_failure(blocker)
		return FALSE
	bot_log_verbose(src, "obstruction check: blocker [blocker] isn't an /obj - nothing bot AI knows how to clear")
	return FALSE

// clear_one_blocker() failing doesn't necessarily mean the pursuit is doomed - it might
// just need a tool the bot doesn't have yet, which seek_tool_for_obstacle() can go
// fetch. But if the SAME object keeps failing (most often: already mid a tool-fetch
// for a DIFFERENT goal, so seek_tool_for_obstacle() correctly refuses to nest another
// one - see its comment in bot_items.dm), naive repath()-and-retry can loop
// indefinitely: repath() can legitimately produce a slightly different path each call
// even though the actual obstacle never changes (e.g. bot_reachable_permissive's
// hack/break pass "succeeding" toward the same unhackable door every time), so the
// turf-identity stuck_repeat_count in bot_movement.dm doesn't reliably catch it. This
// tracks failures against the blocking object itself instead, and ends the pursuit
// outright once it's clearly not going anywhere.
// True for the tesla engine/atmos pump checklist goals specifically - see the comment
// inside handle_blocker_failure() below for why these, and only these, skip the tool-
// fetching/fire-axe escalation on a blocked obstacle. activate_particle_accelerator and
// close_engine_shutters are deliberately NOT included here - each has exactly one real
// target (the one PA console, the one set of shutters), no interchangeable alternative
// to fall back on, so a tool-fetch detour there is still the right call same as it is
// for acquire_captains_id's one specific ID.
/datum/bot_brain/proc/is_replaceable_target_goal()
	return istype(current_goal, /datum/bot_goal/remove_singularity_generator) \
		|| istype(current_goal, /datum/bot_goal/assemble_pa_part) \
		|| istype(current_goal, /datum/bot_goal/activate_tesla_emitter) \
		|| istype(current_goal, /datum/bot_goal/wrench_tesla_coil) \
		|| istype(current_goal, /datum/bot_goal/wrench_grounding_rod) \
		|| istype(current_goal, /datum/bot_goal/activate_field_generator) \
		|| istype(current_goal, /datum/bot_goal/activate_atmos_pump)

/datum/bot_brain/proc/handle_blocker_failure(atom/blocker)
	// This used to try seek_tool_for_obstacle() FIRST, unconditionally, and only track
	// failed_blocker_count/give up once THAT also failed - but seek_tool_for_obstacle()
	// "succeeds" almost every time (the generic no-specific-type case will happily fetch
	// ANY nearby tool-shaped thing that isn't a captains_id_required_tools duplicate,
	// see acquire_tool.dm), which reset the counter back to 0 on every single attempt.
	// For an obstacle that was NEVER a tool problem to begin with (a door type
	// try_hack_door() structurally can't hack at all, say) that meant failed_blocker_
	// count could never actually reach its cap - the bot would fetch an irrelevant tool,
	// come back, fail again exactly the same way, fetch ANOTHER irrelevant tool, forever,
	// never recognizing the real problem was never about tools. Count every failure
	// against this blocker FIRST, then only spend one of the limited remaining attempts
	// on a tool-fetch detour - so a genuinely unfixable obstacle still gets blacklisted
	// within a bounded number of tries instead of looping forever.
	if(blocker == last_failed_blocker)
		failed_blocker_count++
	else
		last_failed_blocker = blocker
		failed_blocker_count = 1
	if(failed_blocker_count >= 3)
		last_path_fail_reason = "couldn't get past [blocker] after repeated attempts"
		bot_log(src, "giving up - can't get past [blocker]")
		LAZYSET(failed_blockers, blocker, world.time + rand(1800, 3600))
		last_failed_blocker = null
		failed_blocker_count = 0
		finish_pursuit(FALSE)
		return TRUE //pursuit ended - don't let the caller repath() into the same wall again

	// The tesla engine/atmos pump checklist goals each pick the NEAREST unfinished part
	// fresh every cycle (find_unanchored_grounding_rod() and friends, setup_tesla_
	// engine.dm/setup_atmospherics.dm) - there are several interchangeable targets of
	// the same kind (6 tesla coils, 7 grounding rods, ...), so a blocked door on the
	// route to ONE of them is never worth a whole tool-fetching or fire-axe side quest.
	// This goal type already has its own cooldown blacklist for exactly this
	// (failed_engine_parts/is_failed_engine_part(), on_give_up()) - giving up on just
	// THIS target (the failed_blocker_count cap above, or the plain repath failure this
	// returns to) lets the very next cycle pick a different, currently-reachable part
	// instead, same as a real engineer would skip a locked-up rod and come back to it
	// later rather than making everyone wait while they cross the station for an axe.
	// Confirmed in-game: a bot mid-grounding-rod-checklist got pulled a huge distance
	// off course fetching an axe for one locked door, eating the rest of the round, with
	// 6 other reachable rods sitting right there the whole time. The cheap stuff try_
	// pry_door()/try_hack_door()/try_smash_door() already tried with whatever's
	// currently in hand (clear_one_blocker(), above) still happens as normal either way
	// - only the FETCH escalation below is skipped for this goal category.
	if(is_replaceable_target_goal())
		return FALSE

	// Out of welding fuel is fixable at the nearest fuel tank - do that before anything
	// more drastic, and before "smash it instead".
	if(state == BOT_STATE_GOAL && istype(blocker, /obj/machinery/door) && world.time >= fuel_retry_time && welder_needs_fuel())
		fuel_retry_time = world.time + 1800
		bot_log(src, "my welder is nearly out of fuel - going to refill it")
		if(suspend_goal_for(new /datum/bot_goal/acquire_fuel()))
			return TRUE

	// A firedoor can NEVER be opened by smashing it, whatever else is true of it - its own
	// obstacle-clearing path (clear_one_blocker(), above) only ever tries crowbar-prying
	// (try_to_crowbar(), firedoor.dm's real mechanic - there's no "damage it open"
	// fallback for a firelock at all, unlike an airlock). Confirmed in-game: a bot sent
	// clear across the station to fetch a fire axe for a firedoor in its way, which then
	// did precisely nothing once it got back, since clear_one_blocker()'s firedoor branch
	// never even looks at what's in its hands besides a crowbar. Seek a crowbar instead -
	// jaws of life (crowbar/power) works exactly as well, find_or_transform_tool()
	// already accepts either form of that pair.
	// Welded shut and no usable welder: go get one (bot_breach.dm unwelds it on the way back).
	var/obj/machinery/door/welded_door = blocker
	if(istype(welded_door) && welded_door.welded && !can_unweld())
		if(seek_tool_for_obstacle(/obj/item/weldingtool))
			return TRUE

	if(istype(blocker, /obj/machinery/door/firedoor))
		if(!can_eventually_provide_tool(/obj/item/crowbar))
			if(seek_tool_for_obstacle(/obj/item/crowbar))
				return TRUE
		return FALSE

	// Only a DOOR can be a missing-tools problem, and only if a specific tool is actually
	// missing. This used to fetch "whatever useful tools" after ANY failed obstacle - so a
	// bot carrying the full kit and a fire axe, whose swing did nothing to a filing
	// cabinet in its way, turned around and walked out of the Bridge (hacking its way back
	// through) to a toolbox in Primary Tool Storage. Fetch the specific missing tool, or
	// nothing.
	//
	// Checked BEFORE the fire-axe fallback below, not after - confirmed in-game: an
	// engineer bot mid-tesla-checklist hit a locked door, was still missing a hacking
	// tool, but the fire-axe branch ran FIRST (it only checks has_strong_weapon(), not
	// whether hacking was ever actually tried with a complete kit) and sent it clear
	// across the station to Atmospherics for a fire axe cabinet - a huge detour that ate
	// the rest of the round instead of just finishing the screwdriver/wirecutters/crowbar
	// kit it was one tool short of. Smashing should be the last resort once hacking is
	// genuinely not an option (a complete kit that still can't get through - a security-
	// shielded door it can't strip, say), not the first thing tried just because nothing's
	// currently in hand.
	if(istype(blocker, /obj/machinery/door))
		var/list/kit = (state == BOT_STATE_GOAL) ? GLOB.captains_id_required_tools : list(/obj/item/screwdriver, /obj/item/multitool)
		for(var/tool_type in kit)
			if(!can_eventually_provide_tool(tool_type))
				if(seek_tool_for_obstacle(tool_type))
					return TRUE
				break

	// A door that can't be hacked (missing/depleted tools, shielding it can't strip) can
	// still be smashed with a fire axe - a real intruder would grab the one from the
	// nearest cabinet (unlocked with a multitool). Only mid-goal, only with a multitool
	// to open the cabinet, and only once per cooldown so it can't loop.
	if(state == BOT_STATE_GOAL && istype(blocker, /obj/machinery/door) && world.time >= fireaxe_retry_time 		&& !has_strong_weapon() && find_carried_tool(/obj/item/multitool))
		fireaxe_retry_time = world.time + 3000
		bot_log(src, "can't get through [blocker] - going for a fire axe to smash it")
		if(suspend_goal_for(new /datum/bot_goal/acquire_fireaxe()))
			return TRUE
	return FALSE

// Faithfully replicates what the real movement engine does when a mover steps from
// `here` to `T` (code/game/atoms_movable.dm): every movable on the departure tile gets
// Uncross() -> CheckExit(mover, T), and every movable on the destination tile gets
// Cross() -> CanPass(mover, mover.loc) (Cross() literally calls
// `CanPass(AM, AM.loc, TRUE)` - AM.loc is still `here` at that point). Returns the
// first thing that would actually refuse the move, or null if nothing would.
/datum/bot_brain/proc/real_move_blocker(turf/here, turf/T)
	if(!here || !T)
		return null
	for(var/atom/movable/AM in here)
		if(AM == owner)
			continue
		if(!AM.CheckExit(owner, T))
			return AM
	for(var/atom/movable/AM in T)
		if(AM == owner)
			continue
		if(!AM.CanPass(owner, here))
			return AM
	return null
