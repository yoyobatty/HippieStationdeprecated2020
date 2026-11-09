// Integrated circuits on tgui-next (the user's rulings, 2026-11-07):
// - an assembly is a node graph (CircuitAssembly.js): every component a box with its pins, wires drawn between them,
//   boxes dragged where you like (graph_x/graph_y, kept on the circuit);
// - the tool rules stay: a multitool or wirer wires, a multitool sets data (typed in the window, no popups), a debugger
//   writes its memory; the window says what the tool in your hand will do;
// - the printer is a shop grid with pictures (CircuitPrinter.js), and a program is pasted into the window;
// - the analyzer's code comes up in a window with the code selected (CircuitCode.js).

/// The sprite sheet key of a printable thing: its type without /obj/item/, slashes as dashes
/proc/circuit_icon_key(path)
	return replacetext(replacetext("[path]", "/obj/item/", ""), "/", "-")

/datum/asset/spritesheet/circuits
	name = "circuits"
	build_after_init = TRUE

/datum/asset/spritesheet/circuits/register()
	var/list/done = list()
	for(var/category in SScircuit.circuit_fabricator_recipe_list)
		for(var/path in SScircuit.circuit_fabricator_recipe_list[category])
			insert_circuit_icon(path, done)
	for(var/path in SScircuit.cached_components) // built-in parts show in the graph too
		insert_circuit_icon(path, done)
	return ..()

/datum/asset/spritesheet/circuits/proc/insert_circuit_icon(path, list/done)
	var/key = circuit_icon_key(path)
	if(done[key])
		return
	done[key] = TRUE
	var/atom/A = path
	var/icon_file = initial(A.icon)
	var/icon_state = initial(A.icon_state)
	if(!icon_file || !(icon_state in spritesheet_icon_states(icon_file)))
		return
	// iconforge makes the sheet from these (spritesheet_forge.dm), scaled to 32x32 if bigger
	Insert(key, icon_file, icon_state, SOUTH, 1, FALSE, spritesheet_scale_to_32(icon_file))

/// The page head for the windows that show parts' pictures
/proc/circuit_sheet_html(html)
	var/datum/asset/spritesheet/sheet = get_asset_datum(/datum/asset/spritesheet/circuits)
	return replacetext(html, "<!--customheadhtml-->", sheet.css_tag())

/proc/circuit_send_sheet(mob/user)
	if(!user.client) // bots click the printer through Topic(), which reopens its window; nothing to send them
		return
	var/datum/asset/assets = get_asset_datum(/datum/asset/spritesheet/circuits)
	assets.send(user)

// ---------------------------------------------------------------------------------------------------------------
// Pins

/// What a pin holds, as plain text (display_data() is HTML)
/proc/circuit_pin_text(value)
	if(isnull(value))
		return "null"
	if(istext(value))
		return "\"[value]\""
	if(islist(value))
		var/list/L = value
		return "list\[[L.len]\]"
	if(isweakref(value))
		var/datum/weakref/W = value
		var/atom/A = W.resolve()
		return istype(A) ? "[A.name] \[Ref\]" : "null"
	return "[value]"

/// What the window offers for setting a pin by hand
/datum/integrated_io/proc/ui_kind()
	return "any"
/datum/integrated_io/activate/ui_kind()
	return "pulse"
/datum/integrated_io/boolean/ui_kind()
	return "bool"
/datum/integrated_io/char/ui_kind()
	return "char"
/datum/integrated_io/color/ui_kind()
	return "color"
/datum/integrated_io/dir/ui_kind()
	return "dir"
/datum/integrated_io/index/ui_kind()
	return "index"
/datum/integrated_io/lists/ui_kind()
	return "list"
/datum/integrated_io/number/ui_kind()
	return "number"
/datum/integrated_io/ref/ui_kind()
	return "ref"
/datum/integrated_io/selfref/ui_kind()
	return "self"
/datum/integrated_io/string/ui_kind()
	return "string"

