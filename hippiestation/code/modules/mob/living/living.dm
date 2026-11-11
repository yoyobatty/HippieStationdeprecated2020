/* This is currently only supported for monkeys */
/mob/living/proc/hippie_equip_mob_with_items(rand_int)
	return

/datum/thrownthing
	/// The zone this throw hit, rolled once by throw_hit_zone() so the hit and an embed land in the same limb
	var/hit_zone

/// Where a thrown thing hits: the zone its thrower aimed at, with melee's accuracy (ran_zone, 80%); a throw nobody aimed
/// (thrown by a machine, an explosion) keeps the old chest-weighted roll. Rolled once per throw: a human's embed check and
/// the hit's damage both read it, so the thing lodges in the limb it hurt.
/mob/living/proc/throw_hit_zone(datum/thrownthing/throwingdatum)
	if(throwingdatum?.hit_zone)
		return throwingdatum.hit_zone
	var/mob/thrower = throwingdatum?.thrower
	var/zone
	if(istype(thrower) && thrower.zone_selected)
		zone = ran_zone(thrower.zone_selected)
	else
		zone = ran_zone(BODY_ZONE_CHEST, 65)
	if(throwingdatum)
		throwingdatum.hit_zone = zone
	return zone

/mob/living/resist_grab(moving_resist)
	if(pulledby.grab_state)
		if(prob(pulledby.grab_state >= GRAB_KILL ? 10 : 30)) // a strangling grab could never be broken; 10% a try now (user, 2026-11-10)
			visible_message("<span class='danger'>[src] has broken free of [pulledby]'s grip!</span>")
			log_combat(pulledby, src, "broke grab")
			pulledby.stop_pulling()
			return FALSE
		if(moving_resist && client) //we resisted by trying to move
			client.move_delay = world.time + 20
	else
		pulledby.stop_pulling()

// Godmode already blocks the damage from being on fire (see damage_procs.dm), but nothing stopped a godmode mob from
// visibly catching fire in the first place (the "on_fire" flag, the fire overlay, the alert icon). This stops it at the source.
/mob/living/IgniteMob()
	if(status_flags & GODMODE)
		return FALSE
	return ..()

/mob/living/proc/canGhost()
	return TRUE

/mob/living/proc/canSuccumb()
	return TRUE

/mob/living/proc/do_pindown(atom/A, tog=1)
	var/pixel_x_diff = 0
	var/pixel_y_diff = 0
	var/direction = get_dir(src, A)
	switch(direction)
		if(NORTH)
			pixel_y_diff = 8
		if(SOUTH)
			pixel_y_diff = -8
		if(EAST)
			pixel_x_diff = 8
		if(WEST)
			pixel_x_diff = -8
		if(NORTHEAST)
			pixel_x_diff = 8
			pixel_y_diff = 8
		if(NORTHWEST)
			pixel_x_diff = -8
			pixel_y_diff = 8
		if(SOUTHEAST)
			pixel_x_diff = 8
			pixel_y_diff = -8
		if(SOUTHWEST)
			pixel_x_diff = -8
			pixel_y_diff = -8
	if (tog)
		animate(src, pixel_x = pixel_x + pixel_x_diff, pixel_y = pixel_y + pixel_y_diff, time = 2)
	else
		animate(src, pixel_x = initial(pixel_x), pixel_y = initial(pixel_y), time = 2)
		setMovetype(movement_type & ~FLOATING) // If we were without gravity, the bouncing animation got stopped, so we make sure we restart the bouncing after the next movement.

/mob/living/Initialize()
	. = ..()
	update_transform()

//Called when we bump onto a mob
/mob/living/MobBump(mob/M)
	// Can't move with pinned people
	if (pinned_to || M.pinned_to)
		return TRUE

	var/turf/they_were_at = M.loc
	. = ..()
	// A player who walked into a bot and didn't get past: the bot steps aside (bots_ai/bot_chatter.dm walked_into_by()). Bots get round
	// each other on their own (bot_movement.dm).
	var/mob/living/carbon/human/me = src
	if(M.loc == they_were_at && ishuman(M) && istype(me) && !me.bot_brain)
		var/mob/living/carbon/human/H = M
		H.bot_brain?.walked_into_by(src)

/mob/living/proc/update_tts_hud()
	if (!hud_used)
		return
	if (!hud_used.tts)
		return
	hud_used.tts.icon_state = "tts_ready"

/mob/living/resist()
	..()
	if(pinned_to && last_special <= world.time) //escape cuffs pinned to a wall
		resist_restraints() //trying to remove cuffs.
