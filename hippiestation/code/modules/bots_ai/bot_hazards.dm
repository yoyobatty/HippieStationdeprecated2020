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
	if(length(GLOB.singularities))
		bot_notice_loose_engine() //goals/sabotage_engine.dm
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
	station_picture_list_changed(GLOB.bot_hazard_turfs, hazards) // a hazard tile is asked about every search (station_picture.dm)
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

// ---------------------------------------------------------------------------------------------
// Footing
// ---------------------------------------------------------------------------------------------

// Slips (the user, 2026-11-04: aware of them, as a person is, in their own time, and still slipping now and then). A wet floor is walked
// over, since walking doesn't slip you on water (_open.dm handle_slip(), NO_SLIP_WHEN_WALKING). A banana peel, soap, lube or ice puts you
// down walking or not, so that's stepped round, a tile to the side, if there's one free. What's two tiles ahead gets one look, and the
// look doesn't always catch it: less often in a hurry, more often for the careful. Bots ran on to everything, the clown's peels included.

/// Out of a hundred, the chance it sees what's on a tile in time.
#define BOT_FOOTING_SEEN 80
#define BOT_FOOTING_SEEN_HURRIED 55
/// How long one look at a tile stands, seen or missed.
#define BOT_FOOTING_LOOK (30 SECONDS)

/datum/bot_brain
	/// REF(turf) -> until when what it saw (or missed) there stands. Positive: seen. Negative: missed.
	var/list/footing_looks
	/// Walking because of the floor, not because a goal asked it to.
	var/walking_for_footing = FALSE
	/// Set by a Bot Gym scenario: the chance it sees something, instead of the usual.
	var/footing_attention

/// What stepping on to T would put it on the floor with, as it's dressed: "wet" (water, which walking over is fine on), "slip" (a peel,
/// soap, lube or ice, which walking won't help with), or null.
/datum/bot_brain/proc/slip_on(turf/T)
	if(!isopenturf(T) || !(owner.status_flags & CANKNOCKDOWN))
		return null
	var/noslip = has_noslip_shoes() //goals/janitor.dm
	var/datum/component/wet_floor/W = T.GetComponent(/datum/component/wet_floor)
	if(W && W.highest_strength != TURF_DRY)
		if(W.highest_strength == TURF_WET_WATER)
			return noslip ? null : "wet"
		return "slip" //lube and ice: galoshes don't help
	if(noslip)
		return null
	for(var/atom/movable/AM in T)
		var/datum/component/slippery/S = AM.GetComponent(/datum/component/slippery)
		if(S)
			return (S.lube_flags & NO_SLIP_WHEN_WALKING) ? "wet" : "slip"
	return null

/// Whether it's seen what's on T in time. One look a tile, so looking again and again doesn't see everything sooner or later.
/datum/bot_brain/proc/sees_footing(turf/T)
	var/key = REF(T)
	var/look = LAZYACCESS(footing_looks, key)
	if(look && abs(look) > world.time)
		return look > 0
	var/chance = footing_attention
	if(isnull(chance))
		var/hurried = state == BOT_STATE_COMBAT || state == BOT_STATE_ARREST || istype(current_goal, /datum/bot_goal/run_from)
		chance = (hurried ? BOT_FOOTING_SEEN_HURRIED : BOT_FOOTING_SEEN) + (is_paranoid() ? 10 : 0) + (owner.m_intent == MOVE_INTENT_WALK ? 10 : 0)
	var/seen = prob(chance)
	LAZYSET(footing_looks, key, seen ? world.time + BOT_FOOTING_LOOK : -(world.time + BOT_FOOTING_LOOK))
	if(seen)
		bot_log_verbose(src, "saw [slip_on(T)] floor at [bot_coord(T)]")
	return seen

