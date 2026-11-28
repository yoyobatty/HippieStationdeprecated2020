// Light textures: a prototype of drawing the lighting as one little picture per chunk of 8 x 8 turfs, instead of one lighting
// object per lit turf.
//
// The lighting engine (lighting_engine.dm) still works out every corner, as it always has: that's what the game reads
// (get_lumcount(), who can see what) and it's the same light. What changes is how it gets to the screen. Each chunk's corners,
// in the colours they draw (tone curve, bounce light and all), are written out as an 11 x 11 picture, one pixel a corner
// (tools/lighting_engine/src/sprites.rs, in data/lightmaps/), and the client scales it up 32 times with smooth filtering, as
// a lighting object's gradient blends its four corners. The pictures are drawn on the lighting plane over its dark backdrop and
// under the full brightness of areas that aren't dynamically lit.
//
// The lighting objects leave the map (they stay, out of the world, for what they keep: their turf's luminosity, which is what
// lets a player see a lit turf). Map sending stops looking at one object a lit turf; it looks at one image per player instead,
// and the 16 or so chunk pictures in it.
//
// How a picture gets to a player: BYOND only sends what's on a turf the player can see, and a picture's own place often isn't
// (a lamp round the corner lighting the corridor you're in). So the pictures are on nobody's turf. Each player has an image of
// their own (in client.images, so nobody else sees it) on the turf they're looking from, whose vis_contents are the chunk
// pictures around them. The image is offset back to the map's corner, so everything in it is drawn where it is in the world;
// it only has to be on a turf the player can see. (Tested with a real client: tools/light_sprites/spike_*.dm.)
//
// World params: lighting-render=sprites  light textures from the start (the engine must be running)
// SSlighting.set_sprites(TRUE/FALSE) switches in a running round (the light bench does, tools/light_sprites/light_bench.dm).

/// Turfs a side in a chunk (sprites.rs CHUNK)
#define LIGHT_TEXTURE_CHUNK 8
/// Pixels a side in a chunk's picture (sprites.rs SIDE)
#define LIGHT_TEXTURE_SIDE 11
/// How far from where a player looks, in turfs, chunks are in their image: half the widest view, and a turf to spare
#define LIGHT_TEXTURE_RANGE 12
/// Chunks redrawn per call to the engine
#define LIGHT_TEXTURE_BATCH 200
/// Where the engine writes the pictures (sprites.rs DIR), in a folder per server named by its port (sprites.rs dir())
#define LIGHTMAP_DIR "data/lightmaps"
/// Bytes of pictures loaded into the resource cache in a round before light textures give way to lighting objects. Every new
/// picture (a flashlight walking makes a few each step) stays in the resource cache, in `lightmaps` and on disk, and goes to each
/// player who sees it, for the rest of the round: nothing can take it back out, so this caps the lot. 32 MB is some 60000
/// pictures (a picture a corner) or 6000 fine ones.
#define LIGHT_TEXTURE_BUDGET (32 * 1024 * 1024)
#define LIGHT_SPRITES_TEXTURES 1
#define LIGHT_SPRITES_OVERLAYS 2
#define LIGHT_SPRITES_FINE 3
/// Pixels a tile in a fine picture (sprites.rs FINE), and pixels a side (FINE_SIDE)
#define LIGHT_TEXTURE_FINE 4
#define LIGHT_TEXTURE_FINE_SIDE 36

/datum/controller/subsystem/lighting
	/// Drawn with light textures or chunk overlays, not lighting objects on their turfs: the objects are out of the world
	var/sprites = FALSE
	/// Which: LIGHT_SPRITES_TEXTURES (a picture a chunk) or LIGHT_SPRITES_OVERLAYS (each chunk wears its lighting objects as overlays)
	var/sprite_kind = 0
	/// Chunks whose lighting objects drew something new, for LIGHT_SPRITES_OVERLAYS
	var/list/obj/effect/light_texture/dirty_chunks = list()
	/// Chunk overlay rebuilds since turned on, and their time (ms)
	var/chunks_rebuilt = 0
	var/chunks_rebuild_ms = 0
	/// "z_kx_ky" -> that chunk's picture
	var/list/obj/effect/light_texture/light_textures = list()
	/// Goes up whenever a chunk gets its first picture, so players' images pick it up
	var/light_texture_epoch = 0
	/// Picture name -> the picture, in the resource cache
	var/list/lightmaps = list()
	/// Since light textures were turned on: chunks redrawn, pictures loaded into the resource cache, and the time those took (ms)
	var/sprites_drawn = 0
	var/lightmaps_loaded = 0
	/// Their size (bytes), against LIGHT_TEXTURE_BUDGET; never goes down in a round, as the resource cache doesn't
	var/lightmap_bytes = 0
	var/sprites_engine_ms = 0
	var/sprites_load_ms = 0

