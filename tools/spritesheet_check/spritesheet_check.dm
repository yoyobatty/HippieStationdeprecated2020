// Spritesheet check (run.sh): every spritesheet built both ways, the old DM way and by iconforge, on the real station, with the
// sheets and where each sprite sits written to data/spritesheet_check/ for compare.py to check pixel by pixel. Also how long the
// main thread spent on each, and what the round's own background build cost it. Not part of the game.

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("spritesheet-check" in world.params)
		sleep_offline_after_initializations = FALSE // nobody connects to this, so the world has to keep ticking
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(spritesheet_check_run))
	return ..()

/proc/ssc_log(text)
	text2file(text, "data/spritesheet_check/results.txt")

/proc/spritesheet_check_run()
	UNTIL(Master.current_runlevel)
	// let SSassets finish its own background build first, and note what it cost the main thread
	var/wait_until = world.time + 120 SECONDS
	UNTIL(!SSassets.can_fire || world.time > wait_until)
	ssc_log("Round's own build: [GLOB.spritesheet_counts["forge"]] by iconforge, [GLOB.spritesheet_counts["dm"]] by DM, [round(GLOB.spritesheet_main_ms, 0.1)] ms on the main thread[SSassets.can_fire ? " (NOT FINISHED)" : ""]")
	for(var/type in SSassets.build_ms)
		ssc_log("  after init, [type]: [round(SSassets.build_ms[type], 0.1)] ms in one fire")
	GLOB.spritesheet_checking = TRUE
	var/total_dm = 0
	var/total_forge = 0
	for(var/type in typesof(/datum/asset/spritesheet))
		var/datum/asset/spritesheet/proto = type
		if(type == initial(proto._abstract))
			continue
		var/list/times = list()
		var/list/built = list()
		for(var/mode in list("dm", "forge"))
			GLOB.spritesheet_mode = mode
			var/start = TICK_USAGE_REAL
			var/datum/asset/spritesheet/sheet = new type
			var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
			times[mode] = ms
			built[mode] = sheet.built_by
			ssc_dump(sheet, mode)
		total_dm += times["dm"]
		total_forge += times["forge"]
		ssc_log("[type]: DM [round(times["dm"], 0.1)] ms, iconforge on the spot [round(times["forge"], 0.1)] ms (built by [built["dm"]] / [built["forge"]])")
	ssc_log("All sheets: DM [round(total_dm, 0.1)] ms, iconforge on the spot [round(total_forge, 0.1)] ms")
	ssc_log("done")
	Master.Shutdown()
	qdel(world)

/// Writes the sheet's images and a JSON of where each sprite is
/proc/ssc_dump(datum/asset/spritesheet/sheet, mode)
	var/dir = "data/spritesheet_check/[mode]/"
	var/list/where = list()
	for(var/sprite_name in sheet.sprites)
		var/list/sprite = sheet.sprites[sprite_name]
		var/size_id = sprite[1]
		var/idx = sprite[2]
		var/list/wh = splittext(size_id, "x")
		var/w = text2num(wh[1])
		var/h = text2num(wh[2])
		if(sheet.built_by == "dm")
			var/list/size = sheet.sizes[size_id]
			var/icon/tiny = size[2]
			var/icon/big = size[3]
			var/per_line = big.Width() / tiny.Width()
			where[sprite_name] = list(size_id, (idx % per_line) * tiny.Width(), round(idx / per_line) * tiny.Height(), w, h)
		else
			where[sprite_name] = list(size_id, idx * w, 0, w, h)
	for(var/size_id in sheet.sizes)
		var/out = "[dir][sheet.name]_[size_id].png"
		fdel(out)
		if(sheet.built_by == "dm")
			var/list/size = sheet.sizes[size_id]
			fcopy(size[3], out)
		else
			fcopy("[sheet.forge_dir("s")][sheet.name]_[size_id].png", out)
	if(mode == "forge")
		var/input_out = "[dir][sheet.name]_input.json"
		fdel(input_out)
		text2file(sheet.forge_input(), input_out)
	var/json_out = "[dir][sheet.name].json"
	fdel(json_out)
	text2file(json_encode(list("type" = "[sheet.type]", "built_by" = sheet.built_by, "sprites" = where)), json_out)
