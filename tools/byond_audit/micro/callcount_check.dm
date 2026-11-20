// Testkit check: BYOND's own profiler for call counts (hippie_prof only samples time).
// ss_call global micro_prof_start, wait, then global micro_prof_dump -> data/byond_audit/callcounts.json
/proc/micro_prof_start()
	hippie_prof("stop")
	SSprofiler.engine = "byond-manual"
	world.Profile(PROFILE_CLEAR)
	world.Profile(PROFILE_START)
	return "started"

/proc/micro_prof_dump(name = "callcounts")
	var/data = world.Profile(PROFILE_REFRESH, format = "json")
	world.Profile(PROFILE_STOP)
	fdel("data/byond_audit/[name].json")
	text2file(data, "data/byond_audit/[name].json")
	return length(data)

// Per-instance var census: for every Nth turf / every obj and mob, which vars differ from the type's default, and how many
// of those are lists (each a separate list the instance owns). -> data/byond_audit/census.json
/proc/micro_census(step = 7)
	var/list/out = list()
	var/list/kinds = list("turf" = list(), "obj" = list(), "mob" = list(), "area" = list())
	var/list/nseen = list("turf" = 0, "obj" = 0, "mob" = 0, "area" = 0)
	var/list/lists_by_var = list()
	var/list/uniq = list()
	var/i = 0
	for(var/atom/A in world)
		var/k
		if(isturf(A))
			if((++i % step))
				continue
			k = "turf"
		else if(isobj(A))
			k = "obj"
		else if(ismob(A))
			k = "mob"
		else if(isarea(A))
			k = "area"
		else
			continue
		nseen[k]++
		var/list/tally = kinds[k]
		for(var/v in A.vars)
			if(v == "vars" || v == "contents" || v == "overlays" || v == "underlays" || v == "verbs" || v == "vis_contents" || v == "vis_locs" || v == "filters" || v == "appearance" || v == "transform" || v == "pixloc" || v == "loc" || v == "x" || v == "y" || v == "z" || v == "locs" || v == "type" || v == "parent_type")
				continue
			var/val = A.vars[v]
			if(val == initial(A.vars[v]))
				continue
			tally[v]++
			if(islist(val))
				var/key = "[k]:[v]"
				lists_by_var[key]++
				var/list/u = uniq[key]
				if(!u)
					u = uniq[key] = list()
				u[val] = 1
		CHECK_TICK
	out["seen"] = nseen
	out["turf_step"] = step
	for(var/k in kinds)
		var/list/t = kinds[k]
		out[k] = t
	out["lists"] = lists_by_var
	var/list/uc = list()
	for(var/key in uniq)
		var/list/u = uniq[key]
		uc[key] = u.len
	out["lists_unique"] = uc
	fdel("data/byond_audit/census.json")
	text2file(json_encode(out), "data/byond_audit/census.json")
	return "ok"

// Who makes timers: tally by callback object type + proc while micro_timer_tally_on
GLOBAL_VAR_INIT(micro_timer_tally_on, FALSE)
GLOBAL_LIST_EMPTY(micro_timer_tally)
/datum/timedevent/New(datum/callback/callBack, wait, flags, hash)
	if(GLOB.micro_timer_tally_on && callBack)
		var/o = callBack.object
		var/key = "[o == GLOBAL_PROC ? "global" : (istype(o, /datum) ? o:type : "?")] [callBack.delegate] w=[wait]"
		GLOB.micro_timer_tally[key]++
	return ..()

/proc/micro_timer_tally(on)
	GLOB.micro_timer_tally_on = on
	if(on)
		GLOB.micro_timer_tally.Cut()
		return "on"
	var/list/L = GLOB.micro_timer_tally
	var/list/out = list()
	for(var/k in L)
		if(L[k] >= 50)
			out[k] = L[k]
	return json_encode(out)

// ---- microlab: A/B timing of real game procs in a live round. micro_lab(name, reps) -> json of min ns per op per variant.
/datum/micro_dummy/proc/noop()
	return

/proc/micro_has_gravity_z(atom/src_atom, turf/T)
	// has_gravity with the z key from a cached list instead of "[T.z]"
	var/static/list/ztext = list()
	if(!T || !isturf(T))
		T = get_turf(src_atom)
	if(!T)
		return 0
	if((src_atom.comp_lookup && src_atom.comp_lookup[COMSIG_ATOM_HAS_GRAVITY]) || (T.comp_lookup && T.comp_lookup[COMSIG_TURF_HAS_GRAVITY]))
		return src_atom.has_gravity(T)
	if(isspaceturf(T))
		return FALSE
	if(istype(T, /turf/open/openspace))
		if(istype(get_area(T), /area/space))
			return FALSE
	var/area/A = get_area(T)
	if(A.has_gravity)
		return A.has_gravity
	var/z = T.z
	if(z > ztext.len)
		for(var/i in ztext.len + 1 to z)
			ztext += "[i]"
	var/list/generators = GLOB.gravity_generators[ztext[z]]
	if(generators)
		var/max_grav = 0
		for(var/obj/machinery/gravity_generator/main/G in generators)
			max_grav = max(G.setting,max_grav)
		return max_grav
	return SSmapping.level_trait(z, ZTRAIT_GRAVITY)

