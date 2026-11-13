#define EXPLOSION_THROW_SPEED 4
GLOBAL_LIST_EMPTY(explosions)

SUBSYSTEM_DEF(explosions)
	name = "Explosions"
	init_order = INIT_ORDER_EXPLOSIONS
	priority = FIRE_PRIORITY_EXPLOSIONS
	wait = 1
	flags = SS_TICKER|SS_NO_INIT
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME

	var/cost_lowturf = 0
	var/cost_medturf = 0
	var/cost_highturf = 0
	var/cost_flameturf = 0

	var/cost_throwturf = 0

	var/cost_lowobj = 0
	var/cost_medobj = 0
	var/cost_highobj = 0


	var/list/lowturf = list()
	var/list/medturf = list()
	var/list/highturf = list()
	var/list/flameturf = list()

	var/list/throwturf = list()

	var/list/lowobj = list()
	var/list/medobj = list()
	var/list/highobj = list()

	var/list/explosions = list()

	var/currentpart = SSAIR_PIPENETS


/datum/controller/subsystem/explosions/stat_entry(msg)
	msg += "C:{"
	msg += "LT:[round(cost_lowturf,1)]|"
	msg += "MT:[round(cost_medturf,1)]|"
	msg += "HT:[round(cost_highturf,1)]|"
	msg += "FT:[round(cost_flameturf,1)]||"

	msg += "LO:[round(cost_lowobj,1)]|"
	msg += "MO:[round(cost_medobj,1)]|"
	msg += "HO:[round(cost_highobj,1)]|"

	msg += "TO:[round(cost_throwturf,1)]"

	msg += "} "

	msg += "AMT:{"
	msg += "LT:[lowturf.len]|"
	msg += "MT:[medturf.len]|"
	msg += "HT:[highturf.len]|"
	msg += "FT:[flameturf.len]||"

	msg += "LO:[lowobj.len]|"
	msg += "MO:[medobj.len]|"
	msg += "HO:[highobj.len]|"

	msg += "TO:[throwturf.len]"

	msg += "} "
	..(msg)


#define SSEX_TURF "turf"
#define SSEX_OBJ "obj"

/datum/controller/subsystem/explosions/proc/is_exploding()
	return (length(batch) || lowturf.len || medturf.len || highturf.len || flameturf.len || throwturf.len || lowobj.len || medobj.len || highobj.len) //hippie -- and one being worked through (fire(), below)


/client/proc/check_bomb_impacts()
	set name = "Check Bomb Impact"
	set category = "Debug"

	var/newmode = tgui_alert(usr, "Use reactionary explosions?", "Check Bomb Impact", list("Yes", "No"))
	var/turf/epicenter = get_turf(mob)
	if(!epicenter)
		return

	var/dev = 0
	var/heavy = 0
	var/light = 0
	var/list/choices = list("Small Bomb","Medium Bomb","Big Bomb","Custom Bomb")
	var/choice = tgui_input_list(usr, "Bomb Size?", null, choices, allow_cancel = FALSE)
	switch(choice)
		if(null)
			return 0
		if("Small Bomb")
			dev = 1
			heavy = 2
			light = 3
		if("Medium Bomb")
			dev = 2
			heavy = 3
			light = 4
		if("Big Bomb")
			dev = 3
			heavy = 5
			light = 7
		if("Custom Bomb")
			dev = tgui_input_number(usr, "Devastation range (Tiles):", allow_cancel = FALSE)
			heavy = tgui_input_number(usr, "Heavy impact range (Tiles):", allow_cancel = FALSE)
			light = tgui_input_number(usr, "Light impact range (Tiles):", allow_cancel = FALSE)

	// hippie start -- what explode() itself works out (explosion_severity_map(), explosions_shape.dm): this had its own copy, which
	// added up what was on the tile being checked at every step instead of what was in the way, and ignored the shape
	var/list/wipe_colours = list()
	var/list/severity = explosion_severity_map(epicenter, dev, heavy, light, newmode == "Yes" ? null : "none")
	for(var/turf/T as anything in severity)
		wipe_colours += T
		switch(severity[T])
			if(EXPLODE_DEVASTATE)
				T.color = "red"
				T.maptext = "Dev"
			if(EXPLODE_HEAVY)
				T.color = "yellow"
				T.maptext = "Heavy"
			if(EXPLODE_LIGHT)
				T.color = "blue"
				T.maptext = "Light"
	// hippie end

	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(wipe_color_and_text), wipe_colours), 100)

