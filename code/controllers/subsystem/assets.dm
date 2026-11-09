SUBSYSTEM_DEF(assets)
	name = "Assets"
	init_order = INIT_ORDER_ASSETS
	flags = SS_BACKGROUND // hippie -- fires only to build the build_after_init assets, then stops
	wait = 1
	runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT
	var/list/cache = list()
	var/list/preload = list()
	/// hippie -- asset types with build_after_init, still to be built by fire()
	var/list/build_queue = list()
	/// hippie -- spritesheets iconforge is making in the background (hippiestation/code/modules/asset_cache/spritesheet_forge.dm)
	var/list/forging = list()
	/// hippie -- main thread ms each build_after_init asset took in fire(), by type
	var/list/build_ms = list()

/datum/controller/subsystem/assets/Initialize(timeofday)
	// hippie start -- a Bot Gym never has a client, so nothing is sent: build nothing ahead (1.35 s of every gym server's boot,
	// 2026-11-09). Anything that asks for an asset still gets it built then, by get_asset_datum().
	if(BOT_GYM_PARAMETER in world.params)
		can_fire = FALSE
		return ..()
	// hippie end
	for(var/type in typesof(/datum/asset))
		var/datum/asset/A = type
		if (type != initial(A._abstract))
			if (initial(A.build_after_init))
				build_queue += type
			else
				get_asset_datum(type)

	preload = cache.Copy() //don't preload assets generated during the round

	for(var/client/C in GLOB.clients)
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(getFilesSlow), C, preload, FALSE), 10)
	if (!length(build_queue))
		can_fire = FALSE
	..()

/// hippie -- builds one build_after_init asset per fire, then adds its files to the preload and sends them to anyone already
/// connected, as if it had been built during init. A spritesheet iconforge can make starts as a background job here and its files
/// go out once the job is done (checked every fire); the rest are built on the spot, up to half a second each.
/datum/controller/subsystem/assets/fire(resumed)
	for (var/datum/asset/spritesheet/sheet as anything in forging.Copy())
		if (sheet.forge_poll())
			forging -= sheet
			preload_new(sheet.asset_names())
	if (!length(build_queue))
		if (!length(forging))
			can_fire = FALSE
			log_world("Spritesheets: [GLOB.spritesheet_counts["forge"]] made by iconforge, [GLOB.spritesheet_counts["dm"]] by DM, [round(GLOB.spritesheet_main_ms, 0.1)] ms on the main thread")
			if (GLOB.spritesheet_counts["forge"])
				rustg_iconforge_cleanup()
		return
	var/type = build_queue[build_queue.len]
	build_queue.len--
	if (GLOB.asset_datums[type]) // something needed it first, and built it then
		return
	var/first_new = length(cache) + 1
	var/start = TICK_USAGE_REAL
	GLOB.spritesheet_async = TRUE
	get_asset_datum(type)
	GLOB.spritesheet_async = FALSE
	build_ms[type] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
	var/datum/asset/spritesheet/sheet = GLOB.asset_datums[type]
	if (istype(sheet) && sheet.forge_job)
		forging += sheet
		return
	var/list/names = list()
	for (var/i in first_new to length(cache))
		names += cache[i]
	preload_new(names)

/// hippie -- adds these assets to the preload and sends them to anyone already connected
/datum/controller/subsystem/assets/proc/preload_new(list/asset_names)
	var/list/new_files = list()
	for (var/asset_name in asset_names)
		if (cache[asset_name])
			new_files[asset_name] = cache[asset_name]
			preload[asset_name] = cache[asset_name]
	if (length(new_files))
		for (var/client/C in GLOB.clients)
			addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(getFilesSlow), C, new_files, FALSE), 10)
