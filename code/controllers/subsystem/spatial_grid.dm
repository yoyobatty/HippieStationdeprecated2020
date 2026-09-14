/**
 * # Spatial Grid Cell
 *
 * used by [/datum/controller/subsystem/spatial_grid] to cover every z level so that the coordinates of every turf in the world corresponds to one of these in
 * the subsystems list of grid cells by z level. each one of these contains content lists holding all atoms meeting a certain criteria that is in our borders.
 * these datums shouldnt have significant behavior, they should just hold data. the lists are filled and emptied by the subsystem.
 */
/datum/spatial_grid_cell
	/// Our x index in the list of cells. this is our index inside of our row list
	var/cell_x
	/// Our y index in the list of cells. this is the index of our row list inside of our z level grid
	var/cell_y
	/// Which z level we belong to, corresponding to the index of our gridmap in SSspatial_grid.grids_by_z_level
	var/cell_z

	// When empty, the contents lists of these grid cell datums are just references to a dummy list from SSspatial_grid
	// This is meant to allow a great compromise between memory usage and speed.

	/// Every hearing sensitive movable inside this cell
	var/list/hearing_contents
	/// Every client possessed mob inside this cell
	var/list/client_contents
	/// Every atmos machine inside this cell
	var/list/atmos_contents

/datum/spatial_grid_cell/New(cell_x, cell_y, cell_z)
	. = ..()
	src.cell_x = cell_x
	src.cell_y = cell_y
	src.cell_z = cell_z

	var/list/dummy_list = SSspatial_grid.dummy_list
	hearing_contents = dummy_list
	client_contents = dummy_list
	atmos_contents = dummy_list

/datum/spatial_grid_cell/Destroy(force)
	if(!force) //the response to someone trying to qdel this is a right proper fuck you
		stack_trace("dont try to destroy spatial grid cells without a good reason. if you need to do it use force")
		return QDEL_HINT_LETMELIVE
	return ..()

/**
 * # Spatial Grid
 *
 * a gamewide grid of spatial_grid_cell datums, each "covering" [SPATIAL_GRID_CELLSIZE] ^ 2 turfs.
 * each spatial_grid_cell datum stores information about what is inside its covered area, so that searches through that area dont have to literally search
 * through all turfs themselves to know what is within it since view() calls are expensive, and so is iterating through stuff you dont want.
 * this allows you to only go through lists of what you want very cheaply.
 *
 * currently this system is only designed for searching for relatively uncommon things, small subsets of /atom/movable.
 * dont add stupid shit to the cells please, keep the information that the cells store to things that need to be searched for often.
 */
SUBSYSTEM_DEF(spatial_grid)
	name = "Spatial Grid"
	flags = SS_NO_FIRE

	///list of the spatial_grid_cell datums per z level, arranged in the order of y index then x index
	var/list/grids_by_z_level = list()
	///everything that spawns before us is added to this list until we initialize
	var/list/waiting_to_add_by_type = list(SPATIAL_GRID_CONTENTS_TYPE_HEARING = list(), SPATIAL_GRID_CONTENTS_TYPE_CLIENTS = list(), SPATIAL_GRID_CONTENTS_TYPE_ATMOS = list())
	///associative list of the form: movable.spatial_grid_key (string) -> inner list of spatial grid types for that key.
	///inner lists contain contents channel types such as SPATIAL_GRID_CONTENTS_TYPE_HEARING etc.
	///we use this to make adding to a cell static cost, and to save on memory
	var/list/spatial_grid_categories = list()

	var/cells_on_x_axis = 0
	var/cells_on_y_axis = 0

	///empty spatial grid cell content lists are just a reference to this instead of a standalone list to save memory without needing to check if its null when iterating
	var/list/dummy_list = list()

