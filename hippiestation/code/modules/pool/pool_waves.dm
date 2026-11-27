// The waves of a pool: how stirred up it is, its wave machine, and the layers of ripple map its tiles share. From Paradise.

// The layers of a pool's waves, from the bottom up
/// The pool's ordinary waves
#define POOL_WAVE_CHOP "chop"
/// Small quick ripples on top of them
#define POOL_WAVE_FINE "fine"
/// The swell from the wave machine, long waves all going one way
#define POOL_WAVE_SWELL "swell"
/// The same swell coming back off the far wall, fainter
#define POOL_WAVE_SWELL_BACK "swell_back"

/// How close to settled a pool has to get, from 0 to 1, before it stops processing
#define POOL_WAVES_SETTLED 0.01
/// How long a pool takes to lose half of what stirred it up
#define POOL_WAVES_HALF_LIFE (6 SECONDS)

/// One piece of a layer of a pool's waves, on the hidden ripple plane.
/// Shared in the vis_contents of every tile that shows it, so one fade changes the whole pool
/obj/effect/abstract/pool_wave_layer
	icon = POOL_WATER_ICON
	plane = WATER_RIPPLE_PLANE
	// Its own plane, not the tile's: an /obj/effect here inherits its holder's plane by default, which drew the hidden ripple
	// map on the water in colour
	vis_flags = NONE
	invisibility = 0
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	alpha = 0
	/// Which of the pool's layers this is a piece of, one of the POOL_WAVE_ layers
	var/wave_layer

/// The waves of one pool of connected water tiles: how stirred up it is and what its wave machine is doing
/datum/pool_waves
	/// The pool's tiles
	var/list/turf/open/pool/tiles = list()
	/// How stirred up the water is, from 0 for left alone to 1
	var/energy = 0
	/// How hard the wave machine is running, one of the POOL_WAVES_ settings
	var/machine = POOL_WAVES_OFF
	/// The shared pieces of each layer, "[layer]|[icon state]" = /obj/effect/abstract/pool_wave_layer
	var/list/layer_objects = list()
	/// Which way the swell runs, "ew" or "ns", set the first time the wave machine is on
	var/swell_axis

/datum/pool_waves/Destroy()
	STOP_PROCESSING(SSprocessing, src)
	for(var/turf/open/pool/tile as anything in tiles)
		tile.vis_contents -= tile_layers(tile)
		tile.waves = null
	tiles.Cut()
	QDEL_LIST_ASSOC_VAL(layer_objects)
	return ..()

/// Makes `tile` part of this pool
/datum/pool_waves/proc/add_tile(turf/open/pool/tile)
	tiles += tile
	tile.waves = src
	tile.vis_contents += tile_layers(tile)

/// Takes `tile` out of this pool, deleting the pool once it has no tiles
/datum/pool_waves/proc/remove_tile(turf/open/pool/tile)
	tile.vis_contents -= tile_layers(tile)
	tile.waves = null
	tiles -= tile
	if(!length(tiles))
		qdel(src)

/// Merges two pools that have met into the bigger one. Returns the pool that's left
/datum/pool_waves/proc/merge(datum/pool_waves/other)
	if(other == src)
		return src
	if(length(other.tiles) > length(tiles))
		return other.merge(src)
	energy = max(energy, other.energy)
	// Fetched first: taking the last tile out of the other pool deletes it
	var/other_machine = other.machine
	for(var/turf/open/pool/tile as anything in other.tiles.Copy())
		other.remove_tile(tile)
		add_tile(tile)
	if(other_machine > machine)
		set_machine(other_machine)
	return src

/// The layer pieces `tile` shows, picked by its place in the 2x2 tile wave pattern
/datum/pool_waves/proc/tile_layers(turf/open/pool/tile)
	// Rows of the sprites count from the top, and y counts up, so odd y is the top row
	var/quarter = "[tile.x % 2][tile.y % 2 ? 0 : 1]"
	. = list(get_layer(POOL_WAVE_CHOP, "chop_[quarter]"), get_layer(POOL_WAVE_FINE, "fine_[quarter]"))
	switch(swell_axis)
		if("ew")
			// The swell going back is the same one flipped left to right, so its pieces are in the other order
			var/row = tile.y % 2 ? 0 : 1
			. += get_layer(POOL_WAVE_SWELL, "swell_ew_[tile.x % 2][row]")
			. += get_layer(POOL_WAVE_SWELL_BACK, "swell_ew_[1 - tile.x % 2][row]")
		if("ns")
			// One wave to a tile, so flipped top to bottom the same piece still meets itself
			. += get_layer(POOL_WAVE_SWELL, "swell_ns_[tile.x % 2]")
			. += get_layer(POOL_WAVE_SWELL_BACK, "swell_ns_[tile.x % 2]")

