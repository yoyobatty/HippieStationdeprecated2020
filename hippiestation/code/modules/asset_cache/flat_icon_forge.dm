// Flat pictures made by rust_g's iconforge instead of BYOND's icon procs: getFlatIcon() blends an atom's icon and every overlay
// and underlay into one /icon with Blend() and Crop() on the main thread, and icon2base64() then writes it to a savefile to get
// the PNG out. The stat panel's tile list did that for every mob on the listed tile every few seconds, and most of the picture
// time in a round was that (2026-11-11 profile of four of the user's rounds).
//
// flat_forge_sprite() walks the atom the way getFlatIcon(no_anim = TRUE) does and writes down what it would draw as an iconforge
// sprite: the same layers in the same order (underlays, the icon itself and overlays sorted by layer, only the ones on the
// atom's plane or FLOAT_PLANE), each overlay flattened the same way in turn, blended with the blend mode getFlatIcon() uses (the
// parent's, which becomes ICON_OVERLAY once the atom's own icon is in), at the same offsets, on a canvas grown the way its
// Crop()s grow it, then the atom's colour and alpha. iconforge draws it into a PNG and rust_g base64s the file. Anything it
// can't draw the same way (an icon made at runtime, a state facing a way it hasn't got, a colour it can't read) gives null and
// the caller uses getFlatIcon() as before. tools/flat_icon_check compares the two pixel by pixel.

/// "forge" when rust_g has iconforge and flat-icons isn't "dm" in the world params
/proc/flat_forge_mode()
	var/static/mode
	if(isnull(mode))
		mode = (spritesheet_mode() == "forge" && world.params["flat-icons"] != "dm") ? "forge" : "dm"
	return mode

/// How many pictures were drawn each way, and main-thread ms spent on the forged ones (for benches)
GLOBAL_LIST_INIT(flat_forge_counts, list("forge" = 0, "dm" = 0, "ms" = 0))
/// Why the last picture iconforge couldn't draw was left to getFlatIcon() (for tools/flat_icon_check)
GLOBAL_VAR(flat_forge_reason)

/// A state's directions in a .dmi (1, 4 or 8), from rust_g's reading of the file (spritesheet_dmi_meta()). 0 if the file or
/// state can't be read that way.
/proc/flat_forge_state_dirs(icon_file, state)
	var/list/meta = spritesheet_dmi_meta(icon_file)
	if(!meta)
		return 0
	var/list/dirs = meta["dirs"]
	return dirs[state] || 0

/// The .dmi iconforge reads an icon from: its own file, or for an icon made at runtime (a woman's jumpsuit, a zombie's body), a
/// copy written out to data/flat_forge_icons/ the first time it's drawn, kept for the round. Null if it can't be had.
/proc/flat_forge_icon_file(icon_file)
	if(spritesheet_forge_file_ok(icon_file))
		return icon_file
	if(!icon_file || length("[icon_file]")) // a named file that isn't a .dmi on disk
		return null
	var/static/list/written = list()
	. = written[icon_file]
	if(.)
		return
	if(length(written) >= 2000) // runtime icons made over and over: start again rather than fill the disk
		written.Cut()
	var/static/count = 0
	var/path = "data/flat_forge_icons/[++count].dmi"
	if(!fcopy(icon_file, path))
		return null
	written[icon_file] = path
	return path

/// A sprite of nothing, 32x32: getFlatIcon()'s blank
/proc/flat_forge_blank()
	return list("icon_file" = "[spritesheet_forge_root()]icons/effects/effects.dmi", "icon_state" = "nothing", "dir" = SOUTH, "frame" = 1, "transform" = list())

/// An atom's color as the transforms getFlatIcon() applies for it (Blend() multiply for a colour, MapColors() for a matrix), or
/// null when it can't be done the same way. FALSE for no colour.
/proc/flat_forge_color(color)
	if(!color)
		return FALSE
	if(istext(color))
		var/hex = spritesheet_hex_color(color)
		if(!istext(hex) || copytext(hex, 1, 2) != "#")
			return null
		return list(list("type" = RUSTG_ICONFORGE_BLEND_COLOR, "color" = hex, "blend_mode" = ICON_MULTIPLY))
	if(!islist(color))
		return null
	var/list/matrix = color
	var/list/numbers = list()
	for(var/value in matrix)
		if(!isnum(value)) // a matrix of colour strings: getFlatIcon() hands it to MapColors() as it is
			return null
		numbers += value
	// MapColors() with 9, 12, 16 or 20 numbers: rgb rows, rgb rows and a constant row, rgba rows, rgba rows and a constant row
	var/list/names
	switch(length(numbers))
		if(9)
			names = list("rr", "rg", "rb", "gr", "gg", "gb", "br", "bg", "bb")
		if(12)
			names = list("rr", "rg", "rb", "gr", "gg", "gb", "br", "bg", "bb", "r0", "g0", "b0")
		if(16)
			names = list("rr", "rg", "rb", "ra", "gr", "gg", "gb", "ga", "br", "bg", "bb", "ba", "ar", "ag", "ab", "aa")
		if(20)
			names = list("rr", "rg", "rb", "ra", "gr", "gg", "gb", "ga", "br", "bg", "bb", "ba", "ar", "ag", "ab", "aa", "r0", "g0", "b0", "a0")
		else
			return null
	var/list/transform = list("type" = RUSTG_ICONFORGE_MAP_COLORS)
	for(var/i in 1 to length(names))
		transform[names[i]] = numbers[i]
	return list(transform)

