// Spritesheets made by rust_g's iconforge on its own thread, instead of icon.Insert() on the main one (research designs alone
// froze a tick for ~0.4 s at every round start). Insert() only notes what goes in; build_sheet() hands the list to iconforge, which
// writes one PNG strip per sprite size and says where each sprite went. The CSS and the sprites list come out the same shape as
// before, so the windows using them don't change.
// A sheet falls back to the old DM build (code/modules/asset_cache/asset_list.dm) when iconforge can't make it: an /icon made at
// runtime, a moving state, a file that isn't a .dmi or isn't on disk, a rust_g without iconforge, or spritesheets=dm in the world
// params. SSassets builds the build_after_init sheets as background jobs; anything that needs one sooner gets it made on the spot.

#define FORGE_NAME 1
#define FORGE_ICON 2
#define FORGE_STATE 3
#define FORGE_DIR 4
#define FORGE_FRAME 5
#define FORGE_MOVING 6
#define FORGE_TRANSFORMS 7

/// "forge" or "dm", decided on first use
GLOBAL_VAR(spritesheet_mode)
/// Set by SSassets while it builds a build_after_init sheet: the sheet starts a background job instead of waiting for it
GLOBAL_VAR_INIT(spritesheet_async, FALSE)
/// Set by the spritesheet check: build without registering anything, and keep the files made
GLOBAL_VAR_INIT(spritesheet_checking, FALSE)
/// Main thread time spent building spritesheets, ms
GLOBAL_VAR_INIT(spritesheet_main_ms, 0)
/// How many sheets were made each way
GLOBAL_LIST_INIT(spritesheet_counts, list("forge" = 0, "dm" = 0))

/// How spritesheets are built this round: "forge" when rust_g has iconforge, else "dm"
/proc/spritesheet_mode()
	if(GLOB.spritesheet_mode)
		return GLOB.spritesheet_mode
	var/wanted = world.params["spritesheets"] == "dm" ? "dm" : "forge"
	if(wanted == "forge")
		var/version
		try
			version = rustg_get_version()
		catch
			version = null
		if(version)
			log_world("Spritesheets: made by iconforge (rust_g [version])")
		else
			wanted = "dm"
			log_world("Spritesheets: made by DM, this rust_g has no iconforge")
	GLOB.spritesheet_mode = wanted
	return wanted

/// Where iconforge finds the icon files: the folder the game runs from, or forge-root=<path> for a build run from elsewhere
/proc/spritesheet_forge_root()
	var/static/root
	if(isnull(root))
		root = world.params["forge-root"] || ""
	return root

/// TRUE if this .dmi is on disk where iconforge will look (answers kept for the round)
/proc/spritesheet_forge_file_ok(icon_file)
	var/static/list/known = list()
	var/key = "[icon_file]"
	if(isnull(known[key]))
		known[key] = (copytext(key, -4) == ".dmi" && fexists("[spritesheet_forge_root()][key]")) ? 1 : 0
	return known[key]

/// A .dmi's metadata read by rust_g (size, and each state's name and movement flag) as list("size" = "WxH", "states" = names,
/// "still" = list(name = TRUE) for the non-movement states), kept for the round. Null when spritesheets are made by DM or rust_g
/// can't read the file; the procs below ask BYOND then.
/proc/spritesheet_dmi_meta(icon_file)
	var/static/list/meta_by_file = list()
	var/key = "[icon_file]"
	if(!isnull(meta_by_file[key]))
		return meta_by_file[key] || null
	if(spritesheet_mode() != "forge")
		return null
	meta_by_file[key] = FALSE
	if(!spritesheet_forge_file_ok(icon_file))
		return null
	var/list/read = rustg_dmi_read_metadata("[spritesheet_forge_root()][key]")
	if(!islist(read) || !islist(read["states"]))
		return null
	var/list/names = list()
	var/list/still = list()
	for(var/list/state as anything in read["states"])
		names += state["name"]
		if(!state["movement"])
			still[state["name"]] = TRUE
	return meta_by_file[key] = list("size" = "[read["width"]]x[read["height"]]", "states" = names, "still" = still)

/// icon_states() of a file, kept for the round (the sheets ask about the same few hundred files thousands of times)
/proc/spritesheet_icon_states(icon_file)
	var/static/list/states_by_file = list()
	var/key = "[icon_file]"
	. = states_by_file[key]
	if(!.)
		var/list/meta = spritesheet_dmi_meta(icon_file)
		. = states_by_file[key] = meta ? meta["states"] : icon_states(icon_file)

