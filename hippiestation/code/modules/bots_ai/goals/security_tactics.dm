// Security against somebody it can't just walk up to and cuff. Officers used to do exactly that, one at a time: in the rounds with suited
// traitors they were the first to die, usually inside twelve minutes, each of them having walked into arm's reach alone with a baton.
//
// None of what beats a nanosuit needs anything new, it only needs doing the way a good team does it:
//  - Nobody goes in alone. The first officer to see them calls it in and everybody free comes (bot_dispatch_security()).
//  - It's done from range. A wearer shrugs off the first few taser hits, but seven to ten stam-crit even a suit, and that's only quick with
//    two or three shooting at once. So officers stop short, keep shooting, and step back from anybody who closes in. Cuffs go on once
//    they're down, by the arrest procedure as usual.
//  - Hurt, an officer falls back and patches up instead of dying where it stands.
//  - An EMP drops the suit for 30 seconds, so the Warden or the Head of Security fetches the armory's ion rifle, or failing that a laser.
//    Lethal force goes by Space Law's cases (bot_may_use_lethal_force()), and it stops when they're down.
//  - Against a nanosuit, gather first and go in together (the user's ruling, 2026-11-04). Short of three, an officer waits out of reach
//    and the others come to it; the crew are told to keep clear. One at a time, officers walked into a suit's reach and died one after
//    another, five or six a shift, most of them in the Brig.

/// Between one call for backup and the next from the same officer.
#define BOT_BACKUP_GAP (20 SECONDS)
/// How close an officer lets somebody dangerous get before stepping back.
#define BOT_SEC_KEEP_AWAY 3
/// How far off it stops to shoot.
#define BOT_SEC_HOLD_AT 5
/// Share of its health at which an officer stops and falls back from somebody it can't take.
#define BOT_SEC_FALL_BACK_AT 0.4
/// How long it stays out of it after falling back, for patching up.
#define BOT_SEC_FALL_BACK_TIME (45 SECONDS)
/// Before it looks in the armory again.
#define BOT_ARMORY_REST (3 MINUTES)
/// Officers together before anybody goes in on a nanosuit, and how close counts as together.
#define BOT_SEC_GROUP 3
#define BOT_SEC_GROUP_RANGE 5
/// How far off an officer waiting for the others keeps: out past a suit's jump, and where it can still see it (BOT_SIGHT_RANGE).
#define BOT_SEC_WAIT_AWAY 7
/// Between one warning to the crew to keep clear and the next, from anybody.
#define BOT_KEEP_CLEAR_GAP (60 SECONDS)

/datum/bot_brain
	var/next_dispatch_call = 0
	var/next_armory_try = 0
	/// Until when it's out of the fight, patching up.
	var/fallen_back_until = 0

/// Somebody you don't walk up to on your own: a Syndicate suit, a gun or something heavy in their hand, or blood on them already.
/proc/bot_too_dangerous(mob/living/carbon/human/S)
	if(!istype(S))
		return FALSE
	if(istype(S.wear_suit, /obj/item/clothing/suit/space/hardsuit/nano))
		return TRUE
	if(bot_held_bomb(S)) //bot_fighting.dm
		return TRUE
	if(bot_armed_and_dangerous(S))
		return TRUE
	var/datum/bot_wanted/W = bot_get_wanted_entry(S)
	return W?.severity >= BOT_CRIME_MURDER

/// In a Syndicate nanosuit.
/proc/bot_in_nanosuit(mob/M)
	var/mob/living/carbon/human/H = M
	return istype(H) && istype(H.wear_suit, /obj/item/clothing/suit/space/hardsuit/nano)

/// A Syndicate space suit or hardsuit worn: an operative, by the look of them, and a confirmed antagonist as a nanosuit is (the user's
/// ruling for the nanosuit, 2026-11-04, applied to the operatives' red suits, overnight 2026-11-10). In a nuke round (n0_nuclear) the crew
/// passed three operatives with SMGs and went about their work, and 27 of them died in 13 minutes.
/proc/bot_in_syndicate_suit(mob/M)
	var/mob/living/carbon/human/H = M
	return istype(H) && (istype(H.wear_suit, /obj/item/clothing/suit/space/hardsuit/syndi) || istype(H.wear_suit, /obj/item/clothing/suit/space/syndicate))

