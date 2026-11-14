// Glide check (tools/glide_check/run_glide_check.sh): things that move a tile at a time on their own. Sparks, steam, a blast's
// fragments, walk_to() at several speeds, a spiderling, the immovable rod, a meteor, a conveyor, a crew bot, a cleanbot, a secbot
// and two mechs. For each step: the gap since the last one, and how long the glide takes to cover the tile (32 / glide_size,
// in ticks). They should match. A glide shorter than the gap darts and then sits; a longer one falls behind and snaps.
// Headless on Runtime Station. Lines to data/glide_check.txt.

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("glide-check" in world.params)
		sleep_offline_after_initializations = FALSE
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_glide_check))
	return ..()

GLOBAL_LIST_EMPTY(glide_check_lines)
GLOBAL_VAR_INIT(glide_check_fails, 0)
GLOBAL_LIST_EMPTY(gl_watch) // mover -> its record
GLOBAL_LIST_EMPTY(gl_auto) // type -> label: watched from its Initialize()
GLOBAL_LIST_EMPTY(gl_log) // label -> records
GLOBAL_LIST_EMPTY(gl_used) // lane turfs taken already
GLOBAL_LIST_EMPTY(gl_bursts) // particle burst kind -> how many

/datum/gl_rec
	var/born
	var/died
	var/list/times = list()
	var/list/glides = list()
	var/list/places = list()
	var/had_emitter = FALSE

/proc/gl_watch(atom/movable/AM, label)
	var/datum/gl_rec/R = new
	R.born = world.time
	GLOB.gl_watch[AM] = R
	if(!GLOB.gl_log[label])
		GLOB.gl_log[label] = list()
	GLOB.gl_log[label] += R
	return R

/atom/movable/Moved(atom/OldLoc, Dir, Forced = FALSE)
	. = ..()
	if(!length(GLOB.gl_watch))
		return
	var/datum/gl_rec/R = GLOB.gl_watch[src]
	if(!R || !isturf(loc))
		return
	R.places += "[world.time - R.born]:[x],[y][moving_diagonally ? "d" : ""][OldLoc == loc ? "=" : ""]"
	if(OldLoc == loc)
		return //a forceMove() on the spot (forced movement ending does one, to slip again): not a step
	if(length(R.times) && R.times[length(R.times)] == world.time)
		return //the second half of a diagonal step
	R.times += world.time
	R.glides += glide_size
	if(length(R.times) == 1)
		R.had_emitter = !!(locate(/obj/effect/particle_fx) in vis_contents)

/atom/movable/Destroy(force)
	if(length(GLOB.gl_watch))
		var/datum/gl_rec/R = GLOB.gl_watch[src]
		if(R)
			R.died = world.time
			GLOB.gl_watch -= src
	return ..()

/obj/effect/particle_effect/Initialize()
	. = ..()
	var/label = GLOB.gl_auto[type]
	if(label)
		gl_watch(src, label)

/obj/effect/particle_fx/burst/Initialize(mapload, kind, at_x = 0, at_y = 0)
	. = ..()
	if(kind)
		GLOB.gl_bursts[kind] = (GLOB.gl_bursts[kind] || 0) + 1

/proc/gl_note(ok, text)
	GLOB.glide_check_lines += "[ok ? "PASS" : "FAIL"] [text]"
	if(!ok)
		GLOB.glide_check_fails++

/proc/gl_median(list/L)
	if(!length(L))
		return "-"
	var/list/S = sortList(L.Copy(), GLOBAL_PROC_REF(cmp_numeric_asc))
	return S[round((length(S) + 1) / 2)]

/proc/gl_clear(turf/T)
	return istype(T, /turf/open/floor) && !T.density && T.has_gravity() && !(locate(/obj/structure) in T) && !(locate(/obj/machinery) in T) && !(locate(/mob) in T)

/proc/gl_far_from_used(turf/T)
	for(var/turf/U as anything in GLOB.gl_used)
		if(U.z == T.z && get_dist(U, T) < 5)
			return FALSE
	return TRUE

/// A floor tile with `len` clear floor tiles east of it, away from the lanes used already
/proc/gl_lane(len)
	GLOB.gl_used.Cut() //one test at a time: only the spark spots need keeping apart
	for(var/turf/open/floor/T in GLOB.station_turfs)
		var/clear = TRUE
		for(var/dx in 0 to len)
			var/turf/along = locate(T.x + dx, T.y, T.z)
			if(!gl_clear(along) || !gl_far_from_used(along))
				clear = FALSE
				break
		if(!clear)
			continue
		for(var/dx in 0 to len)
			GLOB.gl_used += locate(T.x + dx, T.y, T.z)
		return T

