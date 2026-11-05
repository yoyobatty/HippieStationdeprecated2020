// hippie -- the pipe, disposal pipe and transit tube dispensers share a tgui window: what each one makes, in the RPD's groups
// and with its pictures, the bent pipe as before, and the piping layer. A click makes one through the dispenser's own
// Topic(), so the wait between pieces and the checks (bolted down, in reach, room for a disposal pipe) are the old ones.

/obj/machinery/pipedispenser/ui_base_html(html)
	var/datum/asset/spritesheet/assets = get_asset_datum(/datum/asset/spritesheet/pipes)
	. = replacetext(html, "<!--customheadhtml-->", assets.css_tag())

/obj/machinery/pipedispenser/disposal/interact(mob/user)
	ui_interact(user)

/obj/machinery/pipedispenser/disposal/transit_tube/interact(mob/user)
	ui_interact(user)

/obj/machinery/pipedispenser/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		var/datum/asset/assets = get_asset_datum(/datum/asset/spritesheet/pipes)
		assets.send(user)
		ui = new(user, src, ui_key, "pipe_dispenser", name, 460, dispenser_window_height, master_ui, state)
		ui.open()

/obj/machinery/pipedispenser
	/// Tall enough for its list
	var/dispenser_window_height = 600

/obj/machinery/pipedispenser/disposal
	dispenser_window_height = 290

/obj/machinery/pipedispenser/disposal/transit_tube
	dispenser_window_height = 350

/// What this dispenser makes, by group
/obj/machinery/pipedispenser/proc/dispenser_recipes()
	return GLOB.atmos_pipe_recipes

/obj/machinery/pipedispenser/disposal/dispenser_recipes()
	return GLOB.disposal_pipe_recipes

/obj/machinery/pipedispenser/disposal/transit_tube/dispenser_recipes()
	return GLOB.transit_tube_recipes

/obj/machinery/pipedispenser/ui_static_data(mob/user)
	var/list/data = list()
	var/list/groups = list()
	var/list/recipes = dispenser_recipes()
	for(var/category in recipes)
		var/list/items = list()
		var/index = 0
		for(var/datum/pipe_info/info as anything in recipes[category])
			index++
			items += list(list(
				"name" = info.name,
				"index" = index,
				"icon_state" = info.icon_state,
				"bendable" = info.dirtype == PIPE_BENDABLE,
			))
		groups += list(list("name" = category, "items" = items))
	data["groups"] = groups
	data["layers"] = (type == /obj/machinery/pipedispenser) ? PIPING_LAYER_MAX : 0
	return data

/obj/machinery/pipedispenser/ui_data(mob/user)
	var/list/data = list()
	data["piping_layer"] = piping_layer
	data["anchored"] = anchored
	return data

/obj/machinery/pipedispenser/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("layer")
			var/layer = text2num(params["layer"])
			if(layer && type == /obj/machinery/pipedispenser)
				piping_layer = clamp(layer, PIPING_LAYER_MIN, PIPING_LAYER_MAX)
		if("make")
			// Only what this dispenser lists
			var/list/recipes = dispenser_recipes()
			var/list/group = recipes[params["group"]]
			var/index = text2num(params["index"])
			if(!islist(group) || !index || index < 1 || index > length(group))
				return
			var/datum/pipe_info/info = group[index]
			dispense(info, params["bent"] && info.dirtype == PIPE_BENDABLE)
	return TRUE

/// One of these, as the old window's link for it made it
/obj/machinery/pipedispenser/proc/dispense(datum/pipe_info/info, bent)
	if(istype(info, /datum/pipe_info/meter))
		Topic(null, list("makemeter" = "1"))
		return
	var/list/href = list("makepipe" = "[info.id]")
	if(bent)
		href["dir"] = "[NORTHEAST]"
	Topic(null, href)

/obj/machinery/pipedispenser/disposal/dispense(datum/pipe_info/info, bent)
	var/list/href = list("dmake" = "[info.id]")
	if(bent)
		href["dir"] = "[NORTHEAST]"
	Topic(null, href)

/obj/machinery/pipedispenser/disposal/transit_tube/dispense(datum/pipe_info/info, bent)
	var/static/list/tube_numbers = list(
		/obj/structure/c_transit_tube = TRANSIT_TUBE_STRAIGHT,
		/obj/structure/c_transit_tube/crossing = TRANSIT_TUBE_STRAIGHT_CROSSING,
		/obj/structure/c_transit_tube/curved = TRANSIT_TUBE_CURVED,
		/obj/structure/c_transit_tube/diagonal = TRANSIT_TUBE_DIAGONAL,
		/obj/structure/c_transit_tube/diagonal/crossing = TRANSIT_TUBE_DIAGONAL_CROSSING,
		/obj/structure/c_transit_tube/junction = TRANSIT_TUBE_JUNCTION,
		/obj/structure/c_transit_tube/station = TRANSIT_TUBE_STATION,
		/obj/structure/c_transit_tube/station/reverse = TRANSIT_TUBE_TERMINUS,
		/obj/structure/c_transit_tube_pod = TRANSIT_TUBE_POD,
	)
	if(isnull(tube_numbers[info.id]))
		return
	Topic(null, list("tube" = "[tube_numbers[info.id]]"))
