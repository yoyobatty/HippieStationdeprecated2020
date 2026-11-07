// Ghost roles in a round with a bot crew. A midround event that wants a ghost (the blob, a space dragon, a morph) asks the observers,
// and with nobody but bots aboard there are none: the event gave up with "not enough players", so a bots-only round never had a
// midround threat. Now, when no ghost signs up and there's a bot crew, the event goes ahead anyway with what can play the part:
//  - the blob: an overmind played by bots_ai, as on a Bot Shift (goals/blob.dm), the crew's fight against it with it;
//  - a space dragon or a morph: the creature itself, with its own hostile AI, the way a mob nobody's playing behaves.
// Roles nothing can play yet (a scrake's a human with no AI, a slaughter demon would sit in its blood plane, xenomorphs, revenants,
// abductors, ninjas) stay as they were. A real ghost is always asked first and always comes first.
//
// The crew's side of a creature loose on the station is with the slimes' (goals/sabotage_slimes.dm): it's called in, and Security goes
// and shoots it.

/// Whether an event short of ghosts should go ahead with a bot or an AI creature: there's a bot crew, and it's a round, not a test of
/// something else.
/proc/bot_fills_ghost_roles()
	return length(GLOB.bot_brains) && SSticker.IsRoundInProgress() && !(BOT_GYM_PARAMETER in world.params)

/// A spawn point for something coming in from space: the carp spawns, as the events use.
/proc/bot_event_carp_spawn()
	var/list/spawn_locs = list()
	for(var/obj/effect/landmark/carpspawn/C in GLOB.landmarks_list)
		if(isturf(C.loc))
			spawn_locs += C.loc
	return length(spawn_locs) ? pick(spawn_locs) : null

/datum/round_event/ghost_role/blob/spawn_role()
	. = ..()
	if(. != NOT_ENOUGH_PLAYERS || !bot_fills_ghost_roles())
		return
	if(!bot_spawn_blob())
		return
	var/datum/bot_blob/BB = GLOB.bot_blobs[length(GLOB.bot_blobs)]
	if(BB?.owner)
		spawned_mobs += BB.owner
	message_admins("BOT GHOST ROLES: no ghosts for the blob event, a bot overmind has it.")
	log_game("BOT GHOST ROLES: blob event taken by a bot overmind")
	return SUCCESSFUL_SPAWN

/datum/round_event/ghost_role/space_dragon/spawn_role()
	. = ..()
	if(. != NOT_ENOUGH_PLAYERS || !bot_fills_ghost_roles())
		return
	var/turf/T = bot_space_near_crew() || bot_event_carp_spawn() //nobody's flying it in: it turns up where it'll find somebody
	if(!T)
		return MAP_ERROR
	var/mob/living/simple_animal/hostile/megafauna/dragon/space_dragon/S = new(T)
	playsound(S, 'sound/magic/ethereal_exit.ogg', 50, 1, -1)
	S.faction = list("carp") //it's "neutral" for a player to steer, the same as the crew: on its own AI it went for nobody
	// Whoever it turned up beside, it comes in after: a mob nobody's playing only goes for what it sees, and from out in space it saw
	// nobody and floated there all shift.
	var/mob/living/prey = GLOB.bot_space_near_crew_who?.resolve()
	if(prey)
		S.toggle_ai(AI_ON)
		S.GiveTarget(prey)
	spawned_mobs += S
	message_admins("BOT GHOST ROLES: no ghosts for the space dragon event, the dragon's come in on its own AI at [ADMIN_VERBOSEJMP(S)].")
	log_game("BOT GHOST ROLES: space dragon spawned without a player at [AREACOORD(S)]")
	return SUCCESSFUL_SPAWN

/datum/round_event/ghost_role/morph/spawn_role()
	. = ..()
	if(. != NOT_ENOUGH_PLAYERS || !bot_fills_ghost_roles() || !length(GLOB.xeno_spawn))
		return
	var/mob/living/simple_animal/hostile/morph/S = new(get_turf(pick(GLOB.xeno_spawn)))
	SEND_SOUND(S, sound('sound/magic/mutate.ogg'))
	spawned_mobs += S
	message_admins("BOT GHOST ROLES: no ghosts for the morph event, the morph's loose on its own AI at [ADMIN_VERBOSEJMP(S)].")
	log_game("BOT GHOST ROLES: morph spawned without a player at [AREACOORD(S)]")
	return SUCCESSFUL_SPAWN

// ---------------------------------------------------------------------------------------------
// Creatures that nobody's playing wake for the bot crew
// ---------------------------------------------------------------------------------------------
//
// A hostile mob only looks for anybody to go for while a player's client is on its z-level (consider_wakeup(), hostile.dm): with none,
// it parks itself (AI_Z_OFF) until one arrives. Bots have no clients, so in a bots-only round every carp, morph and space dragon on the
// station floated where it came in and never went for anybody: a forced space dragon on Box killed nobody in 25 minutes. Now a level
// with bot crew on it counts. Not by putting bots in SSmobs.clients_by_zlevel: sounds use that list to skip levels nobody can hear on,
// and with bots in it every sound in a bots-only round would search for hearers.

GLOBAL_LIST_EMPTY(bot_crew_by_z)
GLOBAL_VAR_INIT(bot_crew_by_z_at, -100)

/// How many of the bot crew are up and about on a z-level, counted every five seconds at most.
/proc/bot_crew_on_z(z)
	if(world.time >= GLOB.bot_crew_by_z_at + 5 SECONDS)
		GLOB.bot_crew_by_z_at = world.time
		GLOB.bot_crew_by_z = list()
		for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
			var/mob/living/carbon/human/H = B.owner
			if(QDELETED(H) || H.stat == DEAD || !H.z)
				continue
			GLOB.bot_crew_by_z["[H.z]"] += 1
	return GLOB.bot_crew_by_z["[z]"] || 0

/mob/living/simple_animal/hostile/consider_wakeup()
	var/turf/T = get_turf(src)
	if(!T || length(SSmobs.clients_by_zlevel[T.z]) || !bot_crew_on_z(T.z))
		return ..()
	// Nobody's client here, but the bot crew is: look for them as for players, rather than parking.
	if(AIStatus == AI_IDLE && FindTarget(ListTargets(), 1))
		toggle_ai(AI_ON)

/// Space beside the hull, near somebody of the crew: where something coming in from space shows up so as to find anybody.
/proc/bot_space_near_crew()
	var/list/crew = list()
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(!QDELETED(B.owner) && B.owner.stat != DEAD && is_station_level(B.owner.z) && !istype(get_area(B.owner), /area/maintenance))
			crew += B.owner
	while(length(crew))
		var/mob/living/carbon/human/H = pick_n_take(crew)
		var/turf/best
		var/best_dist
		for(var/turf/open/space/S in RANGE_TURFS(12, H))
			var/d = get_dist(S, H)
			if(!best || d < best_dist)
				best = S
				best_dist = d
		if(best)
			GLOB.bot_space_near_crew_who = WEAKREF(H)
			return best
	return null

GLOBAL_DATUM(bot_space_near_crew_who, /datum/weakref)
