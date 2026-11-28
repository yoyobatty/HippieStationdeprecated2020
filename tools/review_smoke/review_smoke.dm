// Review smoke tests, the server side (tools/review_smoke/run.sh drives it; review_smoke.py has the checks). Only in the tool's own
// build (review_smoke.mdme: hippiestation.dme + this file), never in hippiestation.dme. Not part of the game.
//
// What it does, with world param review-smoke=1:
//  - takes commands as world/Topic packets "review_smoke=<cmd>&key=<review-smoke-key>&..." from this machine only, answering text
//    (JSON for status): status, token, admin, disassociate, deactivate, alert, sprites, budget, lights, objects, spawn_check, job.
//    A command that may sleep runs as a job: the answer is "pending:<id>" until "job&id=<id>" has its result.
//  - calls dashboard_alert() and dashboard_revoke() before SSdashboard has initialized, and notes any runtime (early_calls).
//  - keeps every message_admins() text sent after startup (admin_msgs, through SSchat.queue()), as headless no admin sees them.
//  - review-start-round=1: starts the round (extended) as soon as the lobby lets it.
//  - review-lobby-crash=powernets|ruins|atom|maploader|body|atoms_off: a runtime part way through the lobby build. powernets: SSmachines'
//    setup_template_powernets() (a stage, after the atoms are initialized and many sleeps); ruins: seed_startup_ruins() (the
//    maps still loading); atom: the first atom initialized on Lavaland's level (one bad atom, as a broken ruin object would be);
//    maploader: the map loader's instance_atom() while it loads Lavaland (between SSatoms.map_loader_begin() and _stop());
//    body: the build's own code (a datum that isn't an atom put in lobby_build_pending, which the gathering loop reads);
//    atoms_off: no runtime, SSatoms left at map_loader_begin() as a map load stopped part way leaves it.
// Writes data/review_smoke/<port>/ready.txt once the MC has initialized.

GLOBAL_REAL(review_smoke, /datum/review_smoke)

/datum/review_smoke
	var/key
	var/dir
	/// review-lobby-crash
	var/crash_at
	var/crashed = FALSE
	/// What dashboard_alert() and co. did when called before SSdashboard was up: "when: ok" or "when: runtime ..."
	var/list/early_calls = list()
	/// Every message_admins() text
	var/list/admin_msgs = list()
	var/next_job = 0
	var/list/jobs = list()
	/// SSatoms.initialized when the lobby build finished or failed, and the build's world.time then
	var/atoms_state_after_build
	var/build_ended_at
	var/round_started_at

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if(("review-smoke" in world.params) && !global.review_smoke)
		global.review_smoke = new /datum/review_smoke
		global.review_smoke.key = world.params["review-smoke-key"]
		global.review_smoke.crash_at = world.params["review-lobby-crash"]
		global.review_smoke.dir = "data/review_smoke/[world.port]/"
		fdel(global.review_smoke.dir)
		sleep_offline_after_initializations = FALSE
		global.review_smoke.early("before the MC's Initialize")
		INVOKE_ASYNC(global.review_smoke, TYPE_PROC_REF(/datum/review_smoke, boot))
	return ..()

/datum/controller/subsystem/dashboard/Initialize(start_timeofday)
	global.review_smoke?.early("in SSdashboard's Initialize, before it starts")
	. = ..()
	global.review_smoke?.early("after SSdashboard's Initialize ([status])")

/// dashboard_alert() and dashboard_revoke() as early callers make them (a death or admin alert during startup)
/datum/review_smoke/proc/early(when)
	try
		dashboard_alert("review", "review_smoke early alert: [when]")
		dashboard_revoke("review_smoke_nobody")
		early_calls += "[when]: ok (initialized [SSdashboard?.initialized], can_fire [SSdashboard?.can_fire])"
	catch(var/exception/E)
		early_calls += "[when]: runtime [E.name] ([E.file]:[E.line])"

// message_admins() is to_chat(GLOB.admins, ...), which after startup goes through SSchat.queue() (a global proc can't be overridden)
/datum/controller/subsystem/chat/queue(target, message, handle_whitespace = TRUE, confidential = FALSE)
	if(global.review_smoke && target == GLOB.admins)
		global.review_smoke.admin_msgs += "[message]"
	return ..()

