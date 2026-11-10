/datum/holotool_mode
	var/name = "???"
	var/sound
	var/behavior
	var/speed = 0.125
	/// Clicks go through the holotool's own multitool (holotool.dm): the one mode a machine asks the type of.
	var/hands_to_buffer_tool = FALSE

/datum/holotool_mode/proc/can_be_used(var/obj/item/holotool/H)
	return TRUE

/datum/holotool_mode/proc/on_set(var/obj/item/holotool/H)
	H.usesound = sound ? sound : 'sound/items/pshoom.ogg'
	H.toolspeed = speed ? speed : 1
	H.tool_behaviour = behavior ? behavior : null

/datum/holotool_mode/proc/on_unset(var/obj/item/holotool/H)
	H.usesound = initial(H.usesound)
	H.toolspeed = initial(H.toolspeed)
	H.tool_behaviour = initial(H.tool_behaviour)

////////////////////////////////////////////////

/datum/holotool_mode/screwdriver
	name = "holo-screwdriver"
	sound = 'sound/items/rped.ogg'
	behavior = TOOL_SCREWDRIVER

/datum/holotool_mode/crowbar
	name = "holo-crowbar"
	sound = 'sound/items/rped.ogg'
	behavior = TOOL_CROWBAR

/datum/holotool_mode/multitool
	name = "holo-multitool"
	sound = 'sound/items/rped.ogg'
	behavior = TOOL_MULTITOOL
	hands_to_buffer_tool = TRUE

/datum/holotool_mode/wrench
	name = "holo-wrench"
	sound = 'sound/items/rped.ogg'
	behavior = TOOL_WRENCH

/datum/holotool_mode/wirecutters
	name = "holo-wirecutters"
	sound = 'sound/items/rped.ogg'
	behavior = TOOL_WIRECUTTER

/datum/holotool_mode/welder
	name = "holo-welder"
	sound = 'sound/items/rped.ogg'
	behavior = TOOL_WELDER

// A welder that's lit: hot enough to light a cigarette or set plasma off, and it burns what it's swung at. It welded and was
// stone cold, so nothing that wants a flame took it for one.
/datum/holotool_mode/welder/on_set(var/obj/item/holotool/H)
	..()
	H.heat = 3800
	H.damtype = BURN
	H.force = 12
	H.hitsound = 'sound/items/welder.ogg'
	H.attack_verb = list("burned", "seared")

/datum/holotool_mode/welder/on_unset(var/obj/item/holotool/H)
	..()
	H.heat = initial(H.heat)
	H.damtype = initial(H.damtype)
	H.force = initial(H.force)
	H.hitsound = initial(H.hitsound)
	H.attack_verb = initial(H.attack_verb)

////////////////////////////////////////////////

/datum/holotool_mode/knife
	name = "holo-knife"
	sound = 'sound/weapons/blade1.ogg'

/datum/holotool_mode/knife/can_be_used(var/obj/item/holotool/H)
	return (H.obj_flags & EMAGGED)

/datum/holotool_mode/knife/on_set(var/obj/item/holotool/H)
	..()
	H.sharpness = IS_SHARP
	H.force = 17
	H.attack_verb = list("sliced", "torn", "cut")
	H.armour_penetration = 45
	H.embedding = list("embed_chance" = 40, "embedded_fall_chance" = 0, "embedded_pain_multiplier" = 5)
	H.hitsound = 'sound/weapons/blade1.ogg'

/datum/holotool_mode/knife/on_unset(var/obj/item/holotool/H)
	..()
	H.sharpness = initial(H.sharpness)
	H.force = initial(H.force)
	H.attack_verb = initial(H.attack_verb)
	H.armour_penetration = initial(H.armour_penetration)
	H.embedding = initial(H.embedding)
	H.hitsound = initial(H.hitsound)