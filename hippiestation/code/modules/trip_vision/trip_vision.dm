/*
 * A trip's vision. A drug that changes how things look changes one picture of the whole view, as it would change your eyes:
 * nothing in the world is touched, and the game's own planes aren't either, so lights, glows, space and particles all go the same
 * way at once.
 *
 * TRIP_WORLD_PLANE is hidden. It holds a copy of every plane below it, in order (the fullscreen overlays and the HUD stay on top,
 * untouched, so they're always there to use), each blended as its plane
 * master blends it. A plane master's render target carries its colour, alpha, filters and transform, so the copy is the screen as
 * drawn (measured with a real client on 516.1688). The fractal goes over the top. This plane master bends the picture (the
 * flowing warp, the fisheye, shockwaves, melting, streaks when you move).
 * TRIP_TURN_PLANE is hidden: the picture again, as one plain copy that tilts, spins, flips, zooms and flashes its colours now and
 * then. Moving a filtered plane master or a filtered object makes the client redo its filters every frame (turning the picture's
 * plane master took the frame rate from 28 to 12; five masked tunnel copies shrinking, from 30 to 6), so nothing that moves has a
 * filter of its own.
 * TRIP_SPIN_PLANE is hidden too: the turned picture again, turning, for the kaleidoscope. TRIP_DISC_PLANE: the turned picture with
 * its edge faded, once and holding still, for the tunnel's copies to shrink.
 * TRIP_VIEW_PLANE draws the picture over the whole screen: as three copies, one per colour channel, which carry the colour grade
 * and pull apart for double vision; as eight mirrored wedges of the turning picture, a kaleidoscope; and as copies of itself
 * nested ever smaller, a tunnel that falls away forever. Its plane master sways the lot, always far enough in that the screen
 * beneath never shows at its edges.
 *
 * How it moves, all measured with a real client:
 * - Everything that moves all the time is a loop the client plays by itself. The server only changes a loop when the trip's
 *   level changes, and only when the loop is passing through its middle, still, so the change never jerks. A loop started before
 *   the client has the object never plays for it, so every moving part belongs to one tripper and starts once it's on their screen.
 *   A loop of one step plays once and stops, so each ends with an instant step back to where it began.
 * - Whatever else changes glides there over seconds and is left alone until it arrives: two animations of one var at once fight.
 *   Filter animations only run with ANIMATION_PARALLEL. A parallel animation doesn't set the var, and a plain animate() of the same
 *   object ends it and puts the var's value back, so anything that must stay put is set plainly.
 * - Nothing is made or thrown away mid-trip. The filters are all made at the start and only ever animated; the kaleidoscope and
 *   the tunnel stay on the screen and fade.
 * - The fractal is one of GRAPE_FRACTAL_VARIATIONS, each time turned, zoomed, mirrored and coloured at random and drifting, and
 *   every so often it fades into another on the other fractal plane. Its table scrolls a random way at a random speed each trip.
 */

/// How far in the view zooms through a turn, so the corners stay covered at any angle (the square root of 2)
#define TRIP_WIDE 1.4142
// The picture's filters, by place: all made at the start and only ever animated
#define TRIP_FILTER_FLOW 1
#define TRIP_FILTER_FLOW_2 2
#define TRIP_FILTER_STREAK 3
#define TRIP_FILTER_FISHEYE 4
#define TRIP_FILTER_WAVE 5
#define TRIP_FILTER_RIPPLE 6
#define TRIP_FILTER_RADIAL 7
#define TRIP_FILTER_RAYS 8
#define TRIP_FILTER_BLOOM 9

/// A plane master only a tripper has. Not an /obj/screen/plane_master, so no HUD makes one by itself
/obj/screen/trip_plane
	name = "trip plane master"
	screen_loc = "CENTER"
	icon_state = "blank"
	appearance_flags = PLANE_MASTER | NO_CLIENT_COLOR
	blend_mode = BLEND_OVERLAY
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT

/// The picture of the whole screen
/obj/screen/trip_plane/picture
	plane = TRIP_WORLD_PLANE
	render_target = TRIP_WORLD_RENDER_TARGET

/// The picture, drawn over the screen
/obj/screen/trip_plane/view
	plane = TRIP_VIEW_PLANE
	alpha = 0

/obj/screen/trip_plane/lut
	plane = GRAPE_LUT_PLANE
	render_target = GRAPE_LUT_RENDER_TARGET

/obj/screen/trip_plane/fractal
	plane = GRAPE_FRACTAL_PLANE
	render_target = GRAPE_FRACTAL_RENDER_TARGET
	alpha = 0

/obj/screen/trip_plane/fractal/second
	plane = GRAPE_FRACTAL_B_PLANE
	render_target = GRAPE_FRACTAL_B_RENDER_TARGET

/obj/screen/trip_plane/warp
	plane = TRIP_WARP_PLANE
	render_target = TRIP_WARP_RENDER_TARGET

/obj/screen/trip_plane/turn
	plane = TRIP_TURN_PLANE
	render_target = TRIP_TURN_RENDER_TARGET

/obj/screen/trip_plane/kaleido
	plane = TRIP_KALEIDO_PLANE
	render_target = TRIP_KALEIDO_RENDER_TARGET

/obj/screen/trip_plane/spin
	plane = TRIP_SPIN_PLANE
	render_target = TRIP_SPIN_RENDER_TARGET

/obj/screen/trip_plane/disc
	plane = TRIP_DISC_PLANE
	render_target = TRIP_DISC_RENDER_TARGET

/// A plane master for a plane that has none, so the trip can copy it: laser tracers are drawn above the lighting, and open space
/// below the floor. Only a tripper has these, so nobody else's screen changes
/obj/screen/trip_plane/copied
	mouse_opacity = MOUSE_OPACITY_ICON

/obj/screen/trip_plane/copied/above_lighting
	plane = ABOVE_LIGHTING_PLANE
	render_target = "TRIP_ABOVE_LIGHTING"

/obj/screen/trip_plane/copied/openspace
	plane = OPENSPACE_PLANE
	render_target = "TRIP_OPENSPACE"


/// A copy of one plane in the picture, drawn from the screen's bottom-left corner as all the copies are
/obj/screen/trip_copy
	name = "trip"
	plane = TRIP_WORLD_PLANE
	screen_loc = "1,1"
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	appearance_flags = NO_CLIENT_COLOR

/// Black under the picture, so it hides everything beneath it
/obj/screen/trip_backdrop
	name = "trip"
	icon = 'icons/mob/screen_gen.dmi'
	icon_state = "flash"
	color = "#000000"
	plane = TRIP_WORLD_PLANE
	layer = 0
	screen_loc = "CENTER"
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	appearance_flags = NO_CLIENT_COLOR

/obj/screen/trip_backdrop/New()
	..()
	transform = matrix(200, 0, 0, 0, 200, 0)

