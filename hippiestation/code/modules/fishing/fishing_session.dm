// The cast: the bobber, the line from the rod's tip to it that hangs and swings, the wait, the bite and the fight. From Paradise.

/// The float on the end of a cast line. It only shows where the hook is, clicks go through it to the water.
/obj/effect/abstract/fishing_bobber
	name = "bobber"
	desc = "A little float on the end of somebody's fishing line."
	icon = FISHING_ICON
	icon_state = "bobber"
	invisibility = 0
	layer = ABOVE_ALL_MOB_LAYER
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT

/// How many points the line is worked out at, ends included
#define FISHING_LINE_POINTS 11
/// How hard the line falls toward the bottom of the screen, in pixels a second squared
#define FISHING_LINE_GRAVITY 80
/// How much of its speed the line keeps from one step to the next
#define FISHING_LINE_DAMPING 0.86
/// Rounds of pulling the points back to the line's length each step. More makes it stiffer
#define FISHING_LINE_STIFFNESS 20
/// A line whose points move less than this between steps, in pixels, has settled and stops being worked out
#define FISHING_LINE_SETTLED 0.2

/**
 * The line from the rod's tip to the bobber: a rope that hangs, swings and settles.
 *
 * It's FISHING_LINE_POINTS points joined by links that can go slack but don't stretch. Each step the points keep
 * moving the way they were going, fall a little, and are pulled back together, with the ends pinned to the rod's tip
 * and the bobber (a Verlet rope, as in games). A slack line hangs in a curve, a strained one pulls straight, and
 * walking, turning, the cast, a bite or a fish running set it swinging. Once it has settled it isn't worked out until
 * something moves it again, so a line that's just waiting costs nothing.
 *
 * The links are short line sprites in this object's vis_contents, animated to their new places over each step, so
 * the line moves smoothly in between. It sits in the vis_contents of whatever holds the rod, so it moves with them.
 */
/obj/effect/abstract/fishing_line
	invisibility = 0
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	layer = ABOVE_ALL_MOB_LAYER
	// Not turned, tinted or faded with whoever holds the rod
	appearance_flags = KEEP_APART | RESET_COLOR | RESET_TRANSFORM | RESET_ALPHA
	/// The cast this is the line of
	var/datum/fishing_session/session
	/// Where each point is, in pixels across the map
	var/list/point_x
	var/list/point_y
	/// Where each point was a step ago, which is how fast it's moving
	var/list/last_x
	var/list/last_y
	/// The sprites drawing the links between the points
	var/list/obj/effect/abstract/fishing_line_piece/pieces = list()
	/// Is it being worked out? It stops once it has settled
	var/swinging = FALSE

/obj/effect/abstract/fishing_line/Initialize(mapload, datum/fishing_session/owner)
	. = ..()
	session = owner
	for(var/i in 1 to FISHING_LINE_POINTS - 1)
		pieces += new /obj/effect/abstract/fishing_line_piece(null, session.rod.line?.line_color)
	vis_contents += pieces

/obj/effect/abstract/fishing_line/Destroy()
	STOP_PROCESSING(SSfastprocess, src)
	vis_contents.Cut()
	QDEL_LIST(pieces)
	session = null
	return ..()

/// The rod's tip and where the line meets the bobber, in pixels across the map: list(tip x, tip y, end x, end y)
/obj/effect/abstract/fishing_line/proc/ends()
	var/atom/movable/body = session?.body
	var/obj/effect/abstract/fishing_bobber/bobber = session?.bobber
	if(!body || !bobber || body.z != bobber.z)
		return null
	var/list/tip = session.rod.tip_offset(body)
	var/list/float = session.bobber_offset()
	return list(body.x * world.icon_size + tip[1], body.y * world.icon_size + tip[2], bobber.x * world.icon_size + float[1], bobber.y * world.icon_size + float[2])