/datum/controller/subsystem/spatial_grid/Initialize(timeofday)
	cells_on_x_axis = SPATIAL_GRID_CELLS_PER_SIDE(world.maxx)
	cells_on_y_axis = SPATIAL_GRID_CELLS_PER_SIDE(world.maxy)

	// enter_cell only runs if 'initialized'
	initialized = TRUE

	for(var/datum/space_level/z_level as anything in SSmapping.z_list)
		propogate_spatial_grid_to_new_z(null, z_level)
		CHECK_TICK

	//go through the pre init queue for anything waiting to be let in the grid
	for(var/channel_type in waiting_to_add_by_type)
		for(var/atom/movable/movable as anything in waiting_to_add_by_type[channel_type])
			var/turf/movable_turf = get_turf(movable)
			if(movable_turf)
				enter_cell(movable, movable_turf)

			UnregisterSignal(movable, COMSIG_PARENT_QDELETING)
			waiting_to_add_by_type[channel_type] -= movable

	RegisterSignal(SSdcs, COMSIG_GLOB_NEW_Z, "propogate_spatial_grid_to_new_z")

	return ..()

///add a movable to the pre init queue for whichever type is specified so that when the subsystem initializes they get added to the grid
/datum/controller/subsystem/spatial_grid/proc/enter_pre_init_queue(atom/movable/waiting_movable, type)
	RegisterSignal(waiting_movable, COMSIG_PARENT_QDELETING, "queued_item_deleted", override = TRUE)
	//override because something can enter the queue for two different types but that is done through unrelated procs that shouldnt know about eachother
	waiting_to_add_by_type[type] += waiting_movable

///removes an initialized and probably deleted movable from our pre init queue before we're initialized
/datum/controller/subsystem/spatial_grid/proc/remove_from_pre_init_queue(atom/movable/movable_to_remove, exclusive_type)
	if(isnull(exclusive_type))
		UnregisterSignal(movable_to_remove, COMSIG_PARENT_QDELETING)
		for(var/type in waiting_to_add_by_type)
			waiting_to_add_by_type[type] -= movable_to_remove
		return

	waiting_to_add_by_type[exclusive_type] -= movable_to_remove

	// We need to check if this movable is inside the other queues
	for(var/type in waiting_to_add_by_type)
		if(movable_to_remove in waiting_to_add_by_type[type])
			return

	UnregisterSignal(movable_to_remove, COMSIG_PARENT_QDELETING)

///if a movable is inside our pre init queue before we're initialized and it gets deleted we need to remove that reference with this proc
/datum/controller/subsystem/spatial_grid/proc/queued_item_deleted(atom/movable/movable_being_deleted)
	remove_from_pre_init_queue(movable_being_deleted, null)

///creates the spatial grid for a new z level
/datum/controller/subsystem/spatial_grid/proc/propogate_spatial_grid_to_new_z(datum/source, datum/space_level/z_level)
	var/list/new_cell_grid = list()

	grids_by_z_level += list(new_cell_grid)

	for(var/y in 1 to cells_on_y_axis)
		new_cell_grid += list(list())
		for(var/x in 1 to cells_on_x_axis)
			var/datum/spatial_grid_cell/cell = new(x, y, z_level.z_value)
			new_cell_grid[y] += cell

#define BOUNDING_BOX_MIN(center_coord) max(GET_SPATIAL_INDEX(center_coord - range), 1)
#define BOUNDING_BOX_MAX(center_coord, axis_size) min(GET_SPATIAL_INDEX(center_coord + range), axis_size)

/**
 * searches through the grid cells intersecting a rectangular search space (with sides of length 2 * range) then returns all contents of type inside them.
 * much faster than iterating through view() to find all of what you want.
 *
 * this does NOT return things only in range distance from center! the search space is a square not a circle, if you want only things in a certain distance
 * then you need to filter that yourself
 */
