// hippie -- the crew manifest and a character's Notes in tgui (interfaces/CrewManifest.js, interfaces/MindNotes.js).
// The manifest is the one window behind the lobby's Manifest button, a ghost's View Crew Manifest and the AI's and pAI's
// manifest buttons: the records by department as get_manifest() sorted them (a head under Command and their department), with
// a search. Notes are show_memory()'s page: the notes, the antagonists' notes, the objectives with their conspirators, and a box
// to add a note as Add Note does.

// ---------------------------------------------------------------------------------------------
// The crew manifest
// ---------------------------------------------------------------------------------------------

GLOBAL_DATUM_INIT(crew_manifest_window, /datum/crew_manifest_window, new)

/datum/crew_manifest_window

/datum/crew_manifest_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "crew_manifest", "Crew Manifest", 460, 600, master_ui, state)
		ui.open()

/datum/crew_manifest_window/ui_data(mob/user)
	var/list/departments = list(
		list("name" = "Command", "jobs" = GLOB.command_positions),
		list("name" = "Security", "jobs" = GLOB.security_positions),
		list("name" = "Engineering", "jobs" = GLOB.engineering_positions),
		list("name" = "Medical", "jobs" = GLOB.medical_positions),
		list("name" = "Science", "jobs" = GLOB.science_positions),
		list("name" = "Supply", "jobs" = GLOB.supply_positions),
		list("name" = "Service", "jobs" = GLOB.civilian_positions),
		list("name" = "Silicon", "jobs" = GLOB.nonhuman_positions),
	)
	var/list/out = list()
	for(var/list/dept in departments)
		out[dept["name"]] = list()
	out["Other"] = list()
	var/total = 0
	for(var/datum/data/record/R in GLOB.data_core.general)
		var/name = R.fields["name"]
		var/rank = R.fields["rank"]
		var/head = (rank in GLOB.command_positions)
		var/placed = FALSE
		for(var/list/dept in departments)
			if(rank in dept["jobs"])
				out[dept["name"]] += list(list("name" = name, "rank" = rank, "head" = head))
				placed = TRUE
		if(!placed)
			out["Other"] += list(list("name" = name, "rank" = rank, "head" = FALSE))
		total++
	var/list/listed = list()
	for(var/dept_name in out)
		listed += list(list("name" = dept_name, "crew" = out[dept_name]))
	return list("departments" = listed, "total" = total)

/mob/dead/new_player/ViewManifest()
	GLOB.crew_manifest_window.ui_interact(src)

/mob/dead/observer/view_manifest()
	set name = "View Crew Manifest"
	set category = "Ghost"
	GLOB.crew_manifest_window.ui_interact(src)

/mob/living/silicon/ai_roster()
	GLOB.crew_manifest_window.ui_interact(src)

// ---------------------------------------------------------------------------------------------
// Notes
// ---------------------------------------------------------------------------------------------

/datum/mind
	var/datum/mind_notes_window/notes_window

/datum/mind/show_memory(mob/recipient, window = 1)
	if(!window)
		return ..()
	if(!recipient)
		recipient = current
	if(!recipient)
		return
	if(!notes_window)
		notes_window = new(src)
	notes_window.ui_interact(recipient)

/datum/mind_notes_window
	var/datum/mind/mind

/datum/mind_notes_window/New(datum/mind/owner)
	mind = owner

/datum/mind_notes_window/Destroy()
	mind = null
	return ..()

/datum/mind_notes_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "mind_notes", "Notes", 480, 560, master_ui, state)
		ui.open()

// Only the mind's own mob (or its ghost) reads them
/datum/mind_notes_window/ui_status(mob/user, datum/ui_state/state)
	if(!mind || user.mind != mind)
		return UI_CLOSE
	return UI_INTERACTIVE

/datum/mind_notes_window/ui_data(mob/user)
	. = list()
	if(!mind)
		return
	.["name"] = mind.current ? mind.current.real_name : mind.name
	var/list/notes = list()
	for(var/line in splittext("[mind.memory]", regex("<br\\s*/?>", "i")))
		line = trim(comm_plain_text(line))
		if(length(line))
			notes += line
	.["notes"] = notes
	var/list/antag_notes = list()
	var/list/all_objectives = list()
	for(var/datum/antagonist/A in mind.antag_datums)
		var/text = trim(comm_plain_text(A.antag_memory))
		if(length(text))
			antag_notes += list(list("role" = A.name, "text" = text))
		all_objectives |= A.objectives
	.["antag_notes"] = antag_notes
	var/list/objectives = list()
	for(var/datum/objective/objective in all_objectives)
		var/list/others = list()
		for(var/datum/mind/M in objective.get_owners() - mind)
			others += M.name
		objectives += list(list("text" = objective.explanation_text, "conspirators" = others))
	.["objectives"] = objectives
	var/mob/M = mind.current
	.["can_add"] = !!M

/datum/mind_notes_window/ui_act(action, list/params)
	if(..())
		return
	if(action == "add" && mind && usr.mind == mind)
		// /mob/verb/add_memory() with the text from the window
		if(world.time < usr.memory_throttle_time)
			return
		usr.memory_throttle_time = world.time + 5 SECONDS
		var/msg = trim(copytext_char("[params["text"]]", 1, MAX_MESSAGE_LEN))
		if(!msg)
			return
		mind.store_memory(sanitize(msg))
		return TRUE