/// Something moved the line, so it's worked out again until it settles. The first time, it's laid out straight
/obj/effect/abstract/fishing_line/proc/disturb()
	var/list/ends = ends()
	if(!ends)
		return
	if(!point_x)
		point_x = list()
		point_y = list()
		for(var/i in 1 to FISHING_LINE_POINTS)
			var/along = (i - 1) / (FISHING_LINE_POINTS - 1)
			point_x += ends[1] + (ends[3] - ends[1]) * along
			point_y += ends[2] + (ends[4] - ends[2]) * along
		last_x = point_x.Copy()
		last_y = point_y.Copy()
		place_pieces(0)
	if(!swinging)
		swinging = TRUE
		START_PROCESSING(SSfastprocess, src)

/obj/effect/abstract/fishing_line/process(wait)
	var/list/ends = ends()
	if(!ends)
		swinging = FALSE
		return PROCESS_KILL
	var/seconds = wait * 0.1
	// The line is as long as the gap and a little slack, which strain takes up
	var/gap = sqrt((ends[3] - ends[1]) ** 2 + (ends[4] - ends[2]) ** 2)
	var/link = max(gap * (1 + session.line_slack()), 1) / (FISHING_LINE_POINTS - 1)
	var/fall = FISHING_LINE_GRAVITY * seconds * seconds
	var/shake = session.line_shake()
	// A bobber in flight is moved here, a step at a time along the same path as the end of the line, so they stay tied
	if(session.bobber_flying())
		animate(session.bobber, pixel_x = ends[3] - session.bobber.x * world.icon_size - 16, pixel_y = ends[4] - session.bobber.y * world.icon_size - 12, time = wait)
	for(var/i in 2 to FISHING_LINE_POINTS - 1)
		var/x = point_x[i]
		var/y = point_y[i]
		point_x[i] = x + (x - last_x[i]) * FISHING_LINE_DAMPING
		point_y[i] = y + (y - last_y[i]) * FISHING_LINE_DAMPING - fall
		// A strained line trembles
		if(shake)
			point_x[i] += (rand() * 2 - 1) * shake
			point_y[i] += (rand() * 2 - 1) * shake
		last_x[i] = x
		last_y[i] = y
	// The ends are held by the rod and the bobber
	point_x[1] = ends[1]
	point_y[1] = ends[2]
	point_x[FISHING_LINE_POINTS] = ends[3]
	point_y[FISHING_LINE_POINTS] = ends[4]
	for(var/round in 1 to FISHING_LINE_STIFFNESS)
		for(var/i in 1 to FISHING_LINE_POINTS - 1)
			var/dx = point_x[i + 1] - point_x[i]
			var/dy = point_y[i + 1] - point_y[i]
			var/dist = sqrt(dx * dx + dy * dy)
			// It goes slack, but it doesn't stretch
			if(dist <= link)
				continue
			var/pull = (dist - link) / dist
			// A pinned end doesn't move, so the point beside it takes all of the pull
			var/from_share = i == 1 ? 0 : (i + 1 == FISHING_LINE_POINTS ? 1 : 0.5)
			point_x[i] += dx * pull * from_share
			point_y[i] += dy * pull * from_share
			point_x[i + 1] -= dx * pull * (1 - from_share)
			point_y[i + 1] -= dy * pull * (1 - from_share)
	place_pieces(wait)
	var/moved = 0
	for(var/i in 2 to FISHING_LINE_POINTS - 1)
		moved = max(moved, abs(point_x[i] - last_x[i]) + abs(point_y[i] - last_y[i]))
	if(moved < FISHING_LINE_SETTLED && !session.line_busy())
		swinging = FALSE
		return PROCESS_KILL

