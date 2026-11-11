// Where the station is parked: one look for each sky in sky_themes.dm, weighted as the sky is there. SSparallax picks a sky
// before config loads; this rolls it again with config's weights and puts it up at once, so the lobby sees it.

/datum/station_look/sky
	slot = LOOK_SLOT_SKY
	/// The /datum/sky_theme it puts up
	var/theme_type

/datum/station_look/sky/New(path)
	..()
	theme_type = path
	var/datum/sky_theme/T = path
	name = initial(T.name)
	weight = initial(T.weight)
	var/list/parts = splittext("[path]", "/")
	id = "sky_[parts[length(parts)]]"

/datum/station_look/sky/apply(at_start)
	..()
	if(SSparallax.theme?.type != theme_type)
		SSparallax.set_theme(new theme_type)

/datum/station_look/sky/news_line()
	if(theme_type == /datum/sky_theme/quiet)
		return //plain black: nothing to tell
	return "Parked off [name]."
