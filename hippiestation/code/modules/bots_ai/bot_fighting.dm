// Fighting: what a bot does once a fight is on (handle_combat(), bot_brain.dm). It used to be fists and a sidestep.
//
//  - It reaches for the heaviest thing on it or within arm's reach, and a dropped weapon doesn't stay dropped.
//  - On this server a disarm is the strongest thing in a melee (a quarter of them put somebody on the floor for 4 seconds,
//    species/disarm()), so a good third of its clicks are disarms, more against somebody armed. Anybody down gets kicked:
//    kicks never miss.
//  - Out of reach, a gun if it has one, and sometimes whatever's in its hand gets thrown.
//  - Somebody with a fire axe, against bare hands, is run away from, sooner the less nerve it has.

/// Force at which something in somebody's hand is a reason to run from them.
#define BOT_FIGHT_DANGEROUS_FORCE 15

/datum/bot_brain
	/// When it next looks for something to hit with.
	var/next_weapon_reach = 0

/// How hard this hits in a bot's hands.
/proc/bot_weapon_force(obj/item/I)
	if(I.item_flags & (NOBLUDGEON|ABSTRACT) || istype(I, /obj/item/twohanded/spear/explosive)) //a lance is for a nanosuit only (goals/fight_the_suit.dm)
		return 0
	var/obj/item/twohanded/two = I //a fire axe, a spear: wielded before it's swung
	return istype(two) && two.force_wielded ? two.force_wielded : I.force

/// Gets something to hit with into its hands: from the bag, or within arm's reach. Nobody in a fight leaves a toolbox in
/// their backpack, or steps over the crowbar they just knocked out of somebody's hand.
/datum/bot_brain/proc/reach_for_weapon()
	if(world.time < next_weapon_reach)
		return
	next_weapon_reach = world.time + 4 SECONDS
	var/obj/item/melee/transforming/energy/sword/sword = find_carried_tool(/obj/item/melee/transforming/energy/sword)
	if(sword)
		if(!sword.active)
			INVOKE_ASYNC(src, PROC_REF(toggle_in_hand), sword)
		return
	var/obj/item/twohanded/in_hand = weapon_to_hand()
	if(in_hand)
		if(istype(in_hand) && in_hand.force_wielded && !in_hand.wielded) //a spear in one hand is half the weapon
			INVOKE_ASYNC(src, PROC_REF(ready_fireaxe), in_hand)
		return
	breach_kit_cache = null
	var/obj/item/best
	var/best_force = BOT_COMBAT_WEAPON_FORCE - 1
	for(var/atom/source in get_breach_kit())
		var/obj/item/I = source
		if(!istype(I) || QDELETED(I) || istype(I, /obj/item/gun))
			continue
		if(!is_carried(I) && (!isturf(I.loc) || get_dist(owner, I) > 1))
			continue
		var/force = bot_weapon_force(I)
		if(force > best_force)
			best = I
			best_force = force
	if(!best)
		return
	bot_log(src, "reaching for [best]")
	var/obj/item/twohanded/two = best
	if(istype(two) && two.force_wielded && is_carried(best))
		INVOKE_ASYNC(src, PROC_REF(ready_fireaxe), best)
	else if(is_carried(best))
		ready_in_hand(best)
	else
		INVOKE_ASYNC(src, PROC_REF(take_back), best)

/// One click at somebody within reach.
/datum/bot_brain/proc/fight_in_reach(mob/living/target)
	owner.changeNext_move(CLICK_CD_MELEE)
	owner.face_atom(target)
	var/obj/item/weapon = fights_barehanded() ? null : weapon_to_hand() //goals/robust.dm
	var/intent = pick_combat_intent(target)
	if(weapon && (intent != INTENT_DISARM || !target.get_active_held_item())) //anything in hand is swung, unless what they're holding wants knocking away
		owner.a_intent = INTENT_HARM
		telemetry_clicked(target)
		weapon.melee_attack_chain(owner, target)
		bot_log(src, "hitting [target] with [weapon]")
		return
	owner.a_intent = intent
	telemetry_clicked(target)
	owner.UnarmedAttack(target, TRUE)
	bot_log(src, "attacking [target] ([owner.a_intent])")