/datum/review_smoke/proc/boot()
	UNTIL(Master.current_runlevel)
	CONFIG_SET(number/bot_crew_target, 0)
	if(world.params["review-start-round"])
		GLOB.master_mode = "extended"
		CONFIG_SET(flag/allow_random_events, FALSE)
		SSticker.start_immediately = TRUE
	text2file("ready [world.port]", "[dir]ready.txt")
	log_world("REVIEW_SMOKE: ready on port [world.port]")
	if(world.params["review-start-round"])
		UNTIL(SSticker.current_state >= GAME_STATE_PLAYING)
		round_started_at = world.time
		log_world("REVIEW_SMOKE: round started")

/world/Topic(T, addr, master, key)
	if(global.review_smoke && findtext(T, "review_smoke=") && findtext(T, "review_smoke=") <= 2)
		return global.review_smoke.topic(T, addr)
	return ..()

/datum/review_smoke/proc/topic(T, addr)
	if(addr && !findtext(addr, "127.0.0.1"))
		return "error: this machine only"
	var/list/input = params2list(T)
	if(!key || input["key"] != key)
		return "error: bad key"
	var/cmd = input["review_smoke"]
	if(cmd == "job")
		var/id = input["id"]
		if(!(id in jobs))
			return "error: no job [id]"
		return isnull(jobs[id]) ? "pending:[id]" : jobs[id]
	var/id = "[++next_job]"
	jobs[id] = null
	INVOKE_ASYNC(src, PROC_REF(run_job), id, cmd, input)
	return isnull(jobs[id]) ? "pending:[id]" : jobs[id]

/datum/review_smoke/proc/run_job(id, cmd, list/input)
	var/answer
	try
		answer = run_command(cmd, input)
	catch(var/exception/E)
		answer = "error: runtime [E.name] ([E.file]:[E.line])"
	jobs[id] = isnull(answer) ? "" : "[answer]"

/datum/review_smoke/proc/run_command(cmd, list/input)
	switch(cmd)
		if("status")
			return json_encode(status())
		if("token")
			return call_ext(DASHBOARD_LIB, "dashboard_token")(input["name"], input["secs"] || "3600")
		if("admin")
			return make_admin(input["name"], input["owner"] == "1")
		if("disassociate")
			var/datum/admins/D = GLOB.admin_datums[input["name"]] || GLOB.deadmins[input["name"]]
			if(!D)
				return "error: no admin datum"
			D.disassociate()
			return "ok: owner now [D.owner || "none"]"
		if("deactivate")
			var/datum/admins/D = GLOB.admin_datums[input["name"]]
			if(!D)
				return "error: no admin datum"
			D.deactivate()
			return "ok: deadmined [D.deadmined]"
		if("alert")
			dashboard_alert("review", input["text"])
			return "ok"
		if("sprites")
			var/result = SSlighting.set_sprites(text2num(input["kind"]))
			return "ok: [isnull(result) ? "null" : result]; sprites [SSlighting.sprites], kind [SSlighting.sprite_kind], lighting objects queued [length(SSlighting.objects_queue)]"
		if("budget")
			SSlighting.lightmap_bytes = text2num(input["bytes"])
			return "ok: [SSlighting.lightmap_bytes]"
		if("lights")
			return make_lights(text2num(input["n"]) || 4)
		if("objects")
			return json_encode(lighting_objects())
		if("spawn_check")
			return json_encode(spawn_check())
		if("held_check")
			return json_encode(held_check())
	return "error: unknown command [cmd]"

