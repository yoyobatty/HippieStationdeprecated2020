// Does a radio on a shuttle still hear where the shuttle went? A shuttle move sets loc with no Moved(), and the spatial grid is what
// speech looks hearers up in. Puts a radio on the mining shuttle, flies it to the other dock and back, and asks the grid each time.
// sg-old=1 puts back the move without the grid update, to see the difference. Not part of the game:
// AT_END=1 HARNESS=../../gc_hunt/shuttle_grid_check.dm [PARAMS=sg-old=1] bash tools/byond_reports/ref_stall/hippie_check.sh

/datum/controller/master
	sleep_offline_after_initializations = FALSE

/proc/sg_log(text)
	text2file(text, "data/ref_stall.txt")

/world/New()
	. = ..()
	spawn(0)
		sg_run()

/atom/movable/onShuttleMove(turf/newT, turf/oldT, list/movement_force, move_dir, obj/docking_port/stationary/old_dock, obj/docking_port/mobile/moving_dock)
	if(!text2num(world.params["sg-old"]))
		return ..()
	if(newT == oldT)
		return
	if(loc != oldT)
		return
	loc = newT
	return TRUE

/proc/sg_hears(obj/item/radio/R)
	var/turf/T = get_turf(R)
	return (R in SSspatial_grid.orthogonal_range_search(T, SPATIAL_GRID_CONTENTS_TYPE_HEARING, 3)) ? "heard where it is" : "NOT heard where it is"

/proc/sg_cells_holding(obj/item/radio/R)
	. = 0
	for(var/list/z_level_grid as anything in SSspatial_grid.grids_by_z_level)
		for(var/list/cell_row as anything in z_level_grid)
			for(var/datum/spatial_grid_cell/cell as anything in cell_row)
				if(R in cell.hearing_contents)
					.++

/proc/sg_run()
	UNTIL(Master.current_runlevel)
	sleep(50)
	sg_log("[world.params["sg-old"] ? "old shuttle move (loc only)" : "shuttle move with the grid update"]")
	var/obj/docking_port/mobile/M = SSshuttle.getShuttle("mining")
	if(!M)
		sg_log("no mining shuttle")
		sg_log("done")
		return
	var/turf/open/aboard
	for(var/turf/open/T in M.return_turfs())
		aboard = T
		break
	var/obj/item/radio/R = new(aboard)
	sg_log("radio on the mining shuttle at [aboard.x],[aboard.y],[aboard.z]: [sg_hears(R)], on [sg_cells_holding(R)] cell(s)")
	var/home = M.getDockedId()
	var/away = home == "mining_home" ? "mining_away" : "mining_home"
	for(var/target in list(away, home))
		var/result = SSshuttle.moveShuttle("mining", target, FALSE)
		var/turf/T = get_turf(R)
		sg_log("moved to [target] (result [result]), radio now at [T.x],[T.y],[T.z]: [sg_hears(R)], on [sg_cells_holding(R)] cell(s)")
	sg_log("done")