/// A floor tile with clear floor `radius` tiles round it every way
/proc/gl_spot(radius)
	for(var/turf/open/floor/T in GLOB.station_turfs)
		if(!gl_far_from_used(T))
			continue
		var/clear = TRUE
		for(var/turf/near in range(radius, T))
			if(!gl_clear(near))
				clear = FALSE
				break
		if(clear)
			GLOB.gl_used += T
			return T

/// One line for a label: the gaps between steps against the glides, in ticks
/proc/gl_report(label, show_tail = FALSE, reference = FALSE)
	var/list/recs = GLOB.gl_log[label]
	if(!length(recs))
		gl_note(FALSE, "[label]: nothing watched")
		return
	var/steps = 0
	var/list/gaps = list()
	var/list/glide_ticks = list()
	var/list/offs = list()
	var/list/firsts = list()
	var/list/tails = list()
	var/emitters = 0
	for(var/datum/gl_rec/R as anything in recs)
		if(R.had_emitter)
			emitters++
		var/n = length(R.times)
		steps += n
		if(!n)
			continue
		firsts += round((R.times[1] - R.born) / world.tick_lag)
		if(R.died && show_tail)
			tails += round((R.died - R.times[n]) / world.tick_lag)
		for(var/i in 2 to n)
			var/gap = round((R.times[i] - R.times[i - 1]) / world.tick_lag)
			var/covers = CEILING(world.icon_size / max(R.glides[i - 1], 0.01), 1) //the glide a step starts is the one that has to last to the next
			gaps += gap
			glide_ticks += covers
			offs += abs(covers - gap)
	var/text = "[label]: [length(recs)] movers, [steps] steps; gap [gl_median(gaps)] ticks, glide covers [gl_median(glide_ticks)], off by [gl_median(offs)]; first step after [gl_median(firsts)]"
	if(length(tails))
		text += ", gone [gl_median(tails)] ticks after its last step"
	if(emitters)
		text += ", [emitters] carrying a particle emitter"
	if(!length(offs))
		GLOB.glide_check_lines += "  -- [text] (no second step)"
		return
	if(reference)
		GLOB.glide_check_lines += "  -- [text] (for reference: tg's default glide)"
		return
	gl_note(gl_median(offs) <= 1, text)