/proc/wipe_color_and_text(list/atom/wiping)
	for(var/i in wiping)
		var/atom/A = i
		A.color = null
		A.maptext = ""

/proc/dyn_explosion(turf/epicenter, power, flash_range, adminlog = TRUE, ignorecap = TRUE, flame_range = 0, silent = FALSE, smoke = TRUE, atom/explosion_cause = null) //hippie -- explosion_cause, as tgstation
	if(power <= 0) //the root of a negative number is a runtime
		return
	var/range = 0
	range = round((2 * power)**GLOB.DYN_EX_SCALE)
	explosion(epicenter, round(range * 0.25), round(range * 0.5), round(range), flash_range*range, adminlog, ignorecap, flame_range*range, silent, smoke, explosion_cause)

// Using default dyn_ex scale:
// 100 explosion power is a (5, 10, 20) explosion.
// 75 explosion power is a (4, 8, 17) explosion.
// 50 explosion power is a (3, 7, 14) explosion.
// 25 explosion power is a (2, 5, 10) explosion.
// 10 explosion power is a (1, 3, 6) explosion.
// 5 explosion power is a (0, 1, 3) explosion.
// 1 explosion power is a (0, 0, 1) explosion.

/proc/explosion(atom/epicenter, devastation_range, heavy_impact_range, light_impact_range, flash_range, adminlog = TRUE, ignorecap = FALSE, flame_range = 0, silent = FALSE, smoke = FALSE, atom/explosion_cause = null) //hippie -- explosion_cause: what set it off, when different to the epicenter (for logging)
	. = SSexplosions.explode(arglist(args))