/datum/controller/subsystem/spatial_grid/proc/orthogonal_range_search(atom/center, type, range)
	. = list()

	if(!initialized) // can be called before the grid has finished building, e.g. during early roundstart atom init
		return .

	var/turf/center_turf = get_turf(center)
	if(!center_turf)
		return .

	var/center_x = center_turf.x //used inside the macros
	var/center_y = center_turf.y

	var/list/list/datum/spatial_grid_cell/grid_level = grids_by_z_level[center_turf.z]

	switch(type)
		if(SPATIAL_GRID_CONTENTS_TYPE_CLIENTS)
			for(var/row in BOUNDING_BOX_MIN(center_y) to BOUNDING_BOX_MAX(center_y, cells_on_y_axis))
				for(var/x_index in BOUNDING_BOX_MIN(center_x) to BOUNDING_BOX_MAX(center_x, cells_on_x_axis))
					. += grid_level[row][x_index].client_contents

		if(SPATIAL_GRID_CONTENTS_TYPE_HEARING)
			for(var/row in BOUNDING_BOX_MIN(center_y) to BOUNDING_BOX_MAX(center_y, cells_on_y_axis))
				for(var/x_index in BOUNDING_BOX_MIN(center_x) to BOUNDING_BOX_MAX(center_x, cells_on_x_axis))
					. += grid_level[row][x_index].hearing_contents

		if(SPATIAL_GRID_CONTENTS_TYPE_ATMOS)
			for(var/row in BOUNDING_BOX_MIN(center_y) to BOUNDING_BOX_MAX(center_y, cells_on_y_axis))
				for(var/x_index in BOUNDING_BOX_MIN(center_x) to BOUNDING_BOX_MAX(center_x, cells_on_x_axis))
					. += grid_level[row][x_index].atmos_contents

	return .

#undef BOUNDING_BOX_MIN
#undef BOUNDING_BOX_MAX

///get the grid cell encompassing target's coordinates
/datum/controller/subsystem/spatial_grid/proc/get_cell_of(atom/target)
	var/turf/target_turf = get_turf(target)
	if(!target_turf)
		return

	return grids_by_z_level[target_turf.z][GET_SPATIAL_INDEX(target_turf.y)][GET_SPATIAL_INDEX(target_turf.x)]

///get all grid cells intersecting the bounding box around center with sides of length 2 * range
/datum/controller/subsystem/spatial_grid/proc/get_cells_in_range(atom/center, range)
	return get_cells_in_bounds(center, range, range)

///get all grid cells intersecting the bounding box around center with sides of length (2 * range_x, 2 * range_y)
/datum/controller/subsystem/spatial_grid/proc/get_cells_in_bounds(atom/center, range_x, range_y)
	var/turf/center_turf = get_turf(center)

	var/center_x = center_turf.x
	var/center_y = center_turf.y

	var/list/intersecting_grid_cells = list()

	var/min_x = max(GET_SPATIAL_INDEX(center_x - range_x), 1)
	var/min_y = max(GET_SPATIAL_INDEX(center_y - range_y), 1)

	var/max_x = min(GET_SPATIAL_INDEX(center_x + range_x), cells_on_x_axis)
	var/max_y = min(GET_SPATIAL_INDEX(center_y + range_y), cells_on_y_axis)

	var/list/grid_level = grids_by_z_level[center_turf.z]

	for(var/row in min_y to max_y)
		var/list/grid_row = grid_level[row]
		for(var/x_index in min_x to max_x)
			intersecting_grid_cells += grid_row[x_index]

	return intersecting_grid_cells

/// Adds grid awareness to the passed in atom, of the passed in type
/// Basically, when this atom moves between grids, it wants to have enter/exit cell called on it
/datum/controller/subsystem/spatial_grid/proc/add_grid_awareness(atom/movable/add_to, type)
	var/list/current_list = spatial_grid_categories[add_to.spatial_grid_key]
	current_list = current_list ? current_list.Copy() : list()
	if(!(type in current_list))
		current_list += type
	update_grid_awareness(add_to, current_list)