/datum/integrated_io/proc/ui_pin_data()
	var/list/links = list()
	for(var/datum/integrated_io/L in linked)
		links += REF(L)
	. = list(
		"ref" = REF(src),
		"name" = name,
		"type" = display_pin_type(),
		"kind" = ui_kind(),
		"value" = circuit_pin_text(data),
		"links" = links,
	)
	if(istext(data) && ui_kind() == "color")
		.["color"] = data
	if(islist(data))
		var/list/items = list()
		var/list/held = data // data is declared a weakref but holds anything
		for(var/item in held)
			items += circuit_pin_text(item)
		.["items"] = items

/// A value typed in the window, read as the pin's kind would ask for it; the second item is FALSE when it isn't one
/datum/integrated_io/proc/ui_parse(as_type, value)
	switch(as_type)
		if("string")
			return list(copytext(html_encode("[value]"), 1, MAX_MESSAGE_LEN), TRUE)
		if("char")
			return list(html_encode(copytext_char("[value]", 1, 2)), TRUE)
		if("number")
			var/n = text2num(value)
			return list(n, isnum(n))
		if("color")
			var/c = uppertext("[value]")
			return list(c, findtext(c, regex("^#\[0-9A-F]{6}$")) > 0)
		if("null")
			return list(null, TRUE)
	return list(null, FALSE)

/// Sets a pin from the window, what ask_for_pin_data() asked for in popups
/datum/integrated_io/proc/ui_write(mob/user, as_type, value)
	var/kind = ui_kind()
	switch(kind)
		if("any")
			if(!(as_type in list("string", "number", "null")))
				return
		if("string", "char", "color", "number")
			as_type = (as_type == "null") ? "null" : kind
		if("dir", "index")
			as_type = "number"
		else
			return
	var/list/parsed = ui_parse(as_type, value)
	if(!parsed[2])
		to_chat(user, "<span class='warning'>That isn't a valid [as_type].</span>")
		return
	var/new_data = parsed[1]
	write_data_to_pin(new_data)
	if(isnull(new_data))
		to_chat(user, "<span class='notice'>You clear the pin's memory.</span>")
	else
		to_chat(user, "<span class='notice'>You input [new_data] into the pin.</span>")

// ---------------------------------------------------------------------------------------------------------------
// Components (the graph's nodes)

/obj/item/integrated_circuit
	/// Where the component sits in its assembly's graph (null: laid out by the window)
	var/graph_x
	var/graph_y

/obj/item/integrated_circuit/proc/ui_node_data()
	var/list/ins = list()
	var/list/outs = list()
	var/list/pulse_in = list()
	var/list/pulse_out = list()
	for(var/datum/integrated_io/I in inputs)
		ins += list(I.ui_pin_data())
	for(var/datum/integrated_io/O in outputs)
		outs += list(O.ui_pin_data())
	for(var/datum/integrated_io/A in activators)
		if(A.data)
			pulse_out += list(A.ui_pin_data())
		else
			pulse_in += list(A.ui_pin_data())
	return list(
		"ref" = REF(src),
		"name" = displayed_name,
		"type" = name,
		"removable" = removable,
		"x" = graph_x,
		"y" = graph_y,
		"icon" = circuit_icon_key(type),
		"desc" = desc,
		"ext" = extended_desc,
		"complexity" = complexity,
		"size" = size,
		"cooldown" = cooldown_per_use / 10,
		"ext_cooldown" = ext_cooldown / 10,
		"power_idle" = power_draw_idle,
		"power_use" = power_draw_per_use,
		"inputs" = ins,
		"outputs" = outs,
		"pulse_in" = pulse_in,
		"pulse_out" = pulse_out,
	)

/// What the tool in the user's active hand will do to a pin
/proc/circuit_tool_data(mob/user)
	var/obj/item/I = user.get_active_held_item()
	if(istype(I, /obj/item/multitool))
		var/obj/item/multitool/M = I
		return list("kind" = "multitool", "name" = M.name, "selected" = M.selected_io ? REF(M.selected_io) : null)
	if(istype(I, /obj/item/integrated_electronics/wirer))
		var/obj/item/integrated_electronics/wirer/W = I
		return list("kind" = "wirer", "name" = W.name, "mode" = W.mode, "selected" = W.selected_io ? REF(W.selected_io) : null)
	if(istype(I, /obj/item/integrated_electronics/debugger))
		var/obj/item/integrated_electronics/debugger/D = I
		var/mode = "write"
		if(D.accepting_refs)
			mode = "ref"
		else if(D.copy_values)
			mode = "copy"
		else if(D.copy_id)
			mode = "id"
		return list("kind" = "debugger", "name" = D.name, "mode" = mode, "data" = circuit_pin_text(D.data_to_write))
	return list("kind" = "none")

