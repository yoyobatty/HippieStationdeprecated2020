// Find: everything in the world searched by name, type, ref or player, in a window (tgui-next AdminFind.js). Where to look:
// everywhere, this z-level, near the admin, or one tile, which lists everything on it: the turf, its area, and every atom
// there including invisible, underfloor and abstract ones, and what's inside them if asked. Each result says where it is and
// who's carrying it, with Jump, VV, Get, Follow, Mark and Delete; the matches are counted by type. Opened from the Admin
// tab, or "Everything here" in a turf's View Variables. The user asked for finding objects made easy, 2026-11-07.

#define FIND_SHOWN 300

/client/var/datum/admin_find/admin_find

/client/proc/cmd_admin_find()
	set name = "Find"
	set category = "Admin"
	set desc = "Find things by name, type, ref or player, anywhere or on one tile."
	if(!check_rights(R_ADMIN))
		return
	open_admin_find()

/client/proc/open_admin_find(turf/tile, via_hub)
	if(!admin_find)
		admin_find = new
	if(tile)
		admin_find.mode = "name"
		admin_find.query = ""
		admin_find.scope = "tile"
		admin_find.tile_x = tile.x
		admin_find.tile_y = tile.y
		admin_find.tile_z = tile.z
		admin_find.search(mob)
	if(hub_wants(via_hub))
		open_admin_hub("find")
		return
	admin_find.ui_interact(mob)

/datum/admin_find
	/// name, type, ref or player
	var/mode = "name"
	var/query = ""
	/// everywhere, z, near or tile
	var/scope = "everywhere"
	var/radius = 15
	var/tile_x
	var/tile_y
	var/tile_z
	/// Look inside things (a backpack's contents) as well, on a tile
	var/inside = FALSE
	var/list/results = list()
	var/list/type_counts = list()
	var/matched = 0
	var/searched = FALSE
	var/took = 0

/datum/admin_find/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.admin_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "admin_find", "Find", 900, 640, master_ui, state)
		ui.open()

/// Whether a thing is where the search looks
/datum/admin_find/proc/in_scope(atom/A, turf/here)
	switch(scope)
		if("everywhere")
			return TRUE
		if("z")
			var/turf/T = get_turf(A)
			return T && here && T.z == here.z
		if("near")
			var/turf/T = get_turf(A)
			return T && here && T.z == here.z && get_dist(T, here) <= radius
	return TRUE

/datum/admin_find/proc/matches(datum/D, typepath, needle)
	switch(mode)
		if("name")
			return !needle || (isatom(D) && findtext(D:name, needle))
		if("type")
			return istype(D, typepath)
		if("player")
			return ismob(D) && D:ckey && findtext(D:ckey, ckey(needle))
	return FALSE

/datum/admin_find/proc/search(mob/user)
	var/started = REALTIMEOFDAY
	results = list()
	type_counts = list()
	matched = 0
	searched = TRUE
	var/turf/here = get_turf(user)
	var/needle = trim(query)
	var/list/found = list()
	if(mode == "ref")
		var/datum/D = locate(needle)
		if(!D && !findtext(needle, "\["))
			D = locate("\[[needle]\]")
		if(istype(D))
			found += D
	else if(scope == "tile")
		var/turf/T = locate(tile_x, tile_y, tile_z)
		if(T)
			var/list/everything = list(T, T.loc)
			for(var/atom/movable/AM as anything in T.contents)
				everything += AM
				if(inside)
					everything += AM.GetAllContents() - AM
			for(var/datum/D as anything in everything)
				if(mode == "name" && !needle || matches(D, text2path(needle), needle))
					found += D
	else
		var/typepath = mode == "type" ? text2path(needle) : null
		if(mode == "type" && !typepath)
			took = 0
			return
		var/count = 0
		if(mode == "player")
			for(var/mob/M as anything in GLOB.mob_list)
				if(matches(M, null, needle) && in_scope(M, here))
					found += M
		else if(typepath && ispath(typepath, /turf))
			for(var/turf/T in world)
				if(istype(T, typepath) && in_scope(T, here))
					found += T
				if(!(++count % 5000))
					CHECK_TICK
		else if(typepath && ispath(typepath, /area))
			for(var/area/A in world)
				if(istype(A, typepath))
					found += A
		else if(typepath && !ispath(typepath, /atom))
			for(var/datum/D) // every datum: slow, only for a non-atom type
				if(istype(D, typepath))
					found += D
				if(!(++count % 5000))
					CHECK_TICK
		else
			for(var/atom/movable/AM in world)
				if(matches(AM, typepath, needle) && in_scope(AM, here))
					found += AM
				if(!(++count % 5000))
					CHECK_TICK
	matched = found.len
	for(var/datum/D as anything in found)
		type_counts["[D.type]"]++
		if(results.len < FIND_SHOWN)
			results += WEAKREF(D)
	took = round((REALTIMEOFDAY - started) / 10, 0.01)