/// Removes grid awareness from the passed in atom, of the passed in type
/datum/controller/subsystem/spatial_grid/proc/remove_grid_awareness(atom/movable/remove_from, type)
	var/list/current_list = spatial_grid_categories[remove_from.spatial_grid_key]
	current_list = current_list ? current_list.Copy() : list()
	current_list -= type
	update_grid_awareness(remove_from, current_list)

/// Alerts the atom's current cell that it wishes to be treated as a member
/datum/controller/subsystem/spatial_grid/proc/add_grid_membership(atom/movable/add_to, turf/target_turf, type)
	if(!target_turf)
		return
	if(initialized)
		add_single_type(add_to, target_turf, type)
	else //SSspatial_grid isnt init'd yet, add ourselves to the queue
		enter_pre_init_queue(add_to, type)

/// Removes grid membership from the passed in atom, of the passed in type
/datum/controller/subsystem/spatial_grid/proc/remove_grid_membership(atom/movable/remove_from, turf/target_turf, type)
	if(!target_turf)
		return
	if(initialized)
		remove_single_type(remove_from, target_turf, type)
	else //SSspatial_grid isnt init'd yet, remove ourselves from the queue
		remove_from_pre_init_queue(remove_from, type)

/// Updates the string that atoms hold that stores their grid awareness. Used to key into their spatial grid categories later
/datum/controller/subsystem/spatial_grid/proc/update_grid_awareness(atom/movable/update, list/new_list)
	// We locally store a stringified version of the list, to prevent people trying to mutate it
	update.spatial_grid_key = new_list.Join("-")
	if(!spatial_grid_categories[update.spatial_grid_key])
		spatial_grid_categories[update.spatial_grid_key] = new_list

///find the spatial map cell that target belongs to, then add the target to it, as its type prefers.
///make sure to provide the turf new_target is "in"
/datum/controller/subsystem/spatial_grid/proc/enter_cell(atom/movable/new_target, turf/target_turf)
	if(!initialized)
		return
	if(QDELETED(new_target))
		CRASH("qdeleted or null target trying to enter the spatial grid!")

	if(!target_turf || !new_target.spatial_grid_key)
		CRASH("null turf loc or a new_target that doesn't support it trying to enter the spatial grid!")

	var/x_index = GET_SPATIAL_INDEX(target_turf.x)
	var/y_index = GET_SPATIAL_INDEX(target_turf.y)
	var/z_index = target_turf.z

	var/datum/spatial_grid_cell/intersecting_cell = grids_by_z_level[z_index][y_index][x_index]
	for(var/type in spatial_grid_categories[new_target.spatial_grid_key])
		switch(type)
			if(SPATIAL_GRID_CONTENTS_TYPE_CLIENTS)
				var/list/new_target_contents = new_target.important_recursive_contents
				GRID_CELL_SET(intersecting_cell.client_contents, new_target_contents[SPATIAL_GRID_CONTENTS_TYPE_CLIENTS])
				SEND_SIGNAL(intersecting_cell, SPATIAL_GRID_CELL_ENTERED(SPATIAL_GRID_CONTENTS_TYPE_CLIENTS), new_target_contents[SPATIAL_GRID_CONTENTS_TYPE_CLIENTS])

			if(SPATIAL_GRID_CONTENTS_TYPE_HEARING)
				var/list/new_target_contents = new_target.important_recursive_contents
				GRID_CELL_SET(intersecting_cell.hearing_contents, new_target_contents[SPATIAL_GRID_CONTENTS_TYPE_HEARING])
				SEND_SIGNAL(intersecting_cell, SPATIAL_GRID_CELL_ENTERED(SPATIAL_GRID_CONTENTS_TYPE_HEARING), new_target_contents[SPATIAL_GRID_CONTENTS_TYPE_HEARING])

			if(SPATIAL_GRID_CONTENTS_TYPE_ATMOS)
				GRID_CELL_SET(intersecting_cell.atmos_contents, new_target)
				SEND_SIGNAL(intersecting_cell, SPATIAL_GRID_CELL_ENTERED(SPATIAL_GRID_CONTENTS_TYPE_ATMOS), new_target)