/// A file's icon size as "WxH", kept for the round
/proc/spritesheet_icon_size(icon_file)
	var/static/list/size_by_file = list()
	var/key = "[icon_file]"
	. = size_by_file[key]
	if(!.)
		var/list/meta = spritesheet_dmi_meta(icon_file)
		if(meta)
			. = size_by_file[key] = meta["size"]
		else
			var/icon/I = icon(icon_file)
			. = size_by_file[key] = "[I.Width()]x[I.Height()]"

/// The CSS class for a sprite: its name with anything a class can't hold made "_", and "_" in front when it starts with a digit.
/// A design id like "power control" or "1911ammo" never matched its rule, so its icon was whatever sprite came first in the sheet.
/proc/spritesheet_css_class(sprite_name)
	var/static/list/classes = list()
	var/static/regex/unsafe = regex(@"[^A-Za-z0-9_-]", "g")
	var/key = "[sprite_name]"
	. = classes[key]
	if(!.)
		. = unsafe.Replace(key, "_")
		var/first = text2ascii(.)
		if(first >= 48 && first <= 57)
			. = "_[.]"
		classes[key] = .

/// A colour as #rrggbb: BYOND's Blend() takes names like "yellow", iconforge doesn't
/proc/spritesheet_hex_color(color)
	if(!istext(color) || copytext(color, 1, 2) == "#")
		return color
	var/list/rgb = rgb2num(color)
	return rgb(rgb[1], rgb[2], rgb[3])

/// The transform that scales a sprite to 32x32 if its file isn't 32x32, else null
/proc/spritesheet_scale_to_32(icon_file)
	if(spritesheet_icon_size(icon_file) != "32x32")
		return list(list("type" = RUSTG_ICONFORGE_SCALE, "width" = 32, "height" = 32))

/datum/asset/spritesheet
	/// What Insert() was given, in order: list(name, icon, icon_state, dir, frame, moving, transforms)
	var/list/forge_entries = list()
	/// TRUE while Insert() should do the old DM work (the DM build going through forge_entries)
	var/tmp/dm_inserting = FALSE
	/// The background job making this sheet, while it runs
	var/forge_job
	/// "forge" or "dm" once built
	var/built_by

/// Notes a sprite for the sheet. transforms: iconforge transform lists (RUSTG_ICONFORGE_BLEND_COLOR, _BLEND_ICON), done in order
/// after the icon is cut out of its file; the DM build does the same ones with Blend().
/datum/asset/spritesheet/Insert(sprite_name, icon/I, icon_state="", dir=SOUTH, frame=1, moving=FALSE, list/transforms)
	if(dm_inserting)
		return ..()
	forge_entries += list(list(sprite_name, I, icon_state, dir, frame, moving, transforms))

/datum/asset/spritesheet/register()
	if (!name)
		CRASH("spritesheet [type] cannot register without a name")
	build_sheet()

/// Makes the sheet from forge_entries: iconforge if it can, the old DM way if not
/datum/asset/spritesheet/proc/build_sheet()
	var/start = TICK_USAGE_REAL
	if(spritesheet_mode() == "forge" && forge_can_make())
		if(GLOB.spritesheet_async && !GLOB.spritesheet_checking)
			forge_job = rustg_iconforge_generate_async(forge_dir("a"), name, forge_input(), 0, 0, 1)
			GLOB.spritesheet_main_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
			return
		if(forge_finish(rustg_iconforge_generate(forge_dir("s"), name, forge_input(), 0, 0, 1), "s"))
			GLOB.spritesheet_main_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
			return
	dm_build()
	GLOB.spritesheet_main_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)

/// The old DM build: icon.Insert() per sprite, then what the old register() did with the result
/datum/asset/spritesheet/proc/dm_build()
	sizes = list()
	sprites = list()
	dm_inserting = TRUE
	for(var/list/entry as anything in forge_entries)
		if(length(entry[FORGE_TRANSFORMS]))
			Insert(entry[FORGE_NAME], dm_transformed(entry))
		else
			Insert(entry[FORGE_NAME], entry[FORGE_ICON], entry[FORGE_STATE], entry[FORGE_DIR], entry[FORGE_FRAME], entry[FORGE_MOVING])
	dm_inserting = FALSE
	built_by = "dm"
	GLOB.spritesheet_counts["dm"]++
	ensure_stripped()
	if(GLOB.spritesheet_checking)
		return
	var/res_name = "spritesheet_[name].css"
	var/fname = "data/spritesheets/[world.port]_[res_name]" // the port: another test server in this folder could fdel() it mid-copy
	fdel(fname)
	text2file(generate_css(), fname)
	register_asset(res_name, fcopy_rsc(fname))
	fdel(fname)
	for(var/size_id in sizes)
		var/list/size = sizes[size_id]
		register_asset("[name]_[size_id].png", size[3])