/// The pin buttons and wires of the graph, for one component; TRUE when the action was a pin's
/obj/item/integrated_circuit/proc/ui_pin_act(action, list/params, mob/user)
	var/datum/integrated_io/pin = locate(params["pin"]) in inputs + outputs + activators
	if(!pin)
		return FALSE
	var/obj/item/held = user.get_active_held_item()
	var/is_multitool = istype(held, /obj/item/multitool)
	var/is_wirer = istype(held, /obj/item/integrated_electronics/wirer)
	switch(action)
		if("wire")
			if(!is_multitool && !is_wirer)
				to_chat(user, "<span class='warning'>You need a multitool or a circuit wirer to wire pins.</span>")
				return TRUE
			pin.handle_wire(null, held, "wire", user)
		if("unwire")
			var/datum/integrated_io/link = locate(params["link"]) in pin.linked
			if(!link)
				return TRUE
			if(is_wirer)
				var/obj/item/integrated_electronics/wirer/W = held
				if(W.mode != "unwire" && W.mode != "unwiring")
					to_chat(user, "<span class='warning'>Set \the [W] to unwire first.</span>")
					return TRUE
				W.selected_io = null
				W.mode = "unwire"
				W.wire(pin, user)
				W.wire(link, user)
			else if(is_multitool)
				pin.handle_wire(link, held, "unwire", user)
			else
				to_chat(user, "<span class='warning'>You need a multitool or a circuit wirer to cut a wire.</span>")
		if("data") // the pin's value clicked
			if(istype(held, /obj/item/integrated_electronics/debugger))
				pin.handle_wire(null, held, "data", user)
			else if(is_multitool)
				if(pin.ui_kind() in list("bool", "ref", "self", "pulse")) // no popup in these
					pin.handle_wire(null, held, "data", user)
			else
				to_chat(user, "<span class='warning'>You need a multitool or a circuit debugger to set data.</span>")
		if("set")
			if(!is_multitool)
				to_chat(user, "<span class='warning'>You need a multitool to type data into a pin.</span>")
				return TRUE
			pin.ui_write(user, params["type"], params["value"])
		if("list_add", "list_edit", "list_remove", "list_swap", "list_clear")
			if(!is_multitool)
				to_chat(user, "<span class='warning'>You need a multitool to edit a list.</span>")
				return TRUE
			if(!istype(pin, /datum/integrated_io/lists))
				return TRUE
			var/datum/integrated_io/lists/LP = pin
			LP.ui_list_act(action, params, user)
		else
			return FALSE
	if(assembly)
		assembly.add_allowed_scanner(user.ckey)
	return TRUE

/datum/integrated_io/lists/proc/ui_list_act(action, list/params, mob/user)
	var/list/my_list = data
	var/pos = text2num(params["pos"])
	switch(action)
		if("list_add", "list_edit")
			var/list/parsed = ui_parse(params["type"], params["value"])
			if(!parsed[2] || isnull(parsed[1]))
				to_chat(user, "<span class='warning'>That isn't a valid entry.</span>")
				return
			if(action == "list_add")
				Add(parsed[1])
			else if(pos >= 1 && pos <= my_list.len)
				my_list[pos] = parsed[1]
		if("list_remove")
			if(pos >= 1 && pos <= my_list.len)
				my_list.Cut(pos, pos + 1)
		if("list_swap")
			var/other = text2num(params["other"])
			if(pos >= 1 && pos <= my_list.len && other >= 1 && other <= my_list.len && pos != other)
				my_list.Swap(pos, other)
		if("list_clear")
			clear_list(user)

