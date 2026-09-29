// Crate trolley: a low flat cart for moving several crates at once. Drag a closed crate onto it to load it (up to
// CRATE_TROLLEY_CAPACITY, stacked up), pull it like anything else, then click it to set the top crate down beside it,
// drag it onto a floor tile to set the top crate down there, or alt-click to unload the lot. It's a hand tool, not
// automation: someone still loads, pulls and unloads it, just not one crate at a time. Built from metal sheets.
#define CRATE_TROLLEY_CAPACITY 4
/// How far up the first crate sits, and how much higher each one after it: must match make_trolley_sprite.py's preview
#define CRATE_TROLLEY_BASE_Y 3
#define CRATE_TROLLEY_STEP_Y 11
#define CRATE_TROLLEY_LOAD_TIME (1 SECONDS)
/// How much each crate aboard slows down whoever's pulling it
#define CRATE_TROLLEY_SLOWDOWN_PER_CRATE 0.25
#define MOVESPEED_ID_CRATE_TROLLEY "crate_trolley"

/obj/structure/crate_trolley
	name = "crate trolley"
	desc = "A low, flat cart for moving crates. Drag crates onto it to stack them up."
	icon = 'hippiestation/icons/obj/crate_trolley.dmi'
	icon_state = "trolley"
	density = TRUE
	anchored = FALSE
	max_integrity = 150
	/// The crates aboard, bottom first
	var/list/obj/structure/closet/crate/crates = list()

/obj/structure/crate_trolley/Initialize(mapload)
	. = ..()
	update_icon()

/obj/structure/crate_trolley/Destroy()
	for(var/obj/structure/closet/crate/crate in crates)
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
	. += "<span class='warning'>Don't send it off on the supply shuttle loaded unless you mean to: it goes with the crates.</span>"

// Loading: drag a crate onto it
/obj/structure/crate_trolley/MouseDrop_T(atom/movable/dropped, mob/living/user)
	if(!istype(dropped, /obj/structure/closet/crate))
		return ..()
	try_load(dropped, user)

/obj/structure/crate_trolley/proc/can_load(obj/structure/closet/crate/crate, mob/living/user, silent = FALSE)
	if(!istype(user) || user.incapacitated() || !user.Adjacent(src) || !user.Adjacent(crate) || !isturf(crate.loc) || crate.anchored)
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
	crate.forceMove(src)
	crates += crate
	user.visible_message("<span class='notice'>[user] loads [crate] onto [src].</span>", "<span class='notice'>You load [crate] onto [src].</span>")
	load_changed()
	return TRUE

// Unloading
/obj/structure/crate_trolley/attack_hand(mob/living/user)
	. = ..()
	if(. || !length(crates))
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
	var/turf/spot = over
	if(!Adjacent(spot) || !spot_is_free(spot))
		to_chat(user, "<span class='warning'>You can't set a crate down there.</span>")
		return
	unload_top(user, spot)

/obj/structure/crate_trolley/AltClick(mob/living/user)
	if(!istype(user) || !user.canUseTopic(src, BE_CLOSE) || !length(crates))
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
	crates -= crate
	crate.forceMove(spot)
	if(!silent)
		user.visible_message("<span class='notice'>[user] sets [crate] down off [src].</span>", "<span class='notice'>You set [crate] down off [src].</span>")
	load_changed()

/// Somewhere next to the trolley to put a crate: the far side from the user first, then its sides, then the corners
/obj/structure/crate_trolley/proc/free_spot_beside(mob/user)
	var/away = get_dir(user, src) || SOUTH
	for(var/direction in list(away, turn(away, 90), turn(away, -90), turn(away, 45), turn(away, -45), turn(away, 135), turn(away, -135)))
		var/turf/spot = get_step(src, direction)
		if(spot && spot != get_turf(user) && Adjacent(spot) && spot_is_free(spot))
			return spot

/obj/structure/crate_trolley/proc/spot_is_free(turf/spot)
	return isopenturf(spot) && !is_blocked_turf(spot) && !(locate(/obj/structure/closet) in spot)

/// After loading or unloading: redraw the stack, and let whoever's pulling feel the new weight
/obj/structure/crate_trolley/proc/load_changed()
	update_icon()
	if(isliving(pulledby))
		var/mob/living/puller = pulledby
		puller.update_pull_movespeed()

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
	if(length(crates))
		context[SCREENTIP_ALT_LMB] = "Unload all"
		if(!held_item)
			context[SCREENTIP_LMB] = "Unload top crate"
	else if(held_item?.tool_behaviour == TOOL_WRENCH && !(flags_1 & NODECONSTRUCT_1))
		context[SCREENTIP_LMB] = "Take apart"

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
