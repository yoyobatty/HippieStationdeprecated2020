// Heat haze, from Paradise (lava-looks and merged-flames, 2026-11-27): the air over lava and over a middling or big fire
// ripples, bending what's under and behind it a pixel or two, mostly sideways, as hot air does.
//
// Hot things draw ripple maps on a hidden plane (red pushes sideways, green up and down, mid grey not at all). Nobody sees
// them: the floor and game world planes displace themselves by that plane. Paradise had a displacement plane already, the
// gravity pulse one, on every plane master. Here a displace filter is a full screen pass on two planes each frame, so only
// players near lava or a fire get it, on Medium graphics and up (it moves by itself), the way Paradise kept its lava bloom to
// players near lava. Lava's glow and bloom were here already (emissive_glow_hazards.dm).

#define LAVA_HAZE_KINDS 4 // ripple maps, so lava tiles next to each other don't ripple in step
#define HEAT_HAZE_CHUNK 16 // tiles a side of a map chunk, for whether a player is near something hazy

// ---- Lava

/turf/open/lava
	/// Does the air over it ripple with the heat?
	var/hazy = TRUE

/turf/open/lava/plasma // liquid plasma is cold
	hazy = FALSE

/turf/open/lava/Initialize(mapload)
	. = ..()
	if(!hazy)
		return
	add_overlay(lava_heat_haze((x * 7 + y * 13) % LAVA_HAZE_KINDS))
	heat_haze_count(src, 1)

/turf/open/lava/Destroy(force)
	if(hazy)
		heat_haze_count(src, -1)
	return ..()

/// The ripple map over lava, `kind` 0 to LAVA_HAZE_KINDS - 1: half a tile wider than the tile each side and two tiles high, so a
/// lake's tiles run into one haze. Made once and shared by every lava tile.
/proc/lava_heat_haze(kind)
	var/static/list/made = list()
	. = made["[kind]"]
	if(.)
		return
	var/mutable_appearance/shimmer = mutable_appearance('hippiestation/icons/effects/lava_haze.dmi', "shimmer-[kind]", plane = HEAT_HAZE_PLANE)
	shimmer.appearance_flags = KEEP_APART | RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM
	shimmer.pixel_x = -16
	. = shimmer
	made["[kind]"] = .

// ---- Near something hazy: counted per chunk, a list of counts for each z-level

/// z-level -> list of hazy things per chunk, chunk (cx, cy) at cx + cy * width + 1
GLOBAL_LIST_EMPTY(heat_haze_chunks)
/// Off, nobody gets the haze, for before and after pictures in one boot
GLOBAL_VAR_INIT(heat_haze_allowed, TRUE)
GLOBAL_DATUM(heat_haze_watcher, /datum/heat_haze_watcher)

/proc/heat_haze_chunks_wide()
	return CEILING(world.maxx / HEAT_HAZE_CHUNK, 1)

/// Counts something hazy in (change 1) or out (change -1) of T's chunk
/proc/heat_haze_count(turf/T, change)
	if(!T?.z)
		return
	if(GLOB.heat_haze_chunks.len < T.z)
		GLOB.heat_haze_chunks.len = T.z
	var/list/counts = GLOB.heat_haze_chunks[T.z]
	var/wide = heat_haze_chunks_wide()
	if(!counts)
		counts = new /list(wide * CEILING(world.maxy / HEAT_HAZE_CHUNK, 1))
		GLOB.heat_haze_chunks[T.z] = counts
	var/index = round((T.x - 1) / HEAT_HAZE_CHUNK) + round((T.y - 1) / HEAT_HAZE_CHUNK) * wide + 1
	counts[index] = max(0, counts[index] + change)
	if(change > 0 && !GLOB.heat_haze_watcher)
		GLOB.heat_haze_watcher = new

/// Is there something hazy in T's chunk or the ones round it? That reaches a little past a player's screen, so the haze is on
/// before it comes into view.
/proc/heat_haze_near(turf/T)
	if(!T || GLOB.heat_haze_chunks.len < T.z)
		return FALSE
	var/list/counts = GLOB.heat_haze_chunks[T.z]
	if(!counts)
		return FALSE
	var/wide = heat_haze_chunks_wide()
	var/high = counts.len / wide
	var/cx = round((T.x - 1) / HEAT_HAZE_CHUNK)
	var/cy = round((T.y - 1) / HEAT_HAZE_CHUNK)
	for(var/y in max(cy - 1, 0) to min(cy + 1, high - 1))
		for(var/x in max(cx - 1, 0) to min(cx + 1, wide - 1))
			if(counts[x + y * wide + 1])
				return TRUE
	return FALSE

/// Turns the haze on for players near something hazy and off for everyone else, once a second
/datum/heat_haze_watcher

/datum/heat_haze_watcher/New()
	START_PROCESSING(SSprocessing, src)

/datum/heat_haze_watcher/process()
	for(var/client/C as anything in GLOB.clients)
		var/datum/hud/hud = C.mob?.hud_used
		if(!hud)
			continue
		var/near = GLOB.heat_haze_allowed && heat_haze_near(get_turf(C.eye)) && C.prefs?.graphics_quality() >= GRAPHICS_QUALITY_MEDIUM
		if(near != hud.heat_haze_on)
			hud.set_heat_haze(near)

// ---- The planes

/obj/screen/plane_master/heat_haze
	name = "heat haze plane master"
	plane = HEAT_HAZE_PLANE
	blend_mode = BLEND_ADD
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	render_target = HEAT_HAZE_RENDER_TARGET

/datum/hud
	/// Are the floor and game world rippling with heat haze for this player? The watcher above turns it on near lava and fires
	var/heat_haze_on = FALSE

/datum/hud/proc/set_heat_haze(on)
	heat_haze_on = on
	refresh_heat_haze()
	// A displace filter put on as its map's plane comes on screen can come up blank (Paradise puts its gravity pulse one on 2 s
	// late for the same reason), so it's put on again
	if(on)
		addtimer(CALLBACK(src, PROC_REF(refresh_heat_haze)), 2 SECONDS)

/datum/hud/proc/refresh_heat_haze()
	for(var/plane in list("[FLOOR_PLANE]", "[GAME_PLANE]"))
		var/obj/screen/plane_master/master = plane_masters[plane]
		master?.backdrop(mymob)

/obj/screen/plane_master/proc/add_heat_haze(mob/mymob)
	if(!mymob?.hud_used?.heat_haze_on || mymob.client?.prefs?.graphics_quality() < GRAPHICS_QUALITY_MEDIUM)
		return
	filters += filter(type = "displace", render_source = HEAT_HAZE_RENDER_TARGET, size = HEAT_HAZE_DISPLACE_SIZE)

/obj/screen/plane_master/floor/backdrop(mob/mymob)
	. = ..()
	add_heat_haze(mymob)

/obj/screen/plane_master/game_world/backdrop(mob/mymob)
	. = ..()
	add_heat_haze(mymob)

#undef LAVA_HAZE_KINDS
#undef HEAT_HAZE_CHUNK