/datum/controller/subsystem/explosions/proc/explode(atom/epicenter, devastation_range, heavy_impact_range, light_impact_range, flash_range, adminlog, ignorecap, flame_range, silent, smoke, atom/explosion_cause)
	var/atom/origin = epicenter //hippie -- remembered for explosion_blame(), before it becomes a turf
	epicenter = get_turf(epicenter)
	if(!epicenter)
		return

	if(isnull(flame_range))
		flame_range = light_impact_range
	if(isnull(flash_range))
		flash_range = devastation_range

	// Archive the uncapped explosion for the doppler array
	var/orig_dev_range = devastation_range
	var/orig_heavy_range = heavy_impact_range
	var/orig_light_range = light_impact_range

	var/orig_max_distance = max(devastation_range, heavy_impact_range, light_impact_range, flash_range, flame_range)

	//Zlevel specific bomb cap multiplier
	var/cap_multiplier = SSmapping.level_trait(epicenter.z, ZTRAIT_BOMBCAP_MULTIPLIER)
	if (isnull(cap_multiplier))
		cap_multiplier = 1

	if(!ignorecap)
		devastation_range = min(GLOB.MAX_EX_DEVESTATION_RANGE * cap_multiplier, devastation_range)
		heavy_impact_range = min(GLOB.MAX_EX_HEAVY_RANGE * cap_multiplier, heavy_impact_range)
		light_impact_range = min(GLOB.MAX_EX_LIGHT_RANGE * cap_multiplier, light_impact_range)
		flash_range = min(GLOB.MAX_EX_FLASH_RANGE * cap_multiplier, flash_range)
		flame_range = min(GLOB.MAX_EX_FLAME_RANGE * cap_multiplier, flame_range)

	var/max_range = max(devastation_range, heavy_impact_range, light_impact_range, flame_range)
	var/started_at = REALTIMEOFDAY
	//hippie start -- every explosion is logged with a cause, suspects and the call stack that set it off, adminlog or not (see explosion_blame())
	var/list/blame = explosion_blame(origin, explosion_cause)
	// The call stack is ~2 KB, and a chain (a pile of fuel tanks, cluster charges) repeats the same one hundreds of times: 13,000 of
	// them made most of a 32 MB game log in one round, every line also kept in GLOB.bombers. The same stack as the last explosion's
	// within 5 s is said so instead
	var/static/last_trace
	var/static/last_trace_time = -INFINITY
	var/trace = blame["trace"]
	if(trace == last_trace && world.time - last_trace_time < 5 SECONDS)
		trace = "the same as the last explosion's"
	else
		last_trace = trace
	last_trace_time = world.time
	var/blame_message = "Explosion with size ([devastation_range], [heavy_impact_range], [light_impact_range], [flame_range]) in [loc_name(epicenter)]. Cause: [blame["cause"]]. Suspects: [blame["suspects"]]. Call stack: [trace]"
	log_game(blame_message)
	GLOB.bombers += blame_message
	if(adminlog)
		message_admins("Explosion with size ([devastation_range], [heavy_impact_range], [light_impact_range], [flame_range]) in [ADMIN_VERBOSEJMP(epicenter)]. Cause: [blame["cause"]]. Suspects: [blame["admin_suspects"]].")
	//hippie end

	var/x0 = epicenter.x
	var/y0 = epicenter.y
	var/z0 = epicenter.z
	var/area/areatype = get_area(epicenter)
	SSblackbox.record_feedback("associative", "explosion", 1, list("dev" = devastation_range, "heavy" = heavy_impact_range, "light" = light_impact_range, "flash" = flash_range, "flame" = flame_range, "orig_dev" = orig_dev_range, "orig_heavy" = orig_heavy_range, "orig_light" = orig_light_range, "x" = x0, "y" = y0, "z" = z0, "area" = areatype.type, "time" = time_stamp("YYYY-MM-DD hh:mm:ss", 1)))

	// Play sounds; we want sounds to be different depending on distance so we will manually do it ourselves.
	// Stereo users will also hear the direction of the explosion!

	// Calculate far explosion sound range. Only allow the sound effect for heavy/devastating explosions.
	// 3/7/14 will calculate to 80 + 35

	var/far_dist = 0
	far_dist += heavy_impact_range * 5
	far_dist += devastation_range * 20

	if(!silent)
		var/frequency = get_rand_frequency()
		var/sound/explosion_sound = sound(get_sfx("explosion"))
		var/sound/far_explosion_sound = sound('sound/effects/explosionfar.ogg')

		for(var/MN in GLOB.player_list)
			var/mob/M = MN
			// Double check for client
			var/turf/M_turf = get_turf(M)
			if(M_turf && M_turf.z == z0)
				var/dist = get_dist(M_turf, epicenter)
				var/baseshakeamount
				if(orig_max_distance - dist > 0)
					baseshakeamount = sqrt((orig_max_distance - dist)*0.1)
				// If inside the blast radius + world.view - 2
				if(dist <= round(max_range + world.view - 2, 1))
					M.playsound_local(epicenter, null, 100, 1, frequency, falloff = 5, S = explosion_sound)
					if(baseshakeamount > 0 && isliving(M))
						shake_camera(M, 25, clamp(baseshakeamount, 0, 10))
				// You hear a far explosion if you're outside the blast radius. Small bombs shouldn't be heard all over the station.
				else if(dist <= far_dist)
					var/far_volume = clamp(far_dist, 30, 50) // Volume is based on explosion size and dist
					far_volume += (dist <= far_dist * 0.5 ? 50 : 0) // add 50 volume if the mob is pretty close to the explosion
					M.playsound_local(epicenter, null, far_volume, 1, frequency, falloff = 5, S = far_explosion_sound)
					if(baseshakeamount > 0 && isliving(M)) //hippie edit -- ghosts don't get the shake
						shake_camera(M, 10, clamp(baseshakeamount*0.25, 0, 2.5))

	if(!silent && (devastation_range >= 1 || heavy_impact_range >= 1)) //hippie edit -- ripples the screen of everyone who can see it
		screen_shockwave(epicenter, max_range, 3 + devastation_range * 5 + heavy_impact_range * 1.5 + light_impact_range * 0.4)

	if(heavy_impact_range > 1)
		var/datum/effect_system/explosion/E
		if(smoke)
			E = new /datum/effect_system/explosion/smoke
		else
			E = new
		E.set_up(epicenter)
		E.start()

	//flash mobs
	if(flash_range)
		for(var/mob/living/L in viewers(flash_range, epicenter))
			L.flash_act()

	var/list/affected_turfs = GatherSpiralTurfs(max_range, epicenter)

	var/reactionary = CONFIG_GET(flag/reactionary_explosions)
	var/list/cached_exp_block
	var/list/path_block //hippie -- turf -> what's in the way between it and the epicenter

	var/list/shape_extra //hippie -- turf -> how much further the blast comes round to reach it (explosions_shape.dm)
	if(reactionary)
		cached_exp_block = CaculateExplosionBlock(affected_turfs)
		path_block = list()
		shape_extra = explosion_shape(epicenter, max_range, cached_exp_block) //hippie -- null with explosion-shape=line

	//lists are guaranteed to contain at least 1 turf at this point

	for(var/TI in affected_turfs)
		var/turf/T = TI
		var/init_dist = cheap_hypotenuse(T.x, T.y, x0, y0)
		var/dist = init_dist

		if(shape_extra) //hippie -- shaped: round what blocks it, through openings (explosions_shape.dm)
			dist += shape_extra[T]
		else if(reactionary)
			// hippie start -- this walked every tile's whole way back to the epicenter, adding up what blocked it. Its first step lands on a tile
			// one ring nearer (get_dir() never leaves a step that doesn't close the larger gap), and the rings come in order from the middle,
			// so that tile's own sum is already known: its block plus its sum is the same total, without the walk.
			var/sum = 0
			if(T != epicenter)
				var/turf/next = get_step_towards(T, epicenter)
				var/next_sum = next ? path_block[next] : null //0 is a sum; null is not worked out
				if(!isnull(next_sum))
					sum = cached_exp_block[next] + next_sum
				else
					var/turf/Trajectory = T
					while(Trajectory && Trajectory != epicenter)
						Trajectory = get_step_towards(Trajectory, epicenter)
						sum += cached_exp_block[Trajectory]
			path_block[T] = sum
			dist += sum
			// hippie end

		var/flame_dist = dist < flame_range
		var/throw_dist = dist

		if(dist < devastation_range)
			dist = EXPLODE_DEVASTATE
		else if(dist < heavy_impact_range)
			dist = EXPLODE_HEAVY
		else if(dist < light_impact_range)
			dist = EXPLODE_LIGHT
		else
			dist = EXPLODE_NONE

		if(T == epicenter) // Ensures explosives detonating from bags trigger other explosives in that bag
			var/list/items = list()
			for(var/I in T)
				var/atom/A = I
				if (length(A.contents) && !A.prevent_content_explosion()) //The atom/contents_explosion() proc returns null if the contents ex_acting has been handled by the atom, and TRUE if it hasn't.
					items += A.GetAllContents()
			for(var/O in items)
				var/atom/A = O
				if(!QDELETED(A))
					switch(dist)
						if(EXPLODE_DEVASTATE)
							SSexplosions.highobj += A
						if(EXPLODE_HEAVY)
							SSexplosions.medobj += A
						if(EXPLODE_LIGHT)
							SSexplosions.lowobj += A
		switch(dist)
			if(EXPLODE_DEVASTATE)
				SSexplosions.highturf += T
			if(EXPLODE_HEAVY)
				SSexplosions.medturf += T
			if(EXPLODE_LIGHT)
				SSexplosions.lowturf += T


		if(flame_dist && prob(40) && !isspaceturf(T) && !T.density)
			flameturf += T

		//--- THROW ITEMS AROUND ---
		var/throw_dir = get_dir(epicenter,T)
		var/throw_range = max_range-throw_dist
		var/list/throwingturf = T.explosion_throw_details
		if (throwingturf)
			if (throwingturf[1] < throw_range)
				throwingturf[1] = throw_range
				throwingturf[2] = throw_dir
				throwingturf[3] = max_range
		else
			T.explosion_throw_details = list(throw_range, throw_dir, max_range)
			throwturf += T

	var/took = (REALTIMEOFDAY - started_at) / 10

	//You need to press the DebugGame verb to see these now....they were getting annoying and we've collected a fair bit of data. Just -test- changes to explosion code using this please so we can compare
	if(GLOB.Debug2)
		log_world("## DEBUG: Explosion([x0],[y0],[z0])(d[devastation_range],h[heavy_impact_range],l[light_impact_range]): Took [took] seconds.")

	//hippie -- this was indented into the Debug2 check above, so doppler arrays never heard an explosion (tg has it out here)
	SEND_GLOBAL_SIGNAL(COMSIG_GLOB_EXPLOSION, epicenter, devastation_range, heavy_impact_range, light_impact_range, took, orig_dev_range, orig_heavy_range, orig_light_range)


