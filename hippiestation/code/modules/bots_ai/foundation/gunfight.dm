// Gunfights at a player's pace (the user's Captain round, 2026-11-13, round-17.21.40: Security "stood there tanking hits, looking like
// brand new players", and they were "firing at them off screen").
//
//  - The pace. A bot's decisions come once a second (SSprocessing) and so did its shots: about one a second, a new player's rate, while
//    the user fired two and a half a second with a laser and an electrode gun and won every exchange. Now, once it's fired, it keeps
//    firing on them between decisions while it can see them and has a clear shot, at a click rate by skill (shot_interval()).
//  - Somebody it can't see shooting it: out in the dark, round a corner, past the edge of its sight. A laser shows where it came from, and
//    a player shot from off screen turns that way. It takes the spot the shot came from as its last sighting of them, faces it, and with a
//    gun and a line to it fires back into it; Security goes that way. Anybody else with nothing to shoot back with gets out of the line.
//    Casey Nakamura, an officer arresting the user, stood on the spot she'd last seen them and took seven laser shots in three seconds
//    from five tiles off without moving or firing, her taser in her hand.

/datum/bot_brain
	/// Who it's keeping on firing at between decisions, how ("combat", "taser", "range"), and which loop is the live one
	var/datum/weakref/firing_on
	var/firing_how
	var/fire_chain = 0
	/// The last shot that hit it: where it came from, who fired it, and when
	var/turf/shot_from
	var/datum/weakref/shot_by
	var/shot_at = 0

/// Between one shot and the next: a quick player's clicks, a steady one's, or a new one's, and never faster than the gun fires.
/datum/bot_brain/proc/shot_interval(obj/item/gun/G)
	var/pace = is_apex() ? rand(3, 5) : (skill_at_least(BOT_SKILL_MID) ? rand(4, 6) : rand(6, 10))
	return max(pace, CLICK_CD_RANGE, G?.fire_delay)

/// After a shot at `target` (try_shoot_at(), try_taser(), shoot_at_range()): it keeps at them between decisions.
/datum/bot_brain/proc/keep_firing_on(mob/living/target, how)
	if(firing_on?.resolve() == target && firing_how == how)
		return
	firing_on = WEAKREF(target)
	firing_how = how
	addtimer(CALLBACK(src, PROC_REF(fire_tick), ++fire_chain), max(1, next_taser_time - world.time))

/datum/bot_brain/proc/fire_tick(chain)
	if(QDELETED(src) || QDELETED(owner) || chain != fire_chain)
		return
	var/mob/living/target = firing_on?.resolve()
	if(!still_firing_on(target))
		firing_on = null
		firing_how = null
		return
	if(world.time >= next_taser_time && !owner.incapacitated() && !pursuing_kind_is_cover())
		switch(firing_how)
			if("combat")
				try_shoot_at(target)
			if("taser")
				try_taser(target)
			if("range")
				shoot_at_range(target)
	addtimer(CALLBACK(src, PROC_REF(fire_tick), chain), max(1, next_taser_time - world.time))

/// Whether the fight it's firing in is still on, and them in sight and in range for it.
/datum/bot_brain/proc/still_firing_on(mob/living/target)
	if(!target || QDELETED(target) || target.stat != CONSCIOUS || owner.stat != CONSCIOUS || !isturf(owner.loc))
		return FALSE
	var/dist = get_dist(owner, target)
	if(dist < 2 || dist > BOT_SIGHT_RANGE || !can_see_target(target, null, 0))
		return FALSE
	switch(firing_how)
		if("combat")
			return state == BOT_STATE_COMBAT && attacker == target
		if("taser")
			return state == BOT_STATE_ARREST && arrest_suspect == target && !arrest_busy && !is_subdued(target) && dist <= 6 && (arrest_severity >= BOT_CRIME_MAJOR || arrest_resisted)
		if("range")
			return state == BOT_STATE_ARREST && arrest_suspect == target && !arrest_busy && !is_subdued(target) && bot_too_dangerous(target)
	return FALSE

/// Off into cover (mind_the_gun(), threat_read.dm): not stood still firing.
/datum/bot_brain/proc/pursuing_kind_is_cover()
	return cover_spot && world.time < cover_until && get_turf(owner) != cover_spot

// ---------------------------------------------------------------------------------------------
// Shot from somewhere it can't see
// ---------------------------------------------------------------------------------------------

/// From on_attacked() (bot_brain.dm): a shot that hit it.
/datum/bot_brain/proc/note_shot(mob/living/user, atom/object)
	var/obj/item/projectile/P = object
	if(!istype(P) || !user)
		return
	shot_from = P.starting || get_turf(user)
	shot_by = WEAKREF(user)
	shot_at = world.time
	addtimer(CALLBACK(src, PROC_REF(react_to_shot), user), reaction_delay() + 2) //a turn of the head, not the next decision a second on

