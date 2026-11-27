// Crate trolley: a low flat cart for moving several crates at once. Drag a closed crate onto it to load it (up to
// CRATE_TROLLEY_CAPACITY, stacked up), pull it like anything else, then click it to set the top crate down beside it,
// drag it onto a floor tile to set the top crate down there, or alt-click to unload the lot. It's a hand tool, not
// automation: someone still loads, pulls and unloads it, just not one crate at a time. Built from metal sheets.
// Someone can climb up and stand on the crates (drag yourself onto it) and ride along; pulled at a run, they may fall
// off. Climbing is from Paradise (e9e3cf55d5), which took the trolley from here.
#define CRATE_TROLLEY_CAPACITY 4
/// How far up the first crate sits, and how much higher each one after it: must match make_trolley_sprite.py's preview
#define CRATE_TROLLEY_BASE_Y 3
#define CRATE_TROLLEY_STEP_Y 11
#define CRATE_TROLLEY_LOAD_TIME (1 SECONDS)
/// How much each crate aboard slows down whoever's pulling it
#define CRATE_TROLLEY_SLOWDOWN_PER_CRATE 0.25
#define MOVESPEED_ID_CRATE_TROLLEY "crate_trolley"
/// Chance per crate of height that whoever stands on top falls off, each step the trolley is pulled at a run
#define CRATE_TROLLEY_WOBBLE_CHANCE 5
/// Brute damage per crate of height when someone falls off the top
#define CRATE_TROLLEY_FALL_DAMAGE 5
#define CRATE_TROLLEY_CLIMB_TIME (2 SECONDS)

/obj/structure/crate_trolley
	name = "crate trolley"
	desc = "A low, flat cart for moving crates. Drag crates onto it to stack them up."
	icon = 'hippiestation/icons/obj/crate_trolley.dmi'
	icon_state = "trolley"
	density = TRUE
	anchored = FALSE
	max_integrity = 150
	// Standing up, not lying down, while buckled on top. Not `climbable`: that's tables' climbing, and bots route over
	// climbable furniture (bot_pathing_permissive.dm). Climbing on here is its own, in MouseDrop_T().
	buckle_lying = 0
	/// The crates aboard, bottom first
	var/list/obj/structure/closet/crate/crates = list()
	/// How many crates high the person standing on top is
	var/rider_height = 0
	/// Set while someone climbs down on purpose, so post_unbuckle_mob() doesn't make them fall
	var/climbing_down = FALSE
	/// Who's climbing up or down right now, so a held move key doesn't start it again every tick
	var/list/mob/living/climbing

/obj/structure/crate_trolley/Initialize(mapload)
	. = ..()
	update_icon()

/obj/structure/crate_trolley/Destroy()
	unbuckle_all_mobs(force = TRUE) // whoever is on top falls before the crates come off
	for(var/obj/structure/closet/crate/crate in crates.Copy())
		crate.forceMove(drop_location())
	crates.Cut()
	return ..()

/obj/structure/crate_trolley/deconstruct(disassembled = TRUE)
	if(!(flags_1 & NODECONSTRUCT_1))
		new /obj/item/stack/sheet/metal(drop_location(), 5)
	qdel(src)

/obj/structure/crate_trolley/update_icon()
	cut_overlays()
	for(var/i in 1 to length(crates))
		var/mutable_appearance/stacked = new(crates[i])
		stacked.layer = FLOAT_LAYER
		stacked.plane = FLOAT_PLANE
		stacked.pixel_x = 0
		stacked.pixel_y = CRATE_TROLLEY_BASE_Y + CRATE_TROLLEY_STEP_Y * (i - 1)
		add_overlay(stacked)
	add_overlay(mutable_appearance(icon, "handle")) // over the crates, so the handle always shows

/obj/structure/crate_trolley/examine(mob/user)
	. = ..()
	if(length(crates))
		var/list/names = list()
		for(var/obj/structure/closet/crate/crate in crates)
			names += "\a [crate]"
		. += "<span class='notice'>It's carrying [english_list(names)].</span>"
	else
		. += "<span class='notice'>It's empty.</span>"

