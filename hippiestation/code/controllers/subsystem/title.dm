// The lobby's picture fills any view. The title screens (config/title_screens/images, icons/default_title.dmi) are 480 px, a
// 15x15 view, and the default view is 19x15: that left two empty columns either side, black on one and the CentCom sky on the
// other. Behind the picture now sits a copy of it, bigger, blurred and darkened, so the sides carry on in its colours. The
// picture itself stays whole: scaling it to cover the width would crop its top and bottom (the lobby's vertical title text).

/// The title picture again, behind it: 1.6 times as big covers a view 24 tiles wide
/obj/effect/title_backdrop
	name = "Space Station 13"
	icon = 'icons/blank_title.png'
	icon_state = ""
	layer = SPLASHSCREEN_LAYER - 0.1
	plane = SPLASHSCREEN_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	anchored = TRUE
	color = list(0.42, 0, 0, 0, 0.42, 0, 0, 0, 0.42)

/obj/effect/title_backdrop/Initialize(mapload)
	. = ..()
	transform = matrix(1.6, 0, 0, 0, 1.6, 0)
	filters = filter(type = "blur", size = 5)

/turf/closed/indestructible/splashscreen
	/// The blurred copy behind the picture
	var/obj/effect/title_backdrop/backdrop

/turf/closed/indestructible/splashscreen/Initialize(mapload)
	. = ..()
	backdrop = new(src)
	refresh_title_backdrop()

/turf/closed/indestructible/splashscreen/Destroy()
	QDEL_NULL(backdrop)
	return ..()

/// Gives the backdrop the picture the lobby shows now
/turf/closed/indestructible/splashscreen/proc/refresh_title_backdrop()
	backdrop?.icon = icon

/turf/closed/indestructible/splashscreen/vv_edit_var(var_name, var_value)
	. = ..()
	if(. && var_name == NAMEOF(src, icon))
		refresh_title_backdrop()

/datum/controller/subsystem/title/Initialize()
	. = ..()
	splash_turf?.refresh_title_backdrop()

/datum/controller/subsystem/title/vv_edit_var(var_name, var_value)
	. = ..()
	if(. && var_name == NAMEOF(src, icon))
		splash_turf?.refresh_title_backdrop()