/proc/run_glide_check()
	sleep(5 SECONDS)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/round_deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < round_deadline)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	GLOB.glide_check_lines += "tick_lag [world.tick_lag], icon_size [world.icon_size]"

	// The effect systems
	GLOB.gl_auto[/obj/effect/particle_effect/sparks] = "sparks"
	for(var/i in 1 to 4)
		var/turf/T = gl_spot(2)
		if(T)
			do_sparks(8, FALSE, T)
		sleep(3 SECONDS)
	gl_report("sparks", TRUE)
	var/list/bursts = list()
	for(var/kind in GLOB.gl_bursts)
		bursts += "[kind] [GLOB.gl_bursts[kind]]"
	GLOB.glide_check_lines += "     particle bursts left behind: [length(bursts) ? jointext(bursts, ", ") : "none"]"

	GLOB.gl_auto[/obj/effect/particle_effect/steam] = "steam"
	GLOB.gl_used.Cut()
	for(var/i in 1 to 2)
		var/turf/T = gl_spot(2)
		if(T)
			var/datum/effect_system/steam_spread/S = new
			S.set_up(8, FALSE, T)
			S.start()
		sleep(3 SECONDS)
	gl_report("steam", TRUE)

	GLOB.gl_auto[/obj/effect/particle_effect/expl_particles] = "blast fragments"
	GLOB.gl_used.Cut()
	for(var/i in 1 to 2)
		var/turf/T = gl_spot(2)
		if(T)
			var/datum/effect_system/explosion/E = new
			E.set_up(T)
			E.start()
		sleep(3 SECONDS)
	gl_report("blast fragments", TRUE)

	// BYOND's own walk_to() at the delays the game uses, with the default glide and with DELAY_TO_GLIDE_SIZE(lag)
	for(var/lag in list(0, 0.7, 1, 3, 4, 5))
		for(var/matched in list(FALSE, TRUE))
			var/turf/T = gl_lane(9)
			if(!T)
				gl_note(FALSE, "no lane for walk_to lag [lag]")
				continue
			var/obj/item/crowbar/C = new(T)
			if(matched)
				C.set_glide_size(DELAY_TO_GLIDE_SIZE(lag))
			var/label = "walk_to lag [lag], glide [matched ? "DELAY_TO_GLIDE_SIZE(lag)" : "default"]"
			gl_watch(C, label)
			walk_to(C, locate(T.x + 8, T.y, T.z), 0, lag)
			sleep(lag * 8 + 1 SECONDS)
			walk(C, 0)
			gl_report(label, reference = !matched)
			qdel(C)

	// A spiderling skittering off (its own process())
	var/turf/spider_spot = gl_spot(3)
	if(spider_spot)
		for(var/i in 1 to 3)
			var/obj/structure/spider/spiderling/S = new(spider_spot)
			STOP_PROCESSING(SSobj, S)
			var/datum/gl_rec/R = gl_watch(S, "spiderling")
			for(var/tries in 1 to 30)
				S.process()
				sleep(1 SECONDS)
				if(length(R.times) >= 3)
					break
			walk(S, 0)
			qdel(S)
	gl_report("spiderling")

	// The immovable rod and a meteor
	var/turf/rod_lane = gl_lane(10)
	if(rod_lane)
		var/obj/effect/immovablerod/rod = new(rod_lane, locate(rod_lane.x + 10, rod_lane.y, rod_lane.z))
		gl_watch(rod, "immovable rod")
		sleep(3 SECONDS)
		if(!QDELETED(rod))
			qdel(rod)
	gl_report("immovable rod")

	var/turf/meteor_lane = gl_lane(10)
	if(meteor_lane)
		var/obj/effect/meteor/dust/M = new(meteor_lane, locate(meteor_lane.x + 10, meteor_lane.y, meteor_lane.z))
		gl_watch(M, "meteor")
		sleep(3 SECONDS)
		if(!QDELETED(M))
			qdel(M)
	gl_report("meteor")

	// A conveyor carrying someone who walked on to it at a run
	var/turf/belt_lane = gl_lane(9)
	if(belt_lane)
		var/list/belts = list()
		for(var/dx in 0 to 9)
			belts += new /obj/machinery/conveyor/auto(locate(belt_lane.x + dx, belt_lane.y, belt_lane.z), EAST)
		var/mob/living/carbon/human/rider = new(belt_lane)
		rider.set_glide_size(DELAY_TO_GLIDE_SIZE(1))
		gl_watch(rider, "conveyor rider")
		sleep(3 SECONDS)
		qdel(rider)
		for(var/obj/B in belts)
			qdel(B)
	gl_report("conveyor rider")

	// A crew bot going down a hall at a run, and one at a walk
	for(var/walking in list(FALSE, TRUE))
		var/turf/crew_lane = gl_lane(10)
		if(!crew_lane)
			continue
		var/label = walking ? "crew bot slowed" : "crew bot running"
		var/mob/living/carbon/human/H = new(crew_lane)
		H.equipOutfit(/datum/outfit/bot_gym)
		H.mind_initialize()
		if(walking)
			H.add_movespeed_modifier("glide_check_slow", multiplicative_slowdown = 3)
		var/datum/bot_brain/brain = new(H)
		brain.gym_scripted = TRUE
		brain.diligence = 1
		gl_watch(H, label)
		brain.pursue(locate(crew_lane.x + 10, crew_lane.y, crew_lane.z), "wander", force = TRUE)
		sleep(walking ? 6 SECONDS : 4 SECONDS)
		qdel(brain)
		qdel(H)
		gl_report(label)

	// A cleanbot along a path (bot_move()), and a secbot running someone down (walk_to() lag 4)
	var/turf/clean_lane = gl_lane(8)
	if(clean_lane)
		var/mob/living/simple_animal/bot/cleanbot/B = new(clean_lane)
		B.turn_off()
		var/list/route = list()
		for(var/dx in 1 to 8)
			route += locate(clean_lane.x + dx, clean_lane.y, clean_lane.z)
		B.set_path(route)
		gl_watch(B, "cleanbot")
		B.bot_move(route[length(route)], 8)
		sleep(4 SECONDS)
		qdel(B)
	gl_report("cleanbot")

	var/turf/sec_lane = gl_lane(9)
	if(sec_lane)
		var/mob/living/carbon/human/perp = new(locate(sec_lane.x + 9, sec_lane.y, sec_lane.z))
		var/mob/living/simple_animal/bot/secbot/S = new(sec_lane)
		S.target = perp
		S.mode = BOT_HUNT
		gl_watch(S, "secbot")
		for(var/i in 1 to 4)
			if(S.mode != BOT_HUNT)
				break
			S.handle_automated_action()
			sleep(1 SECONDS)
		walk(S, 0)
		qdel(S)
		qdel(perp)
	gl_report("secbot")

	// Mechs driven east, the controls tried every tick as a held key does
	for(var/mech_type in list(/obj/mecha/combat/durand, /obj/mecha/working/ripley))
		var/turf/mech_lane = gl_lane(10)
		if(!mech_lane)
			continue
		var/obj/mecha/M = new mech_type(mech_lane)
		M.setDir(EAST)
		var/label = "mech [M.name] (step_in [M.step_in])"
		gl_watch(M, label)
		var/until = world.time + 3 SECONDS
		while(world.time < until && !QDELETED(M))
			M.domove(EAST)
			sleep(world.tick_lag)
		gl_report(label)
		qdel(M)

	// Forced movement: a lube slide (a tile a decisecond) and a hook's pull (5 a decisecond), 8 tiles each
	for(var/rate in list(1, 5))
		var/turf/slide_lane = gl_lane(10)
		if(!slide_lane)
			continue
		var/mob/living/carbon/human/H = new(slide_lane)
		var/label = "forced movement, [rate] a decisecond"
		var/datum/gl_rec/R = gl_watch(H, label)
		new /datum/forced_movement(H, locate(slide_lane.x + 8, slide_lane.y, slide_lane.z), rate, FALSE)
		sleep(3 SECONDS)
		gl_report(label)
		var/took = length(R.times) ? (R.times[length(R.times)] - R.born) : 0
		gl_note(H.x - slide_lane.x == 8 && abs(took - 8 / rate) <= 0.5, "[label]: went [H.x - slide_lane.x] tiles in [took] deciseconds (8 in [8 / rate] wanted)")
		GLOB.glide_check_lines += "     lane starts [slide_lane.x],[slide_lane.y]; steps (time:x,y): [jointext(R.places, " ")]"
		qdel(H)

	// An extinguisher's water, and the office chair it pushes someone along on
	GLOB.gl_auto[/obj/effect/particle_effect/water] = "extinguisher water"
	var/turf/water_lane = gl_lane(9)
	if(water_lane)
		var/mob/living/carbon/human/H = new(water_lane)
		var/obj/item/extinguisher/E = new(water_lane)
		E.safety = FALSE
		H.put_in_hands(E)
		E.afterattack(locate(water_lane.x + 9, water_lane.y, water_lane.z), H, FALSE)
		sleep(3 SECONDS)
		qdel(E)
		qdel(H)
	gl_report("extinguisher water")
	GLOB.gl_auto -= /obj/effect/particle_effect/water

	var/turf/chair_lane = gl_lane(10)
	if(chair_lane)
		var/turf/seat = locate(chair_lane.x + 10, chair_lane.y, chair_lane.z)
		var/mob/living/carbon/human/H = new(seat)
		var/obj/structure/chair/office/C = new(seat)
		C.buckle_mob(H, TRUE)
		var/obj/item/extinguisher/E = new(seat)
		E.safety = FALSE
		H.put_in_hands(E)
		gl_watch(C, "extinguisher chair ride")
		E.afterattack(locate(seat.x + 3, seat.y, seat.z), H, FALSE)
		sleep(4 SECONDS)
		qdel(E)
		qdel(H)
		qdel(C)
	gl_report("extinguisher chair ride")

	// A spray bottle's puff
	var/turf/spray_lane = gl_lane(6)
	if(spray_lane)
		var/mob/living/carbon/human/H = new(spray_lane)
		var/obj/item/reagent_containers/spray/cleaner/S = new(spray_lane)
		H.put_in_hands(S)
		S.spray(locate(spray_lane.x + 6, spray_lane.y, spray_lane.z), H)
		var/obj/effect/decal/chempuff/D = locate() in range(1, spray_lane)
		if(D)
			gl_watch(D, "spray puff")
		sleep(2 SECONDS)
		qdel(S)
		qdel(H)
	gl_report("spray puff")

	GLOB.gl_watch.Cut()
	var/list/out = GLOB.glide_check_lines.Copy()
	out += "[GLOB.glide_check_fails] FAIL"
	text2file(jointext(out, "\n"), "data/glide_check.txt")
