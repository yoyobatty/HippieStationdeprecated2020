/turf/closed/wall/mineral
	smoothing_groups = SMOOTH_GROUP_CLOSED_TURFS + SMOOTH_GROUP_ANY_WALL + SMOOTH_GROUP_PLAIN_MINERAL_WALL
	canSmoothWith = SMOOTH_GROUP_PLAIN_MINERAL_WALL
	name = "mineral wall"
	desc = "This shouldn't exist"
	icon_state = ""
	var/last_event = 0
	var/active = null

/turf/closed/wall/mineral/gold
	base_icon_state = "gold_wall"
	smoothing_groups = SMOOTH_GROUP_CLOSED_TURFS + SMOOTH_GROUP_ANY_WALL + SMOOTH_GROUP_GOLD_WALLS
	canSmoothWith = SMOOTH_GROUP_GOLD_WALLS
	name = "gold wall"
	desc = "A wall with gold plating. Swag!"
	icon = 'icons/turf/walls/gold_wall.dmi'
	icon_state = "gold"
	sheet_type = /obj/item/stack/sheet/mineral/gold
	explosion_block = 0 //gold is a soft metal you dingus.

/turf/closed/wall/mineral/silver
	base_icon_state = "silver_wall"
	smoothing_groups = SMOOTH_GROUP_CLOSED_TURFS + SMOOTH_GROUP_ANY_WALL + SMOOTH_GROUP_SILVER_WALLS
	canSmoothWith = SMOOTH_GROUP_SILVER_WALLS
	name = "silver wall"
	desc = "A wall with silver plating. Shiny!"
	icon = 'icons/turf/walls/silver_wall.dmi'
	icon_state = "silver"
	sheet_type = /obj/item/stack/sheet/mineral/silver

/turf/closed/wall/mineral/diamond
	base_icon_state = "diamond_wall"
	smoothing_groups = SMOOTH_GROUP_CLOSED_TURFS + SMOOTH_GROUP_ANY_WALL + SMOOTH_GROUP_DIAMOND_WALLS
	canSmoothWith = SMOOTH_GROUP_DIAMOND_WALLS
	name = "diamond wall"
	desc = "A wall with diamond plating. You monster."
	icon = 'icons/turf/walls/diamond_wall.dmi'
	icon_state = "diamond"
	sheet_type = /obj/item/stack/sheet/mineral/diamond
	slicing_duration = 200   //diamond wall takes twice as much time to slice
	explosion_block = 3

/turf/closed/wall/mineral/bananium
	base_icon_state = "bananium_wall"
	smoothing_groups = SMOOTH_GROUP_CLOSED_TURFS + SMOOTH_GROUP_ANY_WALL + SMOOTH_GROUP_BANANIUM_WALLS
	canSmoothWith = SMOOTH_GROUP_BANANIUM_WALLS
	name = "bananium wall"
	desc = "A wall with bananium plating. Honk!"
	icon = 'icons/turf/walls/bananium_wall.dmi'
	icon_state = "bananium"
	sheet_type = /obj/item/stack/sheet/mineral/bananium

/turf/closed/wall/mineral/sandstone
	base_icon_state = "sandstone_wall"
	smoothing_groups = SMOOTH_GROUP_CLOSED_TURFS + SMOOTH_GROUP_ANY_WALL + SMOOTH_GROUP_SANDSTONE_WALLS
	canSmoothWith = SMOOTH_GROUP_SANDSTONE_WALLS
	name = "sandstone wall"
	desc = "A wall with sandstone plating. Rough."
	icon = 'icons/turf/walls/sandstone_wall.dmi'
	icon_state = "sandstone"
	sheet_type = /obj/item/stack/sheet/mineral/sandstone
	explosion_block = 0

/turf/closed/wall/mineral/uranium
	base_icon_state = "uranium_wall"
	smoothing_groups = SMOOTH_GROUP_CLOSED_TURFS + SMOOTH_GROUP_ANY_WALL + SMOOTH_GROUP_URANIUM_WALLS
	canSmoothWith = SMOOTH_GROUP_URANIUM_WALLS
	article = "a"
	name = "uranium wall"
	desc = "A wall with uranium plating. This is probably a bad idea."
	icon = 'icons/turf/walls/uranium_wall.dmi'
	icon_state = "uranium"
	sheet_type = /obj/item/stack/sheet/mineral/uranium

