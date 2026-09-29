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

/datum/controller/subsystem/assets/Initialize(timeofday)
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

/// hippie -- builds one build_after_init asset per fire (each takes up to half a second and can't be split), then adds its
/// files to the preload and sends them to anyone already connected, as if it had been built during init
/datum/controller/subsystem/assets/fire(resumed)
	if (!length(build_queue))
		can_fire = FALSE
		return
	var/type = build_queue[build_queue.len]
	build_queue.len--
	if (GLOB.asset_datums[type]) // something needed it first, and built it then
		return
	var/first_new = length(cache) + 1
	get_asset_datum(type)
	var/list/new_files = list()
	for (var/i in first_new to length(cache))
		var/asset_name = cache[i]
		new_files[asset_name] = cache[asset_name]
		preload[asset_name] = cache[asset_name]
	if (length(new_files))
		for (var/client/C in GLOB.clients)
			addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(getFilesSlow), C, new_files, FALSE), 10)
