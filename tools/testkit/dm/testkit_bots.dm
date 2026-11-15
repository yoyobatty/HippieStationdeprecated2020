// Testkit bot commands: every bot at a glance, one bot's brain laid bare (bot_why), a bot watched every second, a bot's brain stopped
// so commands drive the body, Bot Gym scenarios run on the warm server, and the self-checks (tools/*_check) run as jobs.

/datum/testkit
	/// bot ref -> TRUE: a bot.watch event every second
	var/list/watched = list()
	/// brain ref -> state last seen, for bot.state events
	var/list/last_states = list()

/// Once a second for as long as the server runs: bot state changes, watched bots
/datum/testkit/proc/watch_loop()
	GLOB.bot_crew_panel_open = TRUE // every bot keeps its last 40 log lines (admin/bot_crew_panel.dm), for bot_why
	while(TRUE)
		for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
			if(QDELETED(B) || QDELETED(B.owner))
				continue
			var/key = REF(B)
			var/state = B.state
			if(last_states[key] != state)
				if(last_states[key])
					event("bot.state", list("bot" = B.owner.real_name, "ref" = REF(B.owner), "from" = last_states[key], "to" = state,
						"goal" = bot_telemetry_short(B.current_goal?.type), "at" = at(B.owner)))
				last_states[key] = state
			if(watched[REF(B.owner)])
				event("bot.watch", brain_brief(B))
		sleep(1 SECONDS)

/datum/testkit/proc/brain_of(spec)
	var/mob/living/carbon/human/H = thing(spec)
	if(!istype(H) || !H.bot_brain)
		CRASH("[spec] isn't a bot")
	return H.bot_brain

/datum/testkit/proc/brain_brief(datum/bot_brain/B)
	var/mob/living/carbon/human/H = B.owner
	var/datum/bot_step/step = B.current_strategy && B.current_step_index ? B.current_strategy.steps[min(B.current_step_index, length(B.current_strategy.steps))] : null
	return list("bot" = H.real_name, "ref" = REF(H), "job" = H.mind?.assigned_role, "state" = B.state,
		"goal" = bot_telemetry_short(B.current_goal?.type), "target" = B.current_goal?.target ? "[B.current_goal.target]" : null,
		"step" = bot_telemetry_short(step?.type), "action" = B.telemetry_action, "at" = at(H), "area" = get_area_name(H, TRUE),
		"health" = H.health, "stat" = H.stat, "hands" = list("[H.get_item_for_held_index(1) || ""]", "[H.get_item_for_held_index(2) || ""]"),
		"attacker" = B.attacker ? B.attacker.real_name : null, "possessed" = !(B in SSprocessing.processing))

/datum/testkit/proc/cmd_bots(list/a)
	var/list/result = list()
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(QDELETED(B) || QDELETED(B.owner))
			continue
		result += list(brain_brief(B))
	return result

/datum/testkit/proc/cmd_bot_why(list/a)
	var/datum/bot_brain/B = brain_of(a["bot"])
	var/list/why = brain_brief(B)
	why["question"] = a["question"]
	// What it's after and how far it's got
	var/datum/bot_goal/G = B.current_goal
	if(G)
		var/list/strategies = list()
		for(var/datum/bot_strategy/S as anything in G.strategies)
			var/list/steps = list()
			for(var/datum/bot_step/step as anything in S.steps)
				steps += bot_telemetry_short(step.type)
			strategies += list(list("type" = bot_telemetry_short(S.type), "steps" = steps, "attempts" = S.attempts, "max" = S.max_attempts,
				"current" = S == B.current_strategy))
		why["goal_detail"] = list("type" = "[G.type]", "doing" = G.doing, "target" = out(G.target), "strategies" = strategies,
			"step_index" = B.current_step_index, "exclusive" = G.exclusive, "careful" = G.careful)
	if(B.suspended_goal)
		why["suspended_goal"] = list("type" = "[B.suspended_goal.type]", "target" = out(B.suspended_goal.target))
	// Clocks: what it's waiting for
	var/list/waits = list()
	for(var/v in B.vars)
		if(findtext(v, "next_") == 1 && findtext(v, "_time"))
			var/when = B.vars[v]
			if(isnum(when) && when > world.time)
				waits[v] = round((when - world.time) / 10, 0.1)
	why["waiting_seconds"] = waits
	why["goal_clock"] = list("stalled_for" = B.goal_stalled_since ? (world.time - B.goal_stalled_since) / 10 : null,
		"no_progress_for" = B.goal_progress_time ? (world.time - B.goal_progress_time) / 10 : null,
		"step_quiet_for" = B.goal_watch_since ? (world.time - B.goal_watch_since) / 10 : null,
		"chain_pending" = B.goal_chain_pending, "gave_up_at" = B.goal_giveup_time ? (world.time - B.goal_giveup_time) / 10 : null)
	why["last_gave_up"] = B.last_gave_up
	why["last_gave_up_ago"] = B.last_gave_up_at ? (world.time - B.last_gave_up_at) / 10 : null
	why["path_fail"] = B.last_path_fail_reason
	why["urgency"] = B.get_urgency()
	why["flags"] = B.telemetry_flags
	why["scripted"] = B.gym_scripted
	why["failed_areas"] = out(B.failed_areas, 1)
	var/list/claims = list()
	for(var/claim in GLOB.bot_work_claims)
		if(GLOB.bot_work_claims[claim] == B)
			claims += "[locate(claim) || claim]"
	why["claims"] = claims
	why["lines"] = B.panel_lines
	why["events"] = events_since(max(0, event_seq - 2000), null, 30, "\"ref\":\"[REF(B.owner)]\"")
	return why