/// A tile of moving art: the flow's noise or the fractal's table. Moved by a transform, since pixel offsets do nothing to a
/// screen object and anything bigger than the screen pushes the whole view off centre
/obj/screen/trip_tile
	name = "trip"
	icon = 'hippiestation/icons/effects/trip_vision.dmi'
	screen_loc = "1,1"
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	appearance_flags = NO_CLIENT_COLOR

/// One layer of the fractal: the scrolled table read through that layer's map (tools/trip_vision/trip_vision.py)
/obj/screen/trip_fractal_layer
	name = "trip"
	screen_loc = "1,1"
	blend_mode = BLEND_ADD
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	appearance_flags = NO_CLIENT_COLOR
	render_source = GRAPE_LUT_RENDER_TARGET

/// Every plane the trip copies, lowest first, as list(plane, render target name, blend mode). A plane master with no render
/// target is given this one while its client trips
GLOBAL_LIST_INIT(trip_copied_planes, list_trip_copied_planes())

/proc/list_trip_copied_planes()
	var/list/found = list()
	for(var/path in subtypesof(/obj/screen/plane_master) + subtypesof(/obj/screen/trip_plane/copied))
		var/obj/screen/S = path
		var/plane = initial(S.plane)
		var/target = initial(S.render_target)
		if(plane >= TRIP_WORLD_PLANE || copytext(target, 1, 2) == "*") // the trip's own, and the hidden ones nothing sees
			continue
		found["[plane]"] = list(plane, target || "TRIP_PLANE_[plane]", initial(S.blend_mode))
	. = list()
	while(length(found)) // lowest plane first
		var/lowest
		for(var/key in found)
			if(isnull(lowest) || found[key][1] < found[lowest][1])
				lowest = key
		. += list(found[lowest])
		found -= lowest

/// What every tripper shares: the copies of the planes and the extra plane masters
GLOBAL_LIST_INIT(trip_shared_screens, make_trip_shared_screens())

/proc/make_trip_shared_screens()
	. = list()
	var/layer_number = 0
	for(var/list/copied in GLOB.trip_copied_planes)
		var/obj/screen/trip_copy/copy = new
		copy.render_source = copied[2]
		copy.blend_mode = copied[3]
		copy.layer = ++layer_number
		. += copy
	for(var/path in subtypesof(/obj/screen/trip_plane/copied))
		. += new path

/// Each variation of the fractal's four maps (tools/trip_vision/trip_vision.py). Every filter map is a file of its own: a filter
/// given icon(file, state) gets a new resource made on the spot, which a client hasn't got, and a plane master drawn through such a
/// filter stayed blank till its filters were set again (measured)
GLOBAL_LIST_INIT(trip_fractal_maps, list(
	list('hippiestation/icons/effects/trip/v1map1.png', 'hippiestation/icons/effects/trip/v1map2.png', 'hippiestation/icons/effects/trip/v1map3.png', 'hippiestation/icons/effects/trip/v1map4.png'),
	list('hippiestation/icons/effects/trip/v2map1.png', 'hippiestation/icons/effects/trip/v2map2.png', 'hippiestation/icons/effects/trip/v2map3.png', 'hippiestation/icons/effects/trip/v2map4.png'),
	list('hippiestation/icons/effects/trip/v3map1.png', 'hippiestation/icons/effects/trip/v3map2.png', 'hippiestation/icons/effects/trip/v3map3.png', 'hippiestation/icons/effects/trip/v3map4.png'),
	list('hippiestation/icons/effects/trip/v4map1.png', 'hippiestation/icons/effects/trip/v4map2.png', 'hippiestation/icons/effects/trip/v4map3.png', 'hippiestation/icons/effects/trip/v4map4.png'),
	list('hippiestation/icons/effects/trip/v5map1.png', 'hippiestation/icons/effects/trip/v5map2.png', 'hippiestation/icons/effects/trip/v5map3.png', 'hippiestation/icons/effects/trip/v5map4.png')))

/// What a drug is doing to this mob's eyes, while it's doing anything
/mob/living/var/datum/trip_vision/trip_vision

/// Has the client fetch the trip's art (about 2.4 MB, once: the client keeps it) while the drug comes up, so it's there when the
/// trip starts: an unseen image of each file on the mob, for that client, for a minute. Images on the map, not screen objects: a
/// screen object's icon bigger than the view grows the whole screen to fit it whatever its transform, and the flow's maps are twice
/// the view (it zoomed the player's game right out, 2026-11-12)
/proc/trip_preload(mob/M)
	var/client/C = M?.client
	if(!C)
		return
	var/list/art = list('hippiestation/icons/effects/trip_vision.dmi', 'hippiestation/icons/effects/trip/bulge.png', 'hippiestation/icons/effects/trip/flow1.png', 'hippiestation/icons/effects/trip/flow2.png', 'hippiestation/icons/effects/trip/wedge.png', 'hippiestation/icons/effects/trip/disc.png')
	for(var/list/maps in GLOB.trip_fractal_maps)
		art += maps
	var/list/fetch = list()
	for(var/file in art)
		var/image/I = image(file, M)
		I.alpha = 1
		I.transform = matrix(0.01, 0, 0, 0, 0.01, 0)
		I.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
		I.appearance_flags = RESET_TRANSFORM | RESET_COLOR | RESET_ALPHA | NO_CLIENT_COLOR
		fetch += I
	C.images += fetch
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(trip_preload_done), C, fetch), 1 MINUTES)

/proc/trip_preload_done(client/C, list/fetch)
	C?.images -= fetch
	fetch.Cut()

/datum/trip_vision
	var/mob/living/owner
	var/obj/screen/trip_plane/picture/world_pm
	var/obj/screen/trip_plane/view/view_pm
	var/list/own_screens = list()
	/// The fractal's table, tiled two by two
	var/list/tables = list()
	/// The picture in red, green and blue: they carry the colour grade, and pull apart for double vision
	var/list/channels = list()
	/// The picture's copy that carries its filters: the flow, the fisheye, the bursts and the streaks; and a plain copy under it,
	/// which shows while the warped one draws nothing (see rebuild_warp())
	var/obj/screen/trip_copy/warp_copy
	var/obj/screen/trip_copy/plain_copy
	/// The warped picture's plain copy that tilts, spins, flips and flashes; the turning copy the kaleidoscope folds and its eight wedges;
	/// the faded-edge copy and the tunnel's nested copies of it
	var/obj/screen/trip_copy/turn_copy
	/// The turned picture's still copy that only the turning copy reads: a turning reader moves the render target it reads for
	/// every reader at a map zoom other than 1, so it gets one of its own
	var/obj/screen/trip_copy/kaleido_copy
	var/obj/screen/trip_copy/spin_copy
	var/obj/screen/trip_copy/disc_copy
	var/list/kaleido = list()
	var/list/tunnels = list()
	/// The two fractal planes' masters, each one's four layers, and each one's copy in the picture
	var/list/fractal_pms = list()
	var/list/fractal_layers = list()
	var/list/fractal_copies = list()
	/// Which fractal plane is showing (1 or 2), each one's variation, and each one's colour
	var/fractal_slot = 1
	var/list/fractal_variation = list(0, 0)
	var/list/fractal_hue = list(null, null)
	var/fractal_alpha = 0
	var/next_fractal = 0
	var/active = FALSE
	/// The last strength and mood update() was given
	var/intensity = 0
	var/bad = FALSE
	/// The trip's level, 0 to 3, plus 10 for a bad trip: the loops change shape when it changes
	var/mood = -1
	/// Where the view's sway and the colour grade's loops started and how long a round of each takes, so they're only ever
	/// changed as they pass through their middle
	var/sway_start = 0
	var/sway_period = 0
	var/grade_start = 0
	var/grade_period = 0
	/// How far the flow moves the view, in pixels
	var/flow_size = 0
	var/kaleido_alpha = 0
	// Each of these owns its var until then
	var/fade_until = 0
	var/flow_until = 0
	var/fractal_until = 0
	var/kaleido_until = 0
	var/geometry_until = 0
	var/colour_until = 0
	var/split_until = 0
	/// The grade owns the channels' every var while it glides into a new loop: a split waits
	var/grade_glide_until = 0
	var/streak_until = 0
	var/fisheye_until = 0
	var/tunnel_until = 0
	var/breakthrough_until = 0
	var/list/burst_until = list()