/// Shoves as often as blows, the way a player on this server fights. Anybody on the floor just gets the boot.
/datum/bot_brain/proc/pick_combat_intent(mob/living/target)
	if(!(target.mobility_flags & MOBILITY_STAND))
		return INTENT_HARM
	if(plays_robust()) //goals/robust.dm: 91% of the clicks of the player it's modelled on were on harm
		return prob(10) ? INTENT_DISARM : INTENT_HARM
	var/obj/item/theirs = target.get_active_held_item()
	if(theirs && prob(theirs.force >= BOT_COMBAT_WEAPON_FORCE ? 60 : 40))
		return INTENT_DISARM
	return prob(35) ? INTENT_DISARM : INTENT_HARM

/// Whether it's worth seeing this one through to the end: they've got a real weapon, they're a killer or wrecking the place,
/// it isn't a person at all, or this bot is in real trouble.
/datum/bot_brain/proc/fight_is_serious(mob/living/foe)
	if(!ishuman(foe) || owner.health < owner.maxHealth * 0.4)
		return TRUE
	var/obj/item/theirs = foe.get_active_held_item()
	if(theirs?.force >= 10)
		return TRUE
	var/datum/bot_wanted/W = bot_get_wanted_entry(foe)
	return W && W.severity >= BOT_CRIME_MAJOR

/// A scuffle between crew is over once one side has plainly lost. Two of them kicked a cook to death in a bar over a
/// quarrel, twenty seconds from the first shove: he'd been on the floor for most of it. That's for somebody out to kill.
/datum/bot_brain/proc/fight_is_won(mob/living/foe)
	if(fight_is_serious(foe) || up_to_no_good() && istype(current_goal, /datum/bot_goal/traitor_kill))
		return FALSE
	if(foe.health > foe.maxHealth * 0.6)
		return FALSE
	if(prob(50))
		bot_say(owner, pick("Stay down.", "Had enough?", "That'll teach you.", "Stay out of my way.", "Don't try that again."))
	LAZYREMOVE(grudges, WEAKREF(foe))
	trouble_until = 0
	return TRUE

/// Whether foe is holding something this bot has no answer to.
/datum/bot_brain/proc/outmatched_by(mob/living/foe)
	// Bare hands in a nanosuit, or a gun: no fair fight with a toolbox. A traitor in one killed twenty of a crew in seven minutes, every one
	// of them stood toe to toe with it, because there was nothing in its hands to be outmatched by. The brave still stay (try_run_for_it()).
	if(bot_too_dangerous(foe)) //goals/security_tactics.dm
		return TRUE
	var/obj/item/theirs = foe?.get_active_held_item()
	if(!theirs || theirs.force < BOT_FIGHT_DANGEROUS_FORCE)
		return FALSE
	var/obj/item/mine = owner.get_active_held_item()
	return !mine || mine.force * 2 <= theirs.force

/// Share of its health at which this bot stops fighting and runs: the less nerve, the sooner.
/datum/bot_brain/proc/health_to_run_at()
	if(plays_robust()) //goals/robust.dm: it goes while there's still time, and it means to come back
		return 0.5
	return BOT_COMBAT_RUN_AT + (0.5 - nerve) * 0.5

/// Hurt past where it would run from a fight of its own (try_run_for_it(), bot_brain.dm). In one it can't get out of it still fights with all
/// it has (try_suit_kit() and all), but it doesn't go looking for one: not into somebody else's, and not after a nanosuit (bot_witness.dm,
/// goals/fight_the_suit.dm).
/datum/bot_brain/proc/badly_hurt()
	return owner.health <= owner.maxHealth * health_to_run_at()

