//Engineering Mesons

#define MODE_NONE ""
#define MODE_MESON "meson"
#define MODE_TRAY "t-ray"
#define MODE_RAD "radiation"
#define MODE_SHUTTLE "shuttle"
#define MODE_THERMAL "thermal" //hippie edit -- heat map, see hippiestation/code/modules/clothing/glasses/thermal_vision.dm

/obj/item/clothing/glasses/meson/engine
	name = "engineering scanner goggles"
	desc = "Goggles used by engineers. The Meson Scanner mode lets you see basic structural and terrain layouts through walls, the T-ray Scanner mode lets you see underfloor objects such as cables and pipes, the Radiation Scanner mode let's you see objects contaminated by radiation, and the Thermal Scanner mode draws a heat map of everything in view, even in the dark. Blue is cold, green is comfortable, then yellow, orange and red as it gets hotter, and white is white hot."
	icon_state = "trayson-meson"
	item_state = "trayson-meson"
	actions_types = list(/datum/action/item_action/toggle_mode)

	vision_flags = NONE
	darkness_view = 2
	invis_view = SEE_INVISIBLE_LIVING

	var/list/modes = list(MODE_NONE = MODE_MESON, MODE_MESON = MODE_TRAY, MODE_TRAY = MODE_RAD, MODE_RAD = MODE_THERMAL, MODE_THERMAL = MODE_NONE)
	var/mode = MODE_NONE
	var/range = 1
	var/datum/thermal_vision/thermal //hippie edit -- the heat map, while it's on

/obj/item/clothing/glasses/meson/engine/Initialize()
	. = ..()
	START_PROCESSING(SSobj, src)
	update_icon()

/obj/item/clothing/glasses/meson/engine/Destroy()
	STOP_PROCESSING(SSobj, src)
	QDEL_NULL(thermal) //hippie edit
	return ..()

//hippie edit -- runs the heat map for as long as these are worn on someone's eyes in thermal mode, and stops it the moment they aren't
/obj/item/clothing/glasses/meson/engine/proc/update_thermal(mob/living/carbon/human/user, worn = FALSE)
	if(!user)
		user = ishuman(loc) ? loc : null
	if(mode == MODE_THERMAL && user && user.client && (worn || user.glasses == src))
		if(!thermal || thermal.viewer != user)
			QDEL_NULL(thermal)
			thermal = new(user)
	else
		QDEL_NULL(thermal)

/obj/item/clothing/glasses/meson/engine/equipped(mob/user, slot)
	. = ..()
	update_thermal(user, slot == ITEM_SLOT_EYES)

/obj/item/clothing/glasses/meson/engine/dropped(mob/user)
	. = ..()
	update_thermal()

/obj/item/clothing/glasses/meson/engine/proc/toggle_mode(mob/user, voluntary)
	mode = modes[mode]
	to_chat(user, "<span class='[voluntary ? "notice":"warning"]'>[voluntary ? "You turn the goggles":"The goggles turn"] [mode ? "to [mode] mode":"off"][voluntary ? ".":"!"]</span>")

	switch(mode)
		if(MODE_MESON)
			vision_flags = SEE_TURFS
			darkness_view = 1
			lighting_alpha = LIGHTING_PLANE_ALPHA_MOSTLY_VISIBLE

		if(MODE_TRAY) //undoes the last mode, meson
			vision_flags = NONE
			darkness_view = 2
			lighting_alpha = null

		if(MODE_THERMAL) //hippie edit -- thermal sees in the dark, the same way night vision goggles do
			vision_flags = NONE
			darkness_view = 8
			lighting_alpha = LIGHTING_PLANE_ALPHA_MOSTLY_INVISIBLE

		if(MODE_NONE) //hippie edit -- and this puts things back when they're switched off
			vision_flags = NONE
			darkness_view = 2
			lighting_alpha = null

	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.glasses == src)
			H.update_sight()

	update_thermal(ishuman(user) ? user : null) //hippie edit
	update_icon()
	for(var/X in actions)
		var/datum/action/A = X
		A.UpdateButtonIcon()

