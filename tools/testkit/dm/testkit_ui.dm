// Testkit: tgui windows and verbs driven without a client, the server's costs, and the fuzzers (windows, uses, piles).

/datum/tgui/testkit_stub/New(mob/user, datum/src_object)
	status = UI_INTERACTIVE
	src.user = user
	src.src_object = src_object

/datum/testkit
	/// The person who presses buttons and uses things when a command names nobody: all access, in an arena of its own
	var/mob/living/carbon/human/tester

/datum/testkit/proc/get_tester()
	if(!QDELETED(tester) && tester.stat != DEAD)
		return tester
	var/list/arena = cmd_arena(list("w" = 9, "h" = 9))
	tester = new(arena_middle(arena["id"]))
	tester.real_name = "Testkit Tester"
	tester.name = tester.real_name
	tester.mind_initialize()
	tester.equipOutfit(/datum/outfit/job/assistant)
	var/obj/item/card/id/card = new(tester)
	card.access = get_all_accesses() + get_all_centcom_access()
	card.registered_name = tester.real_name
	var/obj/item/old = tester.wear_id
	if(old)
		qdel(old)
	tester.equip_to_slot_or_del(card, ITEM_SLOT_ID)
	return tester

/datum/testkit/proc/user_of(spec)
	return spec ? need(thing(spec), "user [spec]") : get_tester()

/datum/testkit/proc/cmd_ui_data(list/a)
	var/datum/D = need(thing(a["src"]), "thing [a["src"]]")
	var/mob/user = user_of(a["user"])
	usr = user
	return list("static" = out(D.ui_static_data(user), 6), "data" = out(D.ui_data(user), 6))

/datum/testkit/proc/cmd_ui_act(list/a)
	var/datum/D = need(thing(a["src"]), "thing [a["src"]]")
	var/mob/user = user_of(a["user"])
	var/list/params = list()
	if(islist(a["params"]))
		for(var/k in a["params"])
			var/value = a["params"][k]
			params[k] = isnull(value) ? null : (islist(value) ? json_encode(value) : "[value]") // tgui sends every param as text
	var/before = event_seq
	var/datum/tgui/testkit_stub/stub = new(user, D)
	usr = user
	var/result = D.ui_act(a["action"], params, stub, GLOB.default_state)
	var/list/answer = list("returned" = out(result), "events" = events_since(before, null, 50))
	if(a["data"] != 0 && !QDELETED(D))
		answer["data"] = out(D.ui_data(user), 6)
	return answer

/datum/testkit/proc/cmd_verbs(list/a)
	var/atom/A = need(thing(a["ref"]), "thing [a["ref"]]")
	var/list/names = list()
	for(var/V in A.verbs)
		var/procpath/P = V
		names += list(list("name" = P.name, "path" = "[V]", "category" = P.category))
	return names

/datum/testkit/proc/cmd_verb(list/a)
	var/mob/user = user_of(a["user"])
	var/atom/holder = a["src"] ? need(thing(a["src"]), "thing [a["src"]]") : user
	var/wanted = a["verb"]
	var/found
	for(var/V in holder.verbs)
		var/procpath/P = V
		if(P.name == wanted || "[V]" == wanted || findtext("[V]", "/[wanted]") == length("[V]") - length(wanted))
			found = V
			break
	if(!found)
		CRASH("[holder] has no verb [wanted]")
	var/list/call_args = islist(a["args"]) ? in_value(a["args"]) : list()
	var/before = event_seq
	usr = user
	var/result = call(holder, found)(arglist(call_args))
	return list("returned" = out(result), "events" = events_since(before, null, 50))

/// A holder (/datum/admins) with every right and no client, for admin procs that only check rights: usr is the tester. Procs that need a
/// client window (most verbs) are for the real-client lane.
/datum/testkit/proc/cmd_admin(list/a)
	var/mob/user = get_tester()
	var/proc_name = a["proc"]
	var/list/call_args = islist(a["args"]) ? in_value(a["args"]) : list()
	var/datum/admins/holder = GLOB.admin_datums["testkit"]
	if(!holder)
		holder = new /datum/admins(new /datum/admin_rank("Testkit", R_EVERYTHING), "testkit")
	usr = user
	var/before = event_seq
	var/result
	if(hascall(holder, proc_name))
		result = call(holder, proc_name)(arglist(call_args))
	else
		var/path = text2path("/proc/[proc_name]")
		if(!path)
			CRASH("no admin proc [proc_name]")
		result = call(path)(arglist(call_args))
	return list("returned" = out(result), "events" = events_since(before, null, 50))