/// Lavaland's wildlife, the way a miner takes it on: the accelerator, point blank if need be, a step back while it recharges, and back
/// to the shuttle once it's going badly. Four explorers died in one shift each stood toe to toe with a watcher, one shot and then their
/// fists, from full health to dead. Without a gun it's the ordinary fight (or the ordinary run for it).
/datum/bot_brain/proc/fight_fauna(mob/living/simple_animal/hostile/asteroid/beast)
	// Back to the shuttle at half health, a miner; sooner, anybody who isn't one (an explorer out from the station), who's
	// less to fight with and less idea how. Legions, watchers and goliaths had one or two of them a batch, early on.
	if(owner.health <= owner.maxHealth * max(is_miner() ? 0.5 : 0.7, health_to_run_at()) && world.time >= next_run_for_it)
		next_run_for_it = world.time + 30 SECONDS
		bot_say(owner, pick("Nope, nope, nope.", "Too much, I'm out.", "Back to the shuttle!", ";Getting chewed up out here, heading back."))
		run_from(beast, "hurt, and [beast] is still at me")
		return TRUE
	var/obj/item/gun/energy/kinetic_accelerator/KA = find_carried_tool(/obj/item/gun/energy/kinetic_accelerator)
	if(!KA)
		return FALSE
	// Not let close: a goliath's tentacles hold whoever they come up under, and one that's next to them beats them while they're held - a
	// miner shooting one point blank was beaten to death in twenty seconds. From three tiles off, held is all it is: they're slow. A step
	// back keeps them there, and the shot comes between steps. (Running from them instead left a goliath stood in the only tunnel home,
	// and the miner behind it ran out of air.)
	if(get_dist(owner, beast) <= 2 && world.time >= next_fauna_step)
		next_fauna_step = world.time + 6
		stop_pursuit()
		var/turf/was = get_turf(owner)
		step_back_from(beast)
		if(get_turf(owner) != was)
			return TRUE
	if(try_shoot_at(beast))
		return TRUE
	return TRUE

/datum/bot_brain
	var/next_fauna_step = 0

/// Somebody out of reach and still a threat: shot if it has a gun, or sometimes pelted with what's in its hand.
/datum/bot_brain/proc/try_attack_from_range(mob/living/target)
	var/dist = get_dist(owner, target)
	if(bot_wizard && dist <= BOT_SIGHT_RANGE && (wizard_escape() || wizard_cast_at(target))) //goals/wizard.dm
		return TRUE
	if(dist < 2 || dist > BOT_SIGHT_RANGE)
		return FALSE
	if(try_shoot_at(target))
		return TRUE
	return dist <= 4 && try_throw_at(target)

/datum/bot_brain/proc/try_shoot_at(mob/living/target)
	if(world.time < next_taser_time)
		return FALSE
	var/obj/item/gun/G = find_carried_tool(/obj/item/gun)
	if(G && !G.can_shoot()) //the first one it found is empty: another that isn't
		G = null
		for(var/obj/item/gun/other in owner.GetAllContents())
			if(other.can_shoot())
				G = other
				break
	if(!G)
		return reload_a_gun()
	if(!has_clear_shot(target) || !ready_in_hand(G))
		return FALSE
	owner.a_intent = INTENT_HARM
	owner.face_atom(target)
	owner.changeNext_move(CLICK_CD_RANGE)
	next_taser_time = world.time + max(CLICK_CD_RANGE, G.fire_delay) + 5
	bot_log(src, "firing [G] at [target] (dist [get_dist(owner, target)])")
	INVOKE_ASYNC(G, TYPE_PROC_REF(/obj/item/gun, afterattack), target, owner, FALSE, null)
	return TRUE

/datum/bot_brain
	var/next_reload_time = 0

/// Out of rounds, with a magazine for the gun on it: the magazine into the other hand and onto the gun, which swaps it for the spent
/// one (a tactical reload, ballistic.dm attackby()), and the spent one goes on the floor. Nothing reloaded before: a bot fired one
/// magazine and was done with the gun, an operative's pistol included. Guns loaded a round at a time (revolvers, pump shotguns) aren't.
/datum/bot_brain/proc/reload_a_gun()
	if(world.time < next_reload_time)
		return FALSE
	var/list/carried = owner.GetAllContents()
	for(var/obj/item/gun/ballistic/G in carried)
		if(G.can_shoot() || G.internal_magazine || G.bolt_type == BOLT_TYPE_NO_BOLT)
			continue
		var/obj/item/ammo_box/magazine/fresh
		for(var/obj/item/ammo_box/magazine/M in carried)
			if(M != G.magazine && istype(M, G.mag_type) && M.ammo_count())
				fresh = M
				break
		if(!fresh)
			continue
		next_reload_time = world.time + 2 SECONDS
		if(!ready_in_hand(G))
			return FALSE
		var/obj/item/other = owner.get_inactive_held_item()
		if(other && other != fresh && !put_away(other))
			return FALSE
		if(!(fresh in owner.held_items) && !owner.put_in_inactive_hand(fresh))
			return FALSE
		owner.changeNext_move(CLICK_CD_MELEE)
		G.attackby(fresh, owner)
		for(var/obj/item/ammo_box/magazine/spent in owner.held_items)
			if(!spent.ammo_count())
				owner.dropItemToGround(spent)
		bot_log(src, "reloaded [G]: [G.can_shoot() ? "ready" : "still not firing"]")
		return TRUE
	return FALSE

