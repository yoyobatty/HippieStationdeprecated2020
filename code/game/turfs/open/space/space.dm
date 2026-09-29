// Starlight (as in tgstation): space touching anything that isn't space glows softly, lighting hulls, windows and
// breaches. Kept in globals rather than on the turf type - a space turf with a light_range would light itself in
// Initialize(), and there are ~600k of them. set_starlight() recolors every lit tile at once (Aurora Caelus).
// Range and power are tgstation's (as of tgstation/tgstation@2e686854df), as is lighting from just under the floor
// (LIGHTING_HEIGHT_SPACE, on the turf type below): full brightness right at the edge of space, fading within two tiles.
#define STARLIGHT_DEFAULT_RANGE 2
#define STARLIGHT_DEFAULT_POWER 1

///The base color of light space emits
GLOBAL_VAR_INIT(base_starlight_color, COLOR_STARLIGHT)
///The color of light space is currently emitting
GLOBAL_VAR_INIT(starlight_color, COLOR_STARLIGHT)
///The range of the light space is displaying
GLOBAL_VAR_INIT(starlight_range, STARLIGHT_DEFAULT_RANGE)
///The power of the light space is throwing out
GLOBAL_VAR_INIT(starlight_power, STARLIGHT_DEFAULT_POWER)
///Every space turf currently giving off starlight
GLOBAL_LIST_EMPTY(starlight)
///The icon states SPACE_ICON_STATE picks between, "0" to "24"
GLOBAL_LIST_INIT(space_icon_states, make_space_icon_states())

/proc/make_space_icon_states()
	. = list()
	for(var/i in 0 to 24)
		. += "[i]"

// What lights the space tiles themselves, and anything sitting on them (lattices, catwalks): space turfs have no
// lighting object, so light sources never reach them. As in tgstation, each gets an overlay that mirrors (render_source)
// one hidden screen object tinted the starlight color - retinting that single object (set_starlight()) retints them all.
#define STARLIGHT_RENDER_TARGET "*starlight"

/obj/starlight_appearance
	icon = 'icons/effects/alphacolors.dmi'
	icon_state = "white"
	plane = LIGHTING_PLANE
	layer = LIGHTING_LAYER
	blend_mode = BLEND_ADD
	color = COLOR_STARLIGHT
	screen_loc = "1,1"
	render_target = STARLIGHT_RENDER_TARGET

///The render target every client carries (see /datum/hud/show_hud()) for the starlight overlays to mirror
GLOBAL_DATUM_INIT(starlight_object, /obj/starlight_appearance, new)
///The overlay starlit space turfs get in place of plain fullbright
GLOBAL_DATUM_INIT(starlight_overlay, /mutable_appearance, make_starlight_overlay())

/proc/make_starlight_overlay()
	var/mutable_appearance/glow = new()
	glow.plane = LIGHTING_PLANE
	glow.layer = LIGHTING_LAYER
	glow.blend_mode = BLEND_ADD
	glow.render_source = STARLIGHT_RENDER_TARGET
	return glow

/proc/set_base_starlight(star_color = null, range = null, power = null)
	GLOB.base_starlight_color = star_color
	set_starlight(star_color, range, power)

/proc/set_starlight(star_color = null, range = null, power = null)
	if(isnull(star_color))
		star_color = GLOB.starlight_color
	GLOB.starlight_color = star_color
	var/old_star_color = GLOB.starlight_object.color
	GLOB.starlight_object.color = star_color //the space tiles' own tint (see /obj/starlight_appearance)
	// range/power are deliberately not stored (as in tgstation): the globals stay the normal values, so a temporary
	// change like Aurora Caelus' brightening can fade back to them.
	// set light color on all lit turfs
	for(var/turf/open/space/spess as anything in GLOB.starlight)
		spess.set_light(range, power, star_color)
		CHECK_TICK
	if(star_color != old_star_color)
		for(var/area/starlit as anything in GLOB.starlit_areas) //deep space's area-wide glow
			starlit.starlight_changed(star_color)

///Areas lit by an /area/proc/add_fullbright() starlight overlay
GLOBAL_LIST_EMPTY(starlit_areas)

/proc/make_area_starlight(star_color)
	var/mutable_appearance/glow = mutable_appearance('icons/effects/alphacolors.dmi', "white", LIGHTING_LAYER, LIGHTING_PLANE)
	glow.blend_mode = BLEND_ADD
	glow.color = star_color
	return glow