/datum/trip_vision/New(mob/living/M)
	owner = M
	RegisterSignal(owner, COMSIG_PARENT_QDELETING, PROC_REF(owner_gone))
	world_pm = new // its filters go on once it's on the screen (show_filters())
	view_pm = new
	own_screens += list(world_pm, view_pm, new /obj/screen/trip_plane/lut, new /obj/screen/trip_plane/warp, new /obj/screen/trip_plane/turn, new /obj/screen/trip_plane/kaleido, new /obj/screen/trip_plane/spin, new /obj/screen/trip_plane/disc, new /obj/screen/trip_backdrop)
	plain_copy = new
	plain_copy.plane = TRIP_WARP_PLANE
	plain_copy.layer = 1
	plain_copy.render_source = TRIP_WORLD_RENDER_TARGET
	warp_copy = new
	warp_copy.plane = TRIP_WARP_PLANE
	warp_copy.layer = 2
	warp_copy.render_source = TRIP_WORLD_RENDER_TARGET
	turn_copy = new
	turn_copy.plane = TRIP_TURN_PLANE
	turn_copy.render_source = TRIP_WARP_RENDER_TARGET
	for(var/i in 1 to 4)
		var/obj/screen/trip_tile/table = new
		table.icon_state = "lut"
		table.plane = GRAPE_LUT_PLANE
		tables += table
	for(var/i in 1 to 3)
		var/obj/screen/trip_copy/channel = new
		channel.plane = TRIP_VIEW_PLANE
		channel.render_source = TRIP_TURN_RENDER_TARGET
		channel.blend_mode = BLEND_ADD
		channel.color = channel_mask(i)
		channels += channel
	kaleido_copy = new
	kaleido_copy.plane = TRIP_KALEIDO_PLANE
	kaleido_copy.render_source = TRIP_TURN_RENDER_TARGET
	spin_copy = new
	spin_copy.plane = TRIP_SPIN_PLANE
	spin_copy.render_source = TRIP_KALEIDO_RENDER_TARGET
	var/wedge = 'hippiestation/icons/effects/trip/wedge.png'
	for(var/k in 0 to 7)
		var/obj/screen/trip_copy/fold = new
		fold.plane = TRIP_VIEW_PLANE
		fold.layer = 10
		fold.render_source = TRIP_SPIN_RENDER_TARGET
		fold.alpha = 0
		fold.filters = filter(type = "alpha", icon = wedge)
		fold.transform = kaleido_matrix(k)
		kaleido += fold
	disc_copy = new // faded at the edge once, holding still: the tunnel's copies shrink it with no filter of their own
	disc_copy.plane = TRIP_DISC_PLANE
	disc_copy.render_source = TRIP_TURN_RENDER_TARGET
	disc_copy.filters = filter(type = "alpha", icon = 'hippiestation/icons/effects/trip/disc.png')
	for(var/level in 1 to 5)
		var/obj/screen/trip_copy/nested = new
		nested.plane = TRIP_VIEW_PLANE
		nested.layer = 20 + level
		nested.render_source = TRIP_DISC_RENDER_TARGET
		nested.alpha = 0
		tunnels += nested
	var/list/fractal_planes = list(GRAPE_FRACTAL_PLANE, GRAPE_FRACTAL_B_PLANE)
	var/list/fractal_targets = list(GRAPE_FRACTAL_RENDER_TARGET, GRAPE_FRACTAL_B_RENDER_TARGET)
	for(var/slot in 1 to 2)
		fractal_pms += (slot == 1 ? new /obj/screen/trip_plane/fractal : new /obj/screen/trip_plane/fractal/second)
		var/list/layers = list()
		for(var/i in 1 to 4)
			var/obj/screen/trip_fractal_layer/layer = new
			layer.plane = fractal_planes[slot]
			layers += layer
			own_screens += layer
		fractal_layers += list(layers)
		var/obj/screen/trip_copy/copy = new // the fractal, added over everything
		copy.render_source = fractal_targets[slot]
		copy.blend_mode = BLEND_ADD
		copy.layer = 100 + slot
		fractal_copies += copy
	for(var/slot in list(TRIP_FILTER_WAVE, TRIP_FILTER_RIPPLE, TRIP_FILTER_RADIAL, TRIP_FILTER_RAYS, TRIP_FILTER_BLOOM))
		burst_until["[slot]"] = 0
	own_screens += tables + channels + kaleido + tunnels + fractal_pms + fractal_copies + spin_copy + turn_copy + disc_copy + warp_copy + plain_copy + kaleido_copy

/datum/trip_vision/Destroy()
	hide()
	if(owner)
		UnregisterSignal(owner, COMSIG_PARENT_QDELETING)
		if(owner.trip_vision == src)
			owner.trip_vision = null
	owner = null
	world_pm = null
	view_pm = null
	spin_copy = null
	turn_copy = null
	kaleido_copy = null
	disc_copy = null
	warp_copy = null
	plain_copy = null
	tables.Cut()
	channels.Cut()
	kaleido.Cut()
	tunnels.Cut()
	fractal_pms.Cut()
	fractal_layers.Cut()
	fractal_copies.Cut()
	QDEL_LIST(own_screens)
	return ..()

/datum/trip_vision/proc/owner_gone()
	SIGNAL_HANDLER
	qdel(src)

/datum/trip_vision/proc/screens()
	return own_screens + GLOB.trip_shared_screens

/// Only colour channel i (1 red, 2 green, 3 blue) of whatever comes in
/datum/trip_vision/proc/channel_mask(i)
	var/list/mask = list(0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,1, 0,0,0,0)
	mask[(i - 1) * 5 + 1] = 1
	return mask