/datum/bot_brain/proc/try_throw_at(mob/living/target)
	var/obj/item/I = owner.get_active_held_item()
	if(!I || I.throwforce < 10 || HAS_TRAIT(I, TRAIT_NODROP) || !prob(20 + temper * 30) || !has_clear_shot(target))
		return FALSE
	owner.face_atom(target)
	owner.changeNext_move(CLICK_CD_MELEE)
	bot_log(src, "throwing [I] at [target]")
	owner.throw_item(target)
	return TRUE

// ---------------------------------------------------------------------------------------------
// Getting away
// ---------------------------------------------------------------------------------------------

/// Off out of the way of somebody, as far off as it can think of, by the doors it can open.
/datum/bot_goal/run_from
	lawful = TRUE
	never_rests = TRUE
	doing = "getting away from somebody"
	var/datum/weakref/foe_ref

/datum/bot_goal/run_from/New(atom/foe)
	. = ..()
	foe_ref = WEAKREF(foe)

/datum/bot_goal/run_from/resolve_target(datum/bot_brain/bot)
	var/atom/foe = foe_ref?.resolve()
	// Out in air it can't breathe already (Lavaland's), anywhere else in it is no worse: "Back to the shuttle!" went nowhere, every
	// spot it thought of being open ground it couldn't breathe on unsuited, and a goliath beat an explorer to death where it stood.
	braves_bad_air = bot.in_bad_air(get_turf(bot.owner))
	// On Lavaland, back towards the outpost, not some spot on the station it's a shuttle ride from.
	if(bot.on_lavaland())
		var/obj/machinery/suit_storage_unit/mining/outpost = bot.lavaland_outpost()
		if(outpost && get_dist(outpost, bot.owner) > 3)
			target = outpost
			return
	var/best_score
	// From a live bomb, out of what it'll blow: a tank bomb takes a room and the corridors round it, and running five tiles from a
	// grenade, then wandering back past it, was no running at all.
	var/radius = bot_blast_radius(foe)
	var/turf/foe_at = get_turf(foe)
	var/near_now = foe_at ? get_dist(bot.owner, foe_at) : 0
	// Somebody can come at it, so a way that goes by them is running at them: from somebody, it keeps to its own side of them, never
	// nearer than it stands now. A bomb or a grenade on the floor can't, and the way past one is still the way out of a dead end: a
	// timid assistant who had strolled past a ticking tank bomb ran nowhere further than six tiles from it, rather than back past it.
	var/keep_off = ismob(foe) ? near_now : 0
	var/list/away_spots = list()
	if(foe)
		// Down whatever corridor gets it furthest from it, as well as the places it knows of, which may all be the wrong side of it
		// (or, in an arena, a few tiles off). Straight away from it ran into walls: from beside it on a diagonal, "away" is a wall.
		// From anybody, not only a bomb: the places it knows of can all be behind doors its ID doesn't open, and this one never is.
		var/turf/far = bot.furthest_open_floor_from(foe, radius ? radius : 12, keep_off)
		if(far)
			away_spots += far
	var/list/spots = list() //somewhere to run to -> how good a place it is
	for(var/i in 1 to ((radius ? 10 : 5) + length(away_spots)))
		var/turf/T = i <= length(away_spots) ? away_spots[i] : (bot.gym_run ? bot.pick_local_destination() : (bot.pick_poi_destination() || bot.pick_local_destination()))
		// Not into air it can't breathe from air it can: assign_goal() refuses that, and a bot that picked a breached room ran nowhere.
		// Nor on to a shut door or a machine: a spot is somewhere to stand, and the walk there ends on it or not at all.
		if(!T || is_blocked_turf(T, TRUE) || (!braves_bad_air && bot.in_bad_air(T)))
			continue
		var/away = foe_at ? get_dist(T, foe_at) : 0
		if(foe_at && away <= near_now)
			continue //no further from it than where it stands is no getting away
		spots[T] = (radius ? min(away, radius * 1.5) * 2 : away) - get_dist(T, bot.owner) / 2
	// The best of them it has a way to by its own doors, and not by way of what it's getting away from. The places it thinks of are anywhere
	// on the station, and the one furthest from whoever it is was as often as not somewhere its ID doesn't open (the Armory, Xenobiology,
	// the Captain's office): no route, the run given up the moment it began, and the bot left stood beside what it meant to get away from.
	// A third of all runs went so. The route looked at is the one the walk takes (do_repath(), bot_movement.dm: the legit pass, to the
	// spot itself).
	target = null
	var/obj/item/card/id/id_card = bot.route_card()
	var/simulated_only = !bot.can_path_through_space()
	var/no_tailgating = !bot.is_shut_in()
	bot.begin_reach_scope() //one look at what's out of reach does for all of them (bot_pathing_permissive.dm)
	while(length(spots) && !target && !QDELETED(bot.owner))
		var/turf/best = null
		for(var/turf/spot as anything in spots)
			if(!best || spots[spot] > best_score)
				best = spot
				best_score = spots[spot]
		spots -= best
		bot.pathing_no_tailgating = no_tailgating
		var/list/route = bot.bot_path_to(best, /turf/proc/Distance_cardinal, /turf/proc/bot_reachable_strict, id_card, simulated_only)
		bot.pathing_no_tailgating = FALSE
		if(!length(route) || bot.path_crosses_bad_air(route))
			bot_log_verbose(bot, "run_from: no way to [best] @ [bot_coord(best)]")
			continue
		// From somebody, a way there that goes nearer them than it stands now is running at them, to get past them to the far side.
		var/past_it = FALSE
		if(keep_off)
			for(var/turf/on_the_way as anything in route)
				if(get_dist(on_the_way, foe_at) < keep_off)
					past_it = TRUE
					break
		if(past_it)
			bot_log_verbose(bot, "run_from: the way to [best] @ [bot_coord(best)] goes by [foe]")
			continue
		target = best
	bot.end_reach_scope()
	// None of them: the furthest floor it can walk to without a door (from somebody, without going by them). The flood that found it
	// walked there, so there's a way. In the Bot Gym a saboteur stood on the tank bomb it had just set found no spot at all, and
	// stayed beside it.
	if(!target && length(away_spots) && foe_at)
		var/turf/far = away_spots[1]
		if(get_dist(far, foe_at) > near_now && (braves_bad_air || !bot.in_bad_air(far)))
			bot_log_verbose(bot, "run_from: none of the spots, so the furthest floor it can walk to, [far] @ [bot_coord(far)]")
			target = far

