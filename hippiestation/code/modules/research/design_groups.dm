// The groups a lathe's window lists its designs under (RdFabricator / FabricatorPanel in tgui-next's interfaces/RdConsole.js).
// tg's own categories were lopsided on the protolathe (Medical Designs 52, Equipment 50, Firing Pins 2) and 38 designs carried only
// autolathe ones ("Misc"), so they showed under All alone. Here every design gets one home on each kind of machine: the protolathe and
// techfabs by department and use, the imprinter by department. The autolathe keeps tg's groups.

/// Department to group, first match wins: a design for Science and Engineering is Engineering's (Science is most often the "also").
#define DEPT_GROUP_ORDER list(\
	list(DEPARTMENTAL_FLAG_SECURITY, "Security"),\
	list(DEPARTMENTAL_FLAG_MEDICAL, "Medical"),\
	list(DEPARTMENTAL_FLAG_ENGINEERING, "Engineering"),\
	list(DEPARTMENTAL_FLAG_SERVICE, "Service"),\
	list(DEPARTMENTAL_FLAG_CARGO, "Cargo"),\
	list(DEPARTMENTAL_FLAG_SCIENCE, "Science"))

/datum/design/proc/dept_group()
	if(departmental_flags & DEPARTMENTAL_FLAG_ALL) // "every department", and a design that sets none has every bit (ALL is the default)
		return
	for(var/list/entry in DEPT_GROUP_ORDER)
		if(departmental_flags & entry[1])
			return entry[2]

/// Where the protolathe and the techfabs list it.
/datum/design/proc/lathe_group()
	var/static/list/overrides = list(
		"rglass" = "Materials",
		"emergency_oxygen" = "Engineering",
		"packagewrap" = "Service",
		"desttagger" = "Service",
		"handlabel" = "Service",
		"air_horn" = "Service",
		"donksoft_refill" = "Service",
		"plunger" = "Tools",
		"paicard" = "Science",
		"mmi" = "Science",
		"mmi_posi" = "Science",
		"experi_scanner" = "Science",
		"quantum_keycard" = "Science",
		"anomaly_neutralizer" = "Science",
		"reactive_armour" = "Science",
		"bluebutt" = "Bluespace",
	)
	if(overrides[id])
		return overrides[id]
	var/list/C = category
	if("Ammo" in C)
		return "Ammo"
	if(("Weapons" in C) || ("Firing Pins" in C))
		return "Weapons"
	if("Computer Parts" in C)
		return "Computer Parts"
	if("Bluespace Designs" in C)
		return "Bluespace"
	if(ispath(build_path, /obj/item/stock_parts/cell)) // the user looked for them with the parts (2026-11-11); the research tab has them there too
		return "Stock Parts"
	if("Power Designs" in C)
		return "Power"
	if("Mining Designs" in C)
		return "Mining"
	if("Stock Parts" in C)
		return ispath(build_path, /obj/item/stack) ? "Materials" : "Stock Parts"
	if(ispath(build_path, /obj/item/organ) || ispath(build_path, /obj/item/implanter) || ispath(build_path, /obj/item/implantcase))
		return "Cybernetics"
	if("Tool Designs" in C)
		if(departmental_flags & DEPARTMENTAL_FLAG_MEDICAL)
			return "Medical"
		if(departmental_flags & DEPARTMENTAL_FLAG_SERVICE)
			return "Service"
		return "Tools"
	if("Medical Designs" in C)
		return "Medical"
	var/dept = dept_group()
	if(dept == "Cargo")
		return "Mining" // the protolathe's cargo designs are the miners' kit
	return dept || "Misc"

/// Where the circuit imprinter lists it.
/datum/design/proc/board_group()
	var/static/list/overrides = list(
		"comconsole" = "Command",
		"idcardconsole" = "Command",
		"crewconsole" = "Medical",
		"mining" = "Cargo",
		"space_heater" = "Engineering",
		// for every department: where people go looking for them
		"arcade_battle" = "Service",
		"arcade_orion" = "Service",
		"slotmachine" = "Service",
		"libraryconsole" = "Service",
		"reagentgrinder" = "Service",
		"microwave" = "Service",
		"smartfridge" = "Service",
		"vendor" = "Service",
		"donksofttoyvendor" = "Service",
		"paystand" = "Service",
		"recycler" = "Engineering",
		"holopad" = "Engineering",
		"autolathe" = "Engineering",
		"cell_charger" = "Engineering",
		"recharger" = "Security",
		"scanner_gate" = "Security",
	)
	if(overrides[id])
		return overrides[id]
	var/list/C = category
	if("AI Modules" in C)
		return "AI"
	if("Computer Parts" in C)
		return "Computer Parts"
	if(ispath(build_path, /obj/item/circuitboard/computer/aiupload) || ispath(build_path, /obj/item/circuitboard/computer/borgupload) || ispath(build_path, /obj/item/circuitboard/aicore) || ispath(build_path, /obj/item/circuitboard/computer/aifixer))
		return "AI"
	if(("Mining Designs" in C) || ("Exosuit Modules" in C))
		return dept_group() || "Science"
	return dept_group() || "Misc"

#undef DEPT_GROUP_ORDER