/// Moves the line's sprites to where the points are, over `time`
/obj/effect/abstract/fishing_line/proc/place_pieces(time)
	// The sprites are drawn from the bottom left of the tile whoever holds the rod is on
	var/origin_x = session.body.x * world.icon_size
	var/origin_y = session.body.y * world.icon_size
	for(var/i in 1 to length(pieces))
		var/obj/effect/abstract/fishing_line_piece/piece = pieces[i]
		var/from_x = point_x[i] - origin_x
		var/from_y = point_y[i] - origin_y
		var/to_x = point_x[i + 1] - origin_x
		var/to_y = point_y[i + 1] - origin_y
		// The sprite is a line across the middle of the tile, 32 pixels long
		var/matrix/placed = matrix()
		placed.Scale(max(sqrt((to_x - from_x) ** 2 + (to_y - from_y) ** 2), 0.5) / 32, 1)
		placed.Turn(-arctan(to_x - from_x, to_y - from_y))
		placed.Translate((from_x + to_x) / 2 - 16, (from_y + to_y) / 2 - 16)
		if(time && piece.alpha)
			animate(piece, transform = placed, time = time)
		else
			piece.transform = placed
			piece.alpha = 255

/// One link of a fishing line: a short straight line sprite, turned and stretched into place
/obj/effect/abstract/fishing_line_piece
	icon = FISHING_ICON
	icon_state = "fishing_line_piece"
	invisibility = 0
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	// Kept to whole pixels when it's turned, so it stays a crisp line like the rest of the sprites
	appearance_flags = PIXEL_SCALE
	vis_flags = VIS_INHERIT_PLANE | VIS_INHERIT_LAYER | VIS_INHERIT_ID
	// Hidden until it's first put in place
	alpha = 0

/obj/effect/abstract/fishing_line_piece/Initialize(mapload, line_color)
	. = ..()
	color = line_color

#undef FISHING_LINE_POINTS
#undef FISHING_LINE_GRAVITY
#undef FISHING_LINE_DAMPING
#undef FISHING_LINE_STIFFNESS
#undef FISHING_LINE_SETTLED

/// One cast of a fishing rod: the wait for a bite, the pull, and the fight to reel the catch in.
/datum/fishing_session
	/// The rod that was cast
	var/obj/item/fishing_rod/rod
	/// The angler
	var/mob/living/user
	/// What the line comes out of: the angler, or the exosuit they're fishing from
	var/atom/movable/body
	/// The turf or object being fished in
	var/atom/target
	/// The kind of spot the target is
	var/datum/fishing_spot/spot
	/// The float sitting on the target
	var/obj/effect/abstract/fishing_bobber/bobber
	/// The line drawn from the rod's tip to the bobber
	var/obj/effect/abstract/fishing_line/line_visual
	/// When the bobber was cast, and how long it takes to fly out to the water
	var/cast_started = 0
	var/cast_time = 0
	/// Where the bobber starts its flight from, in pixels from where it lands, and how high it arcs on the way
	var/cast_from_x = 0
	var/cast_from_y = 0
	var/cast_arc = 0
	/// How far along the cast is, one of the FISHING_ stages
	var/state = FISHING_WAITING
	/// Timer for the next nibble or bite, or for the bite being missed
	var/next_timer
	/// How many more times the bobber twitches before something really bites
	var/nibbles_left = 0
	/// How long to wait between those twitches
	var/nibble_wait = 0

	/// What is on the hook, once something is
	var/datum/fishing_catch/hooked
	/// How long the catch is, in cm
	var/length_cm = 0
	/// How hard this one pulls, its kind's strength scaled by its size
	var/fight_strength = 0
	/// Seconds of running it has left before it's worn out
	var/stamina_left = 0
	/// What the fish is doing, one of the FISHING_FISH_ states
	var/fish_state = FISHING_FISH_RESTING
	/// Seconds until the fish does something else
	var/fish_state_time = 0
	/// Strain on the line. It snaps at FISHING_MAX_TENSION
	var/tension = 0
	/// How much line is still out, in tiles. The catch is landed at 0
	var/distance = 0
	/// The catch gets away if this much line is out
	var/max_distance = 0
	/// Is the angler winding the reel?
	var/reeling = FALSE