///acts like enter_cell() but only adds the target to a specified type of grid cell contents list
/datum/controller/subsystem/spatial_grid/proc/add_single_type(atom/movable/new_target, turf/target_turf, exclusive_type)
	if(!initialized)
		return
	if(QDELETED(new_target))
		CRASH("qdeleted or null target trying to enter the spatial grid!")

	if(!target_turf || !(exclusive_type in spatial_grid_categories[new_target.spatial_grid_key]))
		CRASH("null turf loc or a new_target that doesn't support it trying to enter the spatial grid as a [exclusive_type]!")

	var/x_index = GET_SPATIAL_INDEX(target_turf.x)
	var/y_index = GET_SPATIAL_INDEX(target_turf.y)
	var/z_index = target_turf.z

	var/datum/spatial_grid_cell/intersecting_cell = grids_by_z_level[z_index][y_index][x_index]
	switch(exclusive_type)
		if(SPATIAL_GRID_CONTENTS_TYPE_CLIENTS)
			var/list/new_target_contents = new_target.important_recursive_contents
			GRID_CELL_SET(intersecting_cell.client_contents, new_target_contents[SPATIAL_GRID_CONTENTS_TYPE_CLIENTS])
			SEND_SIGNAL(intersecting_cell, SPATIAL_GRID_CELL_ENTERED(SPATIAL_GRID_CONTENTS_TYPE_CLIENTS), new_target_contents[SPATIAL_GRID_CONTENTS_TYPE_CLIENTS])

		if(SPATIAL_GRID_CONTENTS_TYPE_HEARING)
			var/list/new_target_contents = new_target.important_recursive_contents
			GRID_CELL_SET(intersecting_cell.hearing_contents, new_target_contents[SPATIAL_GRID_CONTENTS_TYPE_HEARING])
			SEND_SIGNAL(intersecting_cell, SPATIAL_GRID_CELL_ENTERED(SPATIAL_GRID_CONTENTS_TYPE_HEARING), new_target_contents[SPATIAL_GRID_CONTENTS_TYPE_HEARING])

		if(SPATIAL_GRID_CONTENTS_TYPE_ATMOS)
			GRID_CELL_SET(intersecting_cell.atmos_contents, new_target)
			SEND_SIGNAL(intersecting_cell, SPATIAL_GRID_CELL_ENTERED(SPATIAL_GRID_CONTENTS_TYPE_ATMOS), new_target)

	return intersecting_cell

/**
 * find the spatial map cell that target used to belong to, then remove the target (and sometimes its important_recursive_contents) from it.
 * make sure to provide the turf old_target used to be "in"
 */
/datum/controller/subsystem/spatial_grid/proc/exit_cell(atom/movable/old_target, turf/target_turf, exclusive_type)
	if(!initialized)
		return

	if(!target_turf || !old_target.spatial_grid_key)
		stack_trace("/datum/controller/subsystem/spatial_grid/proc/exit_cell() was given null arguments or a old_target that doesn't use the spatial grid!")
		return FALSE

	var/x_index = GET_SPATIAL_INDEX(target_turf.x)
	var/y_index = GET_SPATIAL_INDEX(target_turf.y)
	var/z_index = target_turf.z

	var/datum/spatial_grid_cell/intersecting_cell = grids_by_z_level[z_index][y_index][x_index]
	for(var/type in spatial_grid_categories[old_target.spatial_grid_key])
		switch(type)
			if(SPATIAL_GRID_CONTENTS_TYPE_CLIENTS)
				var/list/old_target_contents = old_target.important_recursive_contents?[type] || old_target
				GRID_CELL_REMOVE(intersecting_cell.client_contents, old_target_contents)
				SEND_SIGNAL(intersecting_cell, SPATIAL_GRID_CELL_EXITED(type), old_target_contents)

			if(SPATIAL_GRID_CONTENTS_TYPE_HEARING)
				var/list/old_target_contents = old_target.important_recursive_contents?[type] || old_target
				GRID_CELL_REMOVE(intersecting_cell.hearing_contents, old_target_contents)
				SEND_SIGNAL(intersecting_cell, SPATIAL_GRID_CELL_EXITED(type), old_target_contents)

			if(SPATIAL_GRID_CONTENTS_TYPE_ATMOS)
				GRID_CELL_REMOVE(intersecting_cell.atmos_contents, old_target)
				SEND_SIGNAL(intersecting_cell, SPATIAL_GRID_CELL_EXITED(type), old_target)

	return TRUE