/obj/item/clothing/glasses/meson/engine/attack_self(mob/user)
	toggle_mode(user, TRUE)

/obj/item/clothing/glasses/meson/engine/process()
	if(!ishuman(loc))
		return
	var/mob/living/carbon/human/user = loc
	if(user.glasses != src || !user.client)
		return
	switch(mode)
		if(MODE_TRAY)
			t_ray_scan(user, 8, range)
		if(MODE_RAD)
			show_rads()
		if(MODE_SHUTTLE)
			show_shuttle()

/obj/item/clothing/glasses/meson/engine/proc/show_rads()
	var/mob/living/carbon/human/user = loc
	var/list/rad_places = list()
	for(var/datum/component/radioactive/thing in SSradiation.processing)
		var/atom/owner = thing.parent
		var/turf/place = get_turf(owner)
		if(rad_places[place])
			rad_places[place] += thing.strength
		else
			rad_places[place] = thing.strength

	for(var/i in rad_places)
		var/turf/place = i
		if(get_dist(user, place) >= range*2)	//Rads are easier to see than wires under the floor
			continue
		var/strength = round(rad_places[i] / 1000, 0.1)
		var/image/pic = new(loc = place)
		var/mutable_appearance/MA = new()
		MA.alpha = 180
		MA.maptext = "[strength]k"
		MA.color = "#64C864"
		MA.layer = FLY_LAYER
		pic.appearance = MA
		flick_overlay(pic, list(user.client), 8)

/obj/item/clothing/glasses/meson/engine/proc/show_shuttle()
	var/mob/living/carbon/human/user = loc
	var/obj/docking_port/mobile/port = SSshuttle.get_containing_shuttle(user)
	if(!port)
		return
	var/list/shuttle_areas = port.shuttle_areas
	for(var/r in shuttle_areas)
		var/area/region = r
		for(var/turf/place in region.contents)
			if(get_dist(user, place) > 7)
				continue
			var/image/pic
			if(isshuttleturf(place))
				pic = new('icons/turf/overlays.dmi', place, "greenOverlay", AREA_LAYER)
			else
				pic = new('icons/turf/overlays.dmi', place, "redOverlay", AREA_LAYER)
			flick_overlay(pic, list(user.client), 8)

/obj/item/clothing/glasses/meson/engine/update_icon()
	icon_state = "trayson-[mode == MODE_THERMAL ? MODE_RAD : mode]" //hippie edit -- thermal has no sprite of its own yet, so it borrows the radiation one
	update_mob()

/obj/item/clothing/glasses/meson/engine/proc/update_mob()
	item_state = icon_state
	if(isliving(loc))
		var/mob/living/user = loc
		if(user.get_item_by_slot(ITEM_SLOT_EYES) == src)
			user.update_inv_glasses()
		else
			user.update_inv_hands()

/obj/item/clothing/glasses/meson/engine/tray //atmos techs have lived far too long without tray goggles while those damned engineers get their dual-purpose gogles all to themselves
	name = "optical t-ray scanner"
	icon_state = "trayson-t-ray"
	item_state = "trayson-t-ray"
	desc = "Used by engineering staff to see underfloor objects such as cables and pipes. Its thermal mode draws a heat map of everything in view, even in the dark: blue is cold, green is comfortable, then yellow, orange and red as it gets hotter, and white is white hot."
	range = 2

	modes = list(MODE_NONE = MODE_TRAY, MODE_TRAY = MODE_THERMAL, MODE_THERMAL = MODE_NONE)

/obj/item/clothing/glasses/meson/engine/shuttle
	name = "shuttle region scanner"
	icon_state = "trayson-shuttle"
	item_state = "trayson-shuttle"
	desc = "Used to see the boundaries of shuttle regions."

	modes = list(MODE_NONE = MODE_SHUTTLE, MODE_SHUTTLE = MODE_NONE)

#undef MODE_NONE
#undef MODE_MESON
#undef MODE_TRAY
#undef MODE_RAD
#undef MODE_SHUTTLE
#undef MODE_THERMAL