// ---------------------------------------------------------------------------------------------
// Costs
// ---------------------------------------------------------------------------------------------

/datum/testkit
	/// name -> list(proc name -> self seconds), and the subsystems' total_ms
	var/list/perf_marks = list()

/datum/testkit/proc/subsystem_rows()
	var/list/rows = list()
	for(var/datum/controller/subsystem/SS as anything in Master.subsystems)
		rows += list(list("name" = SS.name, "cost" = round(SS.cost, 0.01), "overrun" = round(SS.tick_overrun, 0.01),
			"fired" = SS.times_fired, "total_ms" = round(SS.total_ms, 0.1), "can_fire" = SS.can_fire, "paused" = SS.paused_ticks))
	return rows

/datum/testkit/proc/profile_rows()
	var/raw = SSprofiler.engine == "hippie" ? hippie_prof("dump") : world.Profile(PROFILE_REFRESH, format = "json")
	if(SSprofiler.engine != "hippie")
		SSprofiler.after_read()
	var/list/rows
	try
		rows = json_decode(raw)
	catch
		return list()
	var/list/by_name = list()
	for(var/list/row in rows)
		by_name[row["name"]] = list(row["self"], row["calls"])
	return by_name

/datum/testkit/proc/cmd_perf(list/a)
	var/top = text2num("[a["top"]]") || 25
	var/list/recent = SSprofiler.recent(text2num("[a["ms"]]") || 5000)
	var/list/top_recent = list()
	for(var/name in recent)
		top_recent[name] = recent[name]
		if(length(top_recent) >= top)
			break
	var/list/stacks = SSprofiler.recent_stacks(text2num("[a["ms"]]") || 5000)
	return list("tick_usage" = world.tick_usage, "cpu" = world.cpu, "map_cpu" = world.map_cpu, "subsystems" = subsystem_rows(),
		"recent_procs" = top_recent, "recent_stacks" = stacks, "profiler" = SSprofiler.engine)

/datum/testkit/proc/cmd_perf_mark(list/a)
	var/list/ss_ms = list()
	for(var/datum/controller/subsystem/SS as anything in Master.subsystems)
		ss_ms[SS.name] = SS.total_ms
	perf_marks[a["name"] || "A"] = list("procs" = profile_rows(), "ss" = ss_ms, "rt" = REALTIMEOFDAY, "t" = world.time)
	return TRUE

/datum/testkit/proc/cmd_perf_compare(list/a)
	var/list/mark = need(perf_marks[a["a"] || "A"], "perf mark [a["a"]]")
	var/top = text2num("[a["top"]]") || 30
	var/seconds = max(0.1, (REALTIMEOFDAY - mark["rt"]) / 10)
	var/list/old_procs = mark["procs"]
	var/list/deltas = list()
	var/list/now = profile_rows()
	for(var/name in now)
		var/list/row = now[name]
		var/list/old = old_procs[name]
		var/self = row[1] - (old ? old[1] : 0)
		if(self > 0.0005)
			deltas += list(list("name" = name, "self_ms_per_s" = round(self * 1000 / seconds, 0.001), "calls" = row[2] - (old ? old[2] : 0)))
	deltas = sortTim(deltas, GLOBAL_PROC_REF(cmp_testkit_self))
	if(length(deltas) > top)
		deltas.Cut(top + 1)
	var/list/old_ss = mark["ss"]
	var/list/ss = list()
	for(var/datum/controller/subsystem/SS as anything in Master.subsystems)
		var/ms = SS.total_ms - (old_ss[SS.name] || 0)
		if(ms > 0.5)
			ss[SS.name] = round(ms / seconds, 0.01)
	return list("seconds" = seconds, "game_seconds" = (world.time - mark["t"]) / 10, "procs" = deltas, "subsystem_ms_per_s" = ss)

/proc/cmp_testkit_self(list/a, list/b)
	return b["self_ms_per_s"] - a["self_ms_per_s"]