/datum/review_smoke/proc/status()
	var/list/S = list()
	S["port"] = world.port
	S["time"] = world.time
	S["runlevel"] = Master.current_runlevel
	S["ticker_state"] = SSticker.current_state
	S["round_started_at"] = round_started_at
	S["air_fired"] = SSair.times_fired
	S["air_can_fire"] = SSair.can_fire
	S["air_part"] = SSair.currentpart
	S["air_state"] = SSair.state
	S["air_rebuild"] = length(SSair.adjacent_rebuild)
	S["air_active"] = length(SSair.active_turfs)
	S["lighting_fired"] = SSlighting.times_fired
	S["lighting_can_fire"] = SSlighting.can_fire
	S["lobby_busy"] = SSmapping.lobby_build_busy
	S["lobby_status"] = SSmapping.lobby_build_status
	S["lobby_loading"] = global.lobby_build_loading
	S["lobby_holding"] = global.lobby_build_holding
	S["lobby_levels_held"] = !isnull(SSmapping.lobby_build_levels)
	S["build_ticklimit"] = Master.build_ticklimit
	S["lavaland_z"] = SSmapping.lobby_build_lavaland_z
	S["docks_waiting"] = length(SSmapping.lobby_build_docks)
	S["sleep_after"] = SSmapping.lobby_build_sleep_after
	S["atoms_initialized"] = SSatoms.initialized
	S["atoms_state_after_build"] = atoms_state_after_build
	S["crashed"] = crashed
	S["admin_msgs"] = admin_msgs
	S["early_calls"] = early_calls
	S["dash_status"] = SSdashboard.status
	S["dash_initialized"] = SSdashboard.initialized
	S["dash_clients"] = SSdashboard.clients
	S["dash_lib"] = GLOB.dashboard_lib_file
	S["lighting_native"] = SSlighting.native
	S["lighting_status"] = SSlighting.native_status
	S["lighting_lib"] = GLOB.lighting_engine_lib
	S["sprites"] = SSlighting.sprites
	S["sprite_kind"] = SSlighting.sprite_kind
	S["lightmap_bytes"] = SSlighting.lightmap_bytes
	S["lightmaps_loaded"] = SSlighting.lightmaps_loaded
	S["sprites_drawn"] = SSlighting.sprites_drawn
	S["light_textures"] = length(SSlighting.light_textures)
	return S

/// A fake client: what disassociate() and the overrides of it touch, so an admin can be "here" on a headless server
/datum/review_fake_client
	var/ckey
	var/key
	var/datum/admins/holder
	var/mentor_datum
	var/chatOutput

/datum/review_fake_client/proc/remove_admin_verbs()
	return

/datum/review_fake_client/proc/remove_mentor_verbs()
	return

/// An admin datum for `name` (R_ADMIN), active; with_owner: "here", with a fake client as its owner
/datum/review_smoke/proc/make_admin(name, with_owner)
	if(!name)
		return "error: no name"
	var/datum/admin_rank/R = new("ReviewSmoke", R_ADMIN)
	var/datum/admins/D = new(R, name, TRUE)
	if(with_owner)
		var/datum/review_fake_client/C = new
		C.ckey = name
		C.key = name
		D.owner = C
		C.holder = D
	return "ok: [D.name], owner [D.owner ? "fake client" : "none"], deadmined [D.deadmined]"

/// n coloured lights on open, dynamically lit station turfs near the middle: new light for the light textures to draw
/datum/review_smoke/proc/make_lights(n)
	var/z = SSmapping.levels_by_trait(ZTRAIT_STATION)[1]
	var/made = 0
	var/list/colors = list("#ff3030", "#30ff30", "#3030ff", "#ffff30", "#ff30ff", "#30ffff")
	var/cx = round(world.maxx / 2)
	var/cy = round(world.maxy / 2)
	for(var/r in 0 to 100 step 5)
		for(var/turf/open/floor/T in block(locate(max(1, cx - r), max(1, cy - r), z), locate(min(world.maxx, cx + r), min(world.maxy, cy + r), z)))
			var/area/A = T.loc
			if(!IS_DYNAMIC_LIGHTING(A) || !IS_DYNAMIC_LIGHTING(T) || T.light_range)
				continue
			T.set_light(4, 1.5, colors[(made % length(colors)) + 1])
			made++
			if(made >= n)
				return "ok: [made] lights"
		CHECK_TICK
	return "ok: [made] lights (wanted [n])"

/// On the station level: turfs with a lighting object, and how many of those objects are on their turf (not out of the world)
/datum/review_smoke/proc/lighting_objects()
	var/z = SSmapping.levels_by_trait(ZTRAIT_STATION)[1]
	var/with = 0
	var/on_turf = 0
	for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		var/atom/movable/lighting_object/O = T.lighting_object
		if(!O)
			continue
		with++
		if(O.loc == T)
			on_turf++
		CHECK_TICK
	return list("with_object" = with, "on_turf" = on_turf, "sprites" = SSlighting.sprites)

/// Something made in the round: initialized as a round's things are (SSatoms.initialized INITIALIZATION_INNEW_REGULAR, not mapload)
/datum/review_smoke/proc/spawn_check()
	var/z = SSmapping.levels_by_trait(ZTRAIT_STATION)[1]
	var/turf/T = locate(round(world.maxx / 2), round(world.maxy / 2), z)
	var/obj/item/crowbar/C = new(T)
	. = list("initialized_flag" = !!(C.flags_1 & INITIALIZED_1), "atoms_initialized" = SSatoms.initialized)
	qdel(C)