/// A result as the window shows it
/proc/admin_find_row(datum/D)
	var/list/row = list("ref" = REF(D), "type" = "[D.type]", "name" = isatom(D) ? D:name : "[D]")
	if(isatom(D))
		var/atom/A = D
		var/turf/T = get_turf(A)
		if(T)
			var/area/AR = T.loc
			row["where"] = "[AR?.name] ([T.x], [T.y], [T.z])"
		else if(!isarea(A))
			row["where"] = "nullspace"
		row["movable"] = ismovable(A)
		row["invisible"] = A.invisibility > SEE_INVISIBLE_LIVING || !A.icon
		row["underfloor"] = ismovable(A) && A.level == 1 // goes under floor tiles (pipes, cables); turfs have a level too
		var/atom/at = A.loc
		var/steps = 0
		while(at && !isturf(at) && steps++ < 20)
			if(ismob(at))
				var/mob/M = at
				row["carrier"] = "[M.name][M.ckey ? " ([M.ckey])" : ""]"
				break
			at = at.loc
		if(ismob(A))
			var/mob/M = A
			row["ckey"] = M.ckey
	return row

/datum/admin_find/ui_data(mob/user)
	var/list/rows = list()
	for(var/datum/weakref/W as anything in results)
		var/datum/D = W.resolve()
		if(D)
			rows += list(admin_find_row(D))
	var/list/counts = list()
	var/list/sorted = sortTim(type_counts.Copy(), GLOBAL_PROC_REF(cmp_numeric_dsc), associative = TRUE)
	for(var/type in sorted)
		counts += list(list("type" = type, "count" = sorted[type]))
		if(counts.len >= 12)
			break
	var/turf/here = get_turf(user)
	return list(
		"mode" = mode,
		"query" = query,
		"scope" = scope,
		"radius" = radius,
		"tile" = tile_z ? "[tile_x], [tile_y], [tile_z]" : null,
		"here" = here ? "[here.x], [here.y], [here.z]" : null,
		"inside" = inside,
		"rows" = rows,
		"counts" = counts,
		"matched" = matched,
		"searched" = searched,
		"took" = took,
	)

/datum/admin_find/ui_act(action, list/params)
	if(..())
		return
	if(!check_rights(R_ADMIN))
		return
	if(action == "player_menu") // a name's menu (player_menu.dm)
		return player_menu_act(usr, params)
	switch(action)
		if("search")
			mode = (params["mode"] in list("name", "type", "ref", "player")) ? params["mode"] : "name"
			query = params["query"] || ""
			scope = (params["scope"] in list("everywhere", "z", "near", "tile")) ? params["scope"] : "everywhere"
			radius = clamp(text2num(params["radius"]) || 15, 1, 100)
			if(scope == "tile")
				var/list/xyz = splittext(params["tile"] || "", ",")
				if(xyz.len == 3)
					tile_x = text2num(xyz[1])
					tile_y = text2num(xyz[2])
					tile_z = text2num(xyz[3])
			inside = !!params["inside"]
			search(usr)
			return TRUE
		if("here")
			var/turf/T = get_turf(usr)
			if(T)
				scope = "tile"
				tile_x = T.x
				tile_y = T.y
				tile_z = T.z
				mode = "name"
				query = ""
				search(usr)
			return TRUE
	var/datum/D = locate(params["ref"])
	if(!D)
		return
	var/atom/A = D
	switch(action)
		if("vv")
			usr.client.debug_variables(D)
		if("jmp")
			var/turf/T = get_turf(A)
			if(T)
				usr.client.jumptocoord(T.x, T.y, T.z)
		if("flw")
			if(ismovable(A) && (isobserver(usr) || usr.client.admin_ghost()))
				var/mob/dead/observer/ghost = usr.client.mob
				ghost.ManualFollow(A)
		if("get")
			if(ismovable(A) && !QDELETED(A))
				var/atom/movable/AM = A
				AM.forceMove(get_turf(usr))
				log_admin("[key_name(usr)] brought [AM] ([AM.type]) to [AREACOORD(usr)] with Find")
		if("mark")
			usr.client.mark_datum(D)
		if("tile")
			var/turf/T = get_turf(A)
			if(T)
				scope = "tile"
				tile_x = T.x
				tile_y = T.y
				tile_z = T.z
				mode = "name"
				query = ""
				search(usr)
		if("del")
			usr.client.admin_delete(D) // asks to be sure
			search(usr)
	return TRUE

#undef FIND_SHOWN
