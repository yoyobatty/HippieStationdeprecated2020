// The native map parser (tools/map_engine, hippie_map.dll). It reads a .dmm the way code/modules/mapping/reader.dm does and
// gives back what the parse makes: the key length, the bounds, each model's text, each model split into members and
// fields, and the coordinate blocks' lines. DM still turns paths into types (text2path), reads the values it hands back as
// text (parse_constant) and applies text macros, so the parsed_map comes out the same. tools/map_engine/check.dm checks
// that on every map in _maps.
//
// Without the library (or with map-engine=off in the world params) the DM parser in reader.dm does it all as before.
// map-lib=<name> in the world params loads another build of it (hippie_map_test.dll, say).

#define MAP_ENGINE_VERSION "1"

/// The library to call, or FALSE when there isn't a usable one
/proc/map_engine_lib()
	var/static/lib
	if(!isnull(lib))
		return lib
	lib = FALSE
	var/list/params = world.params
	if(params["map-engine"] == "off")
		return lib
	var/name = params["map-lib"] || "hippie_map"
	var/file_name = world.system_type == UNIX ? "lib[name].so" : "[name].dll"
	if(!fexists(file_name))
		return lib
	var/candidate = world.system_type == UNIX ? "./[file_name]" : name
	var/version = call_ext(candidate, "map_engine_version")()
	if(version != MAP_ENGINE_VERSION)
		log_world("Map parser [file_name] is version [version], not [MAP_ENGINE_VERSION]: maps are parsed in DM")
		return lib
	lib = candidate
	return lib

/// TRUE parses every map in DM (View Variables, or tools/map_engine/check.dm for its before run)
GLOBAL_VAR_INIT(map_engine_off, FALSE)

/// Each model's members and fields as the library split them, by model key. Null for a map DM parsed.
/datum/parsed_map/var/list/native_split

/datum/parsed_map/New(tfile, x_lower = -INFINITY, x_upper = INFINITY, y_lower = -INFINITY, y_upper=INFINITY, measureOnly=FALSE)
	var/lib = isfile(tfile) && !GLOB.map_engine_off && map_engine_lib()
	if(!lib)
		return ..()
	var/path = "[tfile]"
	if(!fexists(path))
		return ..()
	var/result = call_ext(lib, "map_parse")(path, measureOnly ? "1" : "0", \
		x_lower == -INFINITY ? "" : "[x_lower]", x_upper == INFINITY ? "" : "[x_upper]", \
		y_lower == -INFINITY ? "" : "[y_lower]", y_upper == INFINITY ? "" : "[y_upper]")
	var/list/data = json_decode(result)
	if(!islist(data) || data["error"])
		// A map DM would choke on too: let DM parse it, and fail the way it always has
		return ..()

	original_path = path
	key_len = data["key_len"]
	bounds = parsed_bounds = data["bounds"]
	if(measureOnly)
		return

	var/list/split = list()
	native_split = split
	var/list/split_models = data["split"]
	var/index = 0
	for(var/list/model as anything in data["models"])
		var/key = model[1]
		grid_models[key] = model[2]
		split[key] = split_models[++index]

	for(var/list/set_data as anything in data["sets"])
		var/datum/grid_set/gridSet = new
		gridSet.xcrd = set_data[1]
		gridSet.ycrd = set_data[2]
		gridSet.zcrd = set_data[3]
		gridSet.gridLines = set_data[4]
		gridSets += gridSet

/datum/parsed_map/build_cache(no_changeturf, bad_paths=null)
	if(!native_split)
		return ..()
	if(modelCache && !bad_paths)
		return modelCache
	. = modelCache = list()
	var/list/split = native_split
	for(var/model_key in grid_models)
		var/list/members = list()
		var/list/members_attributes = list()
		for(var/list/member as anything in split[model_key])
			var/path_text = member[1]
			var/atom_def = text2path(path_text)
			if(!ispath(atom_def, /atom)) // Skip the item if the path does not exist.  Fix your crap, mappers!
				if(bad_paths)
					LAZYOR(bad_paths[path_text], model_key)
				continue
			members.Add(atom_def)

			var/list/fields = list()
			var/list/raw_fields = member[2]
			if(length(raw_fields))
				for(var/list/field as anything in raw_fields)
					var/name = field[1]
					if(length(field) == 1)
						fields += list(name)
						continue
					switch(field[2])
						if(1, 2) // a whole number, or the inside of "text"
							fields[name] = field[3]
						else // anything else, read as reader.dm reads it
							fields[name] = parse_constant(field[3])
				if(!trim(fields[fields.len]))
					--fields.len
				for(var/I in fields)
					var/value = fields[I]
					if(istext(value))
						fields[I] = apply_text_macros(value)
			members_attributes[++members_attributes.len] = fields

		// The same check as reader.dm's: a plain world.turf and world.area tile needn't be built when no_changeturf is set
		if(no_changeturf \
			&& !(.[SPACE_KEY]) \
			&& members.len == 2 \
			&& members_attributes.len == 2 \
			&& length(members_attributes[1]) == 0 \
			&& length(members_attributes[2]) == 0 \
			&& (world.area in members) \
			&& (world.turf in members))

			.[SPACE_KEY] = model_key
			continue

		.[model_key] = list(members, members_attributes)
		CHECK_TICK