/obj/structure/crate_trolley/examine_more(mob/user)
	. = ..()
	. += "<span class='notice'>Drag a closed crate onto it to load it; it takes [CRATE_TROLLEY_CAPACITY]. Pull it to move it - the more it carries, the slower you go.</span>"
	. += "<span class='notice'>Click it to set the top crate down beside it, drag it onto a floor tile to put the top crate there, or alt-click it to unload everything. Empty, a wrench takes it apart.</span>"
	. += "<span class='notice'>Drag yourself onto it to climb up on its crates. Pull it at a walk, or whoever is up there might fall off.</span>"
	. += "<span class='warning'>Don't send it off on the supply shuttle loaded unless you mean to: it goes with the crates.</span>"

// Loading: drag a crate onto it. Climbing: drag yourself onto it.
/obj/structure/crate_trolley/MouseDrop_T(atom/movable/dropped, mob/living/user)
	if(dropped == user && isliving(user))
		start_climb(user)
		return
	if(!istype(dropped, /obj/structure/closet/crate))
		return ..()
	try_load(dropped, user)

/obj/structure/crate_trolley/proc/can_load(obj/structure/closet/crate/crate, mob/living/user, silent = FALSE)
	if(!istype(user) || user.incapacitated() || !user.Adjacent(src) || !user.Adjacent(crate) || !isturf(crate.loc) || crate.anchored)
		return FALSE
	if(has_buckled_mobs())
		if(!silent)
			to_chat(user, "<span class='warning'>Someone is standing on the crates.</span>")
		return FALSE
	if(length(crates) >= CRATE_TROLLEY_CAPACITY)
		if(!silent)
			to_chat(user, "<span class='warning'>[src] can't take any more crates.</span>")
		return FALSE
	if(crate.opened)
		if(!silent)
			to_chat(user, "<span class='warning'>Close [crate] first.</span>")
		return FALSE
	for(var/mob/living/stowaway in crate.GetAllContents())
		if(!silent)
			to_chat(user, "<span class='warning'>Something shifts inside [crate] as you lift it. You set it back down.</span>")
		return FALSE
	return TRUE

/obj/structure/crate_trolley/proc/try_load(obj/structure/closet/crate/crate, mob/living/user)
	if(!can_load(crate, user))
		return FALSE
	user.visible_message("<span class='notice'>[user] starts lifting [crate] onto [src].</span>", "<span class='notice'>You start lifting [crate] onto [src]...</span>")
	if(!do_after(user, CRATE_TROLLEY_LOAD_TIME, target = crate) || !can_load(crate, user))
		return FALSE
	crate.pulledby?.stop_pulling()
	crates += crate // on the list first, so Entered() knows it's being loaded
	crate.forceMove(src)
	user.visible_message("<span class='notice'>[user] loads [crate] onto [src].</span>", "<span class='notice'>You load [crate] onto [src].</span>")
	load_changed()
	return TRUE

// Unloading
/obj/structure/crate_trolley/attack_hand(mob/living/user)
	. = ..()
	if(.)
		return
	if(has_buckled_mobs())
		pull_down(buckled_mobs[1], user)
		return TRUE
	if(!length(crates))
		return
	var/turf/spot = free_spot_beside(user)
	if(!spot)
		to_chat(user, "<span class='warning'>There's nowhere beside [src] to set a crate down.</span>")
		return
	unload_top(user, spot)
	return TRUE

/obj/structure/crate_trolley/MouseDrop(atom/over, src_location, over_location, src_control, over_control, params)
	var/mob/living/user = usr
	if(!isturf(over) || !length(crates) || !istype(user) || user.incapacitated() || !user.Adjacent(src))
		return ..()
	if(has_buckled_mobs())
		to_chat(user, "<span class='warning'>Someone is standing on the crates.</span>")
		return
	var/turf/spot = over
	if(!Adjacent(spot) || !spot_is_free(spot))
		to_chat(user, "<span class='warning'>You can't set a crate down there.</span>")
		return
	unload_top(user, spot)