/obj/effect/light_texture
	name = ""
	plane = LIGHTING_PLANE
	layer = LIGHTING_LAYER - 0.1 // under the full brightness of areas that aren't dynamically lit (/obj/effect/fullbright)
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	anchored = TRUE
	appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM
	vis_flags = NONE
	/// Where it is, for chunk overlays
	var/chunk_z
	var/chunk_x
	var/chunk_y

/client
	/// This player's light textures (light_sprites.dm): an image on the turf they look from, the chunks around it in its vis_contents
	var/image/light_holder
	/// The chunk (as "z_kx_ky") and texture epoch its vis_contents were picked for
	var/light_holder_chunk
	var/light_holder_epoch = -1

/datum/controller/subsystem/lighting/Initialize(timeofday)
	. = ..()
	switch(world.params["lighting-render"])
		if("sprites", "textures")
			set_sprites(LIGHT_SPRITES_TEXTURES)
		if("chunks")
			set_sprites(LIGHT_SPRITES_OVERLAYS)
		if("fine")
			set_sprites(LIGHT_SPRITES_FINE)

/// Switches between light textures (LIGHT_SPRITES_TEXTURES), chunk overlays (LIGHT_SPRITES_OVERLAYS) and lighting objects (0).
/// Returns why not, or null.
/datum/controller/subsystem/lighting/proc/set_sprites(kind)
	if(kind == sprite_kind)
		return
	if(kind && !native)
		return "the lighting engine isn't running ([native_status])"
	if(sprite_kind)
		// The last kind off first, whatever comes next
		try
			call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_textures")(0)
		catch(var/exception/off_error)
			log_world("Lighting: couldn't turn the engine's light textures off: [off_error]")
		for(var/client/C as anything in GLOB.clients)
			drop_light_holder(C)
		for(var/key in light_textures)
			var/obj/effect/light_texture/T = light_textures[key]
			T.icon = null
			T.overlays.Cut()
		light_textures.Cut()
		dirty_chunks.Cut()
		light_texture_epoch++
	sprite_kind = kind
	var/on = !!kind
	if((kind == LIGHT_SPRITES_TEXTURES || kind == LIGHT_SPRITES_FINE) && lightmap_bytes >= LIGHT_TEXTURE_BUDGET)
		kind = 0
		sprite_kind = 0
		on = FALSE
		. = "the light textures' budget for this round is spent ([round(lightmap_bytes / 1024 / 1024)] MB)"
		log_world("Lighting: [.]")
	if(kind == LIGHT_SPRITES_TEXTURES || kind == LIGHT_SPRITES_FINE)
		var/result
		try
			result = call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_textures")(1, world.port)
		catch(var/exception/on_error)
			result = "[on_error]" // a DLL without light textures: drawn with lighting objects
		if(!isnum(result) || result < 0)
			sprite_kind = 0
			on = FALSE
			. = "the engine can't draw light textures: [result]"
			log_world("Lighting: [.], drawn with lighting objects")
		else
			log_world("Lighting: drawn with [kind == LIGHT_SPRITES_FINE ? "fine " : ""]light textures, [result] chunks to draw")
	else if(kind == LIGHT_SPRITES_OVERLAYS)
		log_world("Lighting: drawn with chunks wearing their lighting objects")
	else
		log_world("Lighting: drawn with lighting objects")
	sprites = on
	// Each lighting object out of the world, or back into it; luminosity goes with it
	for(var/z in 1 to world.maxz)
		for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			var/atom/movable/lighting_object/O = T.lighting_object
			if(!O)
				continue
			if(on)
				O.loc = null
				T.luminosity = O.luminosity
				if(sprite_kind == LIGHT_SPRITES_OVERLAYS)
					O.place_in_chunk()
					// What it drew may be from before (light textures leave it as it was): drawn afresh
					if(!O.needs_update)
						O.needs_update = TRUE
						objects_queue += O
			else
				O.loc = T
				O.pixel_x = 0
				O.pixel_y = 0
				T.luminosity = 0
				// What it drew may be anything from before: drawn afresh
				if(!O.needs_update)
					O.needs_update = TRUE
					objects_queue += O
		CHECK_TICK