/// Window actions every graph has (one loose circuit or a whole assembly); TRUE when handled
/obj/item/integrated_circuit/proc/ui_node_act(action, list/params, mob/user)
	switch(action)
		if("move")
			var/x = text2num(params["x"])
			var/y = text2num(params["y"])
			if(isnum(x) && isnum(y))
				graph_x = clamp(round(x), 0, 4000)
				graph_y = clamp(round(y), 0, 4000)
			return TRUE
		if("rename_component")
			if(!removable && assembly)
				return TRUE
			var/input = reject_bad_name(params["name"], TRUE)
			if(!input)
				input = name
			to_chat(user, "<span class='notice'>The circuit '[name]' is now labeled '[input]'.</span>")
			displayed_name = input
			if(assembly)
				assembly.add_allowed_scanner(user.ckey)
			return TRUE
		if("scan")
			var/obj/held_item = user.get_active_held_item()
			if(istype(held_item, /obj/item/integrated_electronics/debugger))
				var/obj/item/integrated_electronics/debugger/D = held_item
				if(D.accepting_refs)
					D.afterattack(src, user, TRUE)
				else
					to_chat(user, "<span class='warning'>The debugger's 'ref scanner' needs to be on.</span>")
			else
				to_chat(user, "<span class='warning'>You need a debugger set to 'ref' mode to do that.</span>")
			return TRUE
		if("cancel_wire")
			var/obj/item/held = user.get_active_held_item()
			if(istype(held, /obj/item/multitool))
				var/obj/item/multitool/M = held
				M.selected_io = null
				M.update_icon()
			else if(istype(held, /obj/item/integrated_electronics/wirer))
				var/obj/item/integrated_electronics/wirer/W = held
				if(W.selected_io)
					W.attack_self(user) // the wirer's own way of letting go
			return TRUE
	return ui_pin_act(action, params, user)

// A circuit outside an assembly gets the same window with one node

/obj/item/integrated_circuit/interact(mob/user)
	if(assembly)
		assembly.interact(user, src)
		return
	if(!check_interactivity(user))
		return
	ui_interact(user)

/obj/item/integrated_circuit/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
									datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(assembly)
		assembly.interact(user, src)
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		circuit_send_sheet(user)
		ui = new(user, src, ui_key, "circuit_assembly", displayed_name, 720, 520, master_ui, state)
		ui.open()

/obj/item/integrated_circuit/ui_base_html(html)
	return circuit_sheet_html(html)

/obj/item/integrated_circuit/ui_data(mob/user)
	var/list/data = list()
	data["loose"] = TRUE
	data["name"] = displayed_name
	data["components"] = list(ui_node_data())
	data["tool"] = circuit_tool_data(user)
	return data

/obj/item/integrated_circuit/ui_act(action, list/params)
	if(..())
		return
	if(assembly) // put in an assembly while the window was open
		return
	return ui_node_act(action, params, usr)

// ---------------------------------------------------------------------------------------------------------------
// Assemblies

/obj/item/electronic_assembly
	/// REF(user) -> REF(circuit): which part the window picks when it opens (examining a part inside)
	var/list/ui_focus

/obj/item/electronic_assembly/interact(mob/user, obj/item/integrated_circuit/circuit)
	if(!check_interactivity(user))
		return
	if(istype(circuit) && (circuit in assembly_components) && !SStgui.get_open_ui(user, src, "main"))
		LAZYSET(ui_focus, REF(user), REF(circuit))
	ui_interact(user)

/obj/item/electronic_assembly/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
									datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		circuit_send_sheet(user)
		ui = new(user, src, ui_key, "circuit_assembly", name, 980, 660, master_ui, state)
		ui.open()

/obj/item/electronic_assembly/ui_base_html(html)
	return circuit_sheet_html(html)

/// A brain or pAI wired into this assembly (smart.dm) works its window from inside
/obj/item/electronic_assembly/proc/mind_inside(mob/user)
	if(!user.remote_control || !istype(user.remote_control, /obj/item/integrated_circuit))
		return FALSE
	return (user.remote_control in assembly_components)

