// Botanical HUD: glasses that show what a hydroponics tray's own indicator lights and plant sprite don't. The tray's lights
// (update_icon_lights()) only come on while something's planted, and only once it's already in trouble - water at 10 or
// less, nutrients at 2 or less, health at half or less, pests/weeds/toxins hurting it - or ready to harvest. The HUD adds:
// water and nutrient levels up the left edge (on empty trays too), the plant's health across the top (red exactly when the
// tray's low-health light is on), its progress to the next harvest up the right edge, and in the corner which of pests,
// weeds or toxins is the trouble - yellow while it builds up, before the tray's alert light, red when the alert light
// comes on. Nothing that duplicates the tray: no harvest or dead badge, and it stays clear of the tray's light panel.
// The images live on the trays and are refreshed whenever a tray redraws (update_icon()).

/datum/atom_hud/data/botany
	hud_icons = list(PLANT_WATER_HUD, PLANT_NUTRI_HUD, PLANT_HEALTH_HUD, PLANT_GROWTH_HUD, PLANT_ALERT_HUD)

/obj/item/clothing/glasses/hud/botany
	name = "botanical HUD"
	desc = "A heads-up display that shows the water, nutrients, health and growth of every hydroponics tray in view, and flags pests, weeds and toxins."
	icon = 'hippiestation/icons/obj/dept_gear.dmi'
	icon_state = "planthud"
	item_state = "glasses"
	alternate_worn_icon = 'hippiestation/icons/mob/dept_gear_worn.dmi'
	hud_type = DATA_HUD_BOTANY
	glass_colour_type = /datum/client_colour/glass_colour/lightgreen

/obj/machinery/hydroponics
	hud_possible = list(PLANT_WATER_HUD, PLANT_NUTRI_HUD, PLANT_HEALTH_HUD, PLANT_GROWTH_HUD, PLANT_ALERT_HUD)

/obj/machinery/hydroponics/Initialize()
	. = ..()
	prepare_huds()
	for(var/key in hud_list)
		var/image/holder = hud_list[key]
		holder.icon = 'hippiestation/icons/mob/plant_hud.dmi'
		holder.layer = ABOVE_MOB_LAYER // over the plant, and over whoever's tending it
	var/datum/atom_hud/data/botany/hud = GLOB.huds[DATA_HUD_BOTANY]
	hud.add_to_hud(src)
	update_plant_hud()

/obj/machinery/hydroponics/Destroy()
	var/datum/atom_hud/data/botany/hud = GLOB.huds[DATA_HUD_BOTANY]
	hud.remove_from_hud(src)
	for(var/key in hud_list)
		var/image/holder = hud_list[key]
		holder.loc = null
	hud_list = null
	return ..()

/obj/machinery/hydroponics/update_icon()
	. = ..()
	update_plant_hud()

/// Points the tray's botanical HUD images at its current state
/obj/machinery/hydroponics/proc/update_plant_hud()
	if(!hud_list)
		return
	var/image/water = hud_list[PLANT_WATER_HUD]
	var/image/nutri = hud_list[PLANT_NUTRI_HUD]
	if(self_sustaining) // it waters and feeds itself
		water.icon_state = ""
		nutri.icon_state = ""
	else
		water.icon_state = "water[plant_hud_level(waterlevel, maxwater)]"
		nutri.icon_state = "nutri[plant_hud_level(nutrilevel, maxnutri)]"

	var/image/health = hud_list[PLANT_HEALTH_HUD]
	var/image/growth = hud_list[PLANT_GROWTH_HUD]
	if(!myseed || dead) // a dead plant's withered sprite and the tray's low-health light already say it
		health.icon_state = ""
		growth.icon_state = ""
	else
		var/band = "good"
		if(plant_health <= (myseed.endurance / 2)) // the tray's own low-health light (update_icon_lights())
			band = "low"
		else if(plant_health <= myseed.endurance * 0.75)
			band = "fair"
		health.icon_state = "health[plant_hud_level(plant_health, myseed.endurance)]_[band]"
		growth.icon_state = "growth[harvest ? 10 : plant_hud_level(harvest_progress(), 1)]"

	var/image/alert = hud_list[PLANT_ALERT_HUD]
	alert.icon_state = plant_hud_alert()

/// 0 to 10, for the HUD's bars
/proc/plant_hud_level(value, maximum)
	if(maximum <= 0)
		return 0
	return clamp(round(10 * value / maximum), 0, 10)

/// How far along the plant is to its next harvest, 0 to 1. Its first harvest comes at age maturation + production (see
/// process()); after that every production + 1 cycles, counted from the harvest (update_tray() sets lastproduce).
/obj/machinery/hydroponics/proc/harvest_progress()
	if(!myseed)
		return 0
	if(lastproduce < myseed.maturation) // not harvested yet
		return age / max(1, myseed.maturation + myseed.production)
	return (age - lastproduce) / max(1, myseed.production + 1)

/// The worst of pests, weeds and toxins: "<kind>1" while it's building up, "<kind>2" once it hurts the plant - the same
/// thresholds as process()'s damage and the tray's alert light
/obj/machinery/hydroponics/proc/plant_hud_alert()
	var/best
	var/best_severity = 0
	for(var/kind in list("toxic", "pests", "weeds"))
		var/severity = 0
		switch(kind)
			if("toxic")
				severity = toxic >= 40 ? 2 : (toxic >= 20 ? 1 : 0)
			if("pests")
				severity = pestlevel >= 5 ? 2 : (pestlevel >= 3 ? 1 : 0)
			if("weeds")
				severity = weedlevel >= 5 ? 2 : (weedlevel >= 3 ? 1 : 0)
		if(severity > best_severity)
			best = kind
			best_severity = severity
	return best ? "[best][best_severity]" : ""

// A closer look (examine it twice): how to use it
/obj/item/clothing/glasses/hud/botany/examine_more(mob/user)
	. = ..()
	. += "<span class='notice'>Looking at a hydroponics tray, it shows water and nutrients up the left edge, the plant's health across the top, and its progress to the next harvest up the right edge.</span>"
	. += "<span class='notice'>An icon in the corner warns of pests, weeds or toxins: yellow while they build up, red once they're hurting the plant.</span>"