/turf/closed/wall/mineral/uranium/proc/radiate()
	if(!active)
		if(world.time > last_event+15)
			active = 1
			radiation_pulse(src, 40)
			for(var/turf/closed/wall/mineral/uranium/T in orange(1,src))
				T.radiate()
			last_event = world.time
			active = null
			return
	return

/turf/closed/wall/mineral/uranium/attack_hand(mob/user)
	radiate()
	. = ..()

/turf/closed/wall/mineral/uranium/attackby(obj/item/W, mob/user, params)
	radiate()
	..()

/turf/closed/wall/mineral/uranium/Bumped(atom/movable/AM)
	radiate()
	..()

/turf/closed/wall/mineral/plasma
	base_icon_state = "plasma_wall"
	smoothing_groups = SMOOTH_GROUP_CLOSED_TURFS + SMOOTH_GROUP_ANY_WALL + SMOOTH_GROUP_PLASMA_WALLS
	canSmoothWith = SMOOTH_GROUP_PLASMA_WALLS
	name = "plasma wall"
	desc = "A wall with plasma plating. This is definitely a bad idea."
	icon = 'icons/turf/walls/plasma_wall.dmi'
	icon_state = "plasma"
	sheet_type = /obj/item/stack/sheet/mineral/plasma
	thermal_conductivity = 0.04

/turf/closed/wall/mineral/plasma/attackby(obj/item/W, mob/user, params)
	if(W.is_hot() > 300)//If the temperature of the object is over 300, then ignite
		message_admins("Plasma wall ignited by [ADMIN_LOOKUPFLW(user)] in [ADMIN_VERBOSEJMP(src)]")
		log_game("Plasma wall ignited by [key_name(user)] in [AREACOORD(src)]")
		ignite(W.is_hot())
		return
	..()

/turf/closed/wall/mineral/plasma/proc/PlasmaBurn(temperature)
	new girder_type(src)
	ScrapeAway()
	var/turf/open/T = src
	T.atmos_spawn_air("plasma=400;TEMP=[temperature]")

/turf/closed/wall/mineral/plasma/temperature_expose(datum/gas_mixture/air, exposed_temperature)//Doesn't work because walls have superconduction turned off
	if(exposed_temperature > 300)
		PlasmaBurn(exposed_temperature)

/turf/closed/wall/mineral/plasma/proc/ignite(exposed_temperature)
	if(exposed_temperature > 300)
		PlasmaBurn(exposed_temperature)

/turf/closed/wall/mineral/plasma/bullet_act(obj/item/projectile/Proj)
	if(istype(Proj, /obj/item/projectile/beam))
		PlasmaBurn(2500)
	else if(istype(Proj, /obj/item/projectile/ion))
		PlasmaBurn(500)
	. = ..()

/turf/closed/wall/mineral/wood
	base_icon_state = "wood_wall"
	smoothing_groups = SMOOTH_GROUP_CLOSED_TURFS + SMOOTH_GROUP_ANY_WALL + SMOOTH_GROUP_WOOD_WALLS
	canSmoothWith = SMOOTH_GROUP_NONMETAL_WOOD_WALLS + SMOOTH_GROUP_WOOD_WALLS
	name = "wooden wall"
	desc = "A wall with wooden plating. Stiff."
	icon = 'icons/turf/walls/wood_wall.dmi'
	icon_state = "wood"
	sheet_type = /obj/item/stack/sheet/mineral/wood
	hardness = 70
	explosion_block = 0

/turf/closed/wall/mineral/wood/attackby(obj/item/W, mob/user)
	if(W.sharpness && W.force)
		var/duration = (48/W.force) * 2 //In seconds, for now.
		if(istype(W, /obj/item/hatchet) || istype(W, /obj/item/twohanded/fireaxe))
			duration /= 4 //Much better with hatchets and axes.
		if(do_after(user, duration*10, target=src)) //Into deciseconds.
			dismantle_wall(FALSE,FALSE)
			return
	return ..()

/turf/closed/wall/mineral/wood/nonmetal
	smoothing_groups = SMOOTH_GROUP_CLOSED_TURFS + SMOOTH_GROUP_ANY_WALL + SMOOTH_GROUP_NONMETAL_WOOD_WALLS
	desc = "A solidly wooden wall. It's a bit weaker than a wall made with metal."
	girder_type = /obj/structure/barricade/wooden
	hardness = 50