/// The sprite as the old code made it: cut out of its file, then the transforms done with Blend()
/datum/asset/spritesheet/proc/dm_transformed(list/entry)
	var/icon/I = icon(entry[FORGE_ICON], entry[FORGE_STATE], entry[FORGE_DIR], entry[FORGE_FRAME], entry[FORGE_MOVING])
	for(var/list/transform as anything in entry[FORGE_TRANSFORMS])
		switch(transform["type"])
			if(RUSTG_ICONFORGE_BLEND_COLOR)
				I.Blend(transform["color"], transform["blend_mode"])
			if(RUSTG_ICONFORGE_BLEND_ICON)
				var/list/other = transform["icon"]
				I.Blend(icon(other["icon_file"], other["icon_state"], other["dir"], other["frame"]), transform["blend_mode"], transform["x"] || 1, transform["y"] || 1)
			if(RUSTG_ICONFORGE_SCALE)
				I.Scale(transform["width"], transform["height"])
			else
				CRASH("spritesheet [name]: no DM version of iconforge transform [transform["type"]]")
	return I

/// TRUE if iconforge can make every sprite in the sheet
/datum/asset/spritesheet/proc/forge_can_make()
	if(!length(forge_entries))
		return FALSE
	for(var/list/entry as anything in forge_entries)
		if(entry[FORGE_MOVING] || !isfile(entry[FORGE_ICON]) || !spritesheet_forge_file_ok(entry[FORGE_ICON]))
			return FALSE
		for(var/list/transform as anything in entry[FORGE_TRANSFORMS])
			var/list/other = transform["icon"]
			if(other && !spritesheet_forge_file_ok(other["icon_file"]))
				return FALSE
	return TRUE

/// iconforge's "sprites" argument. A name used twice keeps its first sprite, where the old code crashed the whole sheet.
/datum/asset/spritesheet/proc/forge_input()
	var/root = spritesheet_forge_root()
	var/list/sprites_in = list()
	for(var/list/entry as anything in forge_entries)
		var/sprite_name = entry[FORGE_NAME]
		if(sprites_in[sprite_name])
			stack_trace("duplicate sprite \"[sprite_name]\" in sheet [name] ([type])")
			continue
		// DM's icon() finds nothing for a state that's only a movement state (or not there), and Insert() leaves the sprite
		// out; iconforge would draw the movement state, so leave it out here too
		var/list/meta = spritesheet_dmi_meta(entry[FORGE_ICON])
		if(meta && !meta["still"][entry[FORGE_STATE]])
			continue
		// iconforge wants "transform" on every sprite object, the icons inside a blend too, even when it's empty
		var/list/sent = list()
		for(var/list/transform as anything in entry[FORGE_TRANSFORMS])
			var/list/copy = transform.Copy()
			if(copy["color"])
				copy["color"] = spritesheet_hex_color(copy["color"])
			var/list/other = copy["icon"]
			if(other)
				other = other.Copy()
				other["icon_file"] = "[root][other["icon_file"]]"
				if(!other["transform"])
					other["transform"] = list()
				copy["icon"] = other
			sent += list(copy)
		sprites_in[sprite_name] = list("icon_file" = "[root][entry[FORGE_ICON]]", "icon_state" = entry[FORGE_STATE], "dir" = entry[FORGE_DIR], "frame" = entry[FORGE_FRAME], "transform" = sent)
	return json_encode(sprites_in)

/// Where this server's iconforge output goes: kind "a" for background jobs, "s" for sheets made on the spot, so a job nobody waits
/// for any more can't write over files being read
/datum/asset/spritesheet/proc/forge_dir(kind)
	var/static/list/made = list()
	. = "data/spritesheets/forge_[world.port]_[kind]/"
	if(!made[.])
		made[.] = TRUE
		text2file("", "[.].keep") // makes the folder
		fdel("[.].keep")

/// Polls the background job: TRUE once the sheet is built (by iconforge, or on the spot if the job failed)
/datum/asset/spritesheet/proc/forge_poll()
	if(!forge_job)
		return TRUE
	var/result = rustg_iconforge_check(forge_job)
	if(result == RUSTG_JOB_NO_RESULTS_YET)
		return FALSE
	forge_job = null
	var/start = TICK_USAGE_REAL
	var/finished = forge_finish(result, "a")
	GLOB.spritesheet_main_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
	if(!finished)
		build_sheet() // not async now: made on the spot, or with DM
	return TRUE

