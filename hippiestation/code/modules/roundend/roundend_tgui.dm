// The round-end report in tgui-next (RoundEnd.js), as the boarding pass's paperwork (lobby_tgui.dm): your own ending
// stamped on a shift report, the shift's numbers and first death, the antagonists, laws, goals and medals as the game
// writes them (each antagonist type keeps its own report), and a roll call of the whole crew by department with how
// each one ended, which the old report never had. On light or dark paper as the player picked (prefs.pass_dark).
// The old window was one HTML page (code/__HELPERS/roundend.dm); "Your Last Round" reads this round's report back from
// a JSON file, or an old HTML one from before.

GLOBAL_LIST(roundend_shared)

/client
	var/datum/roundend_report/roundend_report_ui

/datum/roundend_report
	var/list/data

/datum/roundend_report/New(list/new_data)
	data = new_data

/datum/roundend_report/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
									datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "roundend_report", "Shift Report", 820, 660, master_ui, state)
		ui.set_autoupdate(FALSE)
		ui.open()

/datum/roundend_report/ui_status(mob/user, datum/ui_state/state)
	return user.client ? UI_INTERACTIVE : UI_CLOSE

/datum/roundend_report/ui_static_data(mob/user)
	. = data.Copy()
	.["dark"] = user.client?.prefs?.pass_dark

/datum/controller/subsystem/ticker/display_report(popcount)
	var/list/sections = roundend_sections()
	var/list/html = list()
	for(var/list/section in sections)
		html += section["html"]
	GLOB.common_report = html.Join() // the report button and the old window still read it
	GLOB.survivor_report = survivor_report(popcount)
	GLOB.roundend_shared = roundend_shared_data(popcount, sections)
	for(var/client/C in GLOB.clients)
		show_roundend_report(C, FALSE)
		give_show_report_button(C)
		CHECK_TICK

/// The parts of build_roundend_report(), kept apart so each gets a card
/datum/controller/subsystem/ticker/proc/roundend_sections()
	var/list/sections = list()
	var/list/parts = list(
		list("Round", mode.special_report()),
		list("Antagonists", antag_report()),
		list("Silicon Laws", law_report()),
		list("Station Goals", goal_report()),
		list("Commendations", medal_report()),
	)
	for(var/list/part in parts)
		var/text = part[2]
		if(length(text))
			sections += list(list("title" = part[1], "html" = text))
		CHECK_TICK
	return sections

/datum/controller/subsystem/ticker/proc/roundend_shared_data(popcount, list/sections)
	var/list/data = list()
	data["station"] = station_name()
	data["round_id"] = GLOB.round_id
	data["map"] = SSmapping.config?.map_name
	data["duration"] = round((world.time - round_start_time) / 10)
	data["nuked"] = !!mode.station_was_nuked
	data["integrity"] = popcount["station_integrity"]
	var/list/crew = roundend_roll_call()
	var/rolled = 0
	for(var/list/dept in crew)
		rolled += length(dept["people"])
	// Who joined, or everyone with a part if more (ghost roles and the like never join)
	data["population"] = max(length(GLOB.joined_player_list), rolled)
	data["evacuated"] = !!EMERGENCY_ESCAPED_OR_ENDGAMED
	data["escapees"] = popcount[POPCOUNT_ESCAPEES]
	data["survivors"] = popcount[POPCOUNT_SURVIVORS]
	var/list/ded = SSblackbox.first_death
	if(length(ded))
		data["first_death"] = list("name" = ded["name"], "role" = ded["role"], "area" = ded["area"], "words" = ded["last_words"])
	if(istype(mode, /datum/game_mode/dynamic))
		var/datum/game_mode/dynamic/dynamic = mode
		data["threat"] = dynamic.threat_level
	data["sections"] = sections
	data["crew"] = crew
	return data

/// How someone's round ended, in a word
/proc/roundend_outcome(datum/mind/M)
	var/mob/body = M.current
	if(!body)
		return "Lost"
	if(body.stat == DEAD || isbrain(body))
		return "Died"
	if(EMERGENCY_ESCAPED_OR_ENDGAMED)
		return (body.onCentCom() || body.onSyndieBase()) ? "Escaped" : "Marooned"
	return "Survived"

/// Everyone who had a part in the round, by department, each with how they ended and what they really were
/proc/roundend_roll_call()
	var/static/list/order = list("Command", "Security", "Engineering", "Medical", "Science", "Supply", "Service", "Silicon", "Other")
	var/list/by_department = list()
	for(var/name in order)
		by_department[name] = list()
	var/list/seen = list()
	for(var/datum/mind/M in SSticker.minds)
		if(seen[M] || (!M.assigned_role && !length(M.antag_datums)))
			continue
		seen[M] = TRUE
		var/list/antags = list()
		for(var/datum/antagonist/A in M.antag_datums)
			if(A.show_in_roundend)
				antags += A.name
		var/list/person = list(
			"name" = M.name,
			"job" = M.assigned_role || "-",
			"outcome" = roundend_outcome(M),
			"antag" = antags.Join(", "),
		)
		by_department[roundend_department(M.assigned_role)] += list(person)
	var/list/out = list()
	for(var/name in order)
		var/list/people = by_department[name]
		if(length(people))
			out += list(list("name" = name, "people" = people))
	return out

/proc/roundend_department(job)
	if(!job)
		return "Other"
	if(job in GLOB.command_positions)
		return "Command"
	if(job in GLOB.security_positions)
		return "Security"
	if(job in GLOB.engineering_positions)
		return "Engineering"
	if(job in GLOB.medical_positions)
		return "Medical"
	if(job in GLOB.science_positions)
		return "Science"
	if(job in GLOB.supply_positions)
		return "Supply"
	if(job in GLOB.civilian_positions)
		return "Service"
	if(job in GLOB.nonhuman_positions)
		return "Silicon"
	return "Other"

/// Your own ending: what the stamp says, and who you were
/datum/controller/subsystem/ticker/proc/roundend_personal(client/C)
	var/mob/M = C.mob
	var/datum/mind/mind = M.mind
	if(!mind || isnewplayer(M) || !mind.assigned_role && !length(mind.antag_datums))
		return list("outcome" = "Observed")
	var/mob/dead/observer/ghost = M
	if(istype(ghost) && ghost.started_as_observer)
		return list("outcome" = "Observed")
	return list("outcome" = roundend_outcome(mind), "name" = mind.name, "job" = mind.assigned_role)

/datum/controller/subsystem/ticker/show_roundend_report(client/C, previous = FALSE)
	var/json_name = "data/roundend_reports/[C.ckey].json"
	var/list/report
	if(previous)
		if(!fexists(json_name))
			return ..() // a report from before this window, kept as HTML
		report = json_decode(file2text(json_name))
	else
		if(!GLOB.roundend_shared)
			return ..()
		report = GLOB.roundend_shared.Copy()
		report["personal"] = roundend_personal(C)
		C.verbs -= /client/proc/show_previous_roundend_report
		fdel(json_name)
		text2file(json_encode(report), json_name)
	if(C.roundend_report_ui)
		SStgui.close_uis(C.roundend_report_ui)
		qdel(C.roundend_report_ui)
	C.roundend_report_ui = new(report)
	C.roundend_report_ui.ui_interact(C.mob)