/turf/closed/wall/mineral/iron
	base_icon_state = "iron_wall"
	smoothing_groups = SMOOTH_GROUP_CLOSED_TURFS + SMOOTH_GROUP_ANY_WALL + SMOOTH_GROUP_IRON_WALLS
	canSmoothWith = SMOOTH_GROUP_IRON_WALLS
	name = "rough metal wall"
	desc = "A wall with rough metal plating."
	icon = 'icons/turf/walls/iron_wall.dmi'
	icon_state = "iron"
	sheet_type = /obj/item/stack/rods

/turf/closed/wall/mineral/snow
	base_icon_state = "snow_wall"
	smoothing_groups = SMOOTH_GROUP_CLOSED_TURFS + SMOOTH_GROUP_ANY_WALL + SMOOTH_GROUP_SNOW_WALLS
	canSmoothWith = SMOOTH_GROUP_SNOW_WALLS
	name = "packed snow wall"
	desc = "A wall made of densely packed snow blocks."
	icon = 'icons/turf/walls/snow_wall.dmi'
	icon_state = "snow"
	hardness = 80
	explosion_block = 0
	slicing_duration = 30
	sheet_type = /obj/item/stack/sheet/mineral/snow
	girder_type = null
	bullet_sizzle = TRUE
	bullet_bounce_sound = null

/turf/closed/wall/mineral/abductor
	smoothing_flags = SMOOTH_BITMASK|SMOOTH_DIAGONAL_CORNERS
	base_icon_state = "abductor_wall"
	smoothing_groups = SMOOTH_GROUP_CLOSED_TURFS + SMOOTH_GROUP_ANY_WALL + SMOOTH_GROUP_ABDUCTOR_WALLS
	canSmoothWith = SMOOTH_GROUP_ABDUCTOR_WALLS
	name = "alien wall"
	desc = "A wall with alien alloy plating."
	icon = 'icons/turf/walls/abductor_wall.dmi'
	icon_state = "abductor"
	sheet_type = /obj/item/stack/sheet/mineral/abductor
	slicing_duration = 200   //alien wall takes twice as much time to slice
	explosion_block = 3

/////////////////////Titanium walls/////////////////////

/turf/closed/wall/mineral/titanium //has to use this path due to how building walls works
	smoothing_flags = SMOOTH_BITMASK|SMOOTH_DIAGONAL_CORNERS
	base_icon_state = "shuttle_wall"
	smoothing_groups = SMOOTH_GROUP_CLOSED_TURFS + SMOOTH_GROUP_ANY_WALL + SMOOTH_GROUP_TITANIUM_WALLS
	canSmoothWith = SMOOTH_GROUP_TITANIUM_WALLS + SMOOTH_GROUP_AIRLOCK + SMOOTH_GROUP_SHUTTLE_AIRLOCK + SMOOTH_GROUP_TITANIUM_FALSEWALL + SMOOTH_GROUP_SHUTTLE_HEATER + SMOOTH_GROUP_SHUTTLE_WINDOWS
	name = "wall"
	desc = "A light-weight titanium wall used in shuttles."
	icon = 'icons/turf/walls/shuttle_wall.dmi'
	icon_state = "map-shuttle"
	explosion_block = 3
	flags_1 = CAN_BE_DIRTY_1 | CHECK_RICOCHET_1
	sheet_type = /obj/item/stack/sheet/mineral/titanium

/turf/closed/wall/mineral/titanium/nodiagonal
	smoothing_flags = SMOOTH_BITMASK
	icon_state = "map-shuttle_nd"

/turf/closed/wall/mineral/titanium/nosmooth
	smoothing_flags = NONE
	icon = 'icons/turf/shuttle.dmi'
	icon_state = "wall"

/turf/closed/wall/mineral/titanium/diagonal
	smoothing_flags = NONE
	icon_state = "map-shuttle-diag"

/turf/closed/wall/mineral/titanium/diagonal/New()
	..()
	add_turf_underlay(dir) // a fixed diagonal piece; the old code passed this a raw adjacency bitfield, not a direction

/turf/closed/wall/mineral/titanium/overspace
	icon_state = "map-overspace"
	fixed_underlay = list("space"=1)