/// Everybody on Security who's free heads there. An officer already in a fight or walking a prisoner down stays where it is. Called by
/// somebody (`caller_mob`), it's their radio call: only if their radio's getting through (bot_radio.dm).
/proc/bot_dispatch_security(turf/T, what, mob/living/caller_mob)
	if(!T)
		return
	if(caller_mob)
		bot_radio_then(caller_mob, world.time - 30 SECONDS, CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_dispatch_security_now), T, what, caller_mob))
		return
	bot_dispatch_security_now(T, what, caller_mob)

/proc/bot_dispatch_security_now(turf/T, what, mob/living/caller_mob)
	for(var/datum/bot_brain/B as anything in GLOB.bot_security_brains)
		if(QDELETED(B.owner) || B.owner.stat != CONSCIOUS || B.owner == caller_mob || B.owner.z != T.z || B.goal_chain_pending || !B.can_drop_for_call())
			continue
		if(world.time < B.next_security_call_time || B.gym_run && get_area(B.owner) != get_area(T))
			continue
		B.next_security_call_time = world.time + BOT_BACKUP_GAP
		if(B.state == BOT_STATE_GOAL)
			B.abandon_goals_for_arrest()
		var/datum/bot_goal/respond_to_call/G = new()
		G.caller_turf = T
		G.caller_name = what
		B.assign_goal(G)
	for(var/datum/bot_silicon/borg/S in GLOB.bot_silicons) //goals/silicon.dm
		S.answer_call(T)

/datum/bot_brain/proc/call_for_backup(mob/living/carbon/human/S)
	if(bot_held_bomb(S))
		warn_of_bomber(S) //bot_fighting.dm
	if(world.time < next_dispatch_call)
		return
	next_dispatch_call = world.time + BOT_BACKUP_GAP
	if(!istype(S.wear_suit, /obj/item/clothing/suit/space/hardsuit/nano))
		bot_say(owner, ":s [pick("Need backup", "All units", "Backup needed")], [S.name], [get_area_name(S, TRUE)]. Don't go in alone.")
		bot_dispatch_security(get_turf(S), S.name, owner)
		return
	// A suit: everybody comes to this officer, not to the suit, and the crew keep out of the way. Said once between them, not by every
	// officer every twenty seconds: that was 279 lines in six shifts.
	if(world.time >= LAZYACCESS(GLOB.bot_rally_called, REF(S)))
		LAZYSET(GLOB.bot_rally_called, REF(S), world.time + 30 SECONDS)
		bot_say(owner, ":s [pick("All units", "Need backup")], [S.name] in a nanosuit, [get_area_name(S, TRUE)]. Rally on me, [get_area_name(owner, TRUE)]. Nobody goes in alone.")
	bot_dispatch_security(get_turf(owner), S.name, owner)
	if(world.time >= GLOB.bot_next_keep_clear)
		GLOB.bot_next_keep_clear = world.time + BOT_KEEP_CLEAR_GAP
		bot_say(owner, ";Everybody keep clear of [get_area_name(S, TRUE)]. [S.name]'s in a Syndicate suit and armed. Get out of there if you're in it.")
		GLOB.bot_keep_clear[get_area(S)] = world.time + 2 MINUTES
		GLOB.bot_keep_clear_for[get_area(S)] = WEAKREF(S)
		bot_note_suit_sighting(S)

/// Area -> until when Security has told the crew to keep out of it.
GLOBAL_LIST_EMPTY(bot_keep_clear)
/// Area -> who it was kept clear for, and REF(them) -> list(area, when) they were last seen in a suit by anybody
GLOBAL_LIST_EMPTY(bot_keep_clear_for)
GLOBAL_LIST_EMPTY(bot_suit_sightings)

/// Somebody in a suit seen, by anybody (bot_witness.dm look_out_for_trouble(), and when Security calls it)
/proc/bot_note_suit_sighting(mob/living/carbon/human/S)
	var/area/A = get_area(S)
	if(A)
		GLOB.bot_suit_sightings[REF(S)] = list(A, world.time)
/// REF(suspect) -> when somebody on Security can next call a rally on them.
GLOBAL_LIST_EMPTY(bot_rally_called)

/datum/bot_brain
	var/next_keep_clear_note = 0
GLOBAL_VAR_INIT(bot_next_keep_clear, 0)