/datum/controller/subsystem/lighting/native_draw(init_tick_checks)
	. = ..()
	if(. && (sprite_kind == LIGHT_SPRITES_TEXTURES || sprite_kind == LIGHT_SPRITES_FINE))
		. = draw_textures(init_tick_checks)
	else if(. && sprite_kind == LIGHT_SPRITES_OVERLAYS)
		. = rebuild_chunks(init_tick_checks)

/// The chunk a turf's lighting is in, made if it isn't there yet (chunk overlays)
/datum/controller/subsystem/lighting/proc/chunk_at(z, kx, ky)
	var/key = "[z]_[kx]_[ky]"
	var/obj/effect/light_texture/T = light_textures[key]
	if(!T)
		T = new
		T.chunk_z = z
		T.chunk_x = kx
		T.chunk_y = ky
		// Its turfs' lighting objects are worn at their offsets from the chunk's south-west turf (kx*8 + 1, ky*8 + 1)
		T.pixel_x = kx * LIGHT_TEXTURE_CHUNK * world.icon_size
		T.pixel_y = ky * LIGHT_TEXTURE_CHUNK * world.icon_size
		light_textures[key] = T
		light_texture_epoch++
	return T

/// Chunks whose lighting objects drew something new wear them again
/datum/controller/subsystem/lighting/proc/rebuild_chunks(init_tick_checks)
	while(length(dirty_chunks))
		var/obj/effect/light_texture/T = dirty_chunks[length(dirty_chunks)]
		dirty_chunks.len--
		var/started = TICK_USAGE_REAL
		var/x0 = T.chunk_x * LIGHT_TEXTURE_CHUNK + 1
		var/y0 = T.chunk_y * LIGHT_TEXTURE_CHUNK + 1
		var/list/worn = list()
		for(var/turf/place as anything in block(locate(max(1, x0), max(1, y0), T.chunk_z), locate(min(world.maxx, x0 + LIGHT_TEXTURE_CHUNK - 1), min(world.maxy, y0 + LIGHT_TEXTURE_CHUNK - 1), T.chunk_z)))
			var/atom/movable/lighting_object/O = place.lighting_object
			if(O && O.icon_state != "dark")
				worn += O.appearance
		T.overlays = worn
		chunks_rebuilt++
		chunks_rebuild_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
		if(init_tick_checks)
			CHECK_TICK
		else if(MC_TICK_CHECK)
			return FALSE
	return TRUE

/// The chunks whose corners changed: each gets its new picture
/datum/controller/subsystem/lighting/proc/draw_textures(init_tick_checks)
	var/list/out = list()
	var/left = 1
	while(left > 0)
		out.Cut()
		var/started = TICK_USAGE_REAL
		try
			left = call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_texture_take")(LIGHT_TEXTURE_BATCH, out, sprite_kind == LIGHT_SPRITES_FINE)
		catch(var/exception/error)
			left = "[error]"
			out.Cut()
		sprites_engine_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
		if(!isnum(left) || left < 0)
			stack_trace("Lighting: light textures: [left]")
			set_sprites(FALSE)
			return TRUE
		for(var/at = 1, at <= length(out), at += 7)
			draw_texture(out[at], out[at + 1], out[at + 2], out[at + 3] || out[at + 4] || out[at + 5] || out[at + 6] ? "[out[at + 3]]_[out[at + 4]]_[out[at + 5]]_[out[at + 6]]" : null)
		if(lightmap_bytes >= LIGHT_TEXTURE_BUDGET)
			log_world("Lighting: light textures loaded [round(lightmap_bytes / 1024 / 1024)] MB of pictures, their budget for this round: drawn with lighting objects")
			set_sprites(FALSE)
			return TRUE
		if(init_tick_checks)
			CHECK_TICK
		else if(left > 0 && MC_TICK_CHECK)
			return FALSE
	return TRUE