/// What a design makes, for the R&D console's Research tab: the kind of thing, not whose it is. The user's ruling (overnight 2026-11-10):
/// research by category, the protolathe by department.
/datum/design/proc/item_kind()
	if(istype(src, /datum/design/surgery))
		return "Surgery"
	var/path = build_path
	if(!ispath(path))
		return "Equipment"
	if(ispath(path, /obj/item/borg/upgrade/modkit)) // the kinetic accelerator's mods are cyborg upgrades by type
		return "Tools"
	if(ispath(path, /obj/item/stock_parts))
		return "Stock Parts"
	if(ispath(path, /obj/item/circuitboard))
		return "Machines"
	if(ispath(path, /obj/item/gun) || ispath(path, /obj/item/ammo_box) || ispath(path, /obj/item/ammo_casing) || ispath(path, /obj/item/firing_pin) || ispath(path, /obj/item/grenade) || ispath(path, /obj/item/melee) || ispath(path, /obj/item/transfer_valve))
		return "Weapons"
	if(ispath(path, /obj/item/organ) || ispath(path, /obj/item/implant) || ispath(path, /obj/item/implanter) || ispath(path, /obj/item/implantcase) || ispath(path, /obj/item/autosurgeon))
		return "Implants"
	if(ispath(path, /obj/item/mecha_parts) || ispath(path, /obj/mecha) || ispath(path, /obj/item/borg) || ispath(path, /obj/item/robot_suit) || ispath(path, /obj/item/mmi) || ispath(path, /obj/item/bodypart))
		return "Mechs & Borgs"
	if(ispath(path, /obj/item/clothing))
		return "Clothing"
	if(ispath(path, /obj/item))
		var/obj/item/I = path
		if(initial(I.tool_behaviour) || ispath(path, /obj/item/construction) || ispath(path, /obj/item/pipe_dispenser) || ispath(path, /obj/item/lightreplacer) || ispath(path, /obj/item/mop) || ispath(path, /obj/item/holosign_creator) || ispath(path, /obj/item/t_scanner) || ispath(path, /obj/item/healthanalyzer) || ispath(path, /obj/item/geiger_counter) || ispath(path, /obj/item/pickaxe) || ispath(path, /obj/item/surgical_drapes) 			|| ispath(path, /obj/item/scalpel) || ispath(path, /obj/item/hemostat) || ispath(path, /obj/item/retractor) || ispath(path, /obj/item/circular_saw) || ispath(path, /obj/item/surgicaldrill) || ispath(path, /obj/item/cautery) 			|| ispath(path, /obj/item/cultivator) || ispath(path, /obj/item/plant_analyzer) || ispath(path, /obj/item/shovel) || ispath(path, /obj/item/hatchet) || ispath(path, /obj/item/stack/cable_coil) 			|| ispath(path, /obj/item/pipe_painter) || ispath(path, /obj/item/airlock_painter) || ispath(path, /obj/item/inducer) || ispath(path, /obj/item/resonator) || ispath(path, /obj/item/gps))
			return "Tools"
	return "Equipment"

/// Where the R&D console's Research tab lists a node: under the kind of thing most of its designs make (item_kind()), one home each.
/// A node that makes nothing (the base, the alien theory) is Equipment.
/datum/techweb_node/proc/node_group()
	var/static/list/cache = list()
	if(cache[id])
		return cache[id]
	var/static/list/tie_order = list("Weapons", "Surgery", "Implants", "Clothing", "Tools", "Machines", "Stock Parts", "Mechs & Borgs", "Equipment")
	if(findtext(id, "mech") || findtext(display_name, "Exosuit") || findtext(id, "cyborg"))
		cache[id] = "Mechs & Borgs" //the mech lines are boards and parts as much as anything: they go together
		return cache[id]
	var/list/votes = list()
	for(var/design_id in design_ids)
		var/datum/design/D = SSresearch.techweb_design_by_id(design_id)
		if(istype(D))
			var/kind = D.item_kind()
			votes[kind] += kind == "Mechs & Borgs" ? 0.5 : 1 //most nodes carry an exosuit version of what they make
	var/best
	for(var/kind in tie_order)
		if(votes[kind] && (!best || votes[kind] > votes[best]))
			best = kind
	cache[id] = best || "Equipment"
	return cache[id]

/// What each player last had open on each kind of lathe, and whether they hide what they can't afford: the window opens the way they
/// left it. Per round, by ckey.
GLOBAL_LIST_EMPTY(lathe_panel_prefs)

/proc/lathe_panel_prefs(mob/user)
	var/list/prefs = user?.ckey && GLOB.lathe_panel_prefs[user.ckey]
	return prefs || list()

/// The page asks to remember something: a category ("lathe", "board", "autolathe" or the console's "node" = its name, "" for All) or
/// "hide" = 0/1, or "sort" = "name"/"tier".
/proc/lathe_panel_pref_set(mob/user, key, value)
	if(!user?.ckey || !(key in list("lathe", "board", "autolathe", "node", "hide", "sort")))
		return
	var/list/prefs = GLOB.lathe_panel_prefs[user.ckey]
	if(!prefs)
		prefs = GLOB.lathe_panel_prefs[user.ckey] = list()
	if(key == "hide")
		prefs[key] = text2num(value) ? 1 : 0
	else if(key == "sort")
		prefs[key] = value == "tier" ? "tier" : "name"
	else
		prefs[key] = copytext("[value]", 1, 64)