/turf/open/space
	icon = 'icons/turf/space.dmi'
	icon_state = "0"
	name = "\proper space"
	intact = 0

	temperature = TCMB
	thermal_conductivity = OPEN_HEAT_TRANSFER_COEFFICIENT
	heat_capacity = 700000

	var/destination_z
	var/destination_x
	var/destination_y

	var/global/datum/gas_mixture/immutable/space/space_gas = new
	plane = PLANE_SPACE
	layer = SPACE_LAYER
	light_power = STARLIGHT_DEFAULT_POWER
	light_height = LIGHTING_HEIGHT_SPACE
	light_bounce = TRUE //unlike most lit turfs: it barely spills at starlight's usual range, but does in an Aurora Caelus
	dynamic_lighting = DYNAMIC_LIGHTING_DISABLED
	bullet_bounce_sound = null
	vis_flags = VIS_INHERIT_ID	//when this be added to vis_contents of something it be associated with something on clicking, important for visualisation of turf in openspace and interraction with openspace that show you turf.

/turf/open/space/basic/New()	//Do not convert to Initialize
	//This is used to optimize the map loader
	return

/turf/open/space/Initialize()
	icon_state = SPACE_ICON_STATE
	air = space_gas

	if(length(vis_contents)) // hippie -- inherited from the turf this replaced, if any; skip the call for the usual empty list
		vis_contents.Cut()

	if(flags_1 & INITIALIZED_1)
		stack_trace("Warning: [src]([type]) initialized multiple times!")
	flags_1 |= INITIALIZED_1

	var/area/A = loc
	if(!IS_DYNAMIC_LIGHTING(src) && IS_DYNAMIC_LIGHTING(A))
		if(CONFIG_GET(flag/starlight))
			add_overlay(GLOB.starlight_overlay) //tinted starlight rather than plain white, so lattices and catwalks out here read as starlit
		else
			add_overlay(/obj/effect/fullbright)

	if(requires_activation)
		SSair.add_to_active(src, TRUE)

	if (light_power && light_range)
		update_light()

	if (opacity)
		has_opaque_atom = TRUE

	// hippie -- for space, ComponentInitialize() (/turf/open's) only ever adds wetness; skipping the call when dry saves
	// ~0.3us on each of the ~675k space turfs. Space turf types override neither it nor this - if one ever needs to, drop the check.
	if (wet)
		ComponentInitialize()

	return INITIALIZE_HINT_NORMAL

//ATTACK GHOST IGNORING PARENT RETURN VALUE
/turf/open/space/attack_ghost(mob/dead/observer/user)
	if(destination_z)
		var/turf/T = locate(destination_x, destination_y, destination_z)
		user.forceMove(T)

/turf/open/space/Initalize_Atmos(times_fired)
	return

/turf/open/space/TakeTemperature(temp)

/turf/open/space/RemoveLattice()
	return

/turf/open/space/AfterChange()
	..()
	atmos_overlay_types = null

/turf/open/space/Assimilate_Air()
	return

/// Updates starlight. Called when we're unsure of a turf's starlight state
/// Returns TRUE if we're lit, FALSE otherwise
/turf/open/space/proc/update_starlight()
	if(!CONFIG_GET(flag/starlight))
		return FALSE
	// Like tgstation's AREA_USES_STARLIGHT: all of a starlit area (the space right around the station) glows, not just
	// its edge against the hull - otherwise lattices, catwalks and solars out there sit in the dark.
	var/area/our_area = loc
	if(initial(our_area.dynamic_lighting) == DYNAMIC_LIGHTING_IFSTARLIGHT)
		enable_starlight()
		return TRUE
	for(var/t in RANGE_TURFS(1,src)) //RANGE_TURFS is in code\__HELPERS\game.dm
		if(isspaceturf(t))
			//let's NOT update this that much pls
			continue
		enable_starlight()
		return TRUE
	if(GLOB.starlight[src])
		GLOB.starlight -= src
		set_light(0)
	return FALSE

/// Turns on the stars, if they aren't already
/turf/open/space/proc/enable_starlight()
	if(!GLOB.starlight[src])
		GLOB.starlight[src] = TRUE
		set_light(GLOB.starlight_range, GLOB.starlight_power, GLOB.starlight_color)

/turf/open/space/Destroy()
	GLOB.starlight -= src
	return ..()

/turf/open/space/attack_paw(mob/user)
	return attack_hand(user)

/turf/open/space/proc/CanBuildHere()
	return TRUE

/turf/open/space/handle_slip()
	return

