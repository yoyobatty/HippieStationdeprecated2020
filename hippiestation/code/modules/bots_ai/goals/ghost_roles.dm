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
	var/turf/T = bot_event_carp_spawn()
	if(!T)
		return MAP_ERROR
	var/mob/living/simple_animal/hostile/megafauna/dragon/space_dragon/S = new(T)
	playsound(S, 'sound/magic/ethereal_exit.ogg', 50, 1, -1)
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