/datum/fishing_session/New(obj/item/fishing_rod/cast_rod, mob/living/angler, atom/cast_target, datum/fishing_spot/cast_spot)
	rod = cast_rod
	user = angler
	target = cast_target
	spot = cast_spot
	body = rod.angler_body(user)
	bobber = new(get_turf(target))
	line_visual = new(null, src)
	body.vis_contents += line_visual

	RegisterSignal(body, COMSIG_MOVABLE_MOVED, PROC_REF(on_user_moved))
	RegisterSignal(body, COMSIG_ATOM_DIR_CHANGE, PROC_REF(on_body_turned))
	RegisterSignal(bobber, COMSIG_PARENT_QDELETING, PROC_REF(on_spot_gone))
	if(isturf(target))
		RegisterSignal(target, COMSIG_TURF_CHANGE, PROC_REF(on_spot_gone))
	else
		RegisterSignal(target, COMSIG_PARENT_QDELETING, PROC_REF(on_spot_gone))

	user.visible_message("<span class='notice'>[user] casts [user.p_their()] line into [spot.name].</span>", "<span class='notice'>You cast your line into [spot.name].</span>")
	wait_for_bite()
	fly_bobber()

/**
 * Throws the bobber out from the rod's tip in an arc, the line paying out behind it, and splashes it down at the end.
 *
 * bobber_offset() works out where it is on the way, and the line moves the bobber there along with its own end.
 */
/datum/fishing_session/proc/fly_bobber()
	var/list/tip = rod.tip_offset(body)
	cast_from_x = body.x * world.icon_size + tip[1] - (bobber.x * world.icon_size + 16)
	cast_from_y = body.y * world.icon_size + tip[2] - (bobber.y * world.icon_size + 12)
	var/tiles = get_dist(body, bobber)
	cast_time = 4 + tiles * 1.2
	cast_arc = 8 + tiles * 3
	cast_started = world.time
	// Hanging off the line while it flies, it only floats once it's down
	bobber.icon_state = "bobber_dry"
	bobber.pixel_x = cast_from_x
	bobber.pixel_y = cast_from_y
	line_visual.disturb()
	addtimer(CALLBACK(src, PROC_REF(bobber_landed)), cast_time)

/datum/fishing_session/proc/bobber_landed()
	animate(bobber, pixel_x = 0, pixel_y = 0, time = 1)
	if(state == FISHING_WAITING)
		bobber.icon_state = bobber_state("")
	if(spot.splash_sound)
		playsound(bobber, spot.splash_sound, 40, TRUE)
	line_visual.disturb()

/// Is the bobber still flying out from the cast?
/datum/fishing_session/proc/bobber_flying()
	return world.time < cast_started + cast_time

/// Where the line meets the bobber, in pixels from the bottom left of its tile, following it while it flies out
/datum/fishing_session/proc/bobber_offset()
	var/flown = cast_time ? (world.time - cast_started) / cast_time : 1
	if(flown >= 1)
		return list(16, 12)
	// The same path as the animation: straight across, and up then down in two eased halves
	var/offset_x = cast_from_x * (1 - flown)
	var/top = cast_from_y / 2 + cast_arc
	var/offset_y
	if(flown < 0.5)
		offset_y = cast_from_y + (top - cast_from_y) * sin(flown * 2 * 90)
	else
		offset_y = top * cos((flown - 0.5) * 2 * 90)
	return list(16 + offset_x, 12 + offset_y)

/// Is the line being moved all the time? While it's flying out or something is fighting on it
/datum/fishing_session/proc/line_busy()
	return state == FISHING_FIGHT || bobber_flying()

/// How much longer than the gap to the bobber the line is, as a share of the gap. More hangs lower
/datum/fishing_session/proc/line_slack()
	// Paying out as it flies, so it trails nearly straight
	if(bobber_flying())
		return 0.02
	// The angler winds in most of the slack once the bobber's down
	switch(state)
		if(FISHING_WAITING)
			return 0.05
		if(FISHING_BITE)
			return 0.02
		if(FISHING_FIGHT)
			// Pulled straighter the harder it's strained
			return 0.03 * (1 - tension / FISHING_MAX_TENSION)
	return 0

/// How many pixels the line trembles each step, while something pulls hard on it
/datum/fishing_session/proc/line_shake()
	if(state != FISHING_FIGHT)
		return 0
	if(fish_state == FISHING_FISH_RUNNING)
		return 0.8
	return tension > 60 ? 0.4 : 0

