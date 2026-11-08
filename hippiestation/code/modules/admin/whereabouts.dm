// Whereabouts: where every player (and bot) was, every five seconds, for the last hour, so admins can see who was where when
// something happened (the Tickets window's Map, and what was said within earshot of a player). The user's tooling plan,
// stage 2 (2026-11-07): "where everyone was" and "speech near them".
//
// A snapshot is list(time, flat list): WB_FIELDS values for each mob with a ckey and a body (not the lobby): ckey, name, x, y, z,
// state. One flat list a snapshot keeps it to a few MB for an hour of 80 players.

#define WB_FIELDS 6
#define WB_CKEY 1
#define WB_NAME 2
#define WB_X 3
#define WB_Y 4
#define WB_Z 5
#define WB_STATE 6
#define WB_KEPT (1 HOURS)

SUBSYSTEM_DEF(whereabouts)
	name = "Whereabouts"
	wait = 5 SECONDS
	flags = SS_BACKGROUND | SS_NO_INIT
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	/// list(time, flat list), oldest first
	var/list/snapshots = list()

/datum/controller/subsystem/whereabouts/stat_entry(msg)
	return ..("[snapshots.len] kept")

/datum/controller/subsystem/whereabouts/fire(resumed)
	var/list/flat = list()
	for(var/mob/M as anything in GLOB.mob_list)
		if(!M?.ckey || isnewplayer(M)) // a hard-deleted mob leaves a null in the list
			continue
		var/turf/T = get_turf(M)
		if(!T)
			continue
		flat += M.ckey
		flat += isobserver(M) ? (M.mind?.name || M.name) : M.real_name
		flat += T.x
		flat += T.y
		flat += T.z
		flat += admin_mob_state(M)
	snapshots += list(list(world.time, flat))
	while(snapshots.len && snapshots[1][1] < world.time - WB_KEPT)
		snapshots.Cut(1, 2)

/// The index of the snapshot nearest a time, or 0 if none are kept
/datum/controller/subsystem/whereabouts/proc/nearest(time)
	var/low = 1
	var/high = snapshots.len
	if(!high)
		return 0
	while(low < high)
		var/mid = round((low + high) / 2)
		if(snapshots[mid][1] < time)
			low = mid + 1
		else
			high = mid
	if(low > 1 && abs(snapshots[low - 1][1] - time) <= abs(snapshots[low][1] - time))
		return low - 1
	return low

/// Where a player was at a time: list(x, y, z, state), from the nearest snapshot within ten seconds
/datum/controller/subsystem/whereabouts/proc/position_of(player_ckey, time)
	var/index = nearest(time)
	if(!index || abs(snapshots[index][1] - time) > 10 SECONDS)
		return null
	var/list/flat = snapshots[index][2]
	for(var/i in 1 to flat.len step WB_FIELDS)
		if(flat[i + WB_CKEY - 1] == player_ckey)
			return list(flat[i + WB_X - 1], flat[i + WB_Y - 1], flat[i + WB_Z - 1], flat[i + WB_STATE - 1])

/// Everyone in a snapshot on one level, as the map draws them
/datum/controller/subsystem/whereabouts/proc/dots(index, z)
	. = list()
	if(index < 1 || index > snapshots.len)
		return
	var/list/flat = snapshots[index][2]
	for(var/i in 1 to flat.len step WB_FIELDS)
		if(flat[i + WB_Z - 1] != z)
			continue
		. += list(list("ckey" = flat[i + WB_CKEY - 1], "name" = flat[i + WB_NAME - 1], "x" = flat[i + WB_X - 1], "y" = flat[i + WB_Y - 1], "state" = flat[i + WB_STATE - 1]))

#undef WB_FIELDS
#undef WB_CKEY
#undef WB_NAME
#undef WB_X
#undef WB_Y
#undef WB_Z
#undef WB_STATE
#undef WB_KEPT