//sub-type to be used for interior shuttle walls
//won't get an underlay of the destination turf on shuttle move
/turf/closed/wall/mineral/titanium/interior/copyTurf(turf/T)
	if(T.type != type)
		T.ChangeTurf(type)
		if(underlays.len)
			T.underlays = underlays
	if(T.icon_state != icon_state)
		T.icon_state = icon_state
	if(T.icon != icon)
		T.icon = icon
	if(color)
		T.atom_colours = atom_colours.Copy()
		T.update_atom_colour()
	if(T.dir != dir)
		T.setDir(dir)
	T.transform = transform
	return T

/turf/closed/wall/mineral/titanium/copyTurf(turf/T)
	. = ..()
	T.transform = transform

/turf/closed/wall/mineral/titanium/survival
	base_icon_state = "survival_pod_walls"
	smoothing_groups = SMOOTH_GROUP_CLOSED_TURFS + SMOOTH_GROUP_ANY_WALL + SMOOTH_GROUP_TITANIUM_WALLS + SMOOTH_GROUP_SURVIVAL_TITANIUM_WALLS
	canSmoothWith = SMOOTH_GROUP_SURVIVAL_TITANIUM_WALLS + SMOOTH_GROUP_AIRLOCK + SMOOTH_GROUP_SHUTTLE_ENGINE + SMOOTH_GROUP_WINDOW_FULLTILE + SMOOTH_GROUP_SHUTTLE_WINDOWS
	name = "pod wall"
	desc = "An easily-compressable wall used for temporary shelter."
	icon = 'icons/turf/walls/survival_pod_walls.dmi'
	icon_state = "smooth"

/turf/closed/wall/mineral/titanium/survival/nodiagonal
	smoothing_flags = SMOOTH_BITMASK

/turf/closed/wall/mineral/titanium/survival/pod
	canSmoothWith = SMOOTH_GROUP_SURVIVAL_TITANIUM_WALLS + SMOOTH_GROUP_SURVIVAL_TITANIUM_POD

/////////////////////Plastitanium walls/////////////////////

/turf/closed/wall/mineral/plastitanium
	smoothing_flags = SMOOTH_BITMASK|SMOOTH_DIAGONAL_CORNERS
	base_icon_state = "plastitanium_wall"
	smoothing_groups = SMOOTH_GROUP_CLOSED_TURFS + SMOOTH_GROUP_ANY_WALL + SMOOTH_GROUP_PLASTITANIUM_WALLS
	canSmoothWith = SMOOTH_GROUP_PLASTITANIUM_WALLS + SMOOTH_GROUP_AIRLOCK + SMOOTH_GROUP_SHUTTLE_AIRLOCK + SMOOTH_GROUP_PLASTITANIUM_SHUTTLE_PARTS + SMOOTH_GROUP_SHUTTLE_ENGINE
	name = "wall"
	desc = "A durable wall made of an alloy of plasma and titanium."
	icon = 'icons/turf/walls/plastitanium_wall.dmi'
	icon_state = "map-shuttle"
	explosion_block = 4
	sheet_type = /obj/item/stack/sheet/mineral/plastitanium

/turf/closed/wall/mineral/plastitanium/nodiagonal
	smoothing_flags = SMOOTH_BITMASK
	icon_state = "map-shuttle_nd"

/turf/closed/wall/mineral/plastitanium/nosmooth
	smoothing_flags = NONE
	icon = 'icons/turf/shuttle.dmi'
	icon_state = "wall"

/turf/closed/wall/mineral/plastitanium/overspace
	icon_state = "map-overspace"
	fixed_underlay = list("space"=1)

/turf/closed/wall/mineral/plastitanium/explosive/ex_act(severity)
	var/obj/item/bombcore/large/bombcore = new(get_turf(src))
	bombcore.detonate()
	..()

//have to copypaste this code
/turf/closed/wall/mineral/plastitanium/interior/copyTurf(turf/T)
	if(T.type != type)
		T.ChangeTurf(type)
		if(underlays.len)
			T.underlays = underlays
	if(T.icon_state != icon_state)
		T.icon_state = icon_state
	if(T.icon != icon)
		T.icon = icon
	if(color)
		T.atom_colours = atom_colours.Copy()
		T.update_atom_colour()
	if(T.dir != dir)
		T.setDir(dir)
	T.transform = transform
	return T

/turf/closed/wall/mineral/plastitanium/copyTurf(turf/T)
	. = ..()
	T.transform = transform
