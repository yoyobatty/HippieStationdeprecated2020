// The borer's Secrete Chemicals window in tgui (interfaces/BorerChems.js): its reservoir, its host, and each chemical by its
// reagent's own name and colour (the old page showed the reagent's type path). Squirting one still goes through the borer's
// Topic() (borer_topic.dm), as the old links did.

/// What a borer can secrete: chem type -> list(name, colour, cost, dose, description), made once
GLOBAL_LIST_EMPTY(borer_chem_menu)

/proc/borer_chem_menu()
	if(length(GLOB.borer_chem_menu))
		return GLOB.borer_chem_menu
	for(var/T in subtypesof(/datum/borer_chem))
		var/datum/borer_chem/C = T
		var/datum/reagent/R = initial(C.chemname)
		if(!ispath(R, /datum/reagent))
			continue
		GLOB.borer_chem_menu += list(list(
			"id" = "[R]",
			"name" = initial(R.name),
			"color" = initial(R.color),
			"cost" = initial(C.chemuse),
			"dose" = initial(C.quantity),
			"desc" = initial(C.chem_desc),
		))
	return GLOB.borer_chem_menu

/mob/living/simple_animal/borer/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	if(user != src)
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "borer_chems", "Borer Chemicals", 460, 560, master_ui, state)
		ui.open()

/mob/living/simple_animal/borer/ui_data(mob/user)
	return list(
		"chemicals" = chemicals,
		"max" = 250, // what Life() fills it to
		"host" = victim ? "[victim]" : null,
		"can_secrete" = (victim && !controlling && !docile && stat == CONSCIOUS) ? TRUE : FALSE,
		"docile" = docile,
	)

/mob/living/simple_animal/borer/ui_static_data(mob/user)
	return list("chems" = borer_chem_menu())

/mob/living/simple_animal/borer/ui_act(action, list/params)
	if(..())
		return
	if(action == "secrete")
		Topic(null, list("borer_use_chem" = params["id"], "src" = REF(src)))
		return TRUE