/// On the owner's screen, with the planes it copies named and its art moving. Again after the owner's HUD is remade.
/// The plane masters go on first, the copies a tick later, and the picture's filters five seconds after that (show_filters()).
/// trip_preload() has the client fetch the art while the drug comes up
/datum/trip_vision/proc/show()
	var/client/C = owner?.client
	if(!C || !owner.hud_used)
		return
	for(var/list/copied in GLOB.trip_copied_planes)
		var/obj/screen/plane_master/PM = owner.hud_used.plane_masters["[copied[1]]"]
		if(PM && !PM.render_target)
			PM.render_target = copied[2]
	warp_copy.filters = list() // put back once it's on the screen again (show_filters())
	var/list/masters = list()
	for(var/obj/screen/S as anything in screens())
		if(S.appearance_flags & PLANE_MASTER)
			masters += S
	C.screen |= masters
	mood = -1 // the loops start again on the next update after this
	sway_period = 0
	grade_period = 0
	addtimer(CALLBACK(src, PROC_REF(show_copies)), 1)

/datum/trip_vision/proc/show_copies()
	var/client/C = owner?.client
	if(!C)
		return
	C.screen |= screens()
	// The picture's filters wait till it has been drawing a while: a picture that has them when it first draws stays blank on the
	// client however long it waits (measured), while one that gets them later takes them up fine
	addtimer(CALLBACK(src, PROC_REF(show_filters)), 1 SECONDS, TIMER_UNIQUE | TIMER_OVERRIDE)
	addtimer(CALLBACK(src, PROC_REF(rebuild_warp)), 12 SECONDS, TIMER_UNIQUE | TIMER_OVERRIDE)
	var/size = GRAPE_FRACTAL_VIEW * world.icon_size
	// The fractal's table scrolls a random way at a random speed from a random place, a new one each trip
	var/dir_x = pick(-1, 1)
	var/dir_y = pick(-1, 1)
	var/start_x = rand(0, GRAPE_FRACTAL_PERIOD - 1)
	var/start_y = rand(0, GRAPE_FRACTAL_PERIOD - 1)
	var/time = GRAPE_FRACTAL_LOOP_TIME * rand(75, 135) / 100
	var/base_x = dir_x < 0 ? 0 : -size // moving right, the tiles start a tile to the left so the screen stays covered
	var/base_y = dir_y < 0 ? 0 : -size
	var/list/corners = list(list(0, 0), list(size, 0), list(0, size), list(size, size))
	for(var/i in 1 to 4)
		var/obj/screen/trip_tile/table = tables[i]
		var/list/at = corners[i]
		var/x = base_x + at[1] - dir_x * start_x
		var/y = base_y + at[2] - dir_y * start_y
		var/matrix/home = matrix(1, 0, x, 0, 1, y)
		table.transform = home
		animate(table, transform = matrix(1, 0, x - dir_x * GRAPE_FRACTAL_LOOP_X, 0, 1, y - dir_y * GRAPE_FRACTAL_LOOP_Y), time = time, loop = -1)
		animate(transform = home, time = 0)
	// The picture the kaleidoscope folds turns all trip long
	spin_copy.transform = matrix()
	animate(spin_copy, transform = turn(matrix(), 120), time = 8 SECONDS, loop = -1)
	animate(transform = turn(matrix(), 240), time = 8 SECONDS)
	animate(transform = matrix(), time = 8 SECONDS)
	// The tunnel falls away all trip long, unseen until it fades in
	for(var/level in 1 to length(tunnels))
		var/obj/screen/trip_copy/nested = tunnels[level]
		nested.transform = tunnel_matrix(level)
		animate(nested, transform = tunnel_matrix(level - 1), time = 3 SECONDS, loop = -1) // each grows into the one before: forever
		animate(transform = tunnel_matrix(level), time = 0)

/// The picture's filters, put on once the picture's plane master and everything it reads are on the client's screen. The flow is
/// two maps of noise, each sliding its own way by one repeat and starting again (trip_flow.dmi, a repeat each way past the screen)
/datum/trip_vision/proc/show_filters()
	if(!warp_copy || length(warp_copy.filters))
		return
	var/half = GRAPE_FRACTAL_VIEW * world.icon_size / 2
	warp_copy.filters = list(
		filter(type = "displace", size = flow_size * 0.6, x = -half, y = -half, icon = 'hippiestation/icons/effects/trip/flow1.png'),
		filter(type = "displace", size = flow_size * 0.6, x = half, y = -half, icon = 'hippiestation/icons/effects/trip/flow2.png'),
		filter(type = "motion_blur", x = 0, y = 0),
		filter(type = "displace", size = 0, icon = 'hippiestation/icons/effects/trip/bulge.png'),
		filter(type = "wave", x = 10, y = 10, size = 0, offset = 0, flags = WAVE_BOUNDED),
		filter(type = "ripple", x = 0, y = 0, size = 0, repeat = 16, radius = 0, falloff = 1),
		filter(type = "radial_blur", x = 0, y = 0, size = 0),
		filter(type = "rays", x = 0, y = 0, size = 0, color = "#ffffff00", offset = 0, density = 10, threshold = 0.4, factor = 1),
		filter(type = "bloom", threshold = "#404040", size = 1, offset = 1, alpha = 0))
	animate(warp_copy.filters[TRIP_FILTER_FLOW], x = half, y = half, time = TRIP_FLOW_LOOP_TIME, loop = -1, flags = ANIMATION_PARALLEL)
	animate(x = -half, y = -half, time = 0)
	animate(warp_copy.filters[TRIP_FILTER_FLOW_2], x = -half, y = half, time = TRIP_FLOW_LOOP_TIME * 1.37, loop = -1, flags = ANIMATION_PARALLEL)
	animate(x = half, y = -half, time = 0)

/// A filtered copy of a plane that's itself made of copies draws nothing until its filters are taken off and put back once the trip
/// has been on the screen a while: off and on at 4 or 6 seconds in left it blank, at 12 or later it drew from then on, through new
/// fractals, the kaleidoscope and the tunnel, and setting its colour or anything else didn't help (all measured on 516.1688). The
/// warped copy, the faded-edge copy and the kaleidoscope's wedges are all that kind. Until then the plain copy under the warped one
/// shows, so the trip is all there but the warp; the others aren't showing yet anyway. Off and on in one tick never reaches the
/// client, so they're two seconds apart
/datum/trip_vision/proc/rebuild_warp()
	if(QDELETED(src) || !warp_copy || !length(warp_copy.filters))
		return
	warp_copy.filters = list()
	disc_copy.filters = list()
	for(var/obj/screen/trip_copy/fold as anything in kaleido)
		fold.filters = list()
	addtimer(CALLBACK(src, PROC_REF(restore_masks)), 2 SECONDS)

