// Explosions on a crewed station, timed (boom-drill=<what> on a Bot Shift, tools/bot_gym/run_shift_batch.sh): five minutes in, at the
// middle of the station, one of
//  maxcap     one bomb at the cap (BOMBCAP)
//  maxcap6    six of them on the same tile at once
//  superboom  1000 units of N-amino azidotetrazole going off, past the cap the way a reagent explosion goes
//  tesla      an energy ball loose with five mini-balls, for the three minutes after
//  nuke       what a nuke on the station does: every station tile hit and everybody on the level gibbed (the cinematic left out)
//  cascade    a cascade charge, or any of the cascade grenades by its last path part (firestorm, wave, fuelair...), primed where it
//             lies (hippiestation/code/game/objects/items/grenades/cascade.dm)
// Every tick's real length is kept from 20 seconds before to 3 minutes after, through timewarp's own clock: the longest tick is the
// freeze players feel, and the time over the ticks before is what it cost in all. What it destroyed is counted, to tell a faster build
// from one that does less.

#define BOOM_BASELINE (20 SECONDS)
#define BOOM_AFTER (3 MINUTES)
/// How far round the epicentre tiles are compared, before and after.
#define BOOM_SURVEY 50

GLOBAL_DATUM(boom_drill, /datum/boom_drill)

/datum/boom_drill
	var/what
	var/turf/epicenter
	var/event_time = 0
	var/sample_until = 0
	// ticks: real milliseconds each
	var/baseline_ms = 0
	var/baseline_ticks = 0
	var/after_ms = 0
	var/after_ticks = 0
	var/worst_ms = 0
	var/worst_at = 0
	var/over_100 = 0
	var/over_1000 = 0
	// the explosion machinery itself
	var/explode_ms = 0
	var/explode_calls = 0
	var/fire_ms = 0
	var/fire_worst_ms = 0
	var/fire_calls = 0
	// what it did
	var/list/turf_types_before
	var/humans_dead_before = 0
	/// weakref of every human in the survey square = their damage before (brute, burn, toxin, oxygen)
	var/list/damage_before
	/// the most humans in the square down (stunned, knocked down, paralysed or out) or on fire at once, in the first minute
	var/peak_down = 0
	var/peak_burning = 0

/datum/bot_shift/proc/boom_drill(what)
	var/datum/boom_drill/D = new
	D.what = what
	GLOB.boom_drill = D
	D.go(src)

/datum/boom_drill/proc/go(datum/bot_shift/shift)
	epicenter = boom_middle()
	if(!epicenter)
		shift.note("boom drill: no middle of the station found")
		return
	event_time = world.time + BOOM_BASELINE
	sample_until = event_time + BOOM_AFTER
	INVOKE_ASYNC(src, PROC_REF(sample))
	sleep(BOOM_BASELINE)
	survey_before()
	shift.note("boom drill: [what] at [AREACOORD(epicenter)]")
	log_game("BOOM DRILL: [what] at [AREACOORD(epicenter)]")
	switch(what)
		if("maxcap")
			explosion(epicenter, GLOB.MAX_EX_DEVESTATION_RANGE, GLOB.MAX_EX_HEAVY_RANGE, GLOB.MAX_EX_LIGHT_RANGE, GLOB.MAX_EX_FLASH_RANGE)
		if("maxcap6")
			for(var/i in 1 to 6)
				explosion(epicenter, GLOB.MAX_EX_DEVESTATION_RANGE, GLOB.MAX_EX_HEAVY_RANGE, GLOB.MAX_EX_LIGHT_RANGE, GLOB.MAX_EX_FLASH_RANGE)
		if("superboom")
			var/datum/effect_system/reagents_explosion/E = new //what superboom's own on_ex_act() does with its volume
			E.set_up(1000, epicenter, 0, 0, message = 0)
			E.start()
		if("tesla")
			var/obj/singularity/energy_ball/ball = new(epicenter, 200)
			for(var/i in 1 to 5)
				ball.new_mini_ball()
		if("nuke")
			SSticker.station_explosion_detonation(null)
			INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(KillEveryoneOnZLevel), epicenter.z)
		else
			var/grenade_type = what == "cascade" ? /obj/item/grenade/cascade : text2path("/obj/item/grenade/cascade/[what]")
			if(!ispath(grenade_type, /obj/item/grenade/cascade))
				shift.note("boom drill: no drill called [what]")
				return
			var/obj/item/grenade/cascade/G = new grenade_type(epicenter)
			G.prime()
	UNTIL(world.time >= sample_until)
	shift.note(report())
	log_game("BOOM DRILL: [report()]")
	text2file(report(), "[world.params["bot-results"]]boom.txt")

/// The middle of the station: the open floor nearest the middle of the station's tiles.
/datum/boom_drill/proc/boom_middle()
	var/sx = 0
	var/sy = 0
	var/n = 0
	var/z
	for(var/turf/T as anything in GLOB.station_turfs)
		sx += T.x
		sy += T.y
		n++
		z = T.z
	if(!n)
		return null
	var/turf/middle = locate(round(sx / n), round(sy / n), z)
	var/turf/best
	for(var/turf/open/floor/F in range(15, middle))
		if(!best || get_dist(F, middle) < get_dist(best, middle))
			best = F
	return best