/// About to step on to `next`: what's underfoot two tiles ahead is looked at. Water ahead, and it walks till it's past. Something that'll
/// put it down anyway, and it takes the tile beside it if one's free and goes on from there. Returns the tile to step on to.
/datum/bot_brain/proc/mind_the_footing(turf/next)
	var/turf/here = get_turf(owner)
	var/turf/after = length(current_path) >= 2 ? current_path[2] : null
	var/wet_ahead = FALSE
	for(var/turf/T in list(next, after))
		if(T && slip_on(T) == "wet" && sees_footing(T))
			wet_ahead = TRUE
	if(wet_ahead && owner.m_intent != MOVE_INTENT_WALK)
		bot_log(src, "wet floor ahead - walking")
		owner.toggle_move_intent()
		walking_for_footing = TRUE
	else if(!wet_ahead && walking_for_footing && slip_on(here) != "wet")
		walking_for_footing = FALSE
		if(owner.m_intent == MOVE_INTENT_WALK && !walking_for_goal)
			owner.toggle_move_intent()
	if(slip_on(next) != "slip" || !sees_footing(next) || !here)
		return next
	// Round it, a step at a time: aside, along past it, and back on to the route. A diagonal step is two straight ones to this engine
	// (atom/movable/Move()), and the first of them went on to the peel.
	if(!after)
		return null //the slippery tile's where the walk ends (the peel it's come to pick up): it stops beside it
	if(get_dist(next, after) != 1)
		return next
	var/ahead = get_dir(here, next)
	var/obj/item/card/id/id_card = owner.get_idcard(TRUE)
	for(var/side_dir in list(turn(ahead, 90), turn(ahead, -90)))
		var/turf/aside = get_step(here, side_dir)
		var/turf/past = get_step(next, side_dir)
		var/turf/beyond = get_step(after, side_dir)
		if(!aside || !past || !beyond || slip_on(aside) || slip_on(past) || slip_on(beyond))
			continue
		if(!here.bot_reachable_strict(owner, aside, id_card, TRUE) || !aside.bot_reachable_strict(owner, past, id_card, TRUE) || !past.bot_reachable_strict(owner, beyond, id_card, TRUE) || !beyond.bot_reachable_strict(owner, after, id_card, TRUE))
			continue
		bot_log(src, "stepping round the [slip_thing(next)] at [bot_coord(next)]")
		current_path.Cut(1, 2)
		current_path.Insert(1, aside, past, beyond)
		return aside
	return next

/// What's slippery there, for the log.
/datum/bot_brain/proc/slip_thing(turf/T)
	for(var/atom/movable/AM in T)
		if(AM.GetComponent(/datum/component/slippery))
			return AM.name
	return "slippery floor"

#undef BOT_FOOTING_SEEN
#undef BOT_FOOTING_SEEN_HURRIED
#undef BOT_FOOTING_LOOK

// ---------------------------------------------------------------------------------------------
// Adrift
// ---------------------------------------------------------------------------------------------

// Out in space with nothing to push off and no jetpack running: an engineer crossing a gap by the walls pushed off into the open, drifted
// for thirteen minutes and ran out of air. A player throws something the other way and rides the push back (carbon.dm throw_item(),
// newtonian_move()): the least use to it first, the ID, the tank, the jetpack and a gun never. With nothing left to throw, it calls for help.

/datum/bot_brain
	var/next_drift_throw = 0
	var/next_drift_call = 0
	/// When it called for help out there; it says so once it's back in, and answers asked about it (bot_chatter.dm adrift_answer())
	var/drift_called_for_help = 0
	var/drift_back_at = -INFINITY

