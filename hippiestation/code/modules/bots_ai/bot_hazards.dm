// Places a person keeps out of without being told: the line of fire of a running emitter, flames, and anywhere near a tesla
// ball or a singularity. A bot already in one can always walk out (bot_steps_into_hazard() only stops it stepping in).
//
// They aren't all the same. Nobody goes near a ball, whatever they're doing: an engineer left inside the containment
// after the ball came up was dusted by it. A beam or a fire only keeps people out on their way about their day: a barman
// strolled through a burning bar to the theatre, and firefighters do have to get to the fire. An engineer
// setting the engine up has to cross them to reach the grounding rods, and with routes kept off the beams for
// everybody the rods went unwrenched, the tesla took out the grid with nothing to earth it, and the fields ran down and
// let it go (setup_tesla_engine.dm says the same of an earlier try).

/// How often the map of them is redrawn, in deciseconds.
#define BOT_HAZARD_REFRESH 30
/// How far from a tesla ball or a singularity a bot will go.
#define BOT_HAZARD_BALL_RANGE 4
/// How far an emitter's beam is followed. They're aimed across an engine room, not across the station.
#define BOT_HAZARD_BEAM_RANGE 24
/// How far a slime's reach is flooded out from where it is.
#define BOT_HAZARD_PEN_REACH 6
#define BOT_HAZARD_BEAM 1
#define BOT_HAZARD_BALL 2

/// Turf -> BOT_HAZARD_*, for everywhere a bot won't step into.
GLOBAL_LIST_EMPTY(bot_hazard_turfs)
GLOBAL_VAR_INIT(bot_hazards_refresh_at, 0)

/// The bots' route planners ask this once a tile, and on nearly every tile it's two list reads.
/proc/bot_steps_into_hazard(turf/from, turf/T, mob/living/carbon/human/caller)
	var/hazard = GLOB.bot_hazard_turfs[T]
	if(!hazard || GLOB.bot_hazard_turfs[from])
		return FALSE
	return hazard == BOT_HAZARD_BALL || caller.bot_brain?.pathing_no_tailgating

/proc/bot_refresh_hazards()
	GLOB.bot_hazards_refresh_at = world.time + BOT_HAZARD_REFRESH
	var/list/hazards = list()
	for(var/obj/machinery/power/emitter/E as anything in bot_instances_of(/obj/machinery/power/emitter))
		if(E.active && !QDELETED(E))
			bot_mark_beam(hazards, E)
	for(var/obj/singularity/S as anything in GLOB.singularities)
		for(var/turf/T as anything in RANGE_TURFS(BOT_HAZARD_BALL_RANGE, S))
			hazards[T] = BOT_HAZARD_BALL
	// A supermatter crystal dusts whatever touches it, lit or not.
	var/obj/machinery/power/supermatter_crystal/crystal = GLOB.main_supermatter_engine
	if(!QDELETED(crystal))
		for(var/turf/T as anything in RANGE_TURFS(1, crystal))
			hazards[T] = BOT_HAZARD_BALL
	for(var/obj/effect/hotspot/H as anything in SSair.hotspots)
		var/turf/T = H?.loc
		if(T && !hazards[T])
			hazards[T] = BOT_HAZARD_BEAM
	for(var/mob/living/simple_animal/slime/S in GLOB.alive_mob_list)
		if(!S.docile && !S.ckey && isturf(S.loc))
			bot_mark_slime_pen(hazards, S)
	GLOB.bot_hazard_turfs = hazards

/// The floor a slime could get to, which is the floor of its pen if the doors are shut: wherever the air goes, a few tiles out.
/// Scientists stroll round their department, and a stroll into a pen let the slime out to feed: three died of it in one batch,
/// in corridors nowhere near the lab. Nobody opens a pen with a slime in it, feeding and all of it is done from the console.
/proc/bot_mark_slime_pen(list/hazards, mob/living/simple_animal/slime/S)
	var/list/frontier = list(S.loc)
	hazards[S.loc] = BOT_HAZARD_BALL
	for(var/depth in 1 to BOT_HAZARD_PEN_REACH)
		var/list/next = list()
		for(var/turf/open/T as anything in frontier)
			for(var/turf/open/out as anything in T.atmos_adjacent_turfs)
				if(hazards[out] != BOT_HAZARD_BALL)
					hazards[out] = BOT_HAZARD_BALL
					next += out
		frontier = next

/// Follows an emitter's muzzle out to the first thing that would stop its beam.
/proc/bot_mark_beam(list/hazards, obj/machinery/power/emitter/E)
	var/turf/T = get_turf(E)
	for(var/i in 1 to BOT_HAZARD_BEAM_RANGE)
		T = get_step(T, E.dir)
		if(!T || T.density)
			return
		for(var/obj/O in T)
			if(O.density)
				return
		hazards[T] = BOT_HAZARD_BEAM

#undef BOT_HAZARD_REFRESH
#undef BOT_HAZARD_BALL_RANGE
#undef BOT_HAZARD_BEAM_RANGE
#undef BOT_HAZARD_PEN_REACH
#undef BOT_HAZARD_BEAM
#undef BOT_HAZARD_BALL