/datum/boom_drill/proc/survey_area()
	return what == "nuke" ? GLOB.station_turfs : block(locate(max(1, epicenter.x - BOOM_SURVEY), max(1, epicenter.y - BOOM_SURVEY), epicenter.z), locate(min(world.maxx, epicenter.x + BOOM_SURVEY), min(world.maxy, epicenter.y + BOOM_SURVEY), epicenter.z))

/datum/boom_drill/proc/survey_before()
	turf_types_before = list()
	for(var/turf/T as anything in survey_area())
		turf_types_before[T] = T.type
	damage_before = list()
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.stat == DEAD)
			humans_dead_before++
		else if(in_survey(H))
			damage_before[WEAKREF(H)] = boom_damage(H)

/datum/boom_drill/proc/in_survey(atom/A)
	var/turf/T = get_turf(A)
	return T && T.z == epicenter.z && get_dist(T, epicenter) <= BOOM_SURVEY

/proc/boom_damage(mob/living/L)
	return L.getBruteLoss() + L.getFireLoss() + L.getToxLoss() + L.getOxyLoss()

/// How many humans in the survey square are down, and on fire, right now.
/datum/boom_drill/proc/count_down()
	var/down = 0
	var/burning = 0
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.stat == DEAD || !in_survey(H))
			continue
		if(H.stat == UNCONSCIOUS || H.IsStun() || H.IsKnockdown() || H.IsParalyzed() || H.IsUnconscious())
			down++
		if(H.on_fire)
			burning++
	peak_down = max(peak_down, down)
	peak_burning = max(peak_burning, burning)

/datum/boom_drill/proc/sample()
	var/last = timewarp_real_ms()
	while(world.time < sample_until)
		sleep(world.tick_lag)
		var/now = timewarp_real_ms()
		var/gap = now - last
		last = now
		if(world.time < event_time)
			baseline_ms += gap
			baseline_ticks++
			continue
		after_ms += gap
		after_ticks++
		if(world.time - event_time <= 1 MINUTES && !((after_ticks - 1) % 10))
			count_down()
		if(gap > worst_ms)
			worst_ms = gap
			worst_at = world.time - event_time
		if(gap > 100)
			over_100++
		if(gap > 1000)
			over_1000++

/datum/boom_drill/proc/report()
	var/changed = 0
	var/space = 0
	for(var/turf/T as anything in turf_types_before)
		if(T.type != turf_types_before[T])
			changed++
			if(isspaceturf(T))
				space++
	var/humans_dead = -humans_dead_before
	var/humans_gone = 0
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.stat == DEAD)
			humans_dead++
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(QDELETED(B.owner))
			humans_gone++
	var/hurt = 0
	var/damage_dealt = 0
	for(var/datum/weakref/W as anything in damage_before)
		var/mob/living/carbon/human/H = W.resolve()
		var/dealt = H ? boom_damage(H) - damage_before[W] : 0
		if(!H || H.stat == DEAD || dealt > 20)
			hurt++
		damage_dealt += max(0, dealt)
	var/per_tick = baseline_ticks ? baseline_ms / baseline_ticks : 0
	var/extra = after_ms - per_tick * after_ticks
	return "boom drill [what]: worst tick [round(worst_ms)] ms at +[round(worst_at / 10, 0.1)]s, [over_100] ticks over 100 ms, [over_1000] over a second; \
		[round(extra / 1000, 0.1)] s more than the ticks before ([round(per_tick, 0.1)] ms a tick then) over [BOOM_AFTER / 10] s; \
		explode() [explode_calls]x [round(explode_ms)] ms, SSexplosions [fire_calls] fires [round(fire_ms)] ms (worst [round(fire_worst_ms)]); \
		[changed] tiles changed ([space] to space), [humans_dead] more dead, [humans_gone] bots' bodies gone; \
		[hurt] of [length(damage_before)] near hurt or dead ([round(damage_dealt)] damage), most down at once [peak_down], most on fire [peak_burning]"

// The explosion machinery's own share, while a drill's running.
/datum/controller/subsystem/explosions/explode(atom/epicenter, devastation_range, heavy_impact_range, light_impact_range, flash_range, adminlog, ignorecap, flame_range, silent, smoke, atom/explosion_cause)
	var/datum/boom_drill/D = GLOB.boom_drill
	if(!D)
		return ..()
	var/start = timewarp_real_ms()
	. = ..()
	D.explode_ms += timewarp_real_ms() - start
	D.explode_calls++

/datum/controller/subsystem/explosions/fire(resumed)
	var/datum/boom_drill/D = GLOB.boom_drill
	if(!D || !is_exploding())
		return ..()
	var/start = timewarp_real_ms()
	..()
	var/took = timewarp_real_ms() - start
	D.fire_ms += took
	D.fire_worst_ms = max(D.fire_worst_ms, took)
	D.fire_calls++

#undef BOOM_BASELINE
#undef BOOM_AFTER
#undef BOOM_SURVEY