/obj/structure/crate_trolley/AltClick(mob/living/user)
	if(!istype(user) || !user.canUseTopic(src, BE_CLOSE) || !length(crates))
		return
	if(has_buckled_mobs())
		to_chat(user, "<span class='warning'>Someone is standing on the crates.</span>")
		return
	var/unloaded = 0
	while(length(crates))
		var/turf/spot = free_spot_beside(user)
		if(!spot)
			break
		unload_top(user, spot, silent = TRUE)
		unloaded++
	if(unloaded)
		user.visible_message("<span class='notice'>[user] unloads [unloaded] crate\s from [src].</span>", "<span class='notice'>You unload [unloaded] crate\s from [src].</span>")
	if(length(crates))
		to_chat(user, "<span class='warning'>There's no room beside [src] for the rest.</span>")

/obj/structure/crate_trolley/proc/unload_top(mob/living/user, turf/spot, silent = FALSE)
	var/obj/structure/closet/crate/crate = crates[length(crates)]
	crate.forceMove(spot) // Exited() takes it off the list
	if(!silent)
		user.visible_message("<span class='notice'>[user] sets [crate] down off [src].</span>", "<span class='notice'>You set [crate] down off [src].</span>")

/// Somewhere next to the trolley to put a crate: the far side from the user first, then its sides, then the corners
/obj/structure/crate_trolley/proc/free_spot_beside(atom/near)
	var/away = get_dir(near, src) || SOUTH
	for(var/direction in list(away, turn(away, 90), turn(away, -90), turn(away, 45), turn(away, -45), turn(away, 135), turn(away, -135)))
		var/turf/spot = get_step(src, direction)
		if(spot && spot != get_turf(near) && Adjacent(spot) && spot_is_free(spot))
			return spot

/obj/structure/crate_trolley/proc/spot_is_free(turf/spot)
	return isopenturf(spot) && !is_blocked_turf(spot) && !(locate(/obj/structure/closet) in spot)

/obj/structure/crate_trolley/Entered(atom/movable/AM, atom/oldLoc)
	. = ..()
	if(AM in crates)
		return
	// Something came out of a crate aboard, like someone breaking out of it. Crates drop their contents into their loc,
	// which is us, so tidy up once the crate has finished opening.
	addtimer(CALLBACK(src, PROC_REF(drop_spilled)), 0, TIMER_UNIQUE)

/// Puts opened crates, and whatever came out of them, on the floor beside the trolley
/obj/structure/crate_trolley/proc/drop_spilled()
	var/turf/spot = drop_location()
	for(var/obj/structure/closet/crate/crate in crates.Copy())
		if(!crate.opened)
			continue
		spot = free_spot_beside(crate) || drop_location()
		crate.forceMove(spot)
	for(var/atom/movable/spilled in contents)
		if(!(spilled in crates))
			spilled.forceMove(spot)

/obj/structure/crate_trolley/Exited(atom/movable/AM, atom/newLoc)
	. = ..()
	if(!(AM in crates))
		return
	crates -= AM
	if(!QDELETED(src))
		load_changed()

// A crate deleted while aboard, like one sold off the supply shuttle, never calls Exited()
/obj/structure/crate_trolley/handle_atom_del(atom/A)
	. = ..()
	if(!(A in crates))
		return
	crates -= A
	if(!QDELETED(src))
		load_changed()

/// After loading or unloading: redraw the stack, and let whoever's pulling feel the new weight
/obj/structure/crate_trolley/proc/load_changed()
	update_icon()
	if(isliving(pulledby))
		var/mob/living/puller = pulledby
		puller.update_pull_movespeed()
	// A crate came out from under whoever is standing on top
	if(has_buckled_mobs() && length(crates) != rider_height)
		unbuckle_mob(buckled_mobs[1], TRUE)

/obj/structure/crate_trolley/wrench_act(mob/living/user, obj/item/tool)
	if(flags_1 & NODECONSTRUCT_1)
		return FALSE
	if(length(crates))
		to_chat(user, "<span class='warning'>Unload [src] first.</span>")
		return TRUE
	to_chat(user, "<span class='notice'>You start taking [src] apart...</span>")
	if(tool.use_tool(src, user, 2 SECONDS, volume = 50) && !length(crates))
		to_chat(user, "<span class='notice'>You take [src] apart.</span>")
		deconstruct(TRUE)
	return TRUE

