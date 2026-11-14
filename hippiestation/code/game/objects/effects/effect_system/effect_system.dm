// How sparks, steam and lightning (/datum/effect_system) move off. tg's version waited half a second, stepped a tile, and did that
// once to three times, with the glide left at 8. At 40 ticks a second a glide of 8 covers a tile in a tenth of a second, so each
// one darted a tile and sat for the other four tenths. A spark also sat for a second after its last step, until its 2 second timer.
// This follows tg today (effect_system.dm, effects_sparks.dm at 9b10c26d), without the move loop subsystem it uses: the glide
// covers a tile in the time to the next step, the first step is at once, and a spark is gone when it reaches its last tile.
// Sparks step every 0.35 seconds, two or three tiles, so they last about as long as their animation (0.7 seconds).
// tools/glide_check measures it.

/datum/effect_system
	/// Deciseconds between an effect's steps. Its glide is set to cover a tile in that time.
	var/step_delay = 5

/// How many tiles an effect goes
/datum/effect_system/proc/effect_steps()
	return pick(1, 2, 3)

/// An effect has gone as far as it goes, or was stopped
/datum/effect_system/proc/effect_done(obj/effect/E)
	return

/datum/effect_system/generate_effect()
	if(holder)
		location = get_turf(holder)
	var/obj/effect/E = new effect_type(location)
	total_effects++
	var/direction = pick(cardinals ? GLOB.cardinals : GLOB.alldirs)
	E.set_glide_size(DELAY_TO_GLIDE_SIZE(step_delay))
	var/steps = effect_steps()
	for(var/j in 1 to steps)
		if(QDELETED(E))
			break
		var/turf/from = E.loc
		step(E, direction)
		if(E.loc == from) //into a wall: seen for a moment, then done
			sleep(1)
			break
		sleep(step_delay)
	if(!QDELETED(E))
		effect_done(E)
	if(!QDELETED(src))
		addtimer(CALLBACK(src, PROC_REF(decrement_total_effect)), 20)

/datum/effect_system/spark_spread
	step_delay = 3.5

/datum/effect_system/spark_spread/effect_steps()
	return pick(2, 3) //tg: "never 1 cause 1 looks dumb"

/datum/effect_system/spark_spread/effect_done(obj/effect/E)
	qdel(E)
