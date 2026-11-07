// A silicon's law display in tgui (interfaces/SiliconLaws.js): every law with its number and kind, and a switch for whether
// State Laws says it, then State Laws itself. The switches are the same lawcheck/ioncheck/hackedcheck/devillawcheck lists the old
// page set, through the same Topic(); statelaws() is unchanged. The window is its own datum, so a silicon's other windows
// (a pAI's, say) keep their ui procs.

/mob/living/silicon
	var/datum/silicon_law_panel/law_panel

/mob/living/silicon/checklaws()
	law_check_defaults()
	if(!law_panel)
		law_panel = new(src)
	law_panel.ui_interact(src)

/// The old page's defaults, without growing the lists on every open as it did: law 0 and hacked laws not stated, ion laws and
/// the rest stated.
/mob/living/silicon/proc/law_check_defaults()
	if(!laws)
		return
	if(laws.devillaws)
		if(devillawcheck.len < laws.devillaws.len)
			devillawcheck.len = laws.devillaws.len
		for(var/index in 1 to laws.devillaws.len)
			if(!devillawcheck[index])
				devillawcheck[index] = "No"
	var/numbered = 0
	for(var/law in laws.inherent + laws.supplied)
		if(length(law))
			numbered++
	if(lawcheck.len < numbered + 1)
		lawcheck.len = numbered + 1
	if(!lawcheck[1])
		lawcheck[1] = "No"
	for(var/index in 2 to numbered + 1)
		if(!lawcheck[index])
			lawcheck[index] = "Yes"
	if(hackedcheck.len < laws.hacked.len)
		hackedcheck.len = laws.hacked.len
	for(var/index in 1 to laws.hacked.len)
		if(!hackedcheck[index])
			hackedcheck[index] = "No"
	if(ioncheck.len < laws.ion.len)
		ioncheck.len = laws.ion.len
	for(var/index in 1 to laws.ion.len)
		if(!ioncheck[index])
			ioncheck[index] = "Yes"

/datum/silicon_law_panel
	var/datum/weakref/owner_ref

/datum/silicon_law_panel/New(mob/living/silicon/owner)
	owner_ref = WEAKREF(owner)

/datum/silicon_law_panel/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	if(user != owner_ref?.resolve())
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "silicon_laws", "Laws", 520, 520, master_ui, state)
		ui.open()

/datum/silicon_law_panel/ui_status(mob/user, datum/ui_state/state)
	return user == owner_ref?.resolve() ? UI_INTERACTIVE : UI_CLOSE

/datum/silicon_law_panel/ui_data(mob/user)
	var/mob/living/silicon/S = owner_ref?.resolve()
	var/list/out = list()
	if(!S?.laws)
		return list("laws" = out)
	var/datum/ai_laws/L = S.laws
	S.law_check_defaults()
	if(L.devillaws)
		for(var/index in 1 to L.devillaws.len)
			out += list(list("kind" = "devil", "number" = "666", "text" = L.devillaws[index], "stated" = S.devillawcheck[index] == "Yes", "key" = "lawdevil", "index" = index))
	if(L.zeroth)
		out += list(list("kind" = "zeroth", "number" = "0", "text" = L.zeroth, "stated" = S.lawcheck[1] == "Yes", "key" = "lawc", "index" = 0))
	for(var/index in 1 to L.hacked.len)
		if(length(L.hacked[index]))
			out += list(list("kind" = "hacked", "number" = "#@!", "text" = L.hacked[index], "stated" = S.hackedcheck[index] == "Yes", "key" = "lawh", "index" = index))
	for(var/index in 1 to L.ion.len)
		if(length(L.ion[index]))
			out += list(list("kind" = "ion", "number" = "!%&", "text" = L.ion[index], "stated" = S.ioncheck[index] == "Yes", "key" = "lawi", "index" = index))
	var/number = 1
	for(var/law in L.inherent)
		if(length(law))
			out += list(list("kind" = "inherent", "number" = "[number]", "text" = law, "stated" = S.lawcheck[number + 1] == "Yes", "key" = "lawc", "index" = number))
			number++
	for(var/law in L.supplied)
		if(length(law))
			out += list(list("kind" = "supplied", "number" = "[number]", "text" = law, "stated" = S.lawcheck[number + 1] == "Yes", "key" = "lawc", "index" = number))
			number++
	return list("laws" = out, "lawset" = L.name, "radio" = S.radiomod)

/datum/silicon_law_panel/ui_act(action, list/params)
	if(..())
		return
	var/mob/living/silicon/S = owner_ref?.resolve()
	if(!S || usr != S)
		return
	switch(action)
		if("toggle")
			var/key = params["key"]
			if(!(key in list("lawc", "lawi", "lawh", "lawdevil")))
				return
			S.Topic(null, list("[key]" = "[text2num(params["index"])]"))
		if("state")
			INVOKE_ASYNC(S, TYPE_PROC_REF(/mob/living/silicon, statelaws)) // it says them a second apart
		else
			return
	return TRUE
