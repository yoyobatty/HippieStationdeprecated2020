// Chemistry redone (tgui-next ChemDispenser.js, ChemMaster.js, ChemHeater.js): what the windows need beyond the machines' own
// data, chiefly each reagent's colour, so the dispenser's buttons, beakers and buffers are drawn in the colours of what's in them.
// The machines' actions are their own (the science bots use them too); only the dispenser's recipe form and clear-all are answered
// in the window here, where they were pop-ups and an alert.

/// What a holder has, in a list the windows draw: name, type, volume, colour
/proc/tgui_reagent_list(datum/reagents/holder)
	var/list/listed = list()
	if(!holder)
		return listed
	for(var/datum/reagent/R in holder.reagent_list)
		listed += list(list("name" = R.name, "id" = "[R.type]", "volume" = round(R.volume, 0.01), "color" = R.color))
	return listed

/proc/tgui_reagent_mix_color(datum/reagents/holder)
	if(!holder || !length(holder.reagent_list))
		return null
	return mix_color_from_reagents(holder.reagent_list)

// The dispenser

/obj/machinery/chem_dispenser/ui_data(mob/user)
	. = ..()
	var/list/colors = list()
	for(var/re in dispensable_reagents)
		var/datum/reagent/temp = GLOB.chemical_reagents_list[re]
		if(temp)
			colors[ckey(temp.name)] = temp.color
	.["chemColors"] = colors
	.["beakerContents"] = beaker ? tgui_reagent_list(beaker.reagents) : list()
	.["beakerColor"] = beaker ? tgui_reagent_mix_color(beaker.reagents) : null
	// A list, where it went out as a keyed list (an object in the page)
	var/list/recipes = list()
	for(var/list/recipe in saved_recipes)
		recipes += list(list("name" = recipe["recipe_name"], "contents" = recipe["contents"]))
	.["recipes"] = recipes

/obj/machinery/chem_dispenser/ui_act(action, params, datum/tgui/ui, datum/ui_state/state)
	var/typed_recipe = (action == "add_recipe" && !isnull(params["name"]))
	if(!typed_recipe && !(action == "clear_recipes" && params["confirmed"]))
		return ..()
	if(!ui || ui.status != UI_INTERACTIVE || !is_operational())
		return
	if(action == "clear_recipes")
		saved_recipes = list()
		return TRUE
	// The recipe typed in the window, checked as the old pop-ups' answers were
	var/name = trim(html_encode(params["name"]), MAX_NAME_LEN)
	var/recipe = trim(html_encode(params["recipe"]), MAX_MESSAGE_LEN)
	if(!name || !recipe)
		return
	var/list/first_process = splittext(recipe, ";")
	if(!LAZYLEN(first_process))
		return
	for(var/reagents in first_process)
		var/list/reagent = splittext(reagents, "=")
		if(length(reagent) < 2)
			to_chat(usr, "<span class='danger'>[src] can't read <b>[reagents]</b>: write each as id=amount.</span>")
			return
		var/amt = text2num(reagent[2]) || 0
		var/reagent_id = GLOB.name2reagent[translate_legacy_chem_id(reagent[1])]
		if(!(dispensable_reagents.Find(reagent_id) || (reagent_id && amt < 0)))
			visible_message("<span class='warning'>[src] buzzes.</span>", "<span class='italics'>You hear a faint buzz.</span>")
			to_chat(usr, "<span class='danger'>[src] cannot find Chemical ID: <b>[reagent[1]]</b>!</span>")
			playsound(src, 'sound/machines/buzz-two.ogg', 50, 1)
			return
	saved_recipes += list(list("recipe_name" = name, "contents" = recipe))
	return TRUE

// The ChemMaster

/obj/machinery/chem_master/ui_data(mob/user)
	. = ..()
	.["beakerContents"] = beaker ? tgui_reagent_list(beaker.reagents) : list()
	.["beakerColor"] = beaker ? tgui_reagent_mix_color(beaker.reagents) : null
	.["bufferContents"] = tgui_reagent_list(reagents)
	.["bufferColor"] = tgui_reagent_mix_color(reagents)
	.["bufferMaxVolume"] = reagents.maximum_volume

// The heater

/obj/machinery/chem_heater/ui_data(mob/user)
	. = ..()
	.["beakerContents"] = beaker ? tgui_reagent_list(beaker.reagents) : list()
	.["beakerColor"] = beaker ? tgui_reagent_mix_color(beaker.reagents) : null