/turf/open/space/attackby(obj/item/C, mob/user, params)
	..()
	if(!CanBuildHere())
		return
	if(istype(C, /obj/item/stack/rods))
		var/obj/item/stack/rods/R = C
		var/obj/structure/lattice/L = locate(/obj/structure/lattice, src)
		var/obj/structure/lattice/catwalk/W = locate(/obj/structure/lattice/catwalk, src)
		if(W)
			to_chat(user, "<span class='warning'>There is already a catwalk here!</span>")
			return
		if(L)
			if(R.use(1))
				to_chat(user, "<span class='notice'>You construct a catwalk.</span>")
				playsound(src, 'sound/weapons/genhit.ogg', 50, 1)
				new/obj/structure/lattice/catwalk(src)
			else
				to_chat(user, "<span class='warning'>You need two rods to build a catwalk!</span>")
			return
		if(R.use(1))
			to_chat(user, "<span class='notice'>You construct a lattice.</span>")
			playsound(src, 'sound/weapons/genhit.ogg', 50, 1)
			ReplaceWithLattice()
		else
			to_chat(user, "<span class='warning'>You need one rod to build a lattice.</span>")
		return
	if(istype(C, /obj/item/stack/tile/plasteel))
		var/obj/structure/lattice/L = locate(/obj/structure/lattice, src)
		if(L)
			var/obj/item/stack/tile/plasteel/S = C
			if(S.use(1))
				qdel(L)
				playsound(src, 'sound/weapons/genhit.ogg', 50, 1)
				to_chat(user, "<span class='notice'>You build a floor.</span>")
				PlaceOnTop(/turf/open/floor/plating, flags = CHANGETURF_INHERIT_AIR)
			else
				to_chat(user, "<span class='warning'>You need one floor tile to build a floor!</span>")
		else
			to_chat(user, "<span class='warning'>The plating is going to need some support! Place metal rods first.</span>")

/turf/open/space/Entered(atom/movable/A)
	..()
	if ((!(A) || src != A.loc))
		return

	if(destination_z && destination_x && destination_y && !(A.pulledby || !A.can_be_z_moved))
		var/tx = destination_x
		var/ty = destination_y
		var/turf/DT = locate(tx, ty, destination_z)
		var/itercount = 0
		while(DT.density || istype(DT.loc,/area/shuttle)) // Extend towards the center of the map, trying to look for a better place to arrive
			if (itercount++ >= 100)
				log_game("SPACE Z-TRANSIT ERROR: Could not find a safe place to land [A] within 100 iterations.")
				break
			if (tx < 128)
				tx++
			else
				tx--
			if (ty < 128)
				ty++
			else
				ty--
			DT = locate(tx, ty, destination_z)

		var/atom/movable/AM = A.pulling
		A.forceMove(DT)
		if(AM)
			var/turf/T = get_step(A.loc,turn(A.dir, 180))
			AM.can_be_z_moved = FALSE
			AM.forceMove(T)
			A.start_pulling(AM)
			AM.can_be_z_moved = TRUE

		//now we're on the new z_level, proceed the space drifting
		stoplag()//Let a diagonal move finish, if necessary
		A.newtonian_move(A.inertia_dir)


/turf/open/space/MakeSlippery(wet_setting, min_wet_time, wet_time_to_add, max_wet_time, permanent)
	return

/turf/open/space/singularity_act()
	return

/turf/open/space/can_have_cabling()
	if(locate(/obj/structure/lattice/catwalk, src))
		return 1
	return 0

/turf/open/space/is_transition_turf()
	if(destination_x || destination_y || destination_z)
		return 1


/turf/open/space/acid_act(acidpwr, acid_volume)
	return 0

/turf/open/space/get_smooth_underlay_icon(mutable_appearance/underlay_appearance, turf/asking_turf, adjacency_dir)
	underlay_appearance.icon = 'icons/turf/space.dmi'
	underlay_appearance.icon_state = SPACE_ICON_STATE
	underlay_appearance.plane = PLANE_SPACE
	return TRUE


/turf/open/space/rcd_vals(mob/user, obj/item/construction/rcd/the_rcd)
	if(!CanBuildHere())
		return FALSE

	switch(the_rcd.mode)
		if(RCD_FLOORWALL)
			var/obj/structure/lattice/L = locate(/obj/structure/lattice, src)
			if(L)
				return list("mode" = RCD_FLOORWALL, "delay" = 0, "cost" = 1)
			else
				return list("mode" = RCD_FLOORWALL, "delay" = 0, "cost" = 3)
	return FALSE

/turf/open/space/rcd_act(mob/user, obj/item/construction/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_FLOORWALL)
			to_chat(user, "<span class='notice'>You build a floor.</span>")
			PlaceOnTop(/turf/open/floor/plating, flags = CHANGETURF_INHERIT_AIR)
			return TRUE
	return FALSE

/turf/open/space/ReplaceWithLattice()
	var/dest_x = destination_x
	var/dest_y = destination_y
	var/dest_z = destination_z
	..()
	destination_x = dest_x
	destination_y = dest_y
	destination_z = dest_z