/datum/bot_goal/run_from/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/run_from/S = new
	S.steps = list(new /datum/bot_step/move_to())
	var/atom/foe = foe_ref?.resolve()
	if(bot_blast_radius(foe))
		S.steps += new /datum/bot_step/paced/keep_clear(foe)
	return list(S)

/// The open floor it can walk to, without a door, that's furthest from A: a flood out from where it stands, a few hundred tiles at
/// most, stopping at the first one out of reach of it. With keep_off, never by way of floor nearer A than that.
/datum/bot_brain/proc/furthest_open_floor_from(atom/A, enough, keep_off = 0)
	var/turf/start = get_turf(owner)
	var/turf/from = get_turf(A)
	if(!start || !from)
		return null
	var/list/seen = list()
	seen[start] = TRUE
	var/list/queue = list(start)
	var/at = 1
	var/turf/best
	var/best_dist = get_dist(start, from)
	while(at <= length(queue) && length(queue) < 400)
		var/turf/T = queue[at++]
		for(var/d in GLOB.cardinals)
			var/turf/next = get_step(T, d)
			if(!next || seen[next] || next.density || isspaceturf(next) || is_blocked_turf(next, TRUE))
				continue
			seen[next] = TRUE
			var/dist = get_dist(next, from)
			if(dist < keep_off)
				continue //that way's by it
			queue += next
			if(dist > best_dist)
				best = next
				best_dist = dist
				if(dist >= enough)
					return best
	return best