/proc/micro_lab(name, reps = 20000, tries = 7)
	var/list/res = list()
	var/list/variants
	switch(name)
		if("gravity")
			variants = list("orig", "zcache", "base")
		if("timer")
			variants = list("addtimer+del", "addtimer cached cb+del", "new callback", "num2text id", "base")
		if("calls")
			variants = list("call(o,name)()", "call(o,name)(arglist(null))", "o.noop()", "base")
	var/list/best = list()
	for(var/v in variants)
		best[v] = 1e9
	var/mob/living/M = locate(/mob/living/carbon/human) in GLOB.mob_living_list
	var/datum/micro_dummy/D = new
	var/datum/callback/cached = CALLBACK(D, TYPE_PROC_REF(/datum/micro_dummy, noop))
	var/dummy
	for(var/t in 1 to tries)
		for(var/v in variants)
			var/t0 = TICK_USAGE_REAL
			switch(v)
				if("base")
					for(var/i in 1 to reps)
						dummy = i
				if("orig")
					for(var/i in 1 to reps)
						dummy = M.has_gravity()
				if("zcache")
					for(var/i in 1 to reps)
						dummy = micro_has_gravity_z(M)
				if("addtimer+del")
					for(var/i in 1 to reps)
						deltimer(addtimer(CALLBACK(D, TYPE_PROC_REF(/datum/micro_dummy, noop)), 50, TIMER_STOPPABLE))
				if("addtimer cached cb+del")
					for(var/i in 1 to reps)
						deltimer(addtimer(cached, 50, TIMER_STOPPABLE))
				if("new callback")
					for(var/i in 1 to reps)
						dummy = CALLBACK(D, TYPE_PROC_REF(/datum/micro_dummy, noop))
				if("num2text id")
					for(var/i in 1 to reps)
						dummy = num2text(1000000 + i, 100)
				if("call(o,name)()")
					for(var/i in 1 to reps)
						dummy = call(D, "noop")()
				if("call(o,name)(arglist(null))")
					var/list/nl = null
					for(var/i in 1 to reps)
						dummy = call(D, "noop")(arglist(nl))
				if("o.noop()")
					for(var/i in 1 to reps)
						dummy = D.noop()
			var/ns = (TICK_USAGE_REAL - t0) * world.tick_lag * 1e6 / reps
			best[v] = min(best[v], ns)
			sleep(world.tick_lag)
	for(var/v in variants)
		res[v] = round(best[v] - best["base"], 0.1)
	return json_encode(res)

// Move lab: steps M back and forth between A and B reps times (Move(), as a walk does), ns per step, min of tries.
/proc/micro_move_lab(mob/living/M, turf/A, turf/B, reps = 2000, tries = 7)
	var/best = 1e9
	var/fails = 0
	for(var/t in 1 to tries)
		M.forceMove(A)
		sleep(world.tick_lag)
		var/t0 = TICK_USAGE_REAL
		for(var/i in 1 to reps)
			var/turf/dest = (i & 1) ? B : A
			M.last_move = 0
			if(!M.Move(dest, get_dir(M.loc, dest)))
				fails++
		var/ns = (TICK_USAGE_REAL - t0) * world.tick_lag * 1e6 / reps
		best = min(best, ns)
	return "[round(best, 1)] ns per step, [fails] failed"

/proc/micro_blackbox_info(reps = 2000)
	var/list/F = SSblackbox.feedback
	var/datum/feedback_variable/last = F[F.len]
	var/datum/feedback_variable/mid = F[round(F.len / 2)]
	var/t0 = TICK_USAGE_REAL
	for(var/i in 1 to reps)
		SSblackbox.find_feedback_datum(mid.key, mid.key_type)
	var/ns_mid = (TICK_USAGE_REAL - t0) * world.tick_lag * 1e6 / reps
	t0 = TICK_USAGE_REAL
	for(var/i in 1 to reps)
		SSblackbox.find_feedback_datum(last.key, last.key_type)
	var/ns_last = (TICK_USAGE_REAL - t0) * world.tick_lag * 1e6 / reps
	return "feedback entries [F.len], lookup mid [round(ns_mid)] ns, last [round(ns_last)] ns"

/mob/living/proc/micro_has_status_effect2(effect)
	. = FALSE
	var/list/effects = status_effects
	if(effects)
		var/datum/status_effect/S1 = effect
		var/want = initial(S1.id)
		for(var/datum/status_effect/S as anything in effects)
			if(want == S.id)
				return S

/proc/micro_status_lab(reps = 20000, tries = 7)
	// the bot with the most status effects
	var/mob/living/M
	for(var/mob/living/carbon/human/H in GLOB.mob_living_list)
		if(!M || length(H.status_effects) > length(M.status_effects))
			M = H
	var/a = 1e9
	var/b = 1e9
	var/dummy
	for(var/t in 1 to tries)
		var/t0 = TICK_USAGE_REAL
		for(var/i in 1 to reps)
			dummy = M.has_status_effect(/datum/status_effect/incapacitating/stun)
		a = min(a, (TICK_USAGE_REAL - t0) * world.tick_lag * 1e6 / reps)
		t0 = TICK_USAGE_REAL
		for(var/i in 1 to reps)
			dummy = M.micro_has_status_effect2(/datum/status_effect/incapacitating/stun)
		b = min(b, (TICK_USAGE_REAL - t0) * world.tick_lag * 1e6 / reps)
		sleep(world.tick_lag)
	return "[length(M.status_effects)] effects: orig [round(a)] ns, hoisted+as anything [round(b)] ns [dummy]"