/// Lavaland's and the space ruins' levels after the lobby build: turfs and things left uninitialized, open turfs with no air
/datum/review_smoke/proc/held_check()
	var/list/levels = list()
	if(SSmapping.lobby_build_lavaland_z)
		levels += SSmapping.lobby_build_lavaland_z
	levels |= SSmapping.levels_by_trait(ZTRAIT_SPACE_RUINS)
	var/turfs = 0
	var/things = 0
	var/uninit = 0
	var/no_air = 0
	var/list/uninit_types = list()
	for(var/z in levels)
		for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			turfs++
			if(!(T.flags_1 & INITIALIZED_1))
				uninit++
				uninit_types["[T.type]"]++
			if(isopenturf(T) && !isspaceturf(T) && !T.blocks_air)
				var/turf/open/O = T
				if(!O.air)
					no_air++
			for(var/atom/movable/AM as anything in T)
				if(istype(AM, /atom/movable/lighting_object))
					continue
				things++
				if(!(AM.flags_1 & INITIALIZED_1))
					uninit++
					uninit_types["[AM.type]"]++
			CHECK_TICK
	var/list/some = list()
	for(var/type in uninit_types)
		some += "[type] x[uninit_types[type]]"
		if(length(some) >= 3)
			break
	return list("levels" = levels, "turfs" = turfs, "things" = things, "uninitialized" = uninit, "open_no_air" = no_air, "some" = some)

// ---- Lobby build failures, injected (review-lobby-crash). Only while lobby_build_run() runs: lobby_build_busy is already TRUE
// through startup, where SSmapping's own templates call setup_template_powernets() too.

/datum/controller/subsystem/machines/setup_template_powernets(list/cables)
	if(global.review_smoke?.crash_at == "powernets" && SSmapping.lobby_build_status == "building" && !global.review_smoke.crashed)
		global.review_smoke.crashed = TRUE
		CRASH("review_smoke: a runtime injected into the lobby build (setup_template_powernets)")
	return ..()

/datum/controller/subsystem/mapping/seed_startup_ruins()
	if(global.review_smoke && lobby_build_status == "building" && !global.review_smoke.crashed)
		if(global.review_smoke.crash_at == "ruins")
			global.review_smoke.crashed = TRUE
			CRASH("review_smoke: a runtime injected into the lobby build (seed_startup_ruins)")
		if(global.review_smoke.crash_at == "body")
			global.review_smoke.crashed = TRUE
			lobby_build_pending += new /datum/review_smoke_bad
		if(global.review_smoke.crash_at == "atoms_off") // as a map load stopped by a runtime between begin and stop leaves it
			global.review_smoke.crashed = TRUE
			SSatoms.map_loader_begin()
	return ..()

/// Not an atom: in lobby_build_pending, lobby_build_run()'s own loop over it runtimes reading its flags_1 (a runtime in the build's
/// own body, not in something it calls)
/datum/review_smoke_bad

/datum/parsed_map/instance_atom(path, list/attributes, turf/crds, no_changeturf, placeOnTop)
	if(global.review_smoke?.crash_at == "maploader" && !global.review_smoke.crashed && crds && crds.z == SSmapping.lobby_build_lavaland_z && SSmapping.lobby_build_status == "building")
		global.review_smoke.crashed = TRUE
		CRASH("review_smoke: a runtime injected into the map loader, loading Lavaland ([path])")
	return ..()

/atom/Initialize(mapload, ...)
	if(global.review_smoke?.crash_at == "atom" && !global.review_smoke.crashed && SSmapping.lobby_build_status == "building" && z && z == SSmapping.lobby_build_lavaland_z)
		global.review_smoke.crashed = TRUE
		CRASH("review_smoke: a runtime injected into one atom's Initialize on Lavaland ([type])")
	return ..()

/datum/controller/subsystem/mapping/lobby_build()
	. = ..()
	if(global.review_smoke)
		global.review_smoke.atoms_state_after_build = SSatoms.initialized
		global.review_smoke.build_ended_at = world.time
		log_world("REVIEW_SMOKE: lobby_build() returned: [lobby_build_status], busy [lobby_build_busy], SSatoms.initialized [SSatoms.initialized]")