/// Something that's about to go off: a grenade with its pin out, a tank bomb with its timer going or on a dead man's switch.
/proc/bot_live_explosive(atom/A)
	if(QDELETED(A))
		return FALSE
	if(istype(A, /obj/item/grenade))
		var/obj/item/grenade/G = A
		return G.active
	if(istype(A, /obj/item/transfer_valve))
		var/obj/item/transfer_valve/V = A
		var/obj/item/assembly/timer/T = V.attached_device
		return (istype(T) && T.timing) || istype(V.attached_device, /obj/item/assembly/health)
	return FALSE

/// How far off to be from a bomb or a grenade being run from: 0 for anything else. Not whether it's live: the bomber log the crew hears
/// a grenade by (bot_note_bomb()) comes before the grenade's marked active, so one being primed read as a dud and nobody kept clear.
/proc/bot_blast_radius(atom/A)
	if(QDELETED(A))
		return 0
	if(ishuman(A))
		return bot_held_bomb(A) ? BOT_BOMB_RUN_FROM : 0 //somebody with one in their hands
	if(istype(A, /obj/item/transfer_valve))
		return 22
	return istype(A, /obj/item/grenade) ? 7 : 0

// ---------------------------------------------------------------------------------------------
// Somebody with a tank bomb in their hands
// ---------------------------------------------------------------------------------------------
// The user's ruling (2026-11-10): bots who see one keep away, warn the radio, and fight from range. In the user's Captain round
// (round-20.37.50) three officers piled into Chemistry on a Captain holding a tank bomb on a health sensor, and it took all three.

/// A tank bomb in their hands with both tanks on it, or null.
/proc/bot_held_bomb(mob/living/carbon/human/H)
	if(!istype(H))
		return null
	for(var/obj/item/transfer_valve/V in H.held_items)
		if(V.tank_one && V.tank_two)
			return V
	return null

/// Somebody nobody walks up to whatever they're doing: a tank bomb in their hands on a dead man's switch (a health sensor: it goes off when
/// they go down), or held by somebody Security's after. A scientist taking a test bomb to the range is neither.
/proc/bot_bomber(mob/living/carbon/human/H)
	var/obj/item/transfer_valve/V = bot_held_bomb(H)
	if(!V)
		return null
	if(istype(V.attached_device, /obj/item/assembly/health) || bot_get_wanted_entry(H) || bot_in_nanosuit(H))
		return V
	return null

/// Whether anybody at all is walking about with one: a look round a few valves, before anybody looks round the room for it.
/proc/bot_any_bomber()
	for(var/obj/item/transfer_valve/V as anything in bot_instances_of(/obj/item/transfer_valve))
		if(!QDELETED(V) && ishuman(V.loc) && bot_bomber(V.loc))
			return TRUE
	return FALSE

/// REF(holder) -> when anybody can next call them out
GLOBAL_LIST_EMPTY(bot_bomber_warned)

/// On the radio, once a minute between everybody: who has it, and where, and the crew are to keep out of there.
/datum/bot_brain/proc/warn_of_bomber(mob/living/carbon/human/H)
	if(GLOB.bot_bomber_warned[REF(H)] > world.time)
		return
	GLOB.bot_bomber_warned[REF(H)] = world.time + 1 MINUTES
	GLOB.bot_keep_clear[get_area(H)] = world.time + 2 MINUTES //goals/security_tactics.dm
	bot_log(src, "[H] has a bomb in their hands")
	bot_say(owner, ";[pick("[H.name]'s got a bomb", "Bomb! [H.name]'s holding a tank bomb", "[H.name] has a bomb in their hands")], [get_area_name(H, TRUE)]! Keep clear!")

/// A look round for anybody with one, from keep_an_eye_out() (bot_witness.dm). The crew say so and get away; Security goes to arrest
/// somebody it wants, from range (goals/security_tactics.dm keep_it_at_range()). TRUE if somebody was seen.
/datum/bot_brain/proc/look_out_for_bombers()
	if(!bot_any_bomber())
		return FALSE
	for(var/mob/living/carbon/human/H in view(BOT_SIGHT_RANGE, owner))
		if(H == owner || H.stat == DEAD || H.handcuffed || !bot_bomber(H))
			continue
		warn_of_bomber(H)
		if(is_security_job() && bot_get_wanted_entry(H) && begin_arrest(H))
			return TRUE
		if(get_dist(owner, H) < BOT_BOMB_RUN_FROM && !istype(current_goal, /datum/bot_goal/run_from))
			run_from(H, "[H.name] has a bomb")
		return TRUE
	return FALSE