/datum/trip_vision/proc/restore_masks()
	if(QDELETED(src) || !warp_copy)
		return
	show_filters()
	disc_copy.filters = filter(type = "alpha", icon = 'hippiestation/icons/effects/trip/disc.png')
	for(var/obj/screen/trip_copy/fold as anything in kaleido)
		fold.filters = filter(type = "alpha", icon = 'hippiestation/icons/effects/trip/wedge.png')

/// The fractal plane slot's four layers read the maps of variation
/datum/trip_vision/proc/set_fractal_maps(slot, variation)
	var/list/layers = fractal_layers[slot]
	for(var/i in 1 to 4)
		var/obj/screen/trip_fractal_layer/layer = layers[i]
		layer.filters = filter(type = "displace", size = GRAPE_FRACTAL_PERIOD, icon = GLOB.trip_fractal_maps[variation][i])

/datum/trip_vision/proc/hide()
	var/client/C = owner?.client
	if(C)
		C.screen -= screens()
	if(owner?.hud_used)
		for(var/list/copied in GLOB.trip_copied_planes)
			var/obj/screen/plane_master/PM = owner.hud_used.plane_masters["[copied[1]]"]
			if(PM?.render_target == copied[2])
				PM.render_target = initial(PM.render_target)

/// Fades the trip in
/datum/trip_vision/proc/start()
	active = TRUE
	show()
	fade_until = world.time + 5 SECONDS
	// not a parallel animation: those leave the var as it was, and the sway's first glide ends this one, which would put the old
	// alpha back. The sway waits for the fade, so nothing cuts it short
	animate(view_pm, alpha = 255, time = 5 SECONDS, easing = SINE_EASING)
	next_fractal = world.time // the first fractal is picked on the first update