/datum/fishing_session/proc/on_body_turned(datum/source, old_dir, new_dir)
	SIGNAL_HANDLER // COMSIG_ATOM_DIR_CHANGE
	// The tip moves to the other side as they turn, once the turn has happened
	addtimer(CALLBACK(line_visual, TYPE_PROC_REF(/obj/effect/abstract/fishing_line, disturb)), 0)

/// The bobber's icon state for a stage of the cast, floating or hanging depending on the spot
/datum/fishing_session/proc/bobber_state(stage)
	return spot.has_surface ? "bobber[stage]" : "bobber[stage]_dry"

/datum/fishing_session/Destroy()
	STOP_PROCESSING(SSfastprocess, src)
	deltimer(next_timer)
	if(rod)
		rod.session = null
		SStgui.close_uis(rod)
	if(bobber)
		UnregisterSignal(bobber, COMSIG_PARENT_QDELETING)
		QDEL_NULL(bobber)
	if(body)
		body.vis_contents -= line_visual
	QDEL_NULL(line_visual)
	rod = null
	user = null
	body = null
	target = null
	spot = null
	hooked = null
	return ..()

/// Can the angler still fish? They have to be up and holding the rod, or still in the exosuit that has it.
/datum/fishing_session/proc/angler_ready()
	return rod?.can_keep_fishing(user)

/datum/fishing_session/proc/on_user_moved(datum/source)
	SIGNAL_HANDLER // COMSIG_MOVABLE_MOVED
	// A couple of tiles of slack past the cast range, then the hook comes out
	if(body.z == bobber.z && get_dist(body, bobber) <= rod.line.cast_range + 2)
		line_visual.disturb()
		return
	to_chat(user, "<span class='warning'>Your line pulls tight and the hook comes loose.</span>")
	qdel(src)

/datum/fishing_session/proc/on_spot_gone(datum/source)
	SIGNAL_HANDLER // COMSIG_TURF_CHANGE, COMSIG_PARENT_QDELETING
	if(!QDELETED(user))
		to_chat(user, "<span class='warning'>Your line goes slack.</span>")
	qdel(src)

/// The rod left the angler's hands
/datum/fishing_session/proc/give_up(mob/living/quitter)
	if(state == FISHING_FIGHT)
		to_chat(quitter, "<span class='warning'>You let go of [rod] and whatever was on the line gets away.</span>")
	qdel(src)

// MARK: Waiting and the bite

/datum/fishing_session/proc/wait_for_bite()
	deltimer(next_timer)
	state = FISHING_WAITING
	bobber.icon_state = bobber_state("")
	line_visual.disturb()
	var/wait = rand(spot.bite_wait_min, spot.bite_wait_max)
	if(rod.get_bait_kind())
		wait *= FISHING_BAIT_WAIT_MULT
	// The wait is split up by a few twitches of the bobber that aren't bites
	nibbles_left = rand(0, 2)
	nibble_wait = wait / (nibbles_left + 1)
	next_timer = addtimer(CALLBACK(src, PROC_REF(nibble_or_bite)), nibble_wait, TIMER_STOPPABLE)

/datum/fishing_session/proc/nibble_or_bite()
	if(!angler_ready())
		qdel(src)
		return
	if(nibbles_left > 0)
		nibbles_left--
		flick(bobber_state("_nibble"), bobber)
		next_timer = addtimer(CALLBACK(src, PROC_REF(nibble_or_bite)), nibble_wait, TIMER_STOPPABLE)
		return
	bite()

/datum/fishing_session/proc/bite()
	deltimer(next_timer)
	// Sometimes what comes for the bobber is something that wants the angler instead
	if(spot.lurker_type && prob(spot.lurker_chance) && disturb_lurker())
		wait_for_bite()
		return
	state = FISHING_BITE
	line_visual.disturb()
	bobber.icon_state = bobber_state("_bite")
	playsound(bobber, spot.splash_sound || 'sound/effects/pop.ogg', 60, TRUE)
	to_chat(user, "<span class='boldnotice'>Something takes the hook! Pull!</span>")
	next_timer = addtimer(CALLBACK(src, PROC_REF(miss_bite)), rod.hook.bite_window, TIMER_STOPPABLE)