///acts like exit_cell() but only removes the target from the specified type of grid cell contents list
/datum/controller/subsystem/spatial_grid/proc/remove_single_type(atom/movable/old_target, turf/target_turf, exclusive_type)
	if(!target_turf || !exclusive_type || !old_target.spatial_grid_key)
		stack_trace("/datum/controller/subsystem/spatial_grid/proc/remove_single_type() was given null arguments or an old_target that doesn't use the spatial grid!")
		return FALSE

	if(!(exclusive_type in spatial_grid_categories[old_target.spatial_grid_key]))
		return FALSE

	var/x_index = GET_SPATIAL_INDEX(target_turf.x)
	var/y_index = GET_SPATIAL_INDEX(target_turf.y)
	var/z_index = target_turf.z

	var/datum/spatial_grid_cell/intersecting_cell = grids_by_z_level[z_index][y_index][x_index]

	switch(exclusive_type)
		if(SPATIAL_GRID_CONTENTS_TYPE_CLIENTS)
			var/list/old_target_contents = old_target.important_recursive_contents?[exclusive_type] || old_target
			GRID_CELL_REMOVE(intersecting_cell.client_contents, old_target_contents)
			SEND_SIGNAL(intersecting_cell, SPATIAL_GRID_CELL_EXITED(exclusive_type), old_target_contents)

		if(SPATIAL_GRID_CONTENTS_TYPE_HEARING)
			var/list/old_target_contents = old_target.important_recursive_contents?[exclusive_type] || old_target
			GRID_CELL_REMOVE(intersecting_cell.hearing_contents, old_target_contents)
			SEND_SIGNAL(intersecting_cell, SPATIAL_GRID_CELL_EXITED(exclusive_type), old_target_contents)

		if(SPATIAL_GRID_CONTENTS_TYPE_ATMOS)
			GRID_CELL_REMOVE(intersecting_cell.atmos_contents, old_target)
			SEND_SIGNAL(intersecting_cell, SPATIAL_GRID_CELL_EXITED(exclusive_type), old_target)

	return TRUE

/**
 * remove this movable from the grid by finding the grid cell its in and removing it from that.
 * if it cant infer a grid cell its located in (e.g. if its in nullspace), search every grid cell as a fallback.
 */
/datum/controller/subsystem/spatial_grid/proc/force_remove_from_grid(atom/movable/to_remove)
	if(!to_remove?.spatial_grid_key)
		return

	if(!initialized)
		remove_from_pre_init_queue(to_remove) //the spatial grid doesnt exist yet, so just take it out of the queue
		return

	var/datum/spatial_grid_cell/loc_cell = get_cell_of(to_remove)

	if(loc_cell)
		GRID_CELL_REMOVE_ALL(loc_cell, to_remove)
	else
		//fallback: something's gone wrong and to_remove isn't where its loc thinks it should be. search every cell for it.
		for(var/list/z_level_grid as anything in grids_by_z_level)
			for(var/list/cell_row as anything in z_level_grid)
				for(var/datum/spatial_grid_cell/cell as anything in cell_row)
					if(to_remove in ALL_CONTENTS_OF_CELL(cell))
						GRID_CELL_REMOVE_ALL(cell, to_remove)