/datum/controller/subsystem/explosions/proc/GatherSpiralTurfs(range, turf/epicenter)
	var/list/outlist = list()
	var/center = epicenter
	var/dist = range
	if(!dist)
		outlist += center
		return outlist

	var/turf/t_center = get_turf(center)
	if(!t_center)
		return outlist

	var/list/L = outlist
	var/turf/T
	var/y
	var/x
	var/c_dist = 1
	L += t_center

	while( c_dist <= dist )
		y = t_center.y + c_dist
		x = t_center.x - c_dist + 1
		for(x in x to t_center.x+c_dist)
			T = locate(x,y,t_center.z)
			if(T)
				L += T

		y = t_center.y + c_dist - 1
		x = t_center.x + c_dist
		for(y in t_center.y-c_dist to y)
			T = locate(x,y,t_center.z)
			if(T)
				L += T

		y = t_center.y - c_dist
		x = t_center.x + c_dist - 1
		for(x in t_center.x-c_dist to x)
			T = locate(x,y,t_center.z)
			if(T)
				L += T

		y = t_center.y - c_dist + 1
		x = t_center.x - c_dist
		for(y in y to t_center.y+c_dist)
			T = locate(x,y,t_center.z)
			if(T)
				L += T
		c_dist++
	. = L

/datum/controller/subsystem/explosions/proc/CaculateExplosionBlock(list/affected_turfs)
	. = list()
	var/I
	for(I in 1 to affected_turfs.len) // we cache the explosion block rating of every turf in the explosion area
		var/turf/T = affected_turfs[I]
		var/current_exp_block = T.density ? T.explosion_block : 0

		for(var/obj/O in T)
			var/the_block = O.explosion_block
			current_exp_block += the_block == EXPLOSION_BLOCK_PROC ? O.GetExplosionBlock() : the_block

		.[T] = current_exp_block