/datum/testkit/proc/cmd_bot_watch(list/a)
	var/datum/bot_brain/B = brain_of(a["bot"])
	if(a["on"] == 0)
		watched -= REF(B.owner)
	else
		watched[REF(B.owner)] = TRUE
	return length(watched)

/datum/testkit/proc/cmd_possess(list/a)
	var/datum/bot_brain/B = brain_of(a["bot"])
	STOP_PROCESSING(SSprocessing, B)
	B.owner.bot_gym_frozen = FALSE
	walk(B.owner, 0)
	event("testkit.possess", list("bot" = B.owner.real_name, "ref" = REF(B.owner)))
	return TRUE

/datum/testkit/proc/cmd_release(list/a)
	var/datum/bot_brain/B = brain_of(a["bot"])
	START_PROCESSING(SSprocessing, B)
	event("testkit.release", list("bot" = B.owner.real_name, "ref" = REF(B.owner)))
	return TRUE

/datum/testkit/proc/cmd_bot_goal(list/a)
	var/datum/bot_brain/B = brain_of(a["bot"])
	var/path = text2path(a["goal"]) || text2path("/datum/bot_goal/[a["goal"]]")
	if(!ispath(path, /datum/bot_goal))
		CRASH("no goal [a["goal"]]")
	var/datum/bot_goal/G = new path
	if(a["target"])
		G.target = thing(a["target"]) || where(a["target"])
	if(islist(a["vars"]))
		for(var/v in a["vars"])
			G.vars[v] = in_value(a["vars"][v])
	return B.assign_goal(G) ? TRUE : "assign_goal refused"

// ---------------------------------------------------------------------------------------------
// Bot Gym on the warm server
// ---------------------------------------------------------------------------------------------

/datum/testkit/proc/cmd_gym_list(list/a)
	var/list/names = list()
	for(var/path in subtypesof(/datum/bot_scenario))
		var/datum/bot_scenario/probe = path
		var/name = initial(probe.name)
		if(name == "unnamed" || !initial(probe.layout))
			continue
		if(a["match"] && !findtext(name, a["match"]))
			continue
		names += name
	return names