/// Fades it out, then takes it off the screen
/datum/trip_vision/proc/stop(time = 8 SECONDS)
	if(!active)
		return
	active = FALSE
	intensity = 0
	animate(view_pm, alpha = 0, time = time, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
	for(var/obj/screen/trip_plane/fractal/PM as anything in fractal_pms)
		animate(PM, alpha = 0, time = time, easing = SINE_EASING)
	addtimer(CALLBACK(src, PROC_REF(finish_stop)), time + 1)

/// Gone once it has faded, unless another trip started meanwhile
/datum/trip_vision/proc/finish_stop()
	if(!active)
		qdel(src)

/// 0 to 3 by how hard it's hitting, and 10 more when it's gone bad
/datum/trip_vision/proc/level_of(strength, gone_bad)
	return (strength < 0.35 ? 0 : (strength < 0.6 ? 1 : (strength < 0.85 ? 2 : 3))) + (gone_bad ? 10 : 0)

/// The trip's strength now (0 to 1), whether it's gone bad, and how strongly the fractal shows (0 to 1). Each life tick. Only
/// sets things going: the client plays them
/datum/trip_vision/proc/update(new_intensity, new_bad, fractal)
	if(!active)
		return
	var/client/C = owner?.client
	if(!C)
		return
	if(!(view_pm in C.screen)) // a new HUD, or a new client
		show()
	intensity = clamp(new_intensity, 0, 1)
	bad = new_bad
	var/new_mood = level_of(intensity, bad)
	if(new_mood != mood && world.time >= fade_until)
		mood = new_mood
		schedule_sway()
		schedule_grade()
	var/breaking = world.time < breakthrough_until
	// the flow glides to its new strength and is left to get there
	var/flow_target = round(TRIP_FLOW_PEAK * intensity * (bad ? 1.6 : 1), 0.5)
	if(!breaking && world.time >= flow_until && abs(flow_target - flow_size) >= 2 && length(warp_copy.filters))
		flow_size = flow_target
		flow_until = world.time + 6 SECONDS
		for(var/slot in list(TRIP_FILTER_FLOW, TRIP_FILTER_FLOW_2))
			animate(warp_copy.filters[slot], size = flow_size * 0.6, time = 6 SECONDS, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
	// the fractal: a faint glow all trip long, swelling with the waves
	var/list/view_size = getviewsize(C.view)
	var/fits = view_size[1] == GRAPE_FRACTAL_VIEW && view_size[2] == GRAPE_FRACTAL_VIEW
	var/fractal_target = fits ? round(clamp(35 + 220 * fractal, 0, 255)) : 0
	if(!breaking && world.time >= fractal_until)
		if(fits && world.time >= next_fractal)
			new_fractal(fractal_target)
		else if(abs(fractal_target - fractal_alpha) >= 15)
			fractal_alpha = fractal_target
			fractal_until = world.time + 5 SECONDS
			animate(fractal_pms[fractal_slot], alpha = fractal_alpha, time = 5 SECONDS, easing = SINE_EASING)
	// near the top of a trip the kaleidoscope ghosts in over everything, more on a bad one
	if(!breaking)
		set_kaleido(clamp((intensity - 0.7) / 0.3, 0, 1) * (bad ? 150 : 100))
	// and the middle of the view swells and sinks now and then
	if(intensity >= 0.5 && prob(35))
		fisheye(intensity * 2)

// The loops: the view's sway and the colour grade

/// How long until the next round of a loop begins (soon, if none is going)
/datum/trip_vision/proc/next_round(started, period)
	if(!period)
		return 1
	return period - ((world.time - started) % period)

/datum/trip_vision/proc/schedule_sway()
	addtimer(CALLBACK(src, PROC_REF(start_sway)), max(next_round(sway_start, sway_period), 1), TIMER_UNIQUE | TIMER_OVERRIDE)

/datum/trip_vision/proc/schedule_grade()
	var/wait = next_round(grade_start, grade_period)
	if(grade_period && world.time + wait < split_until) // the grade's loop and a split share the channels: wait for the split
		wait += grade_period * CEILING((split_until - world.time - wait) / grade_period, 1)
	addtimer(CALLBACK(src, PROC_REF(start_grade)), max(wait, 1), TIMER_UNIQUE | TIMER_OVERRIDE)

/// How far the view sways each way (degrees) and how long a round takes, at the trip's level
/datum/trip_vision/proc/sway_shape()
	var/level = mood % 10
	var/list/amplitudes = list(1.5, 3, 5, 8)
	var/list/periods = list(12 SECONDS, 10 SECONDS, 8 SECONDS, 7 SECONDS)
	return list(amplitudes[level + 1] + (mood >= 10 ? 4 : 0), periods[level + 1])

/// The view turned by angle, zoomed in enough to cover the screen through a sway of amplitude, and past what the flow pulls in
/datum/trip_vision/proc/sway_matrix(angle, amplitude)
	var/flow_most = TRIP_FLOW_PEAK * (mood >= 10 ? 1.6 : 1)
	var/margin = 1 + 2 * (flow_most + 4) / (GRAPE_FRACTAL_VIEW * world.icon_size)
	var/matrix/M = matrix() * ((abs(cos(amplitude)) + abs(sin(amplitude))) * margin)
	return M.Turn(angle)

/// At a round's end, where the sway sits still in the middle: glide to the new middle, then sway the new way
/datum/trip_vision/proc/start_sway()
	if(!active)
		return
	var/list/shape = sway_shape()
	animate(view_pm, transform = sway_matrix(0, shape[1]), time = 15, easing = SINE_EASING) // ends the old loop
	addtimer(CALLBACK(src, PROC_REF(loop_sway), shape[1], shape[2]), 15)

/datum/trip_vision/proc/loop_sway(amplitude, period)
	if(!active)
		return
	var/matrix/middle = sway_matrix(0, amplitude)
	view_pm.transform = middle
	animate(view_pm, transform = sway_matrix(amplitude, amplitude), time = period / 4, easing = SINE_EASING, loop = -1)
	animate(transform = middle, time = period / 4, easing = SINE_EASING)
	animate(transform = sway_matrix(-amplitude, amplitude), time = period / 4, easing = SINE_EASING)
	animate(transform = middle, time = period / 4, easing = SINE_EASING)
	sway_start = world.time
	sway_period = period

/// The colour grade at the trip's level, turned angle round the wheel
/datum/trip_vision/proc/grade(angle)
	if(mood >= 10) // drained and reddened, a little bloodier each swing
		return color_matrix_multiply(color_matrix_saturation(0.35 + abs(angle) / 900), list(1.25,0,0,0, 0,0.75,0,0, 0,0,0.8,0, 0,0,0,1, 0.04,-0.04,-0.02,0))
	var/list/saturations = list(1.2, 1.6, 2.2, 2.8)
	return color_matrix_multiply(color_matrix_saturation(saturations[max(mood, 0) + 1]), color_matrix_rotate_hue(angle))

/// How far round the wheel the colours swing each way, and how long a round takes
/datum/trip_vision/proc/grade_shape()
	var/level = mood % 10
	var/list/swings = list(20, 60, 120, 180)
	var/list/periods = list(16 SECONDS, 14 SECONDS, 12 SECONDS, 10 SECONDS)
	return list(swings[level + 1], periods[level + 1])

/// At a round's end, where the colours sit at their middle: glide to the new middle, then swing the new way
/datum/trip_vision/proc/start_grade()
	if(!active)
		return
	var/list/shape = grade_shape()
	grade_glide_until = world.time + 17
	for(var/i in 1 to 3)
		animate(channels[i], color = color_matrix_multiply(grade(0), channel_mask(i)), time = 15, easing = SINE_EASING) // ends the old loop
	addtimer(CALLBACK(src, PROC_REF(loop_grade), shape[1], shape[2]), 15)

/datum/trip_vision/proc/loop_grade(swing, period)
	if(!active)
		return
	for(var/i in 1 to 3)
		var/obj/screen/trip_copy/channel = channels[i]
		var/list/mask = channel_mask(i)
		var/list/middle = color_matrix_multiply(grade(0), mask)
		channel.color = middle
		animate(channel, color = color_matrix_multiply(grade(swing), mask), time = period / 4, easing = SINE_EASING, loop = -1)
		animate(color = middle, time = period / 4, easing = SINE_EASING)
		animate(color = color_matrix_multiply(grade(-swing), mask), time = period / 4, easing = SINE_EASING)
		animate(color = middle, time = period / 4, easing = SINE_EASING)
	grade_start = world.time
	grade_period = period

// The fractal

/// Fades in another variation of the fractal on the other plane, turned, zoomed, mirrored and coloured at random and drifting,
/// while the one showing fades out
/datum/trip_vision/proc/new_fractal(target_alpha, time = 6 SECONDS)
	var/old_slot = fractal_slot
	var/slot = fractal_variation[old_slot] ? (old_slot == 1 ? 2 : 1) : old_slot
	var/variation = rand(1, GRAPE_FRACTAL_VARIATIONS)
	if(variation == fractal_variation[old_slot])
		variation = (variation % GRAPE_FRACTAL_VARIATIONS) + 1
	fractal_variation[slot] = variation
	set_fractal_maps(slot, variation)
	var/angle = rand(0, 359)
	var/drift = pick(-1, 1) * rand(20, 70)
	var/mirror = pick(-1, 1)
	var/zoom = TRIP_WIDE * rand(100, 125) / 100 // in enough for any turn
	var/obj/screen/trip_copy/copy = fractal_copies[slot]
	var/matrix/from = matrix(zoom * mirror, 0, 0, 0, zoom, 0)
	copy.transform = from.Turn(angle)
	var/end_zoom = TRIP_WIDE * rand(100, 125) / 100
	var/matrix/towards = matrix(end_zoom * mirror, 0, 0, 0, end_zoom, 0)
	animate(copy, transform = towards.Turn(angle + drift), time = 60 SECONDS)
	fractal_hue[slot] = color_matrix_rotate_hue(rand(0, 359))
	copy.color = fractal_hue[slot]
	fractal_alpha = target_alpha
	animate(fractal_pms[slot], alpha = fractal_alpha, time = time, easing = SINE_EASING)
	if(slot != old_slot)
		animate(fractal_pms[old_slot], alpha = 0, time = time, easing = SINE_EASING)
	fractal_slot = slot
	fractal_until = world.time + time
	next_fractal = world.time + rand(25, 45) SECONDS

/// The fractal surges brighter, then settles
/datum/trip_vision/proc/flare(strength = 0.9)
	if(!active || !fractal_alpha)
		return
	var/obj/screen/trip_copy/copy = fractal_copies[fractal_slot]
	var/list/hue = fractal_hue[fractal_slot]
	var/bright = 1 + strength
	animate(copy, color = color_matrix_multiply(hue, list(bright,0,0,0, 0,bright,0,0, 0,0,bright,0, 0,0,0,1, 0,0,0,0)), time = 2 SECONDS, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
	animate(color = hue, time = 4 SECONDS, easing = SINE_EASING)

// The kaleidoscope and the tunnel

/// Wedge k of the kaleidoscope: the mask's eighth (straight right to 45 degrees up), turned to its place, every other one mirrored
/// so the edges meet. Zoomed in so the turning picture it shows never runs out at the corners
/datum/trip_vision/proc/kaleido_matrix(k)
	var/zoom = 1.6
	if(k % 2 == 0)
		var/angle = k * 45
		return matrix(zoom * cos(angle), -zoom * sin(angle), 0, zoom * sin(angle), zoom * cos(angle), 0)
	var/angle = (k + 1) * 45
	return matrix(zoom * cos(angle), zoom * sin(angle), 0, zoom * sin(angle), -zoom * cos(angle), 0)

/// Fades the kaleidoscope to alpha (0 to 255) over time, if it isn't already on its way somewhere
/datum/trip_vision/proc/set_kaleido(target, time = 4 SECONDS)
	target = round(clamp(target, 0, 255))
	if(world.time < kaleido_until || abs(target - kaleido_alpha) < 10)
		return
	kaleido_alpha = target
	kaleido_until = world.time + time
	for(var/obj/screen/trip_copy/fold as anything in kaleido)
		animate(fold, alpha = target, time = time, easing = SINE_EASING)

/// Level n of the tunnel: the picture shrunk by 0.62 for each level and turned 25 degrees more
/datum/trip_vision/proc/tunnel_matrix(level)
	var/matrix/M = matrix() * (0.62 ** level)
	return M.Turn(level * 25)

/// The picture falls away into itself, level after level, for time
/datum/trip_vision/proc/tunnel(time = 8 SECONDS)
	if(!active || world.time < tunnel_until)
		return
	time = max(time, 7 SECONDS)
	tunnel_until = world.time + time
	for(var/obj/screen/trip_copy/nested as anything in tunnels)
		animate(nested, alpha = 255, time = 3 SECONDS, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
		animate(alpha = 255, time = time - 6 SECONDS)
		animate(alpha = 0, time = 3 SECONDS, easing = SINE_EASING)

// The one-shots. Each says what it does to the whole picture, glides in and out, and does nothing if it's still going

/// Takes burst filter slot for time if it's free
/datum/trip_vision/proc/take_burst(slot, time)
	var/key = "[slot]"
	if(!active || world.time < burst_until[key] || !length(warp_copy.filters))
		return FALSE
	burst_until[key] = world.time + time
	return TRUE

/// A shockwave rolls across everything
/datum/trip_vision/proc/ripple(power = 1)
	var/time = rand(40, 55)
	if(!take_burst(TRIP_FILTER_RIPPLE, time))
		return
	var/F = warp_copy.filters[TRIP_FILTER_RIPPLE]
	animate(F, x = rand(-96, 96), y = rand(-96, 96), radius = 0, size = 0, time = 0, flags = ANIMATION_PARALLEL)
	animate(radius = 120, size = 2 + power * 2, time = time * 0.3, easing = SINE_EASING)
	animate(radius = rand(260, 400), size = 0, time = time * 0.7, easing = SINE_EASING)

/// Everything smears outward from the middle
/datum/trip_vision/proc/radial(power = 1)
	if(!take_burst(TRIP_FILTER_RADIAL, 40))
		return
	animate(warp_copy.filters[TRIP_FILTER_RADIAL], size = 0.025 * power, time = 15, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
	animate(size = 0, time = 25, easing = SINE_EASING)

/// Coloured rays sweep out of the middle
/datum/trip_vision/proc/rays(power = 1)
	if(!take_burst(TRIP_FILTER_RAYS, 50))
		return
	var/F = warp_copy.filters[TRIP_FILTER_RAYS]
	var/colour = rgb(rand(100, 255), rand(100, 255), rand(100, 255))
	animate(F, size = 0, offset = 0, color = "[colour]00", time = 0, flags = ANIMATION_PARALLEL)
	animate(size = 60 + power * 40, offset = 1.5, color = "[colour]78", time = 15, easing = SINE_EASING)
	animate(offset = 3, time = 15)
	animate(size = 0, offset = 4.5, color = "[colour]00", time = 20, easing = SINE_EASING)

/// Everything bright swells and glows
/datum/trip_vision/proc/bloom(power = 1)
	if(!take_burst(TRIP_FILTER_BLOOM, 45))
		return
	animate(warp_copy.filters[TRIP_FILTER_BLOOM], size = 4 + power * 2, offset = 3, alpha = 200, time = 20, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
	animate(size = 1, offset = 1, alpha = 0, time = 25, easing = SINE_EASING)

/// The view runs like wet paint
/datum/trip_vision/proc/melt(power = 1)
	if(!take_burst(TRIP_FILTER_WAVE, 80))
		return
	var/F = warp_copy.filters[TRIP_FILTER_WAVE]
	animate(F, x = rand(-20, 20), y = rand(-20, 20), offset = 0, time = 0, flags = ANIMATION_PARALLEL)
	animate(size = 1 + power, offset = 2, time = 35, easing = SINE_EASING)
	animate(size = 0, offset = 4, time = 45, easing = SINE_EASING)

/// The middle of the view swells up like a fishbowl, then sinks in
/datum/trip_vision/proc/fisheye(power = 1)
	if(!active || world.time < fisheye_until || !length(warp_copy.filters))
		return
	fisheye_until = world.time + 70
	animate(warp_copy.filters[TRIP_FILTER_FISHEYE], size = 25 + 10 * power, time = 20, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
	animate(size = -(15 + 6 * power), time = 30, easing = SINE_EASING)
	animate(size = 0, time = 20, easing = SINE_EASING)

/// Moving smears the view the way you went, so everything trails behind you
/datum/trip_vision/proc/streak(dir)
	if(!active || world.time < streak_until || !length(warp_copy.filters))
		return
	streak_until = world.time + 8
	var/length = 3 + 5 * intensity
	var/dx = (dir & EAST) ? length : ((dir & WEST) ? -length : 0)
	var/dy = (dir & NORTH) ? length : ((dir & SOUTH) ? -length : 0)
	animate(warp_copy.filters[TRIP_FILTER_STREAK], x = dx, y = dy, time = 2, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
	animate(x = 0, y = 0, time = 6, easing = SINE_EASING)

/// The colours pull apart, and everything is doubled
/datum/trip_vision/proc/split(power = 1, time = 30)
	if(!active || world.time < split_until || world.time < grade_glide_until) // not while the grade is gliding to a new loop
		return
	split_until = world.time + time + 15
	var/size = 2 + power * 2
	var/angle = rand(0, 359)
	var/dx = round(cos(angle) * size, 0.5)
	var/dy = round(sin(angle) * size, 0.5)
	var/list/offsets = list(list(-dx, -dy), list(0, 0), list(dx, dy))
	for(var/i in 1 to 3)
		var/obj/screen/trip_copy/channel = channels[i]
		animate(channel, transform = matrix(1, 0, offsets[i][1], 0, 1, offsets[i][2]), time = 15, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
		animate(transform = matrix(), time = time, easing = SINE_EASING)

/// Holds the turned copy's transform for time, so nothing else moves it meanwhile
/datum/trip_vision/proc/take_geometry(time)
	if(!active || world.time < geometry_until)
		return FALSE
	geometry_until = world.time + time
	return TRUE

/// The picture turned by angle and zoomed in enough to cover the screen at that angle, times scale
/datum/trip_vision/proc/turned(angle, scale = 1)
	var/matrix/M = matrix() * ((abs(cos(angle)) + abs(sin(angle))) * scale)
	return M.Turn(angle)

/// The picture turned by angle and zoomed in enough to cover the screen at any angle
/datum/trip_vision/proc/wide(angle)
	var/matrix/M = matrix() * TRIP_WIDE
	return M.Turn(angle)

/// The world leans over and rights itself
/datum/trip_vision/proc/tilt(power = 1)
	if(!take_geometry(70))
		return
	var/angle = pick(-1, 1) * rand(8, 10 + power * 6)
	animate(turn_copy, transform = turned(angle, 1.04), time = 25, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
	animate(transform = turned(-angle / 2, 1.02), time = 25, easing = SINE_EASING)
	animate(transform = matrix(), time = 20, easing = SINE_EASING)

/// The world breathes in, and out
/datum/trip_vision/proc/breathe(power = 1)
	if(!take_geometry(45))
		return
	animate(turn_copy, transform = matrix() * (1.04 + 0.02 * power), time = 20, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
	animate(transform = matrix(), time = 25, easing = SINE_EASING)

/// The world rocks gently from side to side and settles, as after a blow
/datum/trip_vision/proc/wobble(power = 1)
	if(!take_geometry(48))
		return
	var/angle = 1.5 + power
	animate(turn_copy, transform = turned(angle), time = 8, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
	animate(transform = turned(-angle * 0.7), time = 10, easing = SINE_EASING)
	animate(transform = turned(angle * 0.4), time = 10, easing = SINE_EASING)
	animate(transform = turned(-angle * 0.15), time = 10, easing = SINE_EASING)
	animate(transform = matrix(), time = 10, easing = SINE_EASING)

/// Something rushes up at you out of the middle of everything
/datum/trip_vision/proc/rush(power = 1)
	if(!take_geometry(40))
		return
	animate(turn_copy, transform = matrix() * (1.25 + 0.05 * power), time = 12, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
	animate(transform = matrix(), time = 28, easing = SINE_EASING)
	radial(power + 1)

/// The whole world turns a full circle
/datum/trip_vision/proc/spin()
	if(!take_geometry(90))
		return
	animate(turn_copy, transform = wide(0), time = 15, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
	animate(transform = wide(120), time = 20)
	animate(transform = wide(240), time = 20)
	animate(transform = wide(0), time = 20)
	animate(transform = matrix(), time = 15, easing = SINE_EASING)

/// The world turns on its side, or upside down, for a while
/datum/trip_vision/proc/turn_view(hold = 50)
	if(!take_geometry(hold + 70))
		return
	var/angle = pick(90, 180, -90)
	animate(turn_copy, transform = wide(0), time = 10, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
	animate(transform = wide(angle / 2), time = 10)
	animate(transform = wide(angle), time = 10)
	animate(transform = turned(angle), time = 5, easing = SINE_EASING)
	animate(transform = turned(angle), time = hold)
	animate(transform = wide(angle), time = 5, easing = SINE_EASING)
	animate(transform = wide(angle / 2), time = 10)
	animate(transform = wide(0), time = 10)
	animate(transform = matrix(), time = 10, easing = SINE_EASING)

/// Left and right swap over, the screen folding through itself like a page, for a while
/datum/trip_vision/proc/mirror(hold = 60)
	if(!take_geometry(hold + 60))
		return
	animate(turn_copy, transform = matrix(0.03, 0, 0, 0, 1, 0), time = 15, easing = SINE_EASING, flags = ANIMATION_PARALLEL | ANIMATION_LINEAR_TRANSFORM)
	animate(transform = matrix(-1, 0, 0, 0, 1, 0), time = 15, easing = SINE_EASING, flags = ANIMATION_LINEAR_TRANSFORM)
	animate(transform = matrix(-1, 0, 0, 0, 1, 0), time = hold, flags = ANIMATION_LINEAR_TRANSFORM)
	animate(transform = matrix(0.03, 0, 0, 0, 1, 0), time = 15, easing = SINE_EASING, flags = ANIMATION_LINEAR_TRANSFORM)
	animate(transform = matrix(), time = 15, easing = SINE_EASING, flags = ANIMATION_LINEAR_TRANSFORM)

/// A wash of colour, or of the photo negative for the nastier moments, then back
/datum/trip_vision/proc/flash(strong = FALSE)
	if(!active || world.time < colour_until)
		return
	var/list/tint = (strong && prob(35)) ? list(-1,0,0,0, 0,-1,0,0, 0,0,-1,0, 0,0,0,1, 1,1,1,0) : color_matrix_multiply(color_matrix_saturation(2), color_matrix_rotate_hue(rand(60, 300)))
	var/time = strong ? rand(15, 20) : rand(20, 30)
	colour_until = world.time + time * 3
	animate(turn_copy, color = tint, time = time, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
	animate(color = tint, time = time)
	animate(color = color_matrix_identity(), time = time, easing = SINE_EASING)

/// Everything goes white, then comes back
/datum/trip_vision/proc/white_out()
	if(!active)
		return
	colour_until = world.time + 70
	var/list/white = list(1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1, 1,1,1,0)
	animate(turn_copy, color = white, time = 15, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
	animate(color = white, time = 20)
	animate(color = color_matrix_identity(), time = 35, easing = SINE_EASING)

/// The colours at their wildest, turned angle round the wheel
/datum/trip_vision/proc/wild(angle)
	return color_matrix_multiply(color_matrix_multiply(color_matrix_saturation(2), color_matrix_rotate_hue(angle)), color_matrix_contrast(1.2))

/// The world goes, and only geometry is left: the kaleidoscope, the tunnel and the fractal all at once, the colours running round
/// the wheel, for time
/datum/trip_vision/proc/breakthrough(time = 12 SECONDS)
	if(!active || world.time < breakthrough_until)
		return
	breakthrough_until = world.time + time
	kaleido_until = 0
	set_kaleido(255, 3 SECONDS)
	kaleido_until = world.time + time // held there till it's over
	tunnel(time)
	flare(1)
	if(world.time >= colour_until)
		colour_until = world.time + time
		var/step = time / 6
		animate(turn_copy, color = wild(60), time = step, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
		for(var/angle in list(120, 180, 240, 300))
			animate(color = wild(angle), time = step)
		animate(color = color_matrix_identity(), time = step, easing = SINE_EASING)
	if(world.time >= flow_until && length(warp_copy.filters))
		flow_until = world.time + time
		for(var/slot in list(TRIP_FILTER_FLOW, TRIP_FILTER_FLOW_2))
			animate(warp_copy.filters[slot], size = TRIP_FLOW_PEAK, time = 3 SECONDS, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
			animate(size = TRIP_FLOW_PEAK, time = time - 6 SECONDS)
			animate(size = flow_size * 0.6, time = 3 SECONDS, easing = SINE_EASING)
	spin() //unless a turn or a flip is still going, which it doesn't cut short
	addtimer(CALLBACK(src, PROC_REF(end_breakthrough)), time + 1)

/datum/trip_vision/proc/end_breakthrough()
	if(world.time < breakthrough_until)
		return
	kaleido_until = 0
	set_kaleido(clamp((intensity - 0.7) / 0.3, 0, 1) * (bad ? 150 : 100), 5 SECONDS)

#undef TRIP_WIDE
#undef TRIP_FILTER_FLOW
#undef TRIP_FILTER_FLOW_2
#undef TRIP_FILTER_STREAK
#undef TRIP_FILTER_FISHEYE
#undef TRIP_FILTER_WAVE
#undef TRIP_FILTER_RIPPLE
#undef TRIP_FILTER_RADIAL
#undef TRIP_FILTER_RAYS
#undef TRIP_FILTER_BLOOM