// hippie start -- a whole explosion used to be done in one tick, however long that took ("force using the entire tick"): on a
// 40-crew station a maxcap froze the server for a tenth of a second, 1000u of superboom for half a second, a nuke for six. Each part
// is now taken whole, as before, and worked through as the tick allows, going on next tick: the tiles nearest the middle first, so a
// blast that takes a few ticks goes out like a shockwave. Explosions set off meanwhile join the next round, as they always did.
/// What's being worked through: things, the force each is hit with (0 for a flame tile), and how far it's got.
/datum/controller/subsystem/explosions/var/list/batch = list()
/datum/controller/subsystem/explosions/var/list/batch_severity = list()
/datum/controller/subsystem/explosions/var/batch_pos = 0
/datum/controller/subsystem/explosions/var/batch_part

/datum/controller/subsystem/explosions/fire(resumed = 0)
	if(!length(batch) && !is_exploding())
		return
	Master.current_ticklimit = TICK_LIMIT_RUNNING //all the tick there is, as before, but no more: on a crewed station its own share took a superboom two seconds to go off
	for(var/parts_taken in 1 to 3) //turfs, then what was in bags at the epicentre, then the throws; at most once round in a fire
		if(!length(batch) && !next_batch())
			return
		var/timer = TICK_USAGE_REAL
		while(batch_pos < length(batch))
			batch_pos++
			var/thing = batch[batch_pos]
			if(thing)
				hit(thing, batch_severity[batch_pos])
			if(MC_TICK_CHECK)
				note_cost(TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer))
				return
		note_cost(TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer))
		batch.Cut()
		batch_severity.Cut()
		batch_pos = 0