// ---------------------------------------------------------------------------------------------
// Fuzzers
// ---------------------------------------------------------------------------------------------

/datum/testkit
	var/fuzz_done = 0

/// Junk a button might be sent
/datum/testkit/proc/junk_param(datum/near)
	switch(rand(1, 10))
		if(1)
			return ""
		if(2)
			return "0"
		if(3)
			return "1"
		if(4)
			return "-1"
		if(5)
			return "99999999"
		if(6)
			return "abc"
		if(7)
			return null
		if(8)
			return near ? REF(near) : "\[0x0]"
		if(9)
			return "1.5"
		else
			return "[rand(1, 20)]"

/datum/testkit/proc/fuzz_act(datum/D, action, list/params, mob/user)
	set waitfor = FALSE
	var/datum/tgui/testkit_stub/stub = new(user, D)
	usr = user
	try
		D.ui_act(action, params, stub, GLOB.default_state)
	catch(var/exception/e)
		note_exception(e, "fuzz_ui [D.type] [action]")
	fuzz_done++

/// cases: list of {type, actions: [...], keys: [...]} (tk.py reads them out of each type's ui_act()). Every action pressed `tries` times
/// with junk params, on a fresh one of each type in an arena, by an all-access tester beside it.
/datum/testkit/proc/cmd_fuzz_ui(list/a)
	if(!isnull(a["seed"]))
		rand_seed(text2num("[a["seed"]]"))
	var/tries = clamp(text2num("[a["tries"]]") || 3, 1, 50)
	var/list/arena = cmd_arena(list("w" = 11, "h" = 11))
	var/turf/middle = arena_middle(arena["id"])
	cmd_mark(list("name" = "fuzz_ui"))
	var/list/per_type = list()
	var/pressed = 0
	var/count = 0
	for(var/list/C in a["cases"])
		var/path = text2path(C["type"])
		if(!path)
			continue
		var/runtimes_before = counters["runtime"]
		var/mob/living/carbon/human/user = get_tester()
		user.forceMove(get_step(middle, WEST))
		var/datum/D
		try
			D = new path(middle)
		catch(var/exception/e)
			per_type[C["type"]] = "couldn't make: [e.name]"
			continue
		for(var/action in C["actions"])
			for(var/i in 1 to tries)
				if(QDELETED(D))
					break
				var/list/params = list()
				var/list/values = C["values"]
				for(var/k in C["keys"])
					if(prob(70))
						params[k] = (length(values) && prob(40)) ? pick(values) : junk_param(user) // the strings its code tests for, or junk
				fuzz_act(D, action, params, user)
				pressed++
			CHECK_TICK
		per_type[C["type"]] = counters["runtime"] - runtimes_before
		if(!QDELETED(D))
			qdel(D, force = TRUE)
		if(!(++count % 20))
			build_arena(arenas[arena["id"]])
			tester = null
		CHECK_TICK
	sleep(2 SECONDS) // what the presses started (timers, do_afters with no wait) has a moment to go wrong
	cmd_arena_free(list("id" = arena["id"]))
	var/list/inv = cmd_invariants(list("mark" = "fuzz_ui"))
	var/list/bad = list()
	for(var/type in per_type)
		if(per_type[type])
			bad[type] = per_type[type]
	return list("types" = length(per_type), "pressed" = pressed, "runtimes_by_type" = bad, "invariants" = inv)

/datum/testkit/proc/fuzz_use_one(atom/movable/A, use, mob/living/carbon/human/H, obj/item/tool)
	set waitfor = FALSE
	usr = H
	try
		fuzz_use_inner(A, use, H, tool)
	catch(var/exception/e)
		note_exception(e, "fuzz_use [A.type] [use]")

/datum/testkit/proc/fuzz_use_inner(atom/movable/A, use, mob/living/carbon/human/H, obj/item/tool)
	switch(use)
		if("hand")
			A.attack_hand(H)
		if("in hand")
			var/obj/item/I = A
			if(H.put_in_active_hand(I))
				I.attack_self(H)
		else
			if(!QDELETED(tool) && tool.loc == H)
				tool.melee_attack_chain(H, A)