/obj/item/electronic_assembly/ui_status(mob/user, datum/ui_state/state)
	if(mind_inside(user) && user.stat == CONSCIOUS)
		return UI_INTERACTIVE
	return ..()

/obj/item/electronic_assembly/ui_data(mob/user)
	var/list/data = list()
	data["loose"] = FALSE
	data["name"] = name
	data["opened"] = opened
	data["space"] = return_total_size()
	data["max_space"] = max_components
	data["complexity"] = return_total_complexity()
	data["max_complexity"] = max_complexity
	if(battery)
		data["cell"] = list("charge" = round(battery.charge, 0.1), "max" = battery.maxcharge, "percent" = round(battery.percent(), 0.1))
	var/list/nodes = list()
	for(var/obj/item/integrated_circuit/C in assembly_components)
		nodes += list(C.ui_node_data())
	data["components"] = nodes
	data["tool"] = circuit_tool_data(user)
	var/focus = LAZYACCESS(ui_focus, REF(user))
	if(focus)
		data["focus"] = focus
		data["focus_time"] = world.time
		LAZYREMOVE(ui_focus, REF(user))
	return data

/obj/item/electronic_assembly/ui_act(action, list/params)
	if(..())
		return
	var/mob/user = usr
	switch(action)
		if("rename")
			var/input = reject_bad_name(params["name"], TRUE)
			if(input)
				to_chat(user, "<span class='notice'>The machine now has a label reading '[input]'.</span>")
				name = input
			return TRUE
		if("remove_cell")
			if(!battery)
				to_chat(user, "<span class='warning'>There's no power cell to remove from \the [src].</span>")
			else
				battery.forceMove(drop_location())
				playsound(src, 'sound/items/Crowbar.ogg', 50, 1)
				to_chat(user, "<span class='notice'>You pull \the [battery] out of \the [src]'s power supplier.</span>")
				battery = null
				diag_hud_set_circuitstat()
			return TRUE
		if("arrange") // "ref,x,y;ref,x,y": the window's own layout
			for(var/entry in splittext("[params["layout"]]", ";"))
				var/list/bits = splittext(entry, ",")
				if(bits.len != 3)
					continue
				var/obj/item/integrated_circuit/C = locate(bits[1]) in assembly_components
				if(C)
					C.ui_node_act("move", list("x" = bits[2], "y" = bits[3]), user)
			return TRUE
	var/obj/item/integrated_circuit/component = locate(params["ref"]) in assembly_components
	if(!component)
		return
	switch(action)
		if("remove", "interact", "order")
			// Built-in parts aren't removed, used or moved about (as the old window)
			if(!component.removable)
				return TRUE
			add_allowed_scanner(user.ckey)
			switch(action)
				if("remove")
					try_remove_component(component, user)
				if("interact")
					var/obj/item/I = user.get_active_held_item()
					if(istype(I))
						I.melee_attack_chain(user, component)
					else
						component.attack_hand(user)
				if("order")
					var/first_removable_pos = 0
					for(var/obj/item/integrated_circuit/C in assembly_components)
						first_removable_pos++
						if(C.removable)
							break
					var/pos = assembly_components.Find(component)
					var/new_pos = clamp(pos + (params["dir"] == "up" ? -1 : 1), first_removable_pos, assembly_components.len)
					if(new_pos != pos)
						assembly_components.Swap(pos, new_pos)
			return TRUE
	return component.ui_node_act(action, params, user)

// ---------------------------------------------------------------------------------------------------------------
// The printer

/obj/item/integrated_circuit_printer/interact(mob/user)
	if(!(in_range(src, user) || issilicon(user)))
		return
	ui_interact(user)

/obj/item/integrated_circuit_printer/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
									datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		circuit_send_sheet(user)
		ui = new(user, src, ui_key, "circuit_printer", name, 820, 640, master_ui, state)
		ui.open()

/obj/item/integrated_circuit_printer/ui_base_html(html)
	return circuit_sheet_html(html)