/// In a fight with somebody holding a tank bomb: shot at from out of its reach if there's a gun to hand, otherwise away from them. Nobody
/// trades punches with that.
/datum/bot_brain/proc/stand_off_bomber(mob/living/carbon/human/H)
	warn_of_bomber(H)
	if(!find_usable_gun()) //goals/security_tactics.dm
		state_before_combat = null
		disengage_combat("they've got a bomb")
		run_from(H, "they've got a bomb")
		return TRUE
	var/dist = get_dist(owner, H)
	if(dist < BOT_BOMB_KEEP_AWAY)
		stop_pursuit()
		step_back_from(H)
	else if(dist > BOT_SIGHT_RANGE)
		var/turf/spot = spot_short_of(H, BOT_BOMB_KEEP_AWAY)
		if(spot)
			combat_chase(spot)
	else
		stop_pursuit()
	try_shoot_at(H)
	return TRUE

/// Out of the way of it until it's gone off or somebody's seen to it: not back past it on some errand. By the clock (do_click()): as long
/// as a fuse can run for something counting down, twenty seconds for anything else.
/datum/bot_step/paced/keep_clear
	max_clicks = 60
	var/datum/weakref/thing_ref
	var/started = 0

/datum/bot_step/paced/keep_clear/New(atom/A)
	. = ..()
	thing_ref = WEAKREF(A)

/datum/bot_step/paced/keep_clear/start(datum/bot_brain/bot)
	started = world.time
	return TRUE

/datum/bot_step/paced/keep_clear/do_click(datum/bot_brain/bot)
	var/atom/A = thing_ref?.resolve()
	if(QDELETED(A) || (!bot_live_explosive(A) && !bot_held_bomb(A) && world.time > started + 2 SECONDS)) //a moment for the pin to come out
		return FALSE
	// By the clock: a wait isn't counted as a click (next_click(), goals/tend_hydroponics.dm), so max_clicks never ended this, and a tank
	// bomb on a dead man's switch never goes off on a clock. Everybody who saw a traitor scientist carrying one stood where they'd run to
	// until the goal was failed for going quiet, three minutes at a time, with him at work four tiles off and walking past them. With
	// nothing counting down there's nothing to wait out: twenty seconds, and where they were seen is kept clear of for two minutes anyway
	// (warn_of_bomber()). A timer running is waited out: a saboteur's fuse is two minutes (sixty ticks of the timer, one every two
	// seconds, goals/sabotage_bomb.dm), so not less than that, and short of the three the goal's failed at.
	var/obj/item/transfer_valve/V = ishuman(A) ? bot_held_bomb(A) : A
	var/obj/item/assembly/timer/fuse = istype(V) ? V.attached_device : null
	var/counting_down = istype(A, /obj/item/grenade) || (istype(fuse) && fuse.timing)
	if(world.time > started + (counting_down ? 150 SECONDS : 20 SECONDS))
		return FALSE
	// And they walk about with it. Back in sight and in reach of it, here isn't out of the way: this run ends, and the next look round
	// (look_out_for_bombers()) starts another.
	if(ishuman(A) && world.time > started + 2 SECONDS && get_dist(bot.owner, A) < BOT_BOMB_RUN_FROM && (A in view(BOT_SIGHT_RANGE, bot.owner)))
		return FALSE
	wait_for = 10
	return TRUE

/datum/bot_strategy/run_from/is_feasible(datum/bot_brain/bot)
	return TRUE

/// Drops what it's doing and goes. TRUE if it's on its way.
/datum/bot_brain/proc/run_from(atom/foe, reason)
	if(state == BOT_STATE_ARREST || owner.incapacitated())
		return FALSE
	bot_log(src, "getting away from [foe] ([reason])")
	bot_tally("ran")
	state_before_combat = null
	drop_goals(reason)
	return assign_goal(new /datum/bot_goal/run_from(foe))

#undef BOT_FIGHT_DANGEROUS_FORCE
