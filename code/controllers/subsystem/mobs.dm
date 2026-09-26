/// hippie -- an unobserved (AI_Z_OFF) simple mob runs Life() on one SSmobs fire in this many. See skip_unobserved_life().
#define UNOBSERVED_LIFE_INTERVAL 4

SUBSYSTEM_DEF(mobs)
	name = "Mobs"
	priority = FIRE_PRIORITY_MOBS
	flags = SS_KEEP_TIMING | SS_NO_INIT
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME

	var/list/currentrun = list()
	var/static/list/clients_by_zlevel[][]
	var/static/list/dead_players_by_zlevel[][] = list(list()) // Needs to support zlevel 1 here, MaxZChanged only happens when z2 is created and new_players can login before that.
	var/static/list/cubemonkeys = list()

/datum/controller/subsystem/mobs/stat_entry()
	..("P:[GLOB.mob_living_list.len]")

/datum/controller/subsystem/mobs/proc/MaxZChanged()
	if (!islist(clients_by_zlevel))
		clients_by_zlevel = new /list(world.maxz,0)
		dead_players_by_zlevel = new /list(world.maxz,0)
	while (clients_by_zlevel.len < world.maxz)
		clients_by_zlevel.len++
		clients_by_zlevel[clients_by_zlevel.len] = list()
		dead_players_by_zlevel.len++
		dead_players_by_zlevel[dead_players_by_zlevel.len] = list()

/datum/controller/subsystem/mobs/fire(resumed = 0)
	var/seconds = wait * 0.1
	if (!resumed)
		src.currentrun = GLOB.mob_living_list.Copy()

	//cache for sanic speed (lists are references anyways)
	var/list/currentrun = src.currentrun
	var/times_fired = src.times_fired
	while(currentrun.len)
		var/mob/living/L = currentrun[currentrun.len]
		currentrun.len--
		if(L)
			if(!skip_unobserved_life(L, times_fired))
				L.Life(seconds, times_fired)
		else
			GLOB.mob_living_list.Remove(L)
		if (MC_TICK_CHECK)
			return

/// hippie -- The idle NPC pool parks a simple mob AI_Z_OFF once no player is on its z-level (usually lavaland
/// fauna), and wakes it as soon as one arrives. Nobody can see it until then, so its Life() only runs on one fire
/// in UNOBSERVED_LIFE_INTERVAL - its AI is already off entirely. Fires are staggered per mob so the cost stays even.
/datum/controller/subsystem/mobs/proc/skip_unobserved_life(mob/living/L, times_fired)
	if(!isanimal(L))
		return FALSE
	var/mob/living/simple_animal/animal = L
	if(animal.AIStatus != AI_Z_OFF || animal.client)
		return FALSE
	if(isnull(animal.unobserved_life_phase))
		animal.unobserved_life_phase = rand(0, UNOBSERVED_LIFE_INTERVAL - 1)
	return (times_fired + animal.unobserved_life_phase) % UNOBSERVED_LIFE_INTERVAL != 0