/// Somewhere Security has told everybody to keep out of, just now. Not once who it was for has been seen somewhere else since, or is down
/// or cuffed: the user lay in crit in a room kept clear for a nanosuit that had moved on, and the doctor called to them wouldn't go in.
/proc/bot_told_to_keep_clear(atom/A)
	var/area/where = get_area(A)
	if(!where || GLOB.bot_keep_clear[where] <= world.time)
		return FALSE
	var/datum/weakref/ref = GLOB.bot_keep_clear_for[where]
	var/mob/living/carbon/human/S = ref?.resolve()
	if(!ref)
		return TRUE //kept clear for something else (a bomb, bot_fighting.dm)
	if(!S || S.stat == DEAD || S.handcuffed)
		return FALSE
	var/list/seen = GLOB.bot_suit_sightings[REF(S)]
	if(seen && seen[1] != where && seen[2] >= GLOB.bot_keep_clear[where] - 2 MINUTES)
		return FALSE //seen somewhere else since it was called
	return TRUE

/// Officers on their feet and fit to fight, close enough to count as together, here for this one: this bot and its colleagues.
/datum/bot_brain/proc/officers_with_me(mob/living/carbon/human/S)
	. = 1
	for(var/datum/bot_brain/B as anything in GLOB.bot_security_brains)
		if(B == src || QDELETED(B.owner) || B.owner.stat != CONSCIOUS || B.owner.z != owner.z || get_dist(B.owner, owner) > BOT_SEC_GROUP_RANGE)
			continue
		if(B.owner.health < B.owner.maxHealth * BOT_SEC_FALL_BACK_AT || world.time < B.fallen_back_until)
			continue
		if((B.state == BOT_STATE_ARREST && B.arrest_suspect == S) || istype(B.current_goal, /datum/bot_goal/respond_to_call))
			.++

/// The nearest colleague also after `S`, to wait beside.
/datum/bot_brain/proc/nearest_colleague_on(mob/living/carbon/human/S)
	var/best_dist
	for(var/datum/bot_brain/B as anything in GLOB.bot_security_brains)
		if(B == src || QDELETED(B.owner) || B.owner.stat != CONSCIOUS || B.owner.z != owner.z || B.state != BOT_STATE_ARREST || B.arrest_suspect != S)
			continue
		var/dist = get_dist(B.owner, owner)
		if(!. || dist < best_dist)
			. = B.owner
			best_dist = dist

/// In a suit, and not enough officers here yet to go in on it.
/datum/bot_brain/proc/short_of_the_others(mob/living/carbon/human/S)
	return istype(S?.wear_suit, /obj/item/clothing/suit/space/hardsuit/nano) && officers_with_me(S) < BOT_SEC_GROUP

/// How far short of somebody dangerous an officer stops: out of a suit's reach while there aren't enough of them, in shooting range
/// otherwise.
/datum/bot_brain/proc/hold_off_distance(mob/living/carbon/human/S)
	return short_of_the_others(S) || bot_held_bomb(S) ? BOT_SEC_WAIT_AWAY : BOT_SEC_HOLD_AT

/// Short of three against a suit: out of reach, nothing fired to draw it, the others called, and over to the nearest of them. TRUE while
/// it waits.
/datum/bot_brain/proc/wait_for_the_others(mob/living/carbon/human/S, dist)
	if(!short_of_the_others(S))
		return FALSE
	if(world.time >= next_waiting_note)
		next_waiting_note = world.time + 20 SECONDS
		bot_log(src, "holding back from [S]: [officers_with_me(S)] of us here, waiting for [BOT_SEC_GROUP]")
	// Out of reach is a band: it backs off when the suit really comes at it, not for every step the suit takes. Matching its distance
	// to the tile had an officer pace three tiles of the Brig corridor for sixteen minutes while a suit shuffled about the Armory.
	if(dist < BOT_SEC_WAIT_AWAY - 1)
		stop_pursuit()
		step_back_from(S)
		return TRUE
	// Over to a colleague only if standing beside them is out of reach too, or it walks in and has to back off again
	var/mob/living/carbon/human/mate = nearest_colleague_on(S)
	if(mate && get_dist(owner, mate) > 2 && get_dist(mate, S) >= BOT_SEC_WAIT_AWAY)
		if(pursuing_kind != "arrest" || pursue_target != mate)
			pursue(mate, "arrest", force = TRUE)
		return TRUE
	stop_pursuit()
	return TRUE

/datum/bot_brain
	var/next_waiting_note = 0