/// What getFlatIcon(A, defdir, deficon, defstate, defblend, start, no_anim = TRUE) would draw, as an iconforge sprite; "" when it
/// draws nothing at all, and null when iconforge can't draw it the same way. `size` gets the picture's width and height.
/proc/flat_forge_sprite(image/A, defdir, deficon, defstate, defblend, start = TRUE, list/size)
	if(!A || A.alpha <= 0)
		size.Cut()
		size.Add(32, 32)
		return flat_forge_blank()

	if(start)
		if(!defdir)
			defdir = A.dir
		if(!deficon)
			deficon = A.icon
		if(!defstate)
			defstate = A.icon_state
		if(!defblend)
			defblend = A.blend_mode

	var/curicon = A.icon || deficon
	var/curstate = A.icon_state || defstate
	var/noIcon = !curicon
	if(!noIcon)
		var/forge_file = flat_forge_icon_file(curicon)
		if(!forge_file)
			GLOB.flat_forge_reason = "icon not a .dmi on disk: [curicon] (state [curstate], layer [A.layer], plane [A.plane], [A.type])"
			return null // not a .dmi, or one that can't be written out
		curicon = forge_file
		var/list/curstates = spritesheet_icon_states(curicon)
		if(!(curstate in curstates))
			if("" in curstates)
				curstate = ""
			else
				noIcon = TRUE

	var/curdir = (!A.dir || A.dir == SOUTH) ? defdir : A.dir
	var/base_icon_dir = curdir
	if(!noIcon)
		var/state_dirs = flat_forge_state_dirs(curicon, curstate)
		if(!state_dirs)
			GLOB.flat_forge_reason = "no directions read for [curicon] [curstate]"
			return null
		if(curdir != SOUTH && state_dirs == 1)
			base_icon_dir = SOUTH // nothing facing another way
		else if((base_icon_dir in GLOB.diagonals) && state_dirs < 8)
			GLOB.flat_forge_reason = "diagonal [base_icon_dir] of a [state_dirs]-way state"
			return null // BYOND's answer for a diagonal of a four-way state isn't one iconforge gives

	var/curblend = A.blend_mode || defblend
	var/root = spritesheet_forge_root()

	if(!length(A.overlays) && !length(A.underlays))
		if(noIcon)
			return "" // getFlatIcon() returns nothing at all here
		var/list/sprite = list("icon_file" = "[root][curicon]", "icon_state" = curstate, "dir" = base_icon_dir, "frame" = 1, "transform" = list())
		var/list/transform = sprite["transform"]
		if(A.alpha < 255)
			transform += list(list("type" = RUSTG_ICONFORGE_BLEND_COLOR, "color" = rgb(255, 255, 255, A.alpha), "blend_mode" = ICON_MULTIPLY))
		var/list/color = flat_forge_color(A.color)
		if(isnull(color))
			GLOB.flat_forge_reason = "colour [json_encode(A.color)]"
			return null
		if(color)
			transform += color
		var/list/dims = splittext(spritesheet_icon_size(curicon), "x")
		size.Cut()
		size.Add(text2num(dims[1]), text2num(dims[2]))
		return sprite

	// Layers in getFlatIcon()'s order: the atom's own icon, then underlays and overlays put in by layer
	var/list/layers = list()
	var/static/self_marker = "self"
	if(!noIcon)
		layers[self_marker] = A.layer
	for(var/process_set in 0 to 1)
		var/list/process = process_set ? A.overlays : A.underlays
		for(var/i in 1 to length(process))
			var/image/current = process[i]
			if(!current)
				continue
			if(current.plane != FLOAT_PLANE && current.plane != A.plane)
				continue
			var/current_layer = current.layer
			if(current_layer < 0)
				if(current_layer <= -1000)
					size.Cut()
					size.Add(32, 32)
					return flat_forge_blank() // getFlatIcon() gives up there and returns its blank
				current_layer = process_set + A.layer + current_layer / 1000
			for(var/p in 1 to length(layers))
				var/cmp = layers[p]
				if(current_layer < layers[cmp])
					layers.Insert(p, current)
					break
			layers[current] = current_layer

	// Each layer flattened and placed where getFlatIcon() puts it; the canvas grows to fit, as its Crop()s grow it
	var/list/placed = list() // sprite, x offset, y offset, blend mode
	var/x1 = 1
	var/x2 = 32
	var/y1 = 1
	var/y2 = 32
	var/list/child_size = list()
	for(var/V in layers)
		var/list/add
		var/add_width
		var/add_height
		var/pixel_x = 0
		var/pixel_y = 0
		if(V == self_marker)
			curblend = BLEND_OVERLAY
			add = list("icon_file" = "[root][curicon]", "icon_state" = curstate, "dir" = base_icon_dir, "frame" = 1, "transform" = list())
			var/list/dims = splittext(spritesheet_icon_size(curicon), "x")
			add_width = text2num(dims[1])
			add_height = text2num(dims[2])
		else
			var/image/I = V
			if(I.alpha == 0)
				continue
			pixel_x = I.pixel_x
			pixel_y = I.pixel_y
			add = flat_forge_sprite(I, curdir, curicon, curstate, curblend, FALSE, child_size)
			if(add == "") // nothing to draw: getFlatIcon() skips it
				continue
			if(isnull(add))
				return null
			add_width = child_size[1]
			add_height = child_size[2]
		x1 = min(x1, pixel_x + 1)
		x2 = max(x2, pixel_x + add_width)
		y1 = min(y1, pixel_y + 1)
		y2 = max(y2, pixel_y + add_height)
		placed += list(list(add, pixel_x, pixel_y, blendMode2iconMode(curblend)))

	// A canvas of nothing the final size, every layer blended onto it at its place in that canvas
	var/width = x2 - x1 + 1
	var/height = y2 - y1 + 1
	var/list/canvas = flat_forge_blank()
	var/list/transform = canvas["transform"]
	if(width != 32 || height != 32)
		transform += list(list("type" = RUSTG_ICONFORGE_SCALE, "width" = width, "height" = height))
	for(var/list/layer as anything in placed)
		transform += list(list("type" = RUSTG_ICONFORGE_BLEND_ICON, "icon" = layer[1], "blend_mode" = layer[4], "x" = layer[2] + 2 - x1, "y" = layer[3] + 2 - y1))
	var/list/color = flat_forge_color(A.color)
	if(isnull(color))
		GLOB.flat_forge_reason = "colour [json_encode(A.color)]"
		return null
	if(color)
		transform += color
	if(A.alpha < 255)
		transform += list(list("type" = RUSTG_ICONFORGE_BLEND_COLOR, "color" = rgb(255, 255, 255, A.alpha), "blend_mode" = ICON_MULTIPLY))
	size.Cut()
	size.Add(width, height)
	return canvas

