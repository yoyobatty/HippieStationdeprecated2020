// Flat icon check (run.sh): mobs flattened both ways, getFlatIcon(no_anim = TRUE) and iconforge (flat_icon_forge.dm), with both
// pictures written to data/flat_icon_check/ for compare.py to check pixel by pixel, and how long each took. Humans in every
// job's clothes facing each way, every kind of simple mob that can be made, cyborgs and the mobs already on the map. Not part of
// the game.

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("flat-icon-check" in world.params)
		sleep_offline_after_initializations = FALSE // nobody connects to this, so the world has to keep ticking
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(flat_icon_check_run))
	return ..()

/proc/fic_log(text)
	text2file(text, "data/flat_icon_check/results.txt")

/proc/flat_icon_check_run()
	UNTIL(Master.current_runlevel)
	sleep(5 SECONDS)
	var/turf/spot = locate(world.maxx / 2, world.maxy / 2, 2)
	var/list/subjects = list()
	// Humans dressed for every job, each facing every way
	for(var/datum/job/J as anything in SSjob.occupations)
		if(istype(J, /datum/job/ai) || istype(J, /datum/job/cyborg))
			continue // no human preview for them (equip() CRASHes on one); the real silicons are flattened below
		var/mob/living/carbon/human/H = new(spot)
		J.equip(H, TRUE, FALSE)
		for(var/D in GLOB.cardinals)
			subjects += list(list(H, D))
		CHECK_TICK
	// Every simple mob that can be made, facing south and east
	var/made = 0
	for(var/path in typesof(/mob/living/simple_animal))
		if(made >= 400)
			break
		var/mob/living/simple_animal/M
		try
			M = new path(spot)
		catch
			continue
		if(QDELETED(M))
			continue
		made++
		subjects += list(list(M, SOUTH), list(M, EAST))
		CHECK_TICK
	for(var/path in list(/mob/living/silicon/robot, /mob/living/silicon/ai, /mob/living/carbon/monkey, /mob/living/carbon/alien/humanoid/hunter))
		var/mob/M = new path(spot)
		subjects += list(list(M, SOUTH))
	// The mobs already on the map, as they are
	for(var/mob/living/M as anything in GLOB.mob_living_list)
		if(M.z && M.z != spot.z)
			subjects += list(list(M, M.dir))
	var/list/rows = list()
	var/dm_ms = 0
	var/forge_ms = 0
	var/n = 0
	for(var/list/subject as anything in subjects)
		var/mob/M = subject[1]
		if(QDELETED(M))
			continue
		M.setDir(subject[2])
		n++
		var/start = TICK_USAGE_REAL
		var/icon/I = getFlatIcon(M, no_anim = TRUE)
		var/b64 = I ? icon2base64(I) : ""
		var/this_dm = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
		if(I)
			fcopy(I, "data/flat_icon_check/dm/[n].png")
		start = TICK_USAGE_REAL
		GLOB.flat_forge_reason = null
		var/forged = flat_forge_png(M, "data/flat_icon_check/forge/[n].png")
		var/forged_b64 = forged == TRUE ? rustg_hash_file(RUSTG_HASH_BASE64, "data/flat_icon_check/forge/[n].png") : ""
		var/this_forge = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
		if(forged == TRUE)
			dm_ms += this_dm
			forge_ms += this_forge
		rows += list(list("n" = n, "type" = "[M.type]", "dir" = subject[2], "dm" = I ? 1 : 0, "w" = I ? I.Width() : 0, "h" = I ? I.Height() : 0, "forge" = isnull(forged) ? "fallback" : (forged == TRUE ? "drawn" : "empty"), "why" = GLOB.flat_forge_reason, "dm_ms" = this_dm, "forge_ms" = this_forge, "b64" = length(b64), "forged_b64" = length(forged_b64)))
		CHECK_TICK
	text2file(json_encode(rows), "data/flat_icon_check/rows.json")
	// Where the time goes, on one dressed human and one simple mob, warm
	for(var/list/subject in list(subjects[1], subjects[length(subjects) - 1]))
		var/mob/M = subject[1]
		if(QDELETED(M))
			continue
		var/list/phase = list("walk" = 0, "json" = 0, "forge" = 0, "base64" = 0, "dm" = 0)
		for(var/k in 1 to 20)
			var/t = TICK_USAGE_REAL
			var/list/size = list()
			var/list/sprite = flat_forge_sprite(M, size = size)
			phase["walk"] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - t)
			t = TICK_USAGE_REAL
			var/text = json_encode(list("flat" = sprite))
			phase["json"] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - t)
			t = TICK_USAGE_REAL
			rustg_iconforge_generate_headless("data/flat_icon_check/phase.png", text, "1")
			phase["forge"] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - t)
			t = TICK_USAGE_REAL
			rustg_hash_file(RUSTG_HASH_BASE64, "data/flat_icon_check/phase.png")
			phase["base64"] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - t)
			t = TICK_USAGE_REAL
			var/icon/I = getFlatIcon(M, no_anim = TRUE)
			icon2base64(I)
			phase["dm"] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - t)
		var/list/parts = list()
		for(var/key in phase)
			parts += "[key] [round(phase[key] / 20, 0.01)]"
		fic_log("per picture, [M.type]: [jointext(parts, ", ")] ms (json [length(json_encode(list("flat" = flat_forge_sprite(M, size = list()))))] chars)")
	fic_log("[n] pictures; where iconforge drew them, DM [round(dm_ms, 0.1)] ms against iconforge [round(forge_ms, 0.1)] ms (each with its base64)")
	fic_log("done")