/// A gun's lethal setting, if it has one with the charge for it.
/datum/bot_brain/proc/ready_lethal_gun()
	for(var/obj/item/gun/energy/G in owner.GetAllContents())
		if(istype(G, /obj/item/gun/energy/ionrifle) || !G.ammo_type || !G.ammo_type.len)
			continue
		for(var/i in 1 to G.ammo_type.len)
			var/obj/item/ammo_casing/energy/shot = G.ammo_type[i]
			var/obj/item/projectile/beam = shot.projectile_type
			if(is_nonlethal_shot(shot) || (beam && (initial(beam.nodamage) || initial(beam.damage) <= 0)) || G.cell.charge < shot.e_cost)
				continue //a practice laser's beam does nothing: one was being fired at a blob, and would have been at anybody due lethal force
			var/guard = G.ammo_type.len
			while(G.select != i && guard-- > 0)
				G.select_fire(owner)
			if(G.select == i)
				return G
	return null

/// What to shoot them with. The ion rifle for a suit, whatever the law allows after that, and a taser for everything else.
/datum/bot_brain/proc/best_gun_against(mob/living/carbon/human/S)
	if(istype(S.wear_suit, /obj/item/clothing/suit/space/hardsuit/nano))
		var/obj/item/gun/energy/ionrifle/ion = find_carried_tool(/obj/item/gun/energy/ionrifle)
		if(ion?.can_shoot())
			return ion
	if(bot_may_use_lethal_force(S)) //bot_law.dm
		var/obj/item/gun/lethal = ready_lethal_gun()
		if(lethal)
			say_going_lethal(S)
			return lethal
	return ready_nonlethal_gun()

/datum/bot_brain/proc/shoot_at_range(mob/living/carbon/human/S)
	if(world.time < next_taser_time || !has_clear_shot(S))
		return FALSE
	var/obj/item/gun/G = best_gun_against(S)
	if(!G)
		return FALSE
	if(owner.get_active_held_item() != G)
		free_hand_for(G)
		if(!owner.put_in_hands(G))
			return FALSE
	var/nonlethal = FALSE
	var/obj/item/gun/energy/E = G
	if(istype(E) && E.ammo_type?.len)
		nonlethal = is_nonlethal_shot(E.ammo_type[E.select])
	owner.a_intent = nonlethal ? INTENT_HELP : INTENT_HARM
	owner.face_atom(S)
	owner.changeNext_move(CLICK_CD_RANGE)
	next_taser_time = world.time + max(CLICK_CD_RANGE, G.fire_delay) + 5
	bot_log(src, "firing [G] at [S] (dist [get_dist(owner, S)])")
	INVOKE_ASYNC(G, TYPE_PROC_REF(/obj/item/gun, afterattack), S, owner, FALSE, null)
	return TRUE

/// A step straight away from them, if the floor's there for it.
/datum/bot_brain/proc/step_back_from(atom/A)
	var/turf/T = get_step_away(owner, A)
	// Only a step that gets it further off. Backed into a corner, the step "away" the engine offers is round the obstacle and back
	// again: an officer waiting on two more for a nanosuit stepped into a nook and out of it once a second for as long as it waited,
	// and another went round the same three tiles of the Brig.
	var/turf/here = get_turf(owner)
	var/turf/them = get_turf(A)
	if(T && here && them && (T.x - them.x) ** 2 + (T.y - them.y) ** 2 <= (here.x - them.x) ** 2 + (here.y - them.y) ** 2)
		return
	if(T && !T.density && !is_blocked_turf(T, TRUE) && !bot_turf_is_deadly(T)) //not backwards into the lava
		step_towards(owner, T)

/// Hurt badly enough that it shouldn't stay on somebody dangerous, whether it can see them right now or not
/datum/bot_brain/proc/too_hurt_to_stay()
	return owner.health <= owner.maxHealth * BOT_SEC_FALL_BACK_AT

/// Hurt, and there's nothing to be gained by staying. It says so, and goes and patches up.
/datum/bot_brain/proc/fall_back_from(mob/living/carbon/human/S)
	fallen_back_until = world.time + BOT_SEC_FALL_BACK_TIME
	bot_say(owner, ":s I'm hit, falling back. [S.name], [get_area_name(S, TRUE)].")
	bot_log(src, "falling back from [S]")
	end_arrest("falling back")
	if(!try_self_heal_round())
		run_from(S, "falling back")