/// The angler didn't pull in time
/datum/fishing_session/proc/miss_bite()
	if(state != FISHING_BITE)
		return
	if(!angler_ready())
		qdel(src)
		return
	if(rod.bait && prob(50))
		to_chat(user, "<span class='warning'>Too slow! Whatever it was, it took [rod.bait] with it.</span>")
		QDEL_NULL(rod.bait)
	else
		to_chat(user, "<span class='warning'>Too slow! Whatever it was, it's gone.</span>")
	wait_for_bite()

/// The angler used the rod while the line is out. What that does depends on how far along the cast is.
/datum/fishing_session/proc/pull(mob/living/puller)
	if(puller != user)
		return
	switch(state)
		if(FISHING_WAITING)
			to_chat(user, "<span class='notice'>You reel your line back in.</span>")
			qdel(src)
		if(FISHING_BITE)
			hook_catch()
		if(FISHING_FIGHT)
			// For anglers without the reel window open, and exosuits
			reeling = !reeling
			to_chat(user, "<span class='notice'>You [reeling ? "start winding the reel" : "let go of the reel"].</span>")

/datum/fishing_session/proc/hook_catch()
	hooked = spot.pick_catch(target, rod.get_bait_kind())
	if(!hooked)
		to_chat(user, "<span class='warning'>The hook comes back empty.</span>")
		qdel(src)
		return
	length_cm = hooked.roll_length()
	if(!hooked.fights)
		land()
		return
	// Whatever fights for it has swallowed the bait
	if(rod.bait)
		QDEL_NULL(rod.bait)
	start_fight()

// MARK: The fight

/datum/fishing_session/proc/start_fight()
	deltimer(next_timer)
	state = FISHING_FIGHT
	var/size = hooked.size_factor(length_cm)
	fight_strength = hooked.strength * size
	stamina_left = hooked.stamina * size
	distance = max(get_dist(body, bobber), 2) + 1
	max_distance = distance + FISHING_SPARE_LINE * rod.hook.spare_line_mult
	tension = 0
	reeling = FALSE
	// It bolts as soon as it feels the hook
	set_fish_state(FISHING_FISH_TENSING)
	to_chat(user, "<span class='notice'>You hook something! There's [hooked.pull_hint(fight_strength)] on the line.</span>")
	START_PROCESSING(SSfastprocess, src)
	rod.ui_interact(user)

/datum/fishing_session/proc/set_fish_state(new_state)
	fish_state = new_state
	switch(fish_state)
		if(FISHING_FISH_RESTING)
			fish_state_time = hooked.rest_time * rand(70, 130) / 100
		if(FISHING_FISH_TENSING)
			fish_state_time = FISHING_TENSING_TIME
		if(FISHING_FISH_RUNNING)
			fish_state_time = hooked.run_time * rand(70, 130) / 100
		if(FISHING_FISH_WORN_OUT)
			fish_state_time = INFINITY
	bobber.icon_state = bobber_state(fish_state == FISHING_FISH_RUNNING ? "_run" : "_fight")

/// Moves the fish on to what it does next: rest, a short warning, run, rest again
/datum/fishing_session/proc/next_fish_state()
	switch(fish_state)
		if(FISHING_FISH_RESTING)
			set_fish_state(FISHING_FISH_TENSING)
		if(FISHING_FISH_TENSING)
			set_fish_state(FISHING_FISH_RUNNING)
		if(FISHING_FISH_RUNNING)
			set_fish_state(FISHING_FISH_RESTING)

