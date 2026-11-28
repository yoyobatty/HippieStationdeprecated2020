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
	make_backdrop()

/// Bigger and blurred. Not left to Initialize() alone: a splash's backdrop can be made before atoms initialize (SStitle's)
/obj/effect/title_backdrop/proc/make_backdrop()
	transform = matrix(1.6, 0, 0, 0, 1.6, 0)
	filters = filter(type = "blur", size = 5)

// The picture that fades out over the game when a round starts, or in at a reboot (/obj/screen/splash): tg put it at the bottom
// left of the view, two columns left of the lobby's, so at round start the lobby jumped left before it faded. Now it's in the
// middle with the same backdrop under it, so the lobby fades into the game where it stands.
/obj/screen/splash
	screen_loc = "CENTER-7,CENTER-7"
	/// The blurred copy under the picture
	var/obj/effect/title_backdrop/backdrop

/obj/screen/splash/New(client/C, visible, use_previous_title)
	. = ..()
	if(QDELETED(src))
		return
	backdrop = new
	backdrop.icon = icon
	backdrop.vis_flags = VIS_UNDERLAY // under the picture, and faded with it
	backdrop.make_backdrop()
	vis_contents += backdrop

/obj/screen/splash/Destroy()
	vis_contents.Cut()
	QDEL_NULL(backdrop)
	return ..()

// ---- A ghost's zoom keeps the view's shape. tg's added a tile to both sides at once and clamped each on its own, so from 19x15
// it went through even sizes (20x16) to a square 21x21 out and 15x15 in, and Auto Fit resized the map pane for each shape.

/// A view `height` tiles tall (odd) in the shape of this client's usual one: 19x15 widescreen or 15x15 square. Its width is the
/// nearest odd number, so the eye stays in the middle tile. The usual height gives the usual view back, as change_view() wants it.
/client/proc/view_in_usual_shape(height)
	var/list/usual = getviewsize((prefs && !prefs.widescreenpref) ? CONFIG_GET(string/default_view_square) : CONFIG_GET(string/default_view))
	if(height == usual[2])
		return CONFIG_GET(string/default_view)
	var/exact = height * usual[1] / usual[2]
	var/width = round(exact)
	if(!(width % 2))
		width += exact > width ? 1 : -1
	return "[width]x[height]"

/// Shift and the mouse wheel: a step is two tiles taller or shorter, from min to max tall, in the view's usual shape
/client/rescale_view(change, min, max)
	var/height = getviewsize(view)[2] + change * 2
	if(!(height % 2))
		height += change > 0 ? -1 : 1
	change_view(view_in_usual_shape(clamp(height, min, max)))

/mob/dead/observer/change_view_range()
	var/max_view = client.prefs.unlock_content ? GHOST_MAX_VIEW_RANGE_MEMBER : GHOST_MAX_VIEW_RANGE_DEFAULT
	if(getviewsize(client.view)[2] == getviewsize(CONFIG_GET(string/default_view))[2])
		var/list/views = list()
		for(var/i in 7 to max_view)
			views |= i
		var/new_view = tgui_input_list(usr, "Choose your new view", "Modify view range", views, 7)
		if(new_view)
			client.change_view(client.view_in_usual_shape(clamp(new_view, 7, max_view) * 2 + 1))
	else
		client.change_view(CONFIG_GET(string/default_view))

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
