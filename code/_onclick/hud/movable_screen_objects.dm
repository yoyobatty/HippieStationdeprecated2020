
//////////////////////////
//Movable Screen Objects//
//   By RemieRichards	//
//////////////////////////


//Movable Screen Object
//Not tied to the grid, places it's center where the cursor is

/obj/screen/movable
	var/snap2grid = FALSE
	var/moved = FALSE
	var/locked = FALSE
	var/x_off = -16
	var/y_off = -16

//Snap Screen Object
//Tied to the grid, snaps to the nearest turf

/obj/screen/movable/snap
	snap2grid = TRUE


/obj/screen/movable/MouseDrop(over_object, src_location, over_location, src_control, over_control, params)
	if(locked) //no! I am locked! begone!
		return
	var/list/PM = params2list(params)

	//No screen-loc information? abort.
	if(!PM || !PM["screen-loc"])
		return

	//Split screen-loc up into X+Pixel_X and Y+Pixel_Y
	var/list/screen_loc_params = splittext(PM["screen-loc"], ",")

	//Split X+Pixel_X up into list(X, Pixel_X)
	var/list/screen_loc_X = splittext(screen_loc_params[1],":")

	//Split Y+Pixel_Y up into list(Y, Pixel_Y)
	var/list/screen_loc_Y = splittext(screen_loc_params[2],":")

	if(snap2grid) //Discard Pixel Values
		screen_loc = "[screen_loc_X[1]],[screen_loc_Y[1]]"

	else //Normalise Pixel Values (So the object drops at the center of the mouse, not 16 pixels off)
		var/pix_X = text2num(screen_loc_X[2]) + x_off
		var/pix_Y = text2num(screen_loc_Y[2]) + y_off
		screen_loc = "[screen_loc_X[1]]:[pix_X],[screen_loc_Y[1]]:[pix_Y]"

	moved = screen_loc

/// hippie -- moved pulled in to fit a view of this size. It's absolute tiles and BYOND grows the map to show whatever is on client.screen, so a
/// button dropped out by the edge of a zoomed out view kept the map that big once the zoom ended. moved itself isn't touched: the button goes
/// back where it was put when the view grows again.
/obj/screen/movable/proc/moved_loc_for_view(view)
	var/list/sides = splittext(moved, ",")
	if(length(sides) != 2)
		return moved
	var/list/loc_x = splittext(sides[1], ":")
	var/list/loc_y = splittext(sides[2], ":")
	var/tile_x = text2num(loc_x[1])
	var/tile_y = text2num(loc_y[1])
	if(isnull(tile_x) || isnull(tile_y)) // relative to the edges, so it follows the view by itself
		return moved
	var/list/view_size = getviewsize(view)
	var/most_x = (view_size[1] - 1) * world.icon_size
	var/most_y = (view_size[2] - 1) * world.icon_size
	var/pixel_x = (tile_x - 1) * world.icon_size + (length(loc_x) > 1 ? text2num(loc_x[2]) : 0)
	var/pixel_y = (tile_y - 1) * world.icon_size + (length(loc_y) > 1 ? text2num(loc_y[2]) : 0)
	if(pixel_x >= 0 && pixel_x <= most_x && pixel_y >= 0 && pixel_y <= most_y)
		return moved
	pixel_x = clamp(pixel_x, 0, most_x)
	pixel_y = clamp(pixel_y, 0, most_y)
	return "[round(pixel_x / world.icon_size) + 1]:[pixel_x % world.icon_size],[round(pixel_y / world.icon_size) + 1]:[pixel_y % world.icon_size]"


//Debug procs
/client/proc/test_movable_UI()
	set category = "Debug"
	set name = "Spawn Movable UI Object"

	var/obj/screen/movable/M = new()
	M.name = "Movable UI Object"
	M.icon_state = "block"
	M.maptext = "Movable"
	M.maptext_width = 64

	var/screen_l = tgui_input_text(usr, "Where on the screen? (Formatted as 'X,Y' e.g: '1,1' for bottom left)", "Spawn Movable UI Object", allow_cancel = FALSE)
	if(!screen_l)
		return

	M.screen_loc = screen_l

	screen += M


/client/proc/test_snap_UI()
	set category = "Debug"
	set name = "Spawn Snap UI Object"

	var/obj/screen/movable/snap/S = new()
	S.name = "Snap UI Object"
	S.icon_state = "block"
	S.maptext = "Snap"
	S.maptext_width = 64

	var/screen_l = tgui_input_text(usr, "Where on the screen? (Formatted as 'X,Y' e.g: '1,1' for bottom left)", "Spawn Snap UI Object", allow_cancel = FALSE)
	if(!screen_l)
		return

	S.screen_loc = screen_l

	screen += S