/obj/structure/crate_trolley/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	if(has_buckled_mobs())
		if(!held_item)
			context[SCREENTIP_LMB] = buckled_mobs[1] == user ? "Climb down" : "Pull down"
		return
	if(length(crates))
		context[SCREENTIP_ALT_LMB] = "Unload all"
		if(!held_item)
			context[SCREENTIP_LMB] = "Unload top crate"
	else if(held_item?.tool_behaviour == TOOL_WRENCH && !(flags_1 & NODECONSTRUCT_1))
		context[SCREENTIP_LMB] = "Take apart"

// Standing on the crates. The person on top is buckled to the trolley, so they ride along when it's pulled.

/obj/structure/crate_trolley/proc/start_climb(mob/living/user)
	if(user.incapacitated() || !user.Adjacent(src) || (user in climbing))
		return
	if(!length(crates))
		to_chat(user, "<span class='warning'>There's nothing on [src] to climb up onto.</span>")
		return
	if(has_buckled_mobs())
		to_chat(user, "<span class='warning'>Someone is already standing on the crates.</span>")
		return
	user.visible_message("<span class='warning'>[user] starts climbing up onto the crates on [src].</span>", "<span class='notice'>You start climbing up onto the crates on [src]...</span>")
	LAZYADD(climbing, user)
	var/climbed = do_after(user, CRATE_TROLLEY_CLIMB_TIME, target = src)
	LAZYREMOVE(climbing, user)
	if(!climbed || QDELETED(src) || !length(crates) || has_buckled_mobs() || !user.Adjacent(src) || user.incapacitated())
		return
	user.forceMove(loc) // straight onto our tile, since walking into a dense trolley would shove it away
	if(buckle_mob(user, TRUE, FALSE))
		user.visible_message("<span class='warning'>[user] climbs up onto the crates on [src]!</span>", "<span class='notice'>You climb up onto the crates on [src].</span>")
		log_combat(user, src, "climbed onto")

/obj/structure/crate_trolley/post_buckle_mob(mob/living/M)
	rider_height = length(crates)
	M.pixel_y = initial(M.pixel_y) + CRATE_TROLLEY_BASE_Y + CRATE_TROLLEY_STEP_Y * rider_height + 2 // feet on the lid of the top crate

/obj/structure/crate_trolley/post_unbuckle_mob(mob/living/M)
	M.pixel_y = initial(M.pixel_y)
	var/height = rider_height
	rider_height = 0
	if(!climbing_down && !QDELETED(M) && M.loc == loc)
		fall_off(M, height)

/// Knocked down, out or dead while standing on top: called from update_mobility() below
/obj/structure/crate_trolley/proc/rider_mobility_changed(mob/living/rider)
	if(rider.stat == CONSCIOUS && !rider.IsKnockdown() && !rider.IsParalyzed() && !rider.IsUnconscious() && !rider.IsSleeping())
		return
	INVOKE_ASYNC(src, TYPE_PROC_REF(/atom/movable, unbuckle_mob), rider, TRUE)

/obj/structure/crate_trolley/Move(atom/newloc, direct)
	. = ..()
	if(!. || !has_buckled_mobs())
		return
	var/mob/living/puller = pulledby
	if(istype(puller) && puller.m_intent == MOVE_INTENT_WALK) // pulling it at a walk keeps it steady
		return
	if(!prob(CRATE_TROLLEY_WOBBLE_CHANCE * rider_height))
		return
	var/mob/living/rider = buckled_mobs[1]
	if(puller)
		log_combat(puller, rider, "made them fall off a crate trolley by pulling it at a run")
	unbuckle_mob(rider, TRUE)

/// Throws the person on top off the side of the stack. The higher they were, the more it hurts.
/obj/structure/crate_trolley/proc/fall_off(mob/living/rider, height)
	var/list/landings = list()
	for(var/turf/spot in orange(1, src))
		if(Adjacent(spot) && !is_blocked_turf(spot))
			landings += spot
	if(length(landings))
		rider.forceMove(pick(landings))
	rider.visible_message("<span class='warning'>[rider] falls off the crates on [src]!</span>", "<span class='userdanger'>You fall off the crates on [src]!</span>")
	playsound(rider, "bodyfall", 50, TRUE)
	if(!height)
		return
	rider.Knockdown(height SECONDS)
	rider.apply_damage(CRATE_TROLLEY_FALL_DAMAGE * height, BRUTE, pick(BODY_ZONE_HEAD, BODY_ZONE_L_ARM, BODY_ZONE_R_ARM, BODY_ZONE_L_LEG, BODY_ZONE_R_LEG))