/// getFlatIcon(A, no_anim = TRUE) drawn by iconforge into a PNG at `path`: TRUE, "" for no picture, or null if it can't be drawn
/// this way (the caller does it the old way)
/proc/flat_forge_png(atom/A, path, defdir)
	if(flat_forge_mode() != "forge")
		return null
	var/list/size = list()
	var/list/sprite = flat_forge_sprite(A, defdir, size = size)
	if(sprite == "")
		return ""
	if(!sprite)
		return null
	var/list/result = rustg_iconforge_generate_headless(path, json_encode(list("flat" = sprite)), "1")
	if(!islist(result) || result["error"] || !result["file_path"])
		return null
	return TRUE

/// getFlatIcon(A, no_anim = TRUE) as base64 PNG data, drawn by iconforge: "" for no picture, null if it can't be drawn this way
/// (the caller does it the old way)
/proc/flat_forge_base64(atom/A, defdir)
	var/start = TICK_USAGE_REAL
	var/static/count = 0
	var/path = "data/flat_forge_[++count % 64].png"
	. = flat_forge_png(A, path, defdir)
	if(. != TRUE)
		return
	. = rustg_hash_file(RUSTG_HASH_BASE64, path)
	if(!istext(.) || !length(.))
		return null
	GLOB.flat_forge_counts["forge"]++
	GLOB.flat_forge_counts["ms"] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