/// What printing a type costs, as Topic() charges it
/proc/circuit_print_cost(path)
	if(ispath(path, /obj/item/electronic_assembly))
		var/obj/item/electronic_assembly/E = SScircuit.cached_assemblies[path]
		return E ? E.materials[MAT_METAL] : 400
	if(ispath(path, /obj/item/integrated_circuit))
		var/obj/item/integrated_circuit/IC = SScircuit.cached_components[path]
		return IC ? IC.materials[MAT_METAL] : 400
	return 400

/// TRUE when the printer's lists offer this type at all; research parts need the upgrade (as the old crossed-out lines)
/obj/item/integrated_circuit_printer/proc/can_print_type(path)
	var/listed = FALSE
	for(var/category in SScircuit.circuit_fabricator_recipe_list)
		if(path in SScircuit.circuit_fabricator_recipe_list[category])
			listed = TRUE
			break
	if(!listed)
		return FALSE
	if(ispath(path, /obj/item/integrated_circuit) && !upgraded && !debug)
		var/obj/item/integrated_circuit/IC = path
		if((initial(IC.spawn_flags) & IC_SPAWN_RESEARCH) && !(initial(IC.spawn_flags) & IC_SPAWN_DEFAULT))
			return FALSE
	return TRUE

/obj/item/integrated_circuit_printer/ui_static_data(mob/user)
	var/list/data = list()
	var/list/categories = list()
	for(var/category in SScircuit.circuit_fabricator_recipe_list)
		var/list/items = list()
		for(var/path in SScircuit.circuit_fabricator_recipe_list[category])
			var/obj/O = path
			var/research = FALSE
			if(ispath(path, /obj/item/integrated_circuit))
				var/obj/item/integrated_circuit/IC = path
				research = (initial(IC.spawn_flags) & IC_SPAWN_RESEARCH) && !(initial(IC.spawn_flags) & IC_SPAWN_DEFAULT)
			items += list(list(
				"path" = "[path]",
				"name" = initial(O.name),
				"desc" = initial(O.desc),
				"cost" = circuit_print_cost(path),
				"icon" = circuit_icon_key(path),
				"research" = research,
			))
		categories += list(list("name" = category, "items" = items))
	data["categories"] = categories
	return data

/obj/item/integrated_circuit_printer/ui_data(mob/user)
	var/list/data = list()
	var/datum/component/material_container/materials = GetComponent(/datum/component/material_container)
	data["metal"] = materials.total_amount
	data["max_metal"] = materials.max_amount
	data["debug"] = debug
	data["upgraded"] = upgraded || debug
	data["cloning_allowed"] = (can_clone && CONFIG_GET(flag/ic_printing)) || debug
	data["fast_clone"] = fast_clone
	data["cloning"] = cloning
	var/obj/item/card/id/lock = idlock?.resolve()
	data["idlock"] = lock ? lock.name : null
	if(program)
		var/list/assembly = program["assembly"]
		var/assembly_name = "assembly"
		if(islist(assembly))
			var/path = text2path("[assembly["type"]]")
			if(ispath(path, /obj/item/electronic_assembly))
				var/obj/item/electronic_assembly/E = path
				assembly_name = initial(E.name)
			if(assembly["name"])
				assembly_name = "[assembly["name"]]"
		data["program"] = list(
			"name" = assembly_name,
			"space" = program["used_space"],
			"max_space" = program["max_space"],
			"complexity" = program["complexity"],
			"max_complexity" = program["max_complexity"],
			"cost" = program["metal_cost"],
			"needs_upgrade" = !!program["requires_upgrades"],
			"unsupported" = !!program["unsupported_circuit"],
		)
	return data

/// Loads a pasted program; what Topic()'s "load" did after its popup
/obj/item/integrated_circuit_printer/proc/load_program_text(mob/user, input)
	if(cloning)
		return
	if(!input)
		program = null
		return
	var/validation = SScircuit.validate_electronic_assembly(input)
	if(istext(validation))
		to_chat(user, "<span class='warning'>Error: [validation]</span>")
		return
	if(islist(validation))
		program = validation
		to_chat(user, "<span class='notice'>This is a valid program for [program["assembly"]["type"]].</span>")
		if(program["requires_upgrades"])
			if(upgraded)
				to_chat(user, "<span class='notice'>It uses advanced component designs.</span>")
			else
				to_chat(user, "<span class='warning'>It uses unknown component designs. Printer upgrade is required to proceed.</span>")
		if(program["unsupported_circuit"])
			to_chat(user, "<span class='warning'>This program uses components not supported by the specified assembly. Please change the assembly type in the save file to a supported one.</span>")