/datum/controller/subsystem/lighting/proc/draw_texture(z, kx, ky, name)
	var/key = "[z]_[kx]_[ky]"
	var/obj/effect/light_texture/T = light_textures[key]
	sprites_drawn++
	if(!name)
		if(T)
			T.icon = null
		return
	if(!T)
		T = new
		light_textures[key] = T
		// A picture `side` pixels across, each `scale` screen pixels, with pixel i's middle at base + i * scale from the map's corner.
		// Scaled about its middle, the picture's bottom-left goes at base - side / 2 - scale / 2 + side * scale / 2.
		// Coarse: pixel i is the corner kx*8 - 1 + i, at 32 (kx*8 - 1 + i). Fine: pixel i's middle is (i - 1.5) / 4 tiles east of the chunk.
		var/side = LIGHT_TEXTURE_SIDE
		var/scale = world.icon_size
		var/base_x = (kx * LIGHT_TEXTURE_CHUNK - 1) * world.icon_size
		var/base_y = (ky * LIGHT_TEXTURE_CHUNK - 1) * world.icon_size
		if(sprite_kind == LIGHT_SPRITES_FINE)
			side = LIGHT_TEXTURE_FINE_SIDE
			scale = world.icon_size / LIGHT_TEXTURE_FINE
			base_x = kx * LIGHT_TEXTURE_CHUNK * world.icon_size - scale * 1.5
			base_y = ky * LIGHT_TEXTURE_CHUNK * world.icon_size - scale * 1.5
		var/edge = (side * scale - side - scale) / 2
		T.transform = matrix(scale, 0, base_x + edge, 0, scale, base_y + edge)
		light_texture_epoch++
	var/picture = lightmaps[name]
	if(!picture)
		var/started = TICK_USAGE_REAL
		var/picture_file = file("[LIGHTMAP_DIR]/[world.port]/[name].png")
		lightmap_bytes += length(picture_file)
		picture = fcopy_rsc(picture_file)
		sprites_load_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
		lightmaps[name] = picture
		lightmaps_loaded++
	T.icon = picture

/// Puts a player's image on the turf they're looking from, with the chunk pictures around them in it
/datum/controller/subsystem/lighting/proc/place_light_holder(client/C)
	var/turf/T = get_turf(C.eye)
	if(!T)
		return
	var/image/holder = C.light_holder
	if(!holder)
		holder = image(null, T)
		holder.plane = LIGHTING_PLANE
		holder.appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM
		C.light_holder = holder
		C.light_holder_chunk = null
		C.images += holder
	if(holder.loc != T)
		holder.loc = T
		holder.pixel_x = (1 - T.x) * world.icon_size
		holder.pixel_y = (1 - T.y) * world.icon_size
	var/kx = round((T.x - 1) / LIGHT_TEXTURE_CHUNK)
	var/ky = round((T.y - 1) / LIGHT_TEXTURE_CHUNK)
	var/key = "[T.z]_[kx]_[ky]"
	if(key == C.light_holder_chunk && C.light_holder_epoch == light_texture_epoch)
		return
	C.light_holder_chunk = key
	C.light_holder_epoch = light_texture_epoch
	var/list/chunks = list()
	for(var/x in round((T.x - 1 - LIGHT_TEXTURE_RANGE) / LIGHT_TEXTURE_CHUNK) to round((T.x - 1 + LIGHT_TEXTURE_RANGE) / LIGHT_TEXTURE_CHUNK))
		for(var/y in round((T.y - 1 - LIGHT_TEXTURE_RANGE) / LIGHT_TEXTURE_CHUNK) to round((T.y - 1 + LIGHT_TEXTURE_RANGE) / LIGHT_TEXTURE_CHUNK))
			var/obj/effect/light_texture/chunk = light_textures["[T.z]_[x]_[y]"]
			if(chunk)
				chunks += chunk
	holder.vis_contents = chunks

