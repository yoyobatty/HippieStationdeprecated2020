// Testkit interaction sweep: every type made fresh and used by an all-access person with an empty hand, each of six tools and (an item)
// in hand, and examined. For each use: what the person was told, what changed on the thing and the tool, what appeared or went, how
// long it took, whether it slept or never came back, what state it left the person in, and any broken text. tools/testkit/sweep.py
// drives it in batches and sorts what it finds: runtimes, hard deletes, stuck or slow uses, broken text, silent uses.

/datum/testkit
	/// The mob whose messages are being kept, and what it was told
	var/mob/capture_mob
	var/list/captured = list()
	/// What's being swept now, for pinning a runtime on it
	var/sweep_label

/datum/controller/subsystem/chat/queue(target, message, handle_whitespace = TRUE, confidential = FALSE)
	var/datum/testkit/kit = GLOB.testkit
	if(kit?.capture_mob && (target == kit.capture_mob || (islist(target) && (kit.capture_mob in target))))
		kit.captured += "[message]"
	return ..()

/mob/show_message(msg, type, alt_msg, alt_type)
	var/datum/testkit/kit = GLOB.testkit
	if(kit?.capture_mob == src)
		kit.captured += "[msg || alt_msg]"
	return ..()

/// Vars that move whatever is done, or say nothing about whether a use did anything
GLOBAL_LIST_INIT(testkit_sweep_ignored, list("tag" = 1, "datum_flags" = 1, "weak_reference" = 1, "gc_destroyed" = 1, "signal_procs" = 1,
	"comp_lookup" = 1, "datum_components" = 1, "active_timers" = 1, "fingerprints" = 1, "fingerprintshidden" = 1, "fingerprintslast" = 1,
	"pixel_x" = 1, "pixel_y" = 1, "layer" = 1, "plane" = 1, "vars" = 1, "verbs" = 1, "contents" = 1, "overlays" = 1, "underlays" = 1,
	"vis_contents" = 1, "vis_locs" = 1, "managed_overlays" = 1, "managed_vis_overlays" = 1, "important_recursive_contents" = 1,
	"last_move" = 1, "last_bumped" = 1, "last_used" = 1, "last_process" = 1, "throwing" = 1, "glide_size" = 1, "user_unbuckle" = 1,
	"blood_DNA" = 1, "forensics" = 1, "examine_cooldown" = 1, "last_examined" = 1, "next_move" = 1, "x" = 1, "y" = 1, "z" = 1, "transform" = 1))

/datum/testkit/proc/snapshot(atom/movable/A)
	var/list/s = list()
	if(QDELETED(A))
		return s
	for(var/v in A.vars)
		if(GLOB.testkit_sweep_ignored[v])
			continue
		var/x = A.vars[v]
		if(isnull(x) || isnum(x) || istext(x))
			s[v] = x
		else if(islist(x))
			var/list/L = x
			s[v] = "#[length(L)]"
		else if(istype(x, /datum))
			s[v] = REF(x)
		else
			s[v] = "[x]"
	s["#contents"] = length(A.contents)
	s["#overlays"] = length(A.overlays)
	s["#loc"] = REF(A.loc)
	return s

/datum/testkit/proc/snapshot_diff(list/before, list/after)
	var/list/changed = list()
	for(var/v in after)
		if(before[v] != after[v])
			changed += v
	return changed

/// Text a player would see that's broken: macros left in, a null in the middle, a path or ref, a word twice
/datum/testkit/proc/bad_text(text)
	var/static/regex/tags = regex(@"<[^>]*>", "g")
	var/static/regex/twice = regex(@"\b(the|a|an|is|of|to|you|your)\s+\1\b", "i")
	var/plain = tags.Replace("[text]", "")
	plain = replacetext(plain, "&nbsp;", " ")
	var/list/found = list()
	if(findtext(plain, "\\improper") || findtext(plain, "\\proper") || findtext(plain, "\\the ") || findtext(plain, "\\a "))
		found += "macro left in"
	if(findtext(plain, "/obj/") || findtext(plain, "/mob/") || findtext(plain, "/datum/") || findtext(plain, "\[0x"))
		found += "path or ref"
	if(findtext(plain, " null ") || findtext(plain, " null.") || findtext(plain, "null's") || copytext(plain, 1, 6) == "null ")
		found += "null"
	if(twice.Find(plain))
		found += "word twice: [twice.match]"
	if(findtext(plain, " .") || findtext(plain, " ,") || findtext(plain, " !"))
		found += "space before punctuation"
	if(findtext(plain, "  ") && !findtext(plain, "   "))
		found += "double space"
	return found