/datum/bot_brain/proc/try_drift_back()
	var/turf/here = get_turf(owner)
	if(drift_called_for_help && here && !isspaceturf(here))
		drift_called_for_help = 0
		drift_back_at = world.time
		bot_log(src, "made it back in after calling for help")
		bot_say(owner, ";[pick("Never mind, I've made it back in. Thanks!", "All good, I made it back inside.", "Made it back in on my own, no need to come out.")]")
	if(!isspaceturf(here) || owner.has_gravity() || owner.incapacitated() || world.time < next_drift_throw)
		return FALSE
	if(owner.Process_Spacemove(0))
		return FALSE //something to push off, or a jetpack under it
	// A jetpack with gas in it is the way back: switched on if it's off, never called for. Process_Spacemove(0) above only counts one
	// with its stabilizers on, so an explorer flying to a ruin on one, between moves at the edge of the level, radioed "Anybody with a
	// jetpack?" with one on its back, and somebody went out looking for it.
	var/obj/item/tank/jetpack/J = worn_jetpack()
	if(J && bot_jetpack_fuel(J) > 0.02)
		if(!J.on)
			J.turn_on(owner)
			bot_log(src, "adrift - switched the jetpack on")
		return FALSE
	var/turf/ground = nearest_solid_ground()
	if(!ground)
		return FALSE
	var/toward = get_dir(here, ground)
	if(owner.inertia_dir && (owner.inertia_dir & toward))
		return FALSE //on its way already: the drift carries it
	next_drift_throw = world.time + 2 SECONDS
	var/obj/item/I = throwaway_item()
	if(!I)
		if(world.time >= next_drift_call)
			next_drift_call = world.time + 1 MINUTES
			drift_called_for_help = world.time
			bot_log(src, "adrift with nothing to throw - calling for help")
			bot_say(owner, ";Help! I'm adrift out in space at [here.x], [here.y], nothing to push off from. Anybody with a jetpack?")
		return FALSE
	if(!ready_in_hand(I))
		return FALSE
	var/turf/away = get_ranged_target_turf(owner, turn(toward, 180), 5)
	bot_log(src, "adrift - throwing [I] the other way to push back towards [bot_coord(ground)]")
	bot_tally("threw something to drift back")
	owner.face_atom(away)
	owner.throw_item(away)
	return TRUE

/// The nearest ground in sight to make for: floor, a lattice or a catwalk, somewhere to stand; a wall if that's all there is (it can push
/// off along one). The middle of the level if there's nothing.
/datum/bot_brain/proc/nearest_solid_ground()
	var/turf/here = get_turf(owner)
	var/turf/best
	var/best_score
	for(var/turf/T in view(10, owner))
		if(isspaceturf(T) && !(locate(/obj/structure/lattice) in T))
			continue
		var/score = get_dist_euclidian(here, T) + (T.density ? 20 : 0) //standing room beats a wall that's nearer; straight at it beats the diagonal
		if(!best || score < best_score)
			best = T
			best_score = score
	return best || locate(world.maxx / 2, world.maxy / 2, here.z)

/// What it would part with to push off: rubbish, paper and food first, then anything small, tools last. Never its ID or PDA, the tank it
/// breathes from, a jetpack, a gun, a bag, or what its goal is about.
/datum/bot_brain/proc/throwaway_item()
	var/list/carried = list()
	for(var/obj/item/I in owner.held_items)
		carried += I
	var/obj/item/storage/bag = owner.back
	if(istype(bag))
		for(var/obj/item/I in bag.contents)
			carried += I
	var/obj/item/best
	var/best_rank = 99
	for(var/obj/item/I as anything in carried)
		if(HAS_TRAIT(I, TRAIT_NODROP) || (I.item_flags & ABSTRACT) || istype(I, /obj/item/card/id) || istype(I, /obj/item/pda) || istype(I, /obj/item/tank) || istype(I, /obj/item/gun) || istype(I, /obj/item/storage) || I == current_goal?.target)
			continue
		var/rank = 5
		if(istype(I, /obj/item/trash) || istype(I, /obj/item/paper) || istype(I, /obj/item/reagent_containers/food) || istype(I, /obj/item/toy) || istype(I, /obj/item/toy/crayon))
			rank = 1
		else if(I.w_class <= WEIGHT_CLASS_SMALL && !is_tool_or_toolbox(I))
			rank = 2
		else if(!is_tool_or_toolbox(I))
			rank = 3
		if(rank < best_rank)
			best = I
			best_rank = rank
	return best