/// The next part's lists, taken whole. FALSE if there's nothing in any of them.
/datum/controller/subsystem/explosions/proc/next_batch()
	for(var/tries in 1 to 3)
		batch_part = currentpart
		switch(currentpart)
			if(SSEXPLOSIONS_TURFS)
				currentpart = SSEXPLOSIONS_MOVABLES
				take(highturf, EXPLODE_DEVASTATE)
				take(medturf, EXPLODE_HEAVY)
				take(lowturf, EXPLODE_LIGHT)
				if(length(batch))
					Master.laggy_byond_map_update_incoming()
				take(flameturf, 0)
				highturf = list()
				medturf = list()
				lowturf = list()
				flameturf = list()
			if(SSEXPLOSIONS_MOVABLES)
				currentpart = SSEXPLOSIONS_THROWS
				take(highobj, EXPLODE_DEVASTATE)
				take(medobj, EXPLODE_HEAVY)
				take(lowobj, EXPLODE_LIGHT)
				highobj = list()
				medobj = list()
				lowobj = list()
			if(SSEXPLOSIONS_THROWS)
				currentpart = SSEXPLOSIONS_TURFS
				take(throwturf, 0)
				throwturf = list()
		if(length(batch))
			return TRUE
	return FALSE

/datum/controller/subsystem/explosions/proc/take(list/things, severity)
	if(!length(things))
		return
	batch += things
	var/list/severities = new /list(length(things))
	for(var/i in 1 to length(severities))
		severities[i] = severity
	batch_severity += severities

/datum/controller/subsystem/explosions/proc/hit(thing, severity)
	switch(batch_part)
		if(SSEXPLOSIONS_TURFS)
			var/turf/T = thing
			if(!severity)
				new /obj/effect/hotspot(T) //Mostly for ambience!
				return
			T.explosion_level = max(T.explosion_level, severity)
			T.ex_act(severity)
		if(SSEXPLOSIONS_MOVABLES)
			var/obj/O = thing
			O.ex_act(severity)
		if(SSEXPLOSIONS_THROWS)
			var/turf/T = thing
			var/list/L = T.explosion_throw_details
			T.explosion_throw_details = null
			if (length(L) != 3)
				return
			var/throw_range = L[1]
			var/throw_dir = L[2]
			var/max_range = L[3]
			for(var/atom/movable/A in T)
				if(!A.anchored && A.move_resist != INFINITY)
					var/atom_throw_range = rand(throw_range, max_range)
					var/turf/throw_at = get_ranged_target_turf(A, throw_dir, atom_throw_range)
					throw_as_missile(A, throw_at, atom_throw_range, EXPLOSION_THROW_SPEED, atom_throw_range * 0.5, quickstart = FALSE) //hippie edit -- thrown items hit hard, like debris

/// For the stat panel: what each part has been costing, a tick at a time.
/datum/controller/subsystem/explosions/proc/note_cost(ms)
	switch(batch_part)
		if(SSEXPLOSIONS_TURFS)
			cost_highturf = MC_AVERAGE(cost_highturf, ms)
		if(SSEXPLOSIONS_MOVABLES)
			cost_highobj = MC_AVERAGE(cost_highobj, ms)
		if(SSEXPLOSIONS_THROWS)
			cost_throwturf = MC_AVERAGE(cost_throwturf, ms)
// hippie end