/// A moment after the shot: back at it, if it's fighting or arresting them and can't see them.
/datum/bot_brain/proc/react_to_shot(mob/living/user)
	if(QDELETED(src) || QDELETED(owner) || owner.stat != CONSCIOUS || QDELETED(user))
		return
	var/fighting = (state == BOT_STATE_COMBAT && attacker == user) || (state == BOT_STATE_ARREST && arrest_suspect == user && !arrest_busy)
	if(!fighting || can_see_target(user, null, 0))
		return
	var/turf/from = unseen_shot_from(user)
	if(!from)
		return
	if(state == BOT_STATE_ARREST)
		arrest_last_seen = world.time
		arrest_last_seen_turf = from
	else
		combat_last_seen = world.time
		combat_last_seen_turf = from
	answer_unseen_fire(user, from)

/// Where `foe` shot it from a moment ago, if it was them and it can't see them now: the last sighting it goes by. Null otherwise.
/datum/bot_brain/proc/unseen_shot_from(mob/living/foe)
	if(!shot_from || world.time - shot_at > 3 SECONDS || shot_by?.resolve() != foe || shot_from.z != owner.z)
		return null
	return shot_from

/// Not in sight, and they've just shot it from `from`: back at the spot with a gun, else Security goes for it and anybody else gets out of
/// the line. TRUE if it's done something about it this time.
/datum/bot_brain/proc/answer_unseen_fire(mob/living/foe, turf/from)
	if(!from || owner.incapacitated() || !isturf(owner.loc))
		return FALSE
	owner.face_atom(from)
	if(world.time < next_taser_time)
		return TRUE //it's only just fired back: the next comes at its pace
	var/obj/item/gun/G = gun_to_answer_with(foe)
	var/dist = get_dist(owner, from)
	if(G && dist >= 1 && dist <= BOT_SIGHT_RANGE && bot_clear_line(get_turf(owner), from) && !crew_toward(from))
		if(!ready_in_hand(G)) //a free hand first, not both emptied (try_taser(), security_patrol.dm)
			return FALSE
		var/obj/item/gun/energy/E = G
		var/nonlethal = istype(E) && E.ammo_type?.len && is_nonlethal_shot(E.ammo_type[E.select])
		owner.a_intent = nonlethal ? INTENT_HELP : INTENT_HARM
		owner.changeNext_move(CLICK_CD_RANGE)
		next_taser_time = world.time + shot_interval(G)
		bot_log(src, "COMBAT: shot from out of sight - firing [G] back where it came from, [bot_coord(from)]")
		bot_tally("fired back at an unseen shooter")
		INVOKE_ASYNC(G, TYPE_PROC_REF(/obj/item/gun, afterattack), from, owner, FALSE, null)
		return TRUE
	if(is_security_job() || G)
		return FALSE //Security goes for the spot as a last sighting (handle_arrest()/handle_combat() walk there)
	// Nothing to shoot back with: out of the line it came along
	if(hold_cover_from(foe))
		return TRUE
	var/turf/spot = cover_from(from)
	if(!spot)
		return FALSE
	bot_log(src, "THREAT: shot by somebody I can't see, from [bot_coord(from)] - out of the line to [bot_coord(spot)]")
	bot_tally("took cover from an unseen shooter")
	cover_spot = spot
	cover_from_ref = WEAKREF(foe)
	cover_until = world.time + 10 SECONDS
	combat_chase(spot)
	return TRUE

/// In the cover it took from `foe` (answer_unseen_fire() above, mind_the_gun() in threat_read.dm), while it holds it: there, or on its way.
/// The shots that miss it there aren't hits, and it used to walk back out at the spot they came from once the last hit was a few seconds old.
/datum/bot_brain/proc/hold_cover_from(mob/living/foe)
	if(!cover_spot || world.time >= cover_until || cover_from_ref?.resolve() != foe)
		return FALSE
	if(get_turf(owner) != cover_spot)
		combat_chase(cover_spot)
	else
		stop_pursuit()
	return TRUE

/// Shot at from out of sight with nothing to shoot back with, and it's had its wait in cover: not out to walk up to whoever it was.
/datum/bot_brain/proc/keeps_out_of_unseen_fire(mob/living/foe)
	return cover_from_ref?.resolve() == foe && !is_security_job() && !find_usable_gun()

/// The gun it'd fire back with: Security's stun setting unless it may use lethal force on them, anybody else whatever fires.
/datum/bot_brain/proc/gun_to_answer_with(mob/living/foe)
	if(is_security_job())
		var/obj/item/gun/G = ready_nonlethal_gun()
		if(!G && bot_may_use_lethal_force(foe))
			G = find_usable_gun()
		return G
	return find_usable_gun()

/// One of the crew, not wanted, along the line to `from` or beside it: not a shot into the dark past them.
/datum/bot_brain/proc/crew_toward(turf/from)
	var/turf/mine = get_turf(owner)
	for(var/turf/T in getline(mine, from))
		if(T == mine)
			continue
		for(var/mob/living/carbon/human/H in range(1, T))
			if(H == owner || H.stat == DEAD || get_dist(H, mine) <= 1 || H == shot_by?.resolve())
				continue
			var/datum/bot_wanted/W = bot_get_wanted_entry(H)
			if(W && W.severity >= BOT_CRIME_MAJOR)
				continue
			if(H in view(BOT_SIGHT_RANGE, owner))
				return TRUE
	return FALSE