/// One go of the arrest loop against somebody dangerous. FALSE leaves the ordinary arrest to carry on: they're out of range, or it's got no gun.
/datum/bot_brain/proc/keep_it_at_range(mob/living/carbon/human/S, dist)
	call_for_backup(S)
	if(owner.health <= owner.maxHealth * BOT_SEC_FALL_BACK_AT)
		fall_back_from(S)
		return TRUE
	if(wait_for_the_others(S, dist))
		return TRUE
	// A tank bomb in their hands: further off, and nobody goes in on them while they're up (bot_fighting.dm)
	var/bomb = bot_held_bomb(S)
	var/hold = hold_off_distance(S)
	var/keep_away = bomb ? BOT_BOMB_KEEP_AWAY : BOT_SEC_KEEP_AWAY
	if(!find_usable_gun())
		// Nothing to shoot with. With another officer by it, or somebody being cut down in front of it, it goes in: the flash first
		// (a sword doesn't stop that), then the baton and the cuffs, the ordinary arrest. Otherwise it doesn't go in alone: it keeps
		// its distance and waits for the others to come.
		if(!bomb && should_go_in_unarmed(S))
			if(world.time >= next_going_in_note)
				next_going_in_note = world.time + 20 SECONDS
				bot_log(src, "out of shots - going in on [S] with [carried_flash() ? "the flash" : "the baton"]")
			return FALSE
		if(dist <= hold)
			stop_pursuit()
			if(dist < keep_away)
				step_back_from(S)
			return TRUE
		return FALSE
	if(!try_suit_grenade(S, dist))
		shoot_at_range(S)
	if(dist <= hold)
		stop_pursuit()
		if(dist < keep_away)
			step_back_from(S)
		return TRUE
	var/turf/spot = spot_short_of(S, hold)
	if(!spot)
		return FALSE
	// A colleague's stood on the spot already, and it's the next tile: behind them will do. Two officers a tile apart, five and six tiles from
	// a man with a toolbox wanted for attempted murder, took turns walking on to the one spot short of him and swapping the other off it, a
	// swap every couple of seconds in the Brig (bugs1112base run11).
	if(spot != get_turf(owner) && get_dist(owner, spot) <= 1)
		for(var/mob/living/carbon/human/there in spot)
			if(there.mobility_flags & MOBILITY_STAND)
				stop_pursuit()
				return TRUE
	if(pursuing_kind != "arrest" || pursue_target != spot)
		pursue(spot, "arrest", force = TRUE)
	return TRUE

/// Somewhere to stop on the way to something, or null if that's in a wall. At a run a bot covers ten tiles between one look and the next, so
/// heading for the suspect itself had it in arm's reach before it knew it.
/datum/bot_brain/proc/spot_short_of(atom/A, by = BOT_SEC_HOLD_AT)
	var/list/line = getline(owner, A)
	var/turf/spot = line[max(1, length(line) - by)]
	return !spot || spot.density || is_blocked_turf(spot, TRUE) ? null : spot

/// Whether there's a charged gun on it at all: any setting with the charge for a shot. It used to ask only the setting it was on, so a
/// hybrid taser with its taser spent (200 a shot) and charge left for its disabler (50) read as nothing to shoot with, and four
/// officers stood off from somebody cutting down the crew with an energy sword without firing once.
/datum/bot_brain/proc/find_usable_gun()
	for(var/obj/item/gun/G in owner.GetAllContents())
		if(G.can_shoot() || bot_gun_has_a_shot(G))
			return G
	return null

/// Any of an energy gun's settings with the charge for one more shot.
/proc/bot_gun_has_a_shot(obj/item/gun/G)
	var/obj/item/gun/energy/E = G
	if(!istype(E) || !E.cell || !length(E.ammo_type))
		return FALSE
	for(var/obj/item/ammo_casing/energy/shot in E.ammo_type)
		if(E.cell.charge >= shot.e_cost)
			return TRUE
	return FALSE

