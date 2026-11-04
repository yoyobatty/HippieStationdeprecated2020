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
/// Flames: nobody walks into them who'd burn there, whatever it's on its way to. A firefighter sprays from outside them (goals/respond_to_fire.dm),
/// and an engineer that walked through a burning engineering bay to fetch an extinguisher and then to mend a cable died of it.
#define BOT_HAZARD_FIRE 3
/// Broken glass: nothing to anybody in shoes, and a cut foot for anybody without (caltrop, shards.dm). Barefoot bots walked straight over it.
#define BOT_HAZARD_GLASS 4
/// Close to a running supermatter: its radiation, for anybody not in a radiation suit or an engineering hardsuit. An assistant, a
/// chemist and a doctor walking through Meta's Engineering died of it, 1300 to 2300 rads apiece, the crystal at 100%.
#define BOT_HAZARD_RADS 5
/// The crystal's power from which its radiation counts, and how far out it does then: two tiles at 150, five at about 900, six at the most.
/// Not from any power at all: a crystal sits at 1 to 10 from roundstart (Bot Shift's crystal line), and with the whole room round it
/// out of bounds the engineers couldn't get in to start it, 0 of 4 shifts.
#define BOT_HAZARD_RADS_FROM 150
#define BOT_HAZARD_RADS_RANGE(power) clamp(round(sqrt(power) / 6), 2, 6)

/// Turf -> BOT_HAZARD_*, for everywhere a bot won't step into.
GLOBAL_LIST_EMPTY(bot_hazard_turfs)
GLOBAL_VAR_INIT(bot_hazards_refresh_at, 0)

/// The bots' route planners ask this once a tile, and on nearly every tile it's two list reads.
/proc/bot_steps_into_hazard(turf/from, turf/T, mob/living/carbon/human/caller)
	var/hazard = GLOB.bot_hazard_turfs[T]
	if(!hazard || GLOB.bot_hazard_turfs[from])
		return FALSE
	if(hazard == BOT_HAZARD_FIRE)
		return !caller.bot_brain?.heat_proof()
	if(hazard == BOT_HAZARD_GLASS)
		return !caller.shoes
	if(hazard == BOT_HAZARD_RADS)
		return !bot_rad_suited(caller)
	return hazard == BOT_HAZARD_BALL || caller.bot_brain?.pathing_no_tailgating

/// Dressed for radiation: the radiation suit. Not the engineering hardsuit: its armour takes three quarters of a dose off its wearer, but
/// what they've got on comes out contaminated all the same. Engineers going back in to reload the collectors at 1500 power carried it out
/// on their suits, and Medbay, treating them, was where Box's crew died of radiation, 4 to 15 a shift.
/proc/bot_rad_suited(mob/living/carbon/human/H)
	return istype(H.wear_suit, /obj/item/clothing/suit/radiation)

/// Where a running crystal's radiation reaches (bot_refresh_hazards()).
/proc/bot_in_crystal_rads(atom/A)
	var/turf/T = get_turf(A)
	return T && GLOB.bot_hazard_turfs[T] == BOT_HAZARD_RADS

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
		if(crystal.power >= BOT_HAZARD_RADS_FROM)
			for(var/turf/T as anything in RANGE_TURFS(BOT_HAZARD_RADS_RANGE(crystal.power), crystal))
				hazards[T] = BOT_HAZARD_RADS
		for(var/turf/T as anything in RANGE_TURFS(1, crystal))
			hazards[T] = BOT_HAZARD_BALL
	for(var/obj/effect/hotspot/H as anything in SSair.hotspots)
		var/turf/T = H?.loc
		if(T && !hazards[T])
			hazards[T] = BOT_HAZARD_FIRE
	for(var/obj/item/shard/S as anything in bot_instances_of(/obj/item/shard))
		var/turf/T = S.loc
		if(isturf(T) && !hazards[T])
			hazards[T] = BOT_HAZARD_GLASS
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
#undef BOT_HAZARD_FIRE
/// Near a running crystal in nothing against its radiation: out, whatever it was at, the way it gets out of flames (goals/respond_to_fire.dm).
/// An officer who answered a call in Engineering chased a suspect round the supermatter at 1444 power, stuck there for minutes, and died
/// of 3000 rads. The routes keep everybody out of there (bot_steps_into_hazard()), but not whoever's already in it.
/datum/bot_brain/proc/try_escape_radiation()
	var/turf/here = get_turf(owner)
	if(!here || GLOB.bot_hazard_turfs[here] != BOT_HAZARD_RADS || owner.buckled || bot_rad_suited(owner))
		return FALSE
	if(pursuing_kind == "flames" && pursue_target && GLOB.bot_hazard_turfs[get_turf(pursue_target)] != BOT_HAZARD_RADS)
		return TRUE //on its way out
	var/turf/out = bot_way_out_of_rads(here)
	if(!out)
		return FALSE
	switch(state)
		if(BOT_STATE_ARREST)
			end_arrest("too close to the crystal")
		if(BOT_STATE_COMBAT)
			disengage_combat("too close to the crystal")
	if(state == BOT_STATE_GOAL)
		drop_goals("too close to the crystal")
	bot_log(src, "too close to the crystal with nothing on against it - getting out to [bot_coord(out)]")
	bot_tally("got away from the crystal")
	pursue(out, "flames", force = TRUE)
	return TRUE

/datum/bot_brain
	var/rads_noted = FALSE

/// The first time a bot's radiation passes what's safe: where it was, what radioactive things are about it, how far the crystal is.
/// For finding where a shift's radiation sickness comes from (Box lost 4 to 15 a shift to it, with nobody near its supermatter).
/datum/bot_brain/proc/note_radiation()
	if(rads_noted || owner.radiation <= RAD_MOB_SAFE)
		return
	rads_noted = TRUE
	var/list/sources = list()
	for(var/atom/movable/A in range(7, owner))
		var/datum/component/radioactive/R = A.GetComponent(/datum/component/radioactive)
		if(R)
			sources += "[A] ([round(R.strength)])"
	var/obj/machinery/power/supermatter_crystal/crystal = GLOB.main_supermatter_engine
	var/crystal_at = (crystal && crystal.z == owner.z) ? "[get_dist(owner, crystal)] tiles from the crystal ([round(crystal.power)] power)" : "no crystal here"
	bot_log(src, "IRRADIATED: [round(owner.radiation)] rads at [bot_coord(get_turf(owner))] in [get_area_name(owner, TRUE)], [crystal_at]; radioactive about: [length(sources) ? english_list(sources) : "nothing"]")
	bot_tally("irradiated")

/// The nearest floor out of the crystal's reach that can be walked to.
/proc/bot_way_out_of_rads(turf/open/from)
	if(!istype(from))
		return null
	var/list/seen = list()
	seen[from] = TRUE
	var/list/frontier = list(from)
	for(var/depth in 1 to 12)
		var/list/next = list()
		for(var/turf/open/T as anything in frontier)
			for(var/turf/open/N as anything in T.atmos_adjacent_turfs)
				if(seen[N])
					continue
				seen[N] = TRUE
				if(isspaceturf(N) || is_blocked_turf(N, TRUE) || bot_turf_is_deadly(N))
					continue
				if(GLOB.bot_hazard_turfs[N] != BOT_HAZARD_RADS && GLOB.bot_hazard_turfs[N] != BOT_HAZARD_BALL)
					return N
				next += N
		frontier = next
	return null

#undef BOT_HAZARD_GLASS
#undef BOT_HAZARD_BALL
#undef BOT_HAZARD_RADS
#undef BOT_HAZARD_RADS_RANGE
#undef BOT_HAZARD_RADS_FROM
