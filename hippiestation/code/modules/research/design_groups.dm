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

/// Where the R&D console's Research tab lists a node: by department, one home each. tg's nodes carry no category at all. Weapons go
/// under Security, nanites and alien tech under Science, and the exosuits get their own: 24 nodes, mostly one mech gun each.
/datum/techweb_node/proc/node_group()
	var/static/list/groups = list(
		"Engineering" = list("basic_tools", "engineering", "adv_engi", "high_efficiency", "adv_power", "basic_plasma", "adv_plasma", "exp_tools", "rcd_upgrade", "emp_basic", "emp_adv", "emp_super"),
		"Medical" = list("biotech", "adv_biotech", "imp_wt_surgery", "adv_surgery", "exp_surgery", "alien_surgery", "cloning", "cryotech", "adv_chem", "autodoc"),
		"Security" = list("sec_basic", "weaponry", "adv_weaponry", "electronic_weapons", "radioactive_weapons", "medical_weapons", "beam_weapons", "adv_beam_weapons", "explosive_weapons", "ballistic_weapons", "exotic_ammo", "magnetic_weapons", "ancient_weapons"),
		"Science" = list("base", "anomaly_research", "nanite_base", "nanite_smart", "nanite_mesh", "nanite_bio", "nanite_neural", "nanite_synaptic", "nanite_harmonic", "nanite_military", "nanite_hazard", "alientech", "alien_bio", "alien_engi", "syndicate_basic"),
		"Robotics" = list("mmi", "cyborg", "robotics", "adv_robotics", "neural_programming", "posibrain", "cyborg_upg_util", "cyborg_upg_med", "cyborg_upg_combat", "ai"),
		"Cybernetics" = list("subdermal_implants", "cyber_organs", "cyber_organs_upgraded", "cyber_implants", "adv_cyber_implants", "combat_cyber_implants", "integrated_HUDs", "NVGtech"),
		"Bluespace" = list("bluespace_basic", "bluespace_travel", "micro_bluespace", "bluespace_storage", "practical_bluespace", "bluespace_power", "regulated_bluespace", "unregulated_bluespace", "advanced_bluetravel", "gravity_gun"),
		"Computers" = list("datatheory", "adv_datatheory", "comptech", "computer_hardware_basic", "computer_board_gaming", "comp_recordkeeping", "telecomms"),
		"Service" = list("clown", "janitor", "botany", "bio_process"),
		"Mining" = list("basic_mining", "adv_mining", "bluemining"),
	)
	var/static/list/by_id
	if(!by_id)
		by_id = list()
		for(var/group in groups)
			for(var/node_id in groups[group])
				by_id[node_id] = group
	if(by_id[id])
		return by_id[id]
	// The exosuit lines go by name ("mech"/"Exosuit": all 24 of them). Anything else not in the table (added since): whichever group most
	// of its designs sit in on the protolathe.
	if(findtext(id, "mech") || findtext(display_name, "Exosuit"))
		return "Exosuits"
	var/list/votes = list()
	for(var/design_id in design_ids)
		var/datum/design/D = SSresearch.techweb_design_by_id(design_id)
		if(!istype(D) || !(D.build_type & PROTOLATHE))
			continue
		var/group = D.lathe_group()
		if(group in groups)
			votes[group]++
	var/best
	for(var/group in votes)
		if(!best || votes[group] > votes[best])
			best = group
	return best || "Science"

/// What each player last had open on each kind of lathe, and whether they hide what they can't afford: the window opens the way they
/// left it. Per round, by ckey.
GLOBAL_LIST_EMPTY(lathe_panel_prefs)

/proc/lathe_panel_prefs(mob/user)
	var/list/prefs = user?.ckey && GLOB.lathe_panel_prefs[user.ckey]
	return prefs || list()

/// The page asks to remember something: a category ("lathe", "board", "autolathe" or the console's "node" = its name, "" for All) or
/// "hide" = 0/1.
/proc/lathe_panel_pref_set(mob/user, key, value)
	if(!user?.ckey || !(key in list("lathe", "board", "autolathe", "node", "hide")))
		return
	var/list/prefs = GLOB.lathe_panel_prefs[user.ckey]
	if(!prefs)
		prefs = GLOB.lathe_panel_prefs[user.ckey] = list()
	if(key == "hide")
		prefs[key] = text2num(value) ? 1 : 0
	else
		prefs[key] = copytext("[value]", 1, 64)