/// What's worth having from the armory just now, going by who's at large.
/datum/bot_brain/proc/armory_want()
	var/suited = FALSE
	var/dangerous = FALSE
	for(var/datum/weakref/ref as anything in GLOB.bot_security_wanted)
		var/mob/living/carbon/human/H = ref.resolve()
		if(!H || H.stat == DEAD || H.handcuffed || !bot_too_dangerous(H))
			continue
		dangerous = TRUE
		if(istype(H.wear_suit, /obj/item/clothing/suit/space/hardsuit/nano))
			suited = TRUE
	if(suited && !find_carried_tool(/obj/item/gun/energy/ionrifle))
		for(var/obj/item/gun/energy/ionrifle/ion as anything in bot_instances_of(/obj/item/gun/energy/ionrifle))
			if(!QDELETED(ion) && isturf(ion.loc) && ion.z == owner.z)
				return /obj/item/gun/energy/ionrifle
	// An EMP grenade drains the suit, where a map has one in the armory (Meta). Not flashbangs: the suit's headset stops a bang and its
	// helmet is a space helmet's, flash-proof (_spacesuits.dm).
	if(suited && !carried_grenade(/obj/item/grenade/empgrenade) && armory_has(/obj/item/grenade/empgrenade))
		return /obj/item/grenade/empgrenade
	if((dangerous || length(GLOB.blob_cores)) && !carries_real(/obj/item/gun/energy/laser)) //a blob takes a laser's whole burn
		return /obj/item/gun/energy/laser
	return null

/// One of these lying in the armory on this level.
/datum/bot_brain/proc/armory_has(path)
	for(var/obj/item/I as anything in bot_instances_of(path))
		if(!QDELETED(I) && isturf(I.loc) && I.z == owner.z && istype(get_area(I), /area/ai_monitored/security/armory))
			return TRUE
	return FALSE

/// An EMP grenade at somebody in a nanosuit, with the others here and none of them next to it: it drains the suit.
/datum/bot_brain/proc/try_suit_grenade(mob/living/carbon/human/S, dist)
	if(world.time < next_needle_time || dist < 3 || dist > 6 || !bot_in_nanosuit(S) || short_of_the_others(S) || !has_clear_shot(S))
		return FALSE
	var/obj/item/grenade/G = carried_grenade(/obj/item/grenade/empgrenade)
	if(!G)
		return FALSE
	for(var/mob/living/carbon/human/H in range(2, S))
		if(H != S && H.stat == CONSCIOUS && bot_means_well(H))
			return FALSE
	if(!ready_in_hand(G))
		return FALSE
	next_needle_time = world.time + 6 SECONDS
	bot_log(src, "throwing [G] at [S] (dist [dist])")
	bot_tally("grenades at a suit")
	owner.face_atom(S)
	G.attack_self(owner)
	owner.throw_item(S)
	return TRUE

/// A grenade of this kind on it, not already going: anywhere on it, a box of them in the bag included.
/datum/bot_brain/proc/carried_grenade(path)
	for(var/obj/item/grenade/G in owner.GetAllContents())
		if(istype(G, path) && !G.active)
			return G
	return null

// ---------------------------------------------------------------------------------------------
// The armory, open at red alert (the user's ruling, 2026-11-04)
// ---------------------------------------------------------------------------------------------

// At red alert with somebody in a nanosuit at large, the Warden or the Head of Security opens the armory for the officers: its lockdown
// lifted, the door opened and held, or bolted open by the AI if there is one, and the officers told on the radio to come and arm up.
// They walk in for the ion rifle, a laser, the EMP grenade, which they've no access of their own for.

GLOBAL_VAR_INIT(bot_armory_open_until, 0)
/// How long the armory stays open to Security once it's opened, and how long the Warden stands at the door.
#define BOT_ARMORY_OPEN_TIME (3 MINUTES)
#define BOT_ARMORY_HOLD_TIME (90 SECONDS)

/// A door that wants armory access.
/proc/bot_is_armory_door(obj/machinery/door/D)
	if(!istype(D))
		return FALSE
	D.gen_access()
	return (ACCESS_ARMORY in D.req_access) || (ACCESS_ARMORY in D.req_one_access)

/// Open to Security just now: the Warden or the Head of Security has opened up at red alert.
/proc/bot_armory_open_for_security()
	return world.time < GLOB.bot_armory_open_until

/// Suit-wearers Security knows of (REF) -> when they were first known of (suit_at_large()).
GLOBAL_LIST_EMPTY(bot_suit_seen_at)
/// Until when the Head of Security's or the Captain's word has the armory open, red alert or not.
GLOBAL_VAR_INIT(bot_armory_ordered_until, 0)
/// How long a suit is loose with no red alert before that word's given, and how long it stands.
#define BOT_ARMORY_ORDER_AFTER (1 MINUTES)
#define BOT_ARMORY_ORDER_TIME (5 MINUTES)