/datum/fishing_session/process(wait)
	if(state != FISHING_FIGHT)
		return PROCESS_KILL
	if(!angler_ready())
		give_up(user)
		return PROCESS_KILL
	var/seconds = wait * 0.1

	fish_state_time -= seconds
	if(fish_state_time <= 0)
		next_fish_state()
	var/running = (fish_state == FISHING_FISH_RUNNING)
	if(running)
		// Holding on while it runs wears it out faster
		stamina_left -= seconds * (reeling ? FISHING_TIRING_BONUS : 1)
		if(stamina_left <= 0)
			set_fish_state(FISHING_FISH_WORN_OUT)
			running = FALSE
			to_chat(user, "<span class='notice'>The pull on the line goes weak. It's worn out!</span>")

	if(reeling)
		var/target_tension = FISHING_REEL_TENSION
		if(running)
			target_tension += fight_strength * FISHING_RUN_STRAIN
		target_tension *= rod.strain_mult / rod.line.strength
		if(tension < target_tension)
			tension = min(target_tension, tension + FISHING_TENSION_RISE * seconds)
		else
			tension = max(target_tension, tension - FISHING_TENSION_FALL * seconds)
		distance -= rod.reel_speed * (running ? FISHING_RUN_REEL_MULT : 1) * seconds
	else
		tension = max(0, tension - FISHING_TENSION_FALL * seconds)
		if(running)
			distance += (FISHING_RUN_SPEED + fight_strength * FISHING_RUN_SPEED_PER_STRENGTH) * seconds

	if(tension >= FISHING_MAX_TENSION)
		snap_line()
		return PROCESS_KILL
	if(distance >= max_distance)
		to_chat(user, "<span class='warning'>It takes all the line it wants, shakes the hook out and is gone.</span>")
		qdel(src)
		return PROCESS_KILL
	if(distance <= 0)
		land()
		return PROCESS_KILL
	line_visual.disturb()
	SStgui.update_uis(rod)

/datum/fishing_session/proc/snap_line()
	user.visible_message("<span class='warning'>[user]'s fishing line snaps!</span>", "<span class='warning'>The line snaps! [rod.hook] is gone, and so is whatever was on it.</span>")
	playsound(user, 'sound/effects/snap.ogg', 50, TRUE)
	QDEL_NULL(rod.hook)
	qdel(src)

// MARK: Lurkers

/**
 * Something in the spot comes up after the angler instead of the bait. It climbs out on the nearest tile of the
 * spot to them, or at the bobber if there isn't one close.
 *
 * Returns TRUE if one came up.
 */
/datum/fishing_session/proc/disturb_lurker()
	var/turf/body_turf = get_turf(body)
	var/turf/climb_out
	var/nearest = INFINITY
	for(var/turf/T as anything in RANGE_TURFS(2, body_turf))
		if(T == body_turf || !spot.matches(T) || is_blocked_turf(T, FALSE))
			continue
		var/dist = get_dist(T, body_turf)
		if(dist < nearest)
			nearest = dist
			climb_out = T
	climb_out = climb_out || get_turf(bobber)
	if(!climb_out)
		return FALSE
	var/mob/living/lurker = new spot.lurker_type(climb_out)
	user.visible_message("<span class='danger'>The [spot.name] heaves and [lurker] climbs out after [user]!</span>", "<span class='userdanger'>The [spot.name] heaves and [lurker] climbs out after you!</span>")
	playsound(climb_out, 'sound/effects/bubbles2.ogg', 60, TRUE)
	return TRUE

// MARK: Landing

/datum/fishing_session/proc/land()
	state = FISHING_DONE
	if(!spot.take_catch(target, hooked))
		to_chat(user, "<span class='warning'>The hook comes back empty.</span>")
		qdel(src)
		return
	var/landed_name = length_cm ? "a [length_cm] cm [hooked.name]" : "\a [hooked.name]"
	user.visible_message("<span class='notice'>[user] reels in [landed_name]!</span>", "<span class='notice'>You reel in [landed_name]!</span>")
	playsound(user, 'sound/items/ratchet.ogg', 30, TRUE)
	if(length_cm && record_fishing_catch(user.real_name, hooked.name, length_cm, spot.name))
		user.visible_message("<span class='boldnotice'>That's the biggest [hooked.name] anyone has caught this shift!</span>")
	hooked.land(user, src)
	qdel(src)
