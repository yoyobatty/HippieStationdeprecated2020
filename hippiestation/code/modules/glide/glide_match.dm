// Things that step on their own, on a timer, with the glide set to match. glide_size is how many pixels a movable slides each
// tick. tg leaves it at 8, which covers a tile in 4 ticks, a tenth of a second at 40 ticks a second. Something that steps every
// four tenths darts across in one and sits for three. The hooks here set the glide to cover a tile in the time to the next step,
// as client/Move() does for a player and tg's move loops do today (DELAY_TO_GLIDE_SIZE). The ones inside long tg procs are marked
// there instead (hippiestation/changes.md). Sparks, steam and lightning: effect_system/effect_system.dm.
// tools/glide_check measures them: the gap between steps against the time the glide takes.

// ---- Bots. A patrol steps every BOT_STEP_DELAY (bot_move()), and secbots, Beepsky, honkbots and ED-209s chase at walk_to() lag 4,
// which is the same. A MULE steps every 2.
/mob/living/simple_animal/bot/handle_automated_action()
	set_glide_size(DELAY_TO_GLIDE_SIZE(BOT_STEP_DELAY))
	return ..()

/mob/living/simple_animal/bot/mulebot/process_bot()
	set_glide_size(DELAY_TO_GLIDE_SIZE(2))
	return ..()

// ---- Mechs. A held key tries the controls every tick, and a step goes through the tick after step_in has run out (domove()'s
// can_move check is >=). A pilot mob walks its mech with walk_to() at step_in.
/obj/mecha/domove(direction)
	set_glide_size(DELAY_TO_GLIDE_SIZE(step_in + world.tick_lag))
	return ..()

/mob/living/simple_animal/hostile/syndicate/mecha_pilot/Goto(target, delay, minimum_distance)
	if(mecha)
		mecha.set_glide_size(DELAY_TO_GLIDE_SIZE(mecha.step_in))
	return ..()

// ---- Sealed vehicles (the clown car, the fire truck): a step every movedelay while the key is held. Ridden ones set their own in
// the riding component.
/obj/vehicle/vehicle_move(direction)
	var/glide = DELAY_TO_GLIDE_SIZE(movedelay)
	set_glide_size(glide)
	trailer?.set_glide_size(glide)
	return ..()

// ---- Conveyors carry what's on them a tile each SSfastprocess fire
/obj/machinery/conveyor/convey(list/affecting)
	var/glide = DELAY_TO_GLIDE_SIZE(SSfastprocess.wait)
	for(var/atom/movable/AM in affecting)
		if(!AM.anchored)
			AM.set_glide_size(glide)
	return ..()

// ---- Parrots fly about at walk_to() lag parrot_speed
/mob/living/simple_animal/parrot/handle_automated_movement()
	set_glide_size(DELAY_TO_GLIDE_SIZE(parrot_speed))
	return ..()

// ---- An extinguisher's water steps every 2. The chair it pushes slows down: steps 1, 1, 1, 2, 2, 3, 3, 3, 3 apart (move_chair()).
/obj/item/extinguisher/move_particles(list/particles, repetition = 0)
	var/glide = DELAY_TO_GLIDE_SIZE(2)
	for(var/obj/effect/particle_effect/water/W in particles)
		W.set_glide_size(glide)
	return ..()

/obj/item/extinguisher/move_chair(obj/B, movementdirection, repetition = 0)
	B?.set_glide_size(DELAY_TO_GLIDE_SIZE(repetition <= 2 ? 1 : (repetition <= 4 ? 2 : 3)))
	return ..()

// ---- A spray bottle's puff steps every wait_step
/obj/item/reagent_containers/spray/do_spray(atom/A, wait_step, obj/effect/decal/chempuff/D, range, puff_reagent_left, mob/user)
	D?.set_glide_size(DELAY_TO_GLIDE_SIZE(wait_step))
	return ..()

// ---- Forced movement: a lube slide, a hook's pull, a larva knocked away. tg moved these on SSfastprocess, every 2 deciseconds,
// so a slide at a tile a decisecond took two tiles in the same tick, and only the second glides. Here each one has a timer of its
// own, one step a time with the glide set to match. Steps owed are carried over, so a hook's 5 a decisecond stays 5.
/datum/forced_movement
	var/step_timer
	var/steps_owed = 0

/datum/forced_movement/New(atom/movable/_victim, atom/_target, _steps_per_tick = 0.5, _allow_climbing = FALSE, datum/callback/_on_step = null)
	. = ..()
	if(QDELETED(src) || victim?.force_moving != src)
		return
	STOP_PROCESSING(SSfastprocess, src)
	victim.set_glide_size(DELAY_TO_GLIDE_SIZE(forced_step_delay()))
	step_timer = addtimer(CALLBACK(src, PROC_REF(forced_step)), forced_step_delay(), TIMER_STOPPABLE)

/datum/forced_movement/Destroy()
	if(step_timer)
		deltimer(step_timer)
		step_timer = null
	return ..()

/// Deciseconds between steps: a tick at the fastest
/datum/forced_movement/proc/forced_step_delay()
	return max(world.tick_lag, 1 / steps_per_tick)

/datum/forced_movement/proc/forced_step()
	step_timer = null
	if(QDELETED(victim) || !victim.loc || QDELETED(target) || !target.loc)
		qdel(src)
		return
	steps_owed += steps_per_tick * forced_step_delay()
	var/steps = round(steps_owed)
	steps_owed -= steps
	for(var/i in 1 to steps)
		if(!TryMove())
			qdel(src)
			return
		moved_at_all = TRUE
		on_step?.InvokeAsync()
	if(QDELETED(src))
		return
	victim.set_glide_size(DELAY_TO_GLIDE_SIZE(forced_step_delay()))
	step_timer = addtimer(CALLBACK(src, PROC_REF(forced_step)), forced_step_delay(), TIMER_STOPPABLE)