/// Something wants the sheet before its background job is done: make it now instead
/datum/asset/spritesheet/proc/ensure_built()
	if(!forge_job)
		return
	forge_job = null // the job's files land in the "a" folder and are never read
	build_sheet()

/// Reads iconforge's answer, registers the PNG strips and the CSS. FALSE if it made nothing usable.
/datum/asset/spritesheet/proc/forge_finish(result, kind)
	var/list/answer
	if(istext(result) && copytext(result, 1, 2) == "{")
		answer = json_decode(result)
	if(!islist(answer) || !islist(answer["sprites"]) || !length(answer["sprites"]))
		log_world("Spritesheets: iconforge couldn't make [name], DM makes it: [islist(answer) ? answer["error"] : result]")
		return FALSE
	if(length(answer["error"]))
		log_world("Spritesheets: [name]: [answer["error"]]")
	sizes = list()
	sprites = list()
	var/list/answer_sprites = answer["sprites"]
	for(var/sprite_name in answer_sprites)
		var/list/sprite = answer_sprites[sprite_name]
		var/size_id = sprite["size_id"]
		var/list/size = sizes[size_id]
		if(!size)
			size = sizes[size_id] = list(0, null, null)
		size[1]++
		sprites[sprite_name] = list(size_id, sprite["position"])
	built_by = "forge"
	GLOB.spritesheet_counts["forge"]++
	if(GLOB.spritesheet_checking)
		return TRUE
	var/dir = forge_dir(kind)
	var/res_name = "spritesheet_[name].css"
	var/css_file = "[dir][res_name]"
	fdel(css_file)
	text2file(forge_css(), css_file)
	register_asset(res_name, fcopy_rsc(css_file))
	fdel(css_file)
	for(var/size_id in sizes)
		var/png = "[dir][name]_[size_id].png"
		register_asset("[name]_[size_id].png", fcopy_rsc(png))
		fdel(png)
	return TRUE

/// The CSS for an iconforge sheet: the same classes as generate_css(), sprites side by side in one row per size
/datum/asset/spritesheet/proc/forge_css()
	var/list/out = list()
	for(var/size_id in sizes)
		var/list/size = splittext(size_id, "x")
		out += ".[name][size_id]{display:inline-block;width:[size[1]]px;height:[size[2]]px;background:url('[name]_[size_id].png') no-repeat;}"
	for(var/sprite_id in sprites)
		var/list/sprite = sprites[sprite_id]
		var/list/size = splittext(sprite[1], "x")
		out += ".[name][sprite[1]].[spritesheet_css_class(sprite_id)]{background-position:-[text2num(size[1]) * sprite[2]]px 0px;}"
	return out.Join("\n")

/// The old DM sheet's CSS (asset_list.dm), with the sprites' classes made safe as in forge_css()
/datum/asset/spritesheet/generate_css()
	var/list/out = list()
	for (var/size_id in sizes)
		var/list/size = sizes[size_id]
		var/icon/tiny = size[2]
		out += ".[name][size_id]{display:inline-block;width:[tiny.Width()]px;height:[tiny.Height()]px;background:url('[name]_[size_id].png') no-repeat;}"
	for (var/sprite_id in sprites)
		var/list/sprite = sprites[sprite_id]
		var/size_id = sprite[1]
		var/idx = sprite[2]
		var/list/size = sizes[size_id]
		var/icon/tiny = size[2]
		var/icon/big = size[3]
		var/per_line = big.Width() / tiny.Width()
		var/x = (idx % per_line) * tiny.Width()
		var/y = round(idx / per_line) * tiny.Height()
		out += ".[name][size_id].[spritesheet_css_class(sprite_id)]{background-position:-[x]px -[y]px;}"
	return out.Join("\n")

/// The asset names this sheet registers
/datum/asset/spritesheet/proc/asset_names()
	. = list("spritesheet_[name].css")
	for(var/size_id in sizes)
		. += "[name]_[size_id].png"

/datum/asset/spritesheet/send(client/C)
	ensure_built()
	return ..()

/datum/asset/spritesheet/icon_tag(sprite_name)
	ensure_built()
	var/list/sprite = sprites[sprite_name]
	if (!sprite)
		return null
	return {"<span class="[name][sprite[1]] [spritesheet_css_class(sprite_name)]"></span>"}

/datum/asset/spritesheet/icon_class_name(sprite_name)
	ensure_built()
	var/list/sprite = sprites[sprite_name]
	if (!sprite)
		return null
	return {"[name][sprite[1]] [spritesheet_css_class(sprite_name)]"}