/// Red alert, or the order to open up without it: if red isn't up a minute after a suit is seen, the Head of Security or the Captain
/// orders the armory opened anyway (the user's ruling, 2026-11-04). Red alert takes two heads at two keycard devices, and in a played
/// round only one of them got there.
/proc/bot_armory_authorised()
	return GLOB.security_level >= SEC_LEVEL_RED || world.time < GLOB.bot_armory_ordered_until

/// The Warden or the Head of Security up and about, a bot, to open the armory: the Captain leaves it to them.
/proc/bot_armory_keeper_up(datum/bot_brain/asking)
	for(var/datum/bot_brain/B as anything in GLOB.bot_security_brains)
		if(B == asking || QDELETED(B.owner) || B.owner.stat != CONSCIOUS || B.owner.handcuffed || !(B.work_role() in list("Warden", "Head of Security")))
			continue
		if(asking?.gym_run && B.gym_run != asking.gym_run)
			continue
		return B
	return null

/datum/bot_duty/order_armory
	name = "ordering the armory open"
	jobs = list("Head of Security", "Captain")
	tier = BOT_DUTY_URGENT
	priority = 32
	interval_min = 50
	interval_max = 100

/datum/bot_duty/order_armory/try_start(datum/bot_brain/bot)
	if(bot_armory_authorised() || bot.owner.handcuffed || bot.state == BOT_STATE_COMBAT)
		return FALSE
	var/mob/living/carbon/human/S = bot.armory_threat() //apex/defenders.dm: a suit, or a killer at large
	if(!S || world.time < GLOB.bot_suit_seen_at[REF(S)] + (bot.is_apex() ? 0 : BOT_ARMORY_ORDER_AFTER)) //an apex head doesn't wait for red
		return FALSE
	var/datum/bot_brain/keeper = bot_armory_keeper_up(bot)
	if(bot.work_role() == "Captain" && keeper?.work_role() == "Head of Security")
		return FALSE //the Head of Security's call
	GLOB.bot_armory_ordered_until = world.time + BOT_ARMORY_ORDER_TIME
	var/suited = bot_in_nanosuit(S) || bot_in_syndicate_suit(S)
	bot_log(bot, "ordering the armory open: [S] loose[suited ? " in a suit" : ", killing people,"] and no red alert")
	bot_tally("armory ordered open")
	var/who = keeper?.work_role() == "Warden" ? "Warden, open the armory" : "Opening the armory"
	bot_say(bot.owner, ":s [S.name]'s still loose[suited ? " in that suit" : " and killing people"] and there's no red alert. [who], everybody arm up. That's an order.")
	return FALSE //the word's given: the door's the Warden's (open_armory)

/// Somebody in a nanosuit wanted and at large, this bot's business (in the Bot Gym, in its own arena).
/datum/bot_brain/proc/suit_at_large()
	for(var/datum/weakref/ref as anything in GLOB.bot_security_wanted)
		var/mob/living/carbon/human/H = ref.resolve()
		if(H && H.stat != DEAD && !H.handcuffed && (bot_in_nanosuit(H) || bot_in_syndicate_suit(H)) && (!gym_run || get_area(H) == get_area(owner)))
			if(!GLOB.bot_suit_seen_at[REF(H)])
				GLOB.bot_suit_seen_at[REF(H)] = world.time
			return H
	return null

/// The nearest armory door its ID opens and it can walk to.
/datum/bot_brain/proc/armory_door()
	var/obj/machinery/door/airlock/best
	for(var/obj/machinery/door/airlock/D as anything in bot_instances_of(/obj/machinery/door/airlock))
		if(QDELETED(D) || D.z != owner.z || !bot_is_armory_door(D) || !D.check_access(owner.get_idcard(TRUE)))
			continue
		if(gym_run && get_area(D) != get_area(owner))
			continue
		if(best && get_dist(owner, D) >= get_dist(owner, best))
			continue
		if(can_walk_lawfully_to(D))
			best = D
	return best

/datum/bot_duty/open_armory
	name = "opening the armory"
	jobs = list("Warden", "Head of Security", "Captain")
	tier = BOT_DUTY_URGENT
	priority = 31
	interval_min = 50
	interval_max = 150