/datum/testkit/proc/cmd_fuzz_use(list/a)
	var/static/list/tools = list("crowbar" = /obj/item/crowbar, "wrench" = /obj/item/wrench, "welder" = /obj/item/weldingtool/largetank,
		"screwdriver" = /obj/item/screwdriver, "wirecutters" = /obj/item/wirecutters, "multitool" = /obj/item/multitool)
	if(!isnull(a["seed"]))
		rand_seed(text2num("[a["seed"]]"))
	var/root = text2path(a["type"] || "/obj")
	var/match = a["match"]
	var/limit = clamp(text2num("[a["n"]]") || 200, 1, 5000)
	var/list/arena = cmd_arena(list("w" = 11, "h" = 11))
	var/turf/middle = arena_middle(arena["id"])
	cmd_mark(list("name" = "fuzz_use"))
	GLOB.code_sweep_no_waiting = TRUE
	var/list/bad = list()
	var/count = 0
	for(var/path in typesof(root))
		if(match && !findtext("[path]", match))
			continue
		if(ispath(path, /obj/effect) || ispath(path, /obj/singularity) || ispath(path, /obj/docking_port))
			continue
		if(++count > limit)
			break
		var/runtimes_before = counters["runtime"]
		for(var/use in list("hand", "in hand") + tools)
			var/atom/movable/A
			try
				A = new path(middle)
			catch
				break
			if(use == "in hand" && !isitem(A))
				qdel(A, force = TRUE)
				continue
			var/mob/living/carbon/human/H = get_tester()
			H.forceMove(get_step(middle, WEST))
			H.drop_all_held_items()
			var/obj/item/tool
			if(tools[use])
				var/tool_path = tools[use]
				tool = new tool_path(H)
				H.put_in_active_hand(tool)
				if(istype(tool, /obj/item/weldingtool))
					var/obj/item/weldingtool/W = tool
					W.switched_on(H)
			fuzz_use_one(A, use, H, tool)
			if(!QDELETED(A))
				qdel(A, force = TRUE)
			if(tool && !QDELETED(tool))
				qdel(tool, force = TRUE)
			CHECK_TICK
		if(counters["runtime"] > runtimes_before)
			bad["[path]"] = counters["runtime"] - runtimes_before
		if(!(count % 25))
			build_arena(arenas[arena["id"]])
			tester = null
	GLOB.code_sweep_no_waiting = FALSE
	sleep(2 SECONDS)
	cmd_arena_free(list("id" = arena["id"]))
	return list("types" = min(count, limit), "runtimes_by_type" = bad, "invariants" = cmd_invariants(list("mark" = "fuzz_use")))

/// A pile on one tile, as players make them (mob_storm): n of a type, then 5 seconds of the MC's costs while it sits there
/datum/testkit/proc/cmd_stall(list/a)
	var/path = need(text2path(a["type"]), "type [a["type"]]")
	var/n = clamp(text2num("[a["n"]]") || 100, 1, 2000)
	var/turf/T
	var/arena_id
	if(a["at"])
		T = need(where(a["at"]), "place [json_encode(a["at"])]")
	else
		var/list/arena = cmd_arena(list("w" = 9, "h" = 9))
		arena_id = arena["id"]
		T = arena_middle(arena_id)
	cmd_mark(list("name" = "stall"))
	cmd_perf_mark(list("name" = "stall"))
	var/started = REALTIMEOFDAY
	var/list/made = list()
	for(var/i in 1 to n)
		made += new path(T)
	var/spawn_ms = (REALTIMEOFDAY - started) * 100
	var/list/usage = list()
	for(var/i in 1 to 50)
		sleep(world.tick_lag)
		usage += world.tick_usage
	var/peak = 0
	var/sum = 0
	for(var/u in usage)
		peak = max(peak, u)
		sum += u
	var/list/result = list("made" = length(made), "spawn_ms" = spawn_ms, "tick_usage_avg" = round(sum / length(usage), 0.1),
		"tick_usage_peak" = peak, "costs" = cmd_perf_compare(list("a" = "stall", "top" = 20)), "invariants" = cmd_invariants(list("mark" = "stall")))
	if(a["keep"] != 1)
		for(var/datum/D as anything in made)
			qdel(D)
		if(arena_id)
			cmd_arena_free(list("id" = arena_id))
	return result