/datum/testkit/proc/cmd_gym_run(list/a)
	var/list/wanted = splittext("[a["name"]]", "|")
	var/runs = clamp(text2num("[a["runs"]]") || 1, 1, 10)
	var/list/datum/bot_scenario/active = list()
	for(var/path in subtypesof(/datum/bot_scenario))
		var/datum/bot_scenario/probe = new path
		if(!probe.layout || probe.name == "unnamed")
			continue
		var/named = FALSE
		for(var/bit in wanted)
			if(probe.name == bit || (a["exact"] != 1 && findtext(probe.name, bit)))
				named = TRUE
				break
		if(!named)
			continue
		for(var/i in 1 to runs)
			var/datum/bot_scenario/S = (i == 1) ? probe : new path
			S.run_index = i
			S.suite_index = length(active) + 1
			active += S
	if(!length(active))
		CRASH("no scenario matches [a["name"]]")
	if(length(active) > 60)
		CRASH("[length(active)] scenarios: name fewer (60 at most on a warm server)")
	GLOB.bot_gym_running = TRUE
	event("gym.start", list("count" = length(active)))
	for(var/datum/bot_scenario/S as anything in active)
		S.prepare()
	for(var/datum/bot_scenario/S as anything in active)
		INVOKE_ASYNC(S, TYPE_PROC_REF(/datum/bot_scenario, start))
	var/deadline = world.time + 10 MINUTES
	while(world.time < deadline)
		sleep(1 SECONDS)
		var/pending = 0
		for(var/datum/bot_scenario/S as anything in active)
			if(S.brain && S.result == 0 && !S.judging) // as bot_gym_judge(): not before its bot is there
				INVOKE_ASYNC(S, TYPE_PROC_REF(/datum/bot_scenario, judge))
			if(S.result == 0)
				pending++
		if(!pending)
			break
	var/list/results = list()
	var/passed = 0
	for(var/datum/bot_scenario/S as anything in active)
		var/verdict = S.result == 1 ? "PASS" : (S.result == 2 ? "FAIL" : "TIMEOUT")
		if(!S.expect_success)
			verdict = S.result == 1 ? "XPASS" : "XFAIL"
		if(verdict == "PASS" || verdict == "XFAIL")
			passed++
		var/list/transcript = S.transcript
		var/from = max(1, length(transcript) - 80)
		results += list(list("name" = S.name, "run" = S.run_index, "verdict" = verdict, "reason" = S.fail_reason,
			"seconds" = S.end_time ? (S.end_time - S.start_time) / 10 : null, "bot" = S.bot ? REF(S.bot) : null,
			"transcript" = transcript.Copy(from)))
		event("gym.result", list("name" = S.name, "run" = S.run_index, "verdict" = verdict, "reason" = S.fail_reason))
	return list("passed" = passed, "total" = length(active), "results" = results)

// ---------------------------------------------------------------------------------------------
// The self-checks (tools/*_check): each is a global proc that writes PASS/FAIL lines to a results file and "done" at the end.
// run.sh adds the check's .dm with CHECKS=; testkit_checks.dm stops its world/New() starting it by itself.
// ---------------------------------------------------------------------------------------------

/datum/testkit/proc/cmd_run_check(list/a)
	var/proc_name = a["proc"]
	var/path = text2path("/proc/[proc_name]")
	if(!path)
		CRASH("no global proc [proc_name] (was its check built in? CHECKS= on run.sh)")
	var/results = a["results"]
	if(results)
		fdel(results)
	var/done_word = a["done"] || "done"
	var/before = event_seq
	cmd_mark(list("name" = "check:[proc_name]"))
	event("check.start", list("proc" = proc_name))
	var/started = REALTIMEOFDAY
	var/list/state = list("returned" = FALSE)
	INVOKE_ASYNC(src, PROC_REF(run_check_proc), path, state)
	var/deadline = world.time + (text2num("[a["seconds"]]") || 600) SECONDS
	var/list/lines
	while(world.time < deadline)
		sleep(1 SECONDS)
		if(results && fexists(results))
			lines = splittext(file2text(results), "\n")
			if(length(lines) && (done_word in lines))
				break
			var/last = length(lines) ? lines[length(lines)] : null
			if(last == "" && length(lines) > 1)
				last = lines[length(lines) - 1]
			if(last == done_word)
				break
		if(state["returned"])
			if(results && fexists(results))
				lines = splittext(file2text(results), "\n")
			break
	var/passes = 0
	var/fails = 0
	var/list/fail_lines = list()
	for(var/line in lines)
		if(findtext(line, "PASS") == 1)
			passes++
		else if(findtext(line, "FAIL") == 1)
			fails++
			fail_lines += line
	var/list/inv = cmd_invariants(list("mark" = "check:[proc_name]"))
	event("check.end", list("proc" = proc_name, "pass" = passes, "fail" = fails))
	return list("proc" = proc_name, "pass" = passes, "fail" = fails, "fails" = fail_lines, "seconds" = (REALTIMEOFDAY - started) / 10,
		"finished" = (done_word in lines) || state["returned"], "invariants" = inv, "lines" = lines, "events_from" = before)

/datum/testkit/proc/run_check_proc(path, list/state)
	call(path)()
	state["returned"] = TRUE
