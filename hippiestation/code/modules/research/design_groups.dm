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

/// What each player last had open on each kind of lathe, and whether they hide what they can't afford: the window opens the way they
/// left it. Per round, by ckey.
GLOBAL_LIST_EMPTY(lathe_panel_prefs)

/proc/lathe_panel_prefs(mob/user)
	var/list/prefs = user?.ckey && GLOB.lathe_panel_prefs[user.ckey]
	return prefs || list()

/// The page asks to remember something: a category ("lathe", "board" or "autolathe" = its name, "" for All) or "hide" = 0/1.
/proc/lathe_panel_pref_set(mob/user, key, value)
	if(!user?.ckey || !(key in list("lathe", "board", "autolathe", "hide")))
		return
	var/list/prefs = GLOB.lathe_panel_prefs[user.ckey]
	if(!prefs)
		prefs = GLOB.lathe_panel_prefs[user.ckey] = list()
	if(key == "hide")
		prefs[key] = text2num(value) ? 1 : 0
	else
		prefs[key] = copytext("[value]", 1, 64)