// Resisting or moving while on top climbs down instead of falling
/obj/structure/crate_trolley/user_unbuckle_mob(mob/living/buckled_mob, mob/user)
	if(buckled_mob != user)
		return ..()
	INVOKE_ASYNC(src, PROC_REF(climb_down), user)

/obj/structure/crate_trolley/relaymove(mob/living/user, direction)
	if(user.buckled == src)
		INVOKE_ASYNC(src, PROC_REF(climb_down), user, direction)

/// Climbs down off the crates on purpose, on the given side if there's room there
/obj/structure/crate_trolley/proc/climb_down(mob/living/user, direction)
	if(user in climbing) // moving calls this every tick while the key is held
		return
	var/turf/landing = direction ? get_step(src, direction) : null
	if(!landing || !Adjacent(landing) || is_blocked_turf(landing))
		landing = free_spot_beside(user)
	if(!landing)
		to_chat(user, "<span class='warning'>There's nowhere to climb down to.</span>")
		return
	user.visible_message("<span class='notice'>[user] starts climbing down from [src].</span>", "<span class='notice'>You start climbing down from [src]...</span>")
	LAZYADD(climbing, user)
	var/done = do_after(user, CRATE_TROLLEY_CLIMB_TIME, target = src)
	LAZYREMOVE(climbing, user)
	if(!done || user.buckled != src)
		return
	if(!Adjacent(landing) || is_blocked_turf(landing))
		to_chat(user, "<span class='warning'>Something is in the way.</span>")
		return
	climbing_down = TRUE
	unbuckle_mob(user, TRUE)
	climbing_down = FALSE
	user.forceMove(landing)
	user.visible_message("<span class='notice'>[user] climbs down from [src].</span>", "<span class='notice'>You climb down from [src].</span>")

/// Someone pulls the person on top down off the crates. They fall.
/obj/structure/crate_trolley/proc/pull_down(mob/living/rider, mob/living/user)
	if(rider == user)
		climb_down(user)
		return
	user.visible_message("<span class='warning'>[user] starts pulling [rider] down off [src]!</span>", "<span class='warning'>You start pulling [rider] down off [src]...</span>")
	if(!do_after(user, 1 SECONDS, target = rider) || rider.buckled != src)
		return
	log_combat(user, rider, "pulled them off a crate trolley")
	unbuckle_mob(rider, TRUE)

/mob/living/update_mobility()
	. = ..()
	if(istype(buckled, /obj/structure/crate_trolley))
		var/obj/structure/crate_trolley/trolley = buckled
		trolley.rider_mobility_changed(src)

// Pulling a loaded trolley is slower, the more so the more it carries. Called from update_pull_movespeed()
// (hippiestation/code/modules/mob/living/living_movement.dm); start_pulling() only refreshes the pull speed for mobs, so
// refresh it for everything.
/mob/living/start_pulling(atom/movable/AM, state, force = pull_force, supress_message = FALSE)
	. = ..()
	update_pull_movespeed()

/mob/living/proc/update_crate_trolley_movespeed()
	var/obj/structure/crate_trolley/trolley = pulling
	if(istype(trolley) && length(trolley.crates))
		add_movespeed_modifier(MOVESPEED_ID_CRATE_TROLLEY, update = TRUE, priority = 100, override = TRUE, multiplicative_slowdown = CRATE_TROLLEY_SLOWDOWN_PER_CRATE * length(trolley.crates))
	else
		remove_movespeed_modifier(MOVESPEED_ID_CRATE_TROLLEY)

#undef CRATE_TROLLEY_CAPACITY
#undef CRATE_TROLLEY_BASE_Y
#undef CRATE_TROLLEY_STEP_Y
#undef CRATE_TROLLEY_LOAD_TIME
#undef CRATE_TROLLEY_SLOWDOWN_PER_CRATE
#undef MOVESPEED_ID_CRATE_TROLLEY
#undef CRATE_TROLLEY_WOBBLE_CHANCE
#undef CRATE_TROLLEY_FALL_DAMAGE
#undef CRATE_TROLLEY_CLIMB_TIME