/datum/bot_duty/open_armory/try_start(datum/bot_brain/bot)
	if(!bot_armory_authorised() || bot_armory_open_for_security() || !bot.armory_threat())
		return FALSE
	if(bot.work_role() == "Captain" && bot_armory_keeper_up(bot))
		return FALSE //the Warden's or the Head of Security's to open
	var/obj/machinery/door/airlock/D = bot.armory_door()
	return D ? bot.assign_goal(new /datum/bot_goal/open_armory(D)) : FALSE

/datum/bot_goal/open_armory
	lawful = TRUE
	exclusive = TRUE
	holds_for_calls = TRUE
	doing = "opening the armory"

/datum/bot_goal/open_armory/New(obj/machinery/door/airlock/D)
	. = ..()
	target = D

/datum/bot_goal/open_armory/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/hold_armory())
	return list(S)

/// At the armory door: opened, the officers told, the AI asked to bolt it, and held open till it's bolted or the time's up.
/datum/bot_step/paced/hold_armory
	max_clicks = 60
	var/until = 0

/datum/bot_step/paced/hold_armory/start(datum/bot_brain/bot)
	var/obj/machinery/door/airlock/D = bot.current_goal?.target
	if(!istype(D) || !bot.owner.Adjacent(D))
		return FALSE
	until = world.time + BOT_ARMORY_HOLD_TIME
	GLOB.bot_armory_open_until = world.time + BOT_ARMORY_OPEN_TIME
	bot_log(bot, "opening the armory for the officers")
	bot_tally("armory opened")
	bot_say(bot.owner, ":s Armory's open. Lasers, the ion rifle, the EMP grenade if there is one: get armed and get back to me.")
	if(locate(/datum/bot_silicon/ai) in GLOB.bot_silicons)
		bot_say(bot.owner, ";AI, bolt the Armory open, we're arming up.")
	return TRUE

/datum/bot_step/paced/hold_armory/do_click(datum/bot_brain/bot)
	var/obj/machinery/door/airlock/D = bot.current_goal?.target
	if(!istype(D) || QDELETED(D) || world.time > until || !bot.owner.Adjacent(D))
		return FALSE
	if(D.locked && !D.density)
		return FALSE //bolted open: done
	if(D.density && !D.operating && !D.locked && D.hasPower())
		bot.use_atom(D)
	wait_for = 20
	return TRUE

/datum/bot_step/paced/hold_armory/finish(datum/bot_brain/bot)
	return GOAL_STEP_SUCCESS

/datum/bot_duty/arm_up
	name = "getting something heavier from the armory"
	jobs = list("Warden", "Head of Security", "Security Officer")
	tier = BOT_DUTY_URGENT
	priority = 30
	interval_min = 100
	interval_max = 200

/datum/bot_duty/arm_up/try_start(datum/bot_brain/bot)
	if(world.time < bot.next_armory_try || (!length(GLOB.bot_security_wanted) && !length(GLOB.blob_cores)))
		return FALSE
	if(bot.work_role() == "Security Officer" && !bot_armory_open_for_security())
		return FALSE //no access of its own: only once the Warden or the Head of Security has opened up
	// Somebody dangerous in sight: deal with them with what it has. The Head of Security reached the Kitchen, said it was off for
	// something heavier, gave that up ten seconds later and went back to its rounds while the chemist was killed in front of it.
	if(bot.dangerous_suspect_in_sight())
		return FALSE
	var/want = bot.armory_want()
	if(!want)
		return FALSE
	bot.next_armory_try = world.time + BOT_ARMORY_REST
	var/datum/bot_goal/acquire_item_type/G = new()
	G.item_type = want
	G.lawful = TRUE
	G.holds_for_calls = TRUE
	if(!bot.assign_goal(G))
		return FALSE
	bot_say(bot.owner, ":s Getting something heavier from the armory.")
	return TRUE

#undef BOT_BACKUP_GAP
#undef BOT_SEC_KEEP_AWAY
#undef BOT_SEC_HOLD_AT
#undef BOT_SEC_FALL_BACK_AT
#undef BOT_SEC_FALL_BACK_TIME
#undef BOT_ARMORY_REST
#undef BOT_ARMORY_OPEN_TIME
#undef BOT_ARMORY_HOLD_TIME
#undef BOT_ARMORY_ORDER_AFTER
#undef BOT_ARMORY_ORDER_TIME
#undef BOT_SEC_GROUP
#undef BOT_SEC_GROUP_RANGE
#undef BOT_SEC_WAIT_AWAY
#undef BOT_KEEP_CLEAR_GAP
