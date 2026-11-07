// The experimentor in a tgui window (tgui-next ResearchMachines.js). Its tests go through its old Topic(), which the science bots
// use too, so its checks and reactions stay the same. The R&D server controller's window is the research dashboard now
// (research_dashboard.dm).

/obj/machinery/rnd/experimentor/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "experimentor", "Experimentor", 520, 520, master_ui, state)
		ui.open()

/obj/machinery/rnd/experimentor/ui_data(mob/user)
	var/list/data = list()
	data["linked"] = !!linked_console
	data["item"] = loaded_item ? loaded_item.name : null
	data["relic"] = istype(loaded_item, /obj/item/relic)
	data["cooling"] = !!recentlyExperimented
	var/list/boosts = list()
	if(loaded_item)
		var/list/listin = techweb_item_boost_check(src)
		for(var/node_id in listin)
			var/datum/techweb_node/N = SSresearch.techweb_node_by_id(node_id)
			if(!SSresearch.science_tech.visible_nodes[N.id] && !SSresearch.science_tech.researched_nodes[N.id])
				continue
			var/state = "Boost available"
			if(SSresearch.science_tech.researched_nodes[N.id])
				state = "Already researched"
			else if(SSresearch.science_tech.boosted_nodes[N.id])
				state = "Already boosted"
			var/points = 0
			var/boost = listin[node_id]
			if(islist(boost))
				for(var/point_type in boost)
					points += boost[point_type]
			else if(isnum(boost))
				points = boost
			boosts += list(list("name" = N.display_name, "points" = points, "state" = state))
	data["boosts"] = boosts
	return data

/obj/machinery/rnd/experimentor/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("search", "eject")
			Topic(null, list("function" = action))
		if("test")
			var/test = text2num(params["test"])
			if(!loaded_item || !(test in 1 to 7))
				return
			Topic(null, list("function" = "[test]", "item" = REF(loaded_item)))
	return TRUE