/datum/controller/subsystem/lighting/proc/drop_light_holder(client/C)
	if(!C.light_holder)
		return
	C.images -= C.light_holder
	C.light_holder.vis_contents.Cut()
	C.light_holder = null
	C.light_holder_chunk = null

/// Each player's image follows where they look: every tick, as it's only a comparison for each player who hasn't moved
SUBSYSTEM_DEF(light_sprites)
	name = "Light Textures"
	wait = 1
	flags = SS_TICKER | SS_NO_INIT
	runlevels = RUNLEVELS_DEFAULT

/datum/controller/subsystem/light_sprites/fire(resumed)
	if(!SSlighting.sprites)
		return
	for(var/client/C as anything in GLOB.clients)
		SSlighting.place_light_holder(C)

// ---- The lighting objects, out of the world while light textures draw

/atom/movable/lighting_object/Initialize(mapload)
	. = ..()
	if(SSlighting.sprites)
		loc = null
		if(SSlighting.sprite_kind == LIGHT_SPRITES_OVERLAYS)
			place_in_chunk()

/// Chunk overlays: offset within its chunk, and the chunk told to wear it again
/atom/movable/lighting_object/proc/place_in_chunk()
	if(!myturf)
		return
	var/kx = round((myturf.x - 1) / LIGHT_TEXTURE_CHUNK)
	var/ky = round((myturf.y - 1) / LIGHT_TEXTURE_CHUNK)
	pixel_x = (myturf.x - 1 - kx * LIGHT_TEXTURE_CHUNK) * world.icon_size
	pixel_y = (myturf.y - 1 - ky * LIGHT_TEXTURE_CHUNK) * world.icon_size
	SSlighting.dirty_chunks[SSlighting.chunk_at(myturf.z, kx, ky)] = TRUE

/atom/movable/lighting_object/Destroy(force)
	if(force && SSlighting.sprites && myturf)
		loc = myturf // tg's checks expect it on its turf
	return ..()

/atom/movable/lighting_object/draw(rr, rg, rb, gr, gg, gb, br, bg, bb, ar, ag, ab, max)
	if(!SSlighting.sprites)
		return ..()
	// What's drawn is the light textures'; this keeps only whether its turf is lit, as tg's draw() works it out
	#if LIGHTING_SOFT_THRESHOLD != 0
	var/set_luminosity = max > LIGHTING_SOFT_THRESHOLD
	#else
	var/set_luminosity = max > 1e-6
	#endif
	luminosity = set_luminosity
	if(myturf)
		myturf.luminosity = set_luminosity
	if(SSlighting.sprite_kind != LIGHT_SPRITES_OVERLAYS)
		return
	// What tg's draw() puts on it, worn by its chunk
	if((rr & gr & br & ar) && (rg + gg + bg + ag + rb + gb + bb + ab == 8))
		icon_state = "transparent"
		color = null
	else if(!set_luminosity)
		icon_state = "dark"
		color = null
	else
		icon_state = null
		color = list(
			rr, rg, rb, 00,
			gr, gg, gb, 00,
			br, bg, bb, 00,
			ar, ag, ab, 00,
			00, 00, 00, 01
		)
	if(myturf)
		SSlighting.dirty_chunks[SSlighting.chunk_at(myturf.z, round((myturf.x - 1) / LIGHT_TEXTURE_CHUNK), round((myturf.y - 1) / LIGHT_TEXTURE_CHUNK))] = TRUE

/turf/lighting_engine_push()
	..()
	if(SSlighting.sprites && lighting_object)
		luminosity = lighting_object.luminosity // a turf made by ChangeTurf() starts at its type's

#undef LIGHT_TEXTURE_CHUNK
#undef LIGHT_TEXTURE_SIDE
#undef LIGHT_TEXTURE_RANGE
#undef LIGHT_TEXTURE_BATCH
#undef LIGHTMAP_DIR
#undef LIGHT_TEXTURE_BUDGET
#undef LIGHT_SPRITES_TEXTURES
#undef LIGHT_SPRITES_OVERLAYS
#undef LIGHT_SPRITES_FINE
#undef LIGHT_TEXTURE_FINE
#undef LIGHT_TEXTURE_FINE_SIDE