/datum/asset/spritesheet/icon_size_id(sprite_name)
	ensure_built()
	return ..()

// The slow sheets that blended icons in DM, with the blends given to iconforge as transforms instead. These replace the versions
// in code/modules/asset_cache/asset_list_items.dm (same sprites, same names) and end in build_sheet(), not ..(), which would run
// the old versions too.

/datum/asset/spritesheet/research_designs/register()
	for (var/path in subtypesof(/datum/design))
		var/datum/design/D = path
		var/icon_file
		var/icon_state
		var/list/transforms
		if(initial(D.research_icon) && initial(D.research_icon_state)) //If the design has an icon replacement skip the rest
			icon_file = initial(D.research_icon)
			icon_state = initial(D.research_icon_state)
			if(!(icon_state in spritesheet_icon_states(icon_file)))
				warning("design [D] with icon '[icon_file]' missing state '[icon_state]'")
				continue
		else
			var/atom/item = initial(D.build_path)
			if (!ispath(item, /atom))
				// biogenerator outputs to beakers by default
				if (initial(D.build_type) & BIOGENERATOR)
					item = /obj/item/reagent_containers/glass/beaker/large
				else
					continue
			// circuit boards become their resulting machines or computers
			if (ispath(item, /obj/item/circuitboard))
				var/obj/item/circuitboard/C = item
				var/machine = initial(C.build_path)
				if (machine)
					item = machine
			icon_file = initial(item.icon)
			icon_state = initial(item.icon_state)
			var/list/all_states = spritesheet_icon_states(icon_file)
			if(!(icon_state in all_states))
				warning("design [D] with icon '[icon_file]' missing state '[icon_state]'")
				continue
			// computers (and snowflakes) get their screen and keyboard sprites
			if (ispath(item, /obj/machinery/computer) || ispath(item, /obj/machinery/power/solar_control))
				var/obj/machinery/computer/C = item
				for(var/overlay_state in list(initial(C.icon_screen), initial(C.icon_keyboard)))
					if (overlay_state && (overlay_state in all_states))
						LAZYADD(transforms, list(list("type" = RUSTG_ICONFORGE_BLEND_ICON, "icon" = list("icon_file" = icon_file, "icon_state" = overlay_state, "dir" = SOUTH, "frame" = 1), "blend_mode" = ICON_OVERLAY)))
		Insert(initial(D.id), icon_file, icon_state, SOUTH, 1, FALSE, transforms)
	build_sheet()

/datum/asset/spritesheet/crafting/register()
	var/start_time = REALTIMEOFDAY
	init_crafting_ui_data()
	for (var/id in 1 to length(GLOB.crafting_ui_atoms))
		var/atom/item = GLOB.crafting_ui_atoms[id]
		if (!ispath(item, /atom))
			continue // reagents have no sprite, the menu draws an icon font glyph for them
		var/icon_file = initial(item.icon)
		var/icon_state = initial(item.icon_state)
		if (!icon_file || !icon_state || !(icon_state in spritesheet_icon_states(icon_file)))
			continue
		Insert("a[id]", icon_file, icon_state)
	build_sheet()
	log_world("Crafting menu spritesheet: [length(forge_entries)] icons, [(REALTIMEOFDAY - start_time) / 10]s on the main thread")

/datum/asset/spritesheet/vending/register()
	for (var/k in GLOB.vending_products)
		var/atom/item = k
		if (!ispath(item, /atom))
			continue
		var/imgid = replacetext(replacetext("[item]", "/obj/item/", ""), "/", "-")
		var/icon_file = initial(item.icon)
		var/icon_state = initial(item.icon_state)
		if(icon_state in spritesheet_icon_states(icon_file))
			var/c = initial(item.color)
			var/list/transforms
			if (!isnull(c) && c != "#FFFFFF")
				transforms = list(list("type" = RUSTG_ICONFORGE_BLEND_COLOR, "color" = c, "blend_mode" = ICON_MULTIPLY))
			Insert(imgid, icon_file, icon_state, SOUTH, 1, FALSE, transforms)
		else
			// The state comes from its New(): make one and look. The old code named these after the made item ("[item]" of an
			// instance is its name), so the windows, which look sprites up by path, never found them.
			var/atom/made = new item()
			Insert(imgid, made.icon, made.icon_state)
			qdel(made)
	build_sheet()

#undef FORGE_NAME
#undef FORGE_ICON
#undef FORGE_STATE
#undef FORGE_DIR
#undef FORGE_FRAME
#undef FORGE_MOVING
#undef FORGE_TRANSFORMS
