// The camera console's tgui window (tgui-next CameraConsole.js), after tgstation's of 2020: a searchable list of the cameras and the
// picture from the one picked, drawn in the window by a second map control (hippiestation/code/_onclick/hud/map_view.dm). The old
// console asked in a pop-up list and moved your whole view to the camera, so you couldn't see your own surroundings while watching.
// Everyone watching a console sees the same camera. The picture is the turfs the camera sees, refreshed every couple of seconds so
// doors opening and closing show; a camera that's off or cut shows static.

#define CAMERA_MAP_DEFAULT_SIZE 15
#define CAMERA_VIEW_REFRESH (2 SECONDS)

/obj/machinery/computer/security
	ui_x = 870
	ui_y = 708
	/// The map control in the window that shows the picture
	var/map_name
	/// What shows the camera's turfs
	var/obj/screen/map_view/cam_screen
	/// The camera map's own plane masters
	var/list/cam_plane_masters
	/// Black under the picture, static when there's no signal
	var/obj/screen/background/cam_background
	/// The camera being shown
	var/obj/machinery/camera/active_camera
	/// The living users watching (refs), for the console's sounds and power
	var/list/concurrent_users = list()
	/// When the picture's turfs were last worked out
	var/last_view_update = 0

/obj/screen/map_view
	name = "screen"
	// Turfs take the plane of what shows them (VIS_INHERIT_PLANE): on the HUD plane they'd be drawn over the darkness
	plane = FLOOR_PLANE
	layer = TURF_LAYER

/obj/screen/background
	name = "background"
	icon = 'icons/effects/alphacolors.dmi'
	color = "#000000"
	layer = -1
	plane = -100

/obj/machinery/computer/security/Initialize()
	. = ..()
	map_name = "camera_console_[REF(src)]_map"
	cam_screen = new
	cam_screen.assigned_map = map_name
	cam_screen.del_on_map_removal = FALSE
	cam_screen.screen_loc = "[map_name]:1,1"
	cam_plane_masters = map_view_plane_masters(map_name)
	cam_background = new
	cam_background.assigned_map = map_name
	cam_background.del_on_map_removal = FALSE

/obj/machinery/computer/security/Destroy()
	SStgui.close_uis(src)
	active_camera = null
	QDEL_NULL(cam_screen)
	QDEL_LIST(cam_plane_masters)
	QDEL_NULL(cam_background)
	return ..()

/obj/machinery/computer/security/interact(mob/user)
	if(stat)
		return
	if(!islist(network))
		CRASH("Camera network is not a list")
	ui_interact(user)

/obj/machinery/computer/security/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(!user.client)
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!active_camera || !active_camera.can_use())
		show_camera_static()
	if(!ui)
		if(isliving(user))
			concurrent_users |= REF(user)
			if(length(concurrent_users) == 1)
				playsound(src, 'sound/machines/terminal_on.ogg', 25, FALSE)
				use_power(active_power_usage)
		user.client.register_map_obj(cam_screen)
		for(var/plane in cam_plane_masters)
			user.client.register_map_obj(plane)
		user.client.register_map_obj(cam_background)
		ui = new(user, src, ui_key, "camera_console", name, ui_x, ui_y, master_ui, state)
		ui.open()

/// Telescreens hung for watching from across the room work from anywhere you can see them
/obj/machinery/computer/security/ui_status(mob/user, datum/ui_state/state)
	if(!long_ranged)
		return ..()
	if(stat & (NOPOWER|BROKEN) || user.incapacitated() || user.eye_blind || !(user in viewers(world.view, src)))
		return UI_CLOSE
	return UI_INTERACTIVE

/obj/machinery/computer/security/ui_data(mob/user)
	var/list/data = list()
	data["network"] = network
	data["activeCamera"] = null
	if(active_camera)
		if(world.time > last_view_update + CAMERA_VIEW_REFRESH)
			update_camera_view()
		data["activeCamera"] = list(
			"name" = active_camera.c_tag,
			"status" = active_camera.can_use(),
		)
	return data

/obj/machinery/computer/security/ui_static_data(mob/user)
	var/list/data = list()
	data["mapRef"] = map_name
	var/list/cameras = list()
	for(var/obj/machinery/camera/C as anything in get_available_cameras_by_tag())
		cameras += list(list("name" = C.c_tag, "on" = C.status, "area" = get_area_name(C, TRUE)))
	data["cameras"] = cameras
	return data

/obj/machinery/computer/security/ui_act(action, params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	if(action != "switch_camera")
		return
	var/obj/machinery/camera/picked
	for(var/obj/machinery/camera/C in get_available_cameras_by_tag())
		if(C.c_tag == params["name"])
			picked = C
			break
	if(!picked)
		return
	active_camera = picked
	playsound(src, get_sfx("terminal_type"), 25, FALSE)
	use_power(50)
	update_camera_view()
	return TRUE

/// The cameras this console reaches, without the old pop-up's "Cancel" entry
/obj/machinery/computer/security/proc/get_available_cameras_by_tag()
	var/list/cameras = get_available_cameras()
	cameras -= "Cancel"
	var/list/found = list()
	for(var/c_tag in cameras)
		found += cameras[c_tag]
	return found

/// Shows what the active camera sees, or static when it can't
/obj/machinery/computer/security/proc/update_camera_view()
	last_view_update = world.time
	if(!active_camera || !active_camera.can_use())
		show_camera_static()
		return
	var/list/visible_turfs = list()
	for(var/turf/T in (active_camera.isXRay() ? range(active_camera.view_range, active_camera) : view(active_camera.view_range, active_camera)))
		visible_turfs += T
	var/list/bbox = get_bbox_of_atoms(visible_turfs)
	var/size_x = bbox[3] - bbox[1] + 1
	var/size_y = bbox[4] - bbox[2] + 1
	cam_screen.vis_contents = visible_turfs
	cam_background.icon = initial(cam_background.icon)
	cam_background.icon_state = ""
	cam_background.color = "#000000"
	cam_background.fill_rect(1, 1, size_x, size_y)

/obj/machinery/computer/security/proc/show_camera_static()
	cam_screen.vis_contents.Cut()
	// The static an AI sees where no camera reaches
	cam_background.icon = 'icons/effects/cameravis.dmi'
	cam_background.icon_state = ""
	cam_background.color = null
	cam_background.fill_rect(1, 1, CAMERA_MAP_DEFAULT_SIZE, CAMERA_MAP_DEFAULT_SIZE)

/obj/machinery/computer/security/ui_close(mob/user)
	if(!user)
		return
	var/was_watching = (REF(user) in concurrent_users)
	concurrent_users -= REF(user)
	if(user.client)
		user.client.clear_map(map_name)
	if(was_watching && !length(concurrent_users))
		active_camera = null
		playsound(src, 'sound/machines/terminal_off.ogg', 25, FALSE)

#undef CAMERA_MAP_DEFAULT_SIZE
#undef CAMERA_VIEW_REFRESH