/datum/testkit/proc/sweep_one_use(atom/movable/A, use, mob/living/carbon/human/H, obj/item/tool, list/state)
	set waitfor = FALSE
	usr = H
	try
		switch(use)
			if("hand")
				H.a_intent = INTENT_HELP
				A.attack_hand(H)
			if("in hand")
				var/obj/item/I = A
				if(H.put_in_active_hand(I))
					I.attack_self(H)
			if("examine")
				state["examine"] = A.examine(H)
			else
				if(!QDELETED(tool) && tool.loc == H)
					tool.melee_attack_chain(H, A)
	catch(var/exception/e)
		note_exception(e, sweep_label)
	state["done"] = TRUE

/datum/testkit/proc/cmd_types(list/a)
	var/root = text2path(a["root"] || "/obj")
	var/list/skip = sweep_skipped()
	var/list/found = list()
	for(var/path in typesof(root))
		if(skip[path])
			continue
		if(a["match"] && !findtext("[path]", a["match"]))
			continue
		found += "[path]"
	return found

/datum/testkit/proc/sweep_skipped()
	var/static/list/skip
	if(skip)
		return skip
	skip = list()
	for(var/path in typesof(/atom/movable/lighting_object) + typesof(/obj/screen) + typesof(/mob/dead) + typesof(/obj/docking_port) + \
		typesof(/obj/singularity) + typesof(/obj/machinery/doomsday_device) + typesof(/obj/effect/landmark) + typesof(/mob/living/carbon) - \
		typesof(/mob/living/carbon/human) - typesof(/mob/living/carbon/monkey) - typesof(/mob/living/carbon/alien))
		skip[path] = TRUE
	return skip