/// The shared piece of a layer with that icon state, made the first time a tile needs it
/datum/pool_waves/proc/get_layer(wave_layer, state)
	var/key = "[wave_layer]|[state]"
	var/obj/effect/abstract/pool_wave_layer/piece = layer_objects[key]
	if(piece)
		return piece
	piece = new
	piece.icon_state = state
	piece.wave_layer = wave_layer
	piece.alpha = layer_alpha(wave_layer)
	switch(wave_layer)
		if(POOL_WAVE_CHOP)
			piece.layer = TURF_LAYER + 0.01
		if(POOL_WAVE_FINE)
			piece.layer = TURF_LAYER + 0.02
		if(POOL_WAVE_SWELL)
			piece.layer = TURF_LAYER + 0.03
		if(POOL_WAVE_SWELL_BACK)
			piece.layer = TURF_LAYER + 0.04
			// Flipped to run the other way, with its slope colour (red or green) flipped to match
			if(swell_axis == "ew")
				piece.transform = matrix(-1, 0, 0, 0, 1, 0)
				piece.color = list(-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0)
			else
				piece.transform = matrix(1, 0, 0, 0, -1, 0)
				piece.color = list(1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0)
	layer_objects[key] = piece
	return piece

/// How stirred up the pool stays with nothing disturbing it, from its wave machine
/datum/pool_waves/proc/rest_energy()
	switch(machine)
		if(POOL_WAVES_GENTLE)
			return 0.25
		if(POOL_WAVES_STRONG)
			return 0.55
	return 0

/// How strongly a layer is drawn right now, as an alpha
/datum/pool_waves/proc/layer_alpha(wave_layer)
	switch(wave_layer)
		if(POOL_WAVE_CHOP)
			return round(255 * (0.3 + 0.5 * energy))
		if(POOL_WAVE_FINE)
			return round(255 * (0.25 + 0.25 * energy))
		if(POOL_WAVE_SWELL)
			return round(255 * 0.5 * machine)
		if(POOL_WAVE_SWELL_BACK)
			return round(255 * 0.25 * machine)
	return 0

/// Fades every layer to how strong it should be now, over `time`
/datum/pool_waves/proc/update_layers(time)
	for(var/key in layer_objects)
		var/obj/effect/abstract/pool_wave_layer/piece = layer_objects[key]
		var/new_alpha = layer_alpha(piece.wave_layer)
		if(piece.alpha != new_alpha)
			animate(piece, alpha = new_alpha, time = time)

/// Stirs the pool up by `amount`, out of 1. A wading step is 0.03, jumping in is 0.2
/datum/pool_waves/proc/stir(amount)
	energy = min(1, energy + amount)
	update_layers(0.5 SECONDS)
	START_PROCESSING(SSprocessing, src)

// Settles the water toward flat, or toward what the wave machine keeps up
/datum/pool_waves/process(wait)
	var/rest = rest_energy()
	energy = rest + (energy - rest) * 0.5 ** (wait / POOL_WAVES_HALF_LIFE)
	if(abs(energy - rest) < POOL_WAVES_SETTLED)
		energy = rest
		update_layers(wait)
		return PROCESS_KILL
	update_layers(wait)

/// Sets the pool's wave machine. The first time it's on, the swell is added along the pool
/datum/pool_waves/proc/set_machine(setting)
	machine = setting
	if(setting && !swell_axis)
		add_swell()
	update_layers(2 SECONDS)
	START_PROCESSING(SSprocessing, src)
	// Things floating on the pool ride higher on bigger waves
	for(var/datum/component/pool_sunk/afloat as anything in GLOB.pool_things_afloat)
		var/atom/movable/thing = afloat.parent
		var/turf/open/pool/under = thing.loc
		if(istype(under) && under.waves == src)
			afloat.bob()

/// Adds the swell's layers to the tiles, running along the pool's longer side
/datum/pool_waves/proc/add_swell()
	var/min_x = INFINITY
	var/max_x = -INFINITY
	var/min_y = INFINITY
	var/max_y = -INFINITY
	for(var/turf/open/pool/tile as anything in tiles)
		min_x = min(min_x, tile.x)
		max_x = max(max_x, tile.x)
		min_y = min(min_y, tile.y)
		max_y = max(max_y, tile.y)
	// The chop and the ripples are already on the tiles, so only the swell's pieces are new
	var/list/before = list()
	for(var/turf/open/pool/tile as anything in tiles)
		before[tile] = tile_layers(tile)
	swell_axis = (max_x - min_x >= max_y - min_y) ? "ew" : "ns"
	for(var/turf/open/pool/tile as anything in tiles)
		tile.vis_contents += tile_layers(tile) - before[tile]

#undef POOL_WAVE_CHOP
#undef POOL_WAVE_FINE
#undef POOL_WAVE_SWELL
#undef POOL_WAVE_SWELL_BACK
#undef POOL_WAVES_SETTLED
#undef POOL_WAVES_HALF_LIFE