/obj/item/integrated_circuit_printer/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("build")
			Topic(null, list("build" = "[params["path"]]"))
			return TRUE
		if("load")
			if(!CONFIG_GET(flag/ic_printing) && !debug)
				to_chat(usr, "<span class='warning'>CentCom has disabled printing of custom circuitry due to recent allegations of copyright infringement.</span>")
				return TRUE
			if(!can_clone)
				return TRUE
			add_fingerprint(usr)
			load_program_text(usr, "[params["code"]]")
			return TRUE
		if("unload")
			if(!cloning)
				program = null
			return TRUE
		if("print", "cancel")
			Topic(null, list("print" = action))
			return TRUE
		if("id_lock")
			Topic(null, list("id-lock" = "1"))
			return TRUE

// ---------------------------------------------------------------------------------------------------------------
// Code from the analyzer (or a ghost's scan): the save code coloured and laid out (CircuitCode.js), with what it builds
// listed in words beside it (the parts, the values typed into them that a copy keeps, the wires). Copy copies the
// one-line code the printer's Program box takes.

/datum/circuit_code_view
	var/title
	var/code
	/// What the code builds, in words (circuit_outline()); null when shown without its assembly
	var/list/outline

/datum/circuit_code_view/New(_title, _code, list/_outline)
	title = _title
	code = _code
	outline = _outline

/proc/circuit_show_code(mob/user, title, code, obj/item/electronic_assembly/A)
	var/datum/circuit_code_view/V = new(title, code, istype(A) ? circuit_outline(A) : null)
	V.ui_interact(user)

/// The assembly as its save code keeps it: parts in order, typed values (save() keeps numbers, text and lists that
/// differ from the part's defaults), and every wire once
/proc/circuit_outline(obj/item/electronic_assembly/A)
	var/list/parts = list()
	var/list/wires = list()
	var/list/seen = list()
	var/n = 0
	for(var/obj/item/integrated_circuit/C in A.assembly_components)
		n++
		var/list/values = list()
		for(var/index in 1 to length(C.inputs))
			var/datum/integrated_io/P = C.inputs[index]
			if(P.data == C.inputs_default["[index]"] || P.data == initial(P.data))
				continue
			if(islist(P.data) || isnum(P.data) || istext(P.data))
				values += list(list("pin" = P.name, "value" = circuit_pin_text(P.data)))
		parts += list(list(
			"n" = n,
			"name" = C.displayed_name,
			"type" = C.name,
			"icon" = circuit_icon_key(C.type),
			"values" = values,
		))
		for(var/datum/integrated_io/P in C.outputs + C.activators + C.inputs)
			for(var/datum/integrated_io/L in P.linked)
				var/key = "[REF(P)]" < "[REF(L)]" ? "[REF(P)]|[REF(L)]" : "[REF(L)]|[REF(P)]"
				if(seen[key])
					continue
				seen[key] = TRUE
				wires += list(list(
					"from" = "[C.displayed_name]: [P.name]",
					"to" = "[L.holder.displayed_name]: [L.name]",
					"pulse" = P.io_type == PULSE_CHANNEL,
				))
	return list("name" = A.name, "type" = initial(A.name), "parts" = parts, "wires" = wires)

/datum/circuit_code_view/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, 									datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		circuit_send_sheet(user)
		ui = new(user, src, ui_key, "circuit_code", title, 760, 520, master_ui, state)
		ui.set_autoupdate(FALSE)
		ui.open()

/datum/circuit_code_view/ui_base_html(html)
	return circuit_sheet_html(html)

/datum/circuit_code_view/ui_static_data(mob/user)
	return list("title" = title, "code" = code, "outline" = outline)

/datum/circuit_code_view/ui_close(mob/user)
	QDEL_IN(src, 1) // after the window's own close is done with it