/// types: a batch of paths. Writes each one to progress.txt before it starts, so a server that goes down names what took it.
/datum/testkit/proc/cmd_sweep_use(list/a)
	var/static/list/tools = list("crowbar" = /obj/item/crowbar, "wrench" = /obj/item/wrench, "welder" = /obj/item/weldingtool/largetank,
		"screwdriver" = /obj/item/screwdriver, "wirecutters" = /obj/item/wirecutters, "multitool" = /obj/item/multitool)
	var/static/list/use_names = list("hand", "crowbar", "wrench", "welder", "screwdriver", "wirecutters", "multitool", "in hand", "examine")
	var/list/arena = cmd_arena(list("w" = 9, "h" = 9))
	var/arena_id = arena["id"]
	var/turf/middle = arena_middle(arena_id)
	var/turf/beside = get_step(middle, WEST)
	var/list/records = list()
	var/count = 0
	GLOB.code_sweep_no_waiting = TRUE
	for(var/type_text in a["types"])
		var/path = text2path(type_text)
		if(!path)
			continue
		text2file(type_text, dir + "sweep_progress.txt")
		var/list/record = list("type" = type_text)
		var/list/uses_done = list()
		var/runtimes_before = counters["runtime"]
		try // a runtime that gets out of a use (a Destroy(), say) is pinned on this type, not the whole batch
			for(var/use in use_names)
				if(use == "in hand" && !ispath(path, /obj/item))
					continue
				sweep_label = "[type_text]: [use]"
				var/atom/movable/A
				try
					A = new path(middle)
				catch(var/exception/e)
					note_exception(e, "[type_text]: made")
					record["made"] = "[e.name]"
					break
				if(QDELETED(A))
					record["made"] = "deleted itself"
					break
				if(isanimal(A))
					var/mob/living/simple_animal/animal = A
					animal.toggle_ai(AI_OFF)
				var/mob/living/carbon/human/H = tester
				if(QDELETED(H) || H.stat != CONSCIOUS || H.loc != beside || H.incapacitated() || H.restrained() || H.buckled)
					if(!QDELETED(H))
						qdel(H, force = TRUE)
					tester = null
					H = get_tester()
				H.forceMove(beside)
				H.setDir(EAST)
				for(var/obj/item/held in H.held_items)
					qdel(held, force = TRUE)
				var/obj/item/tool
				if(tools[use])
					var/tool_path = tools[use]
					tool = new tool_path(H)
					H.put_in_active_hand(tool)
					var/obj/item/weldingtool/W = tool
					if(istype(W))
						W.switched_on(H)
				var/list/before = snapshot(A)
				var/list/tool_before = tool ? snapshot(tool) : null
				var/list/around_before = list()
				for(var/turf/T in range(1, middle))
					around_before += T.contents
				captured = list()
				capture_mob = H
				var/list/state = list("done" = FALSE)
				var/started = TICK_USAGE_REAL
				var/time = world.time
				sweep_one_use(A, use, H, tool, state)
				var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
				var/slept = !state["done"]
				if(slept)
					var/deadline = world.time + 3 SECONDS
					while(!state["done"] && world.time < deadline)
						sleep(1)
				capture_mob = null
				var/list/u = list("u" = use, "ms" = round(ms, 0.01))
				if(slept)
					u["slept"] = TRUE
					u["stuck"] = !state["done"]
					u["took"] = (world.time - time) / 10
				if(use == "examine")
					var/list/text = state["examine"]
					var/list/bad = list()
					for(var/line in text)
						for(var/problem in bad_text(line))
							bad += "[problem]: [copytext(line, 1, 160)]"
					if(length(bad))
						u["bad_text"] = bad
					uses_done += list(u)
					if(!QDELETED(A))
						qdel(A, force = TRUE)
					continue
				var/list/changed = snapshot_diff(before, snapshot(A))
				var/list/tool_changed = tool_before ? snapshot_diff(tool_before, snapshot(tool)) : list()
				var/list/around_after = list()
				for(var/turf/T in range(1, middle))
					around_after += T.contents
				var/appeared = length(around_after - around_before - H)
				var/went = QDELETED(A) || (A.loc != middle && A.loc != H)
				if(length(captured))
					var/list/msgs = list()
					var/list/bad = list()
					for(var/m in captured)
						msgs += copytext(m, 1, 200)
						for(var/problem in bad_text(m))
							bad += "[problem]: [copytext(m, 1, 160)]"
					u["msgs"] = msgs.Copy(1, min(length(msgs), 4) + 1)
					if(length(bad))
						u["bad_text"] = bad
				if(length(changed))
					u["changed"] = changed.Copy(1, min(length(changed), 8) + 1)
				if(length(tool_changed))
					u["tool_changed"] = tool_changed.Copy(1, min(length(tool_changed), 5) + 1)
				if(appeared)
					u["appeared"] = appeared
				if(went)
					u["went"] = TRUE
				if(!length(captured) && !length(changed) && !length(tool_changed) && !appeared && !went)
					u["silent"] = TRUE
				if(!QDELETED(H))
					var/list/user_state = list()
					if(H.stat != CONSCIOUS)
						user_state += "stat [H.stat]"
					if(H.loc != beside)
						user_state += "moved to [H.loc?.type]"
					if(H.buckled)
						user_state += "buckled to [H.buckled.type]"
					if(H.restrained())
						user_state += "restrained"
					if(H.notransform)
						user_state += "notransform"
					if(length(user_state))
						u["user"] = user_state
				else
					u["user"] = list("deleted")
				uses_done += list(u)
				if(!QDELETED(A))
					qdel(A, force = TRUE)
				if(!QDELETED(tool))
					qdel(tool, force = TRUE)
				for(var/turf/T in range(1, middle))
					for(var/atom/movable/AM as anything in T.contents - around_before)
						if(AM != H && !istype(AM, /atom/movable/lighting_object))
							qdel(AM, force = TRUE)
				CHECK_TICK
		catch(var/exception/e)
			note_exception(e, sweep_label)
			record["escaped"] = "[e.name] at [e.file]:[e.line]"
		record["uses"] = uses_done
		record["runtimes"] = counters["runtime"] - runtimes_before
		records += list(record)
		if(!(++count % 20))
			build_arena(arenas[arena_id])
			tester = null
		CHECK_TICK
	GLOB.code_sweep_no_waiting = FALSE
	sweep_label = null
	try // what the batch left on the tester or the floor goes with them: a bad Destroy() is noted, not the batch's answer lost
		cmd_arena_free(list("id" = arena_id))
		if(!QDELETED(tester))
			qdel(tester, force = TRUE)
	catch(var/exception/e)
		note_exception(e, "batch cleanup")
	tester = null
	return records

/// Where each runtime site was first seen, for the sweep's report
/datum/testkit/proc/cmd_runtime_sites(list/a)
	return runtime_sites
