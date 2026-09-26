/datum/admins/proc/HippieMentorLogSecret()
	var/dat = "<B>Mentor Log<HR></B>"
	for(var/l in GLOB.mentorlog)
		dat += "<li>[l]</li>"

	if(!GLOB.mentorlog.len)
		dat += "No mentors have done anything this round!"
	usr << browse(dat, "window=mentor_log")

/datum/admins/Secrets_topic(item,href_list)
	. = ..()
	if (item == "winter")
		if(href_list["toggle"])
			StartWinter()
		else
			StopWinter()
	if (item == "upgrade_machines")
		if(!check_rights(R_FUN))
			return
		if(alert("Upgrade every machine, APC, SMES, mech and cyborg on the station to the best parts and cells?", "Upgrade Station", "Yes", "No") != "Yes")
			return
		UpgradeAllMachinesSecret()
	if (item == "plasma_flood")
		if(!check_rights(R_FUN))
			return
		if(alert("Flood every pressurised area of the station with plasma?", "Plasma Flood", "Yes", "No") != "Yes")
			return
		var/moles = input("Moles of plasma to add to every tile. A normal tile holds about [round(MOLES_CELLSTANDARD)] moles of air in total.", "Plasma Flood", 20) as null|num
		if(isnull(moles) || moles <= 0)
			return
		PlasmaFloodSecret(clamp(moles, 1, 200))

//The best stock part of a family, going by rating, so this keeps working if higher tiers are ever added
/proc/hippie_best_stock_part(family)
	var/best = family
	for(var/T in subtypesof(family))
		var/obj/item/stock_parts/candidate = T
		var/obj/item/stock_parts/current = best
		if(initial(candidate.rating) > initial(current.rating))
			best = T
	return best

//Whether a cell is worth replacing, an infinite cell has less capacity than a bluespace one but is far better
/proc/hippie_cell_upgradable(obj/item/stock_parts/cell/C, best_charge)
	if(!C)
		return TRUE
	return !istype(C, /obj/item/stock_parts/cell/infinite) && C.maxcharge < best_charge

//What upgrading each kind of machine does. Each entry is the kind of machine, what to call a group of them, what the upgrade
//does for them in plain english, and then any number of stats to show going from before the upgrade to after it, each as
//list(label, name of the variable on the machine, how to show it). Put more specific kinds of machine above the general ones.
//How to show a stat: num, x (a multiplier), pct (0.4 is 40%), pctnum (40 is 40%), milli (0.4 is 400%), sec (deciseconds), mj, kw, len (how long a list is)
/proc/hippie_machine_entries()
	return list(
		list(/obj/machinery/holopad, "Holopads", "Project their holograms further.", list("Hologram range", "holo_range", "num")),
		list(/obj/machinery/hydroponics/constructable, "Hydroponics trays", "Hold more water and fertiliser, and grow plants more efficiently.", list("Water capacity", "maxwater", "num"), list("Fertiliser capacity", "maxnutri", "num"), list("Tray efficiency", "rating", "pct")),
		list(/obj/machinery/recharger, "Rechargers", "Charge whatever is put in them much faster.", list("Charge speed", "recharge_coeff", "x")),
		list(/obj/machinery/space_heater, "Space heaters", "Heat harder and can be set across a wider range of temperatures.", list("Heating power", "heatingPower", "num"), list("Temperature range", "settableTemperatureRange", "num")),
		list(/obj/machinery/cell_charger, "Cell chargers", "Charge power cells faster.", list("Charge rate", "charge_rate", "num")),
		list(/obj/machinery/reagentgrinder, "Reagent grinders", "Grind faster.", list("Grinding speed", "speed", "x")),
		list(/obj/machinery/power/smes, "SMES units", "Store much more power and move more of it in and out.", list("Capacity", "capacity", "mj"), list("Max input", "input_level_max", "kw"), list("Max output", "output_level_max", "kw")),
		list(/obj/machinery/atmospherics/components/unary/thermomachine, "Freezers and heaters", "Have a much bigger heat capacity, so they shift the temperature of gas further.", list("Heat capacity", "heat_capacity", "num")),
		list(/obj/machinery/recharge_station, "Cyborg recharge stations", "Recharge cyborgs faster and repair them more.", list("Recharge speed", "recharge_speed", "num"), list("Repairs", "repairs", "num")),
		list(/obj/machinery/power/emitter, "Emitters", "Fire more often.", list("Time between shots", "fire_delay", "sec")),
		list(/obj/machinery/power/tesla_coil, "Tesla coils", "Turn more of the lightning they catch into power, and can shock more often.", list("Power generation", "input_power_multiplier", "pct"), list("Time between shocks", "zap_cooldown", "sec")),
		list(/obj/machinery/microwave, "Microwaves", "Cook faster and hold more ingredients.", list("Cooking speed", "efficiency", "x"), list("Capacity", "max_n_of_items", "num")),
		list(/obj/machinery/sleeper, "Sleepers", "Treat patients better and offer more chemicals.", list("Effectiveness", "efficiency", "x"), list("Chemicals available", "available_chems", "len")),
		list(/obj/machinery/power/port_gen/pacman, "PACMAN generators", "Produce more power and hold more fuel.", list("Power output", "power_gen", "num"), list("Fuel capacity", "max_sheets", "num")),
		list(/obj/machinery/biogenerator, "Biogenerators", "Process biomass better and store more.", list("Efficiency", "efficiency", "num"), list("Productivity", "productivity", "num"), list("Storage", "max_items", "num")),
		list(/obj/machinery/mech_bay_recharge_port, "Mech bay recharge ports", "Recharge mechs faster.", list("Recharge rate", "max_charge", "num")),
		list(/obj/machinery/dna_scannernew, "DNA scanners", "Scan at a higher level, with more accurate radiation pulses that do less damage.", list("Scan level", "scan_level", "num")),
		list(/obj/machinery/chem_dispenser, "Chemical dispensers", "Recharge faster, dispense in finer amounts, and unlock extra chemicals at the top tier.", list("Recharge", "recharge_amount", "num"), list("Smallest dispense step", "macroresolution", "num"), list("Chemicals available", "dispensable_reagents", "len")),
		list(/obj/machinery/chem_heater, "Chemical heaters", "Heat reagents faster.", list("Heating speed", "heater_coefficient", "milli")),
		list(/obj/machinery/atmospherics/components/unary/cryo_cell, "Cryo tubes", "Treat patients much more effectively.", list("Treatment efficiency", "efficiency", "x")),
		list(/obj/machinery/teleport/hub, "Teleporter hubs", "Malfunction less often.", list("Accuracy", "accuracy", "num")),
		list(/obj/machinery/teleport/station, "Teleporter stations", "Work more efficiently.", list("Efficiency", "efficiency", "num")),
		list(/obj/machinery/rnd/server, "Research servers", "Produce less heat.", list("Heat produced", "heat_gen", "num")),
		list(/obj/machinery/rnd/production, "Protolathes, techfabs and circuit imprinters", "Use much less material for everything they make, and store more material.", list("Material efficiency", "efficiency_coeff", "x")),
		list(/obj/machinery/nanite_chamber, "Nanite chambers", "Scan at a higher level.", list("Scan level", "scan_level", "num")),
		list(/obj/machinery/monkey_recycler, "Monkey recyclers", "Make more monkey cubes from every monkey.", list("Cubes per monkey", "cube_production", "num")),
		list(/obj/machinery/mecha_part_fabricator, "Mech fabricators", "Use less material for every part they make, and store more material.", list("Material use", "component_coeff", "pct")),
		list(/obj/machinery/gibber, "Gibbers", "Work faster and give more meat.", list("Time to gib", "gibtime", "sec"), list("Meat per gib", "meat_produced", "num")),
		list(/obj/machinery/deepfryer, "Deep fryers", "Fry faster and use less oil.", list("Frying speed", "fry_speed", "x")),
		list(/obj/machinery/clonepod, "Cloning pods", "Heal a clone further before letting it out, and clone faster.", list("Clone health when released", "heal_level", "pctnum"), list("Cloning speed", "speed_coeff", "x")),
		list(/obj/machinery/smartfridge, "Smart fridges", "Hold far more items.", list("Capacity", "max_n_of_items", "num")),
		list(/obj/machinery/rnd/destructive_analyzer, "Destructive analyzers", "Get more out of the things they take apart.", list("Deconstruction bonus", "decon_mod", "num")),
		list(/obj/machinery/recycler, "Recyclers", "Recover more of the material they crush, and store more.", list("Material recovered", "amount_produced", "pctnum")),
		list(/obj/machinery/processor, "Food processors", "Work faster and make more each time.", list("Items per use", "rating_amount", "num"), list("Speed", "rating_speed", "pct")),
		list(/obj/machinery/power/turbine, "Turbines", "Make more power from the gas going through them.", list("Productivity", "productivity", "pct")),
		list(/obj/machinery/autolathe, "Autolathes", "Use much less material for everything they make, and store more material.", list("Material use", "prod_coeff", "pct")),
		list(/obj/machinery/mineral/ore_redemption, "Ore redemption machines", "Smelt ore faster and get more out of it.", list("Ore per cycle", "ore_pickup_rate", "num"), list("Sheets per ore", "sheet_per_ore", "num"), list("Points multiplier", "point_upgrade", "x")))

//Finds the entry for a machine, or null if there isn't a description for it
/proc/hippie_find_machine_entry(obj/machinery/M, list/entries)
	for(var/list/entry in entries)
		if(istype(M, entry[1]))
			return entry
	return null

//Reads the stats an entry wants to show from a machine, as label = value
/proc/hippie_read_stats(obj/machinery/M, list/entry)
	var/list/out = list()
	for(var/i in 4 to entry.len)
		var/list/stat = entry[i]
		if(!(stat[2] in M.vars))
			continue
		var/value = M.vars[stat[2]]
		if(islist(value))
			value = length(value)
		if(isnum(value))
			out[stat[1]] = value
	return out

/proc/hippie_format_stat(value, format)
	if(!isnum(value))
		return "?"
	if(value == INFINITY)
		return "free"
	switch(format)
		if("x")
			return "[round(value, 0.01)]x"
		if("pct")
			return "[round(value * 100)]%"
		if("pctnum")
			return "[round(value)]%"
		if("milli")
			return "[round(value * 1000)]%"
		if("sec")
			return "[round(value / 10, 0.1)]s"
		if("mj")
			return "[round(value / 1000000, 0.1)] MJ"
		if("kw")
			return "[round(value / 1000)] kW"
	return "[round(value, 0.01)]"

//A list of values shown as one value, or as low to high if they differ
/proc/hippie_format_range(list/values, format)
	var/low = min(values)
	var/high = max(values)
	if(low == high)
		return hippie_format_stat(low, format)
	return "[hippie_format_stat(low, format)] to [hippie_format_stat(high, format)]"

//Adds an upgraded machine to its group, keeping what its stats were before and after so they can be compared
/proc/hippie_note_machine(list/groups, list/others, obj/machinery/M, list/entry, list/before)
	if(!entry)
		others[initial(M.name)]++
		return
	var/key = entry[2]
	var/list/group = groups[key]
	if(!group)
		group = list("count" = 0, "entry" = entry, "before" = list(), "after" = list())
		groups[key] = group
	group["count"]++
	var/list/after = hippie_read_stats(M, entry)
	var/list/before_all = group["before"]
	var/list/after_all = group["after"]
	for(var/label in before)
		if(isnull(after[label]))
			continue
		if(!before_all[label])
			before_all[label] = list()
			after_all[label] = list()
		before_all[label] += before[label]
		after_all[label] += after[label]

//Turns the groups of upgraded machines into a plain english line for each kind of machine, biggest groups first
/proc/hippie_machine_explanations(list/groups, list/others)
	var/list/keys = list()
	for(var/key in groups)
		keys += key
	for(var/i in 1 to keys.len)
		for(var/j in i + 1 to keys.len)
			var/list/group_i = groups[keys[i]]
			var/list/group_j = groups[keys[j]]
			if(group_j["count"] > group_i["count"])
				keys.Swap(i, j)
	var/list/lines = list()
	for(var/key in keys)
		var/list/group = groups[key]
		var/list/entry = group["entry"]
		var/line = "<B>[key]</B> ([group["count"]] upgraded): [entry[3]]"
		var/list/bits = list()
		var/list/before_all = group["before"]
		var/list/after_all = group["after"]
		for(var/i in 4 to entry.len)
			var/list/stat = entry[i]
			var/list/before = before_all[stat[1]]
			var/list/after = after_all[stat[1]]
			if(!before || !after)
				continue
			var/before_text = hippie_format_range(before, stat[3])
			var/after_text = hippie_format_range(after, stat[3])
			if(before_text != after_text)
				bits += "[stat[1]] [before_text] -&gt; [after_text]"
		if(bits.len)
			line += " ([bits.Join(", ")])"
		else if(entry.len >= 4) //better parts went in but nothing we measure moved, so don't claim they do anything
			line = "<B>[key]</B> ([group["count"]] upgraded): Their parts were upgraded, but nothing that could be measured on them changed."
		lines += line
	if(others.len)
		var/list/names = list()
		var/total = 0
		for(var/name in others)
			names += "[html_encode(name)] x[others[name]]"
			total += others[name]
		lines += "<B>Other machines</B> ([total] upgraded): their parts were upgraded, but no description of what that changes has been written for them yet: [names.Join(", ")]."
	return lines

//Turns a list of "old part -> new part" and how many times it happened into something readable
/proc/hippie_format_changes(list/changes)
	var/list/out = list()
	for(var/change in changes)
		out += "[change][changes[change] > 1 ? " x[changes[change]]" : ""]"
	return out.Join(", ")

//One titled block of the upgrade report
/proc/hippie_report_section(title, list/lines)
	var/list/out = list("<B>[title] ([lines.len])</B><BR>")
	if(!lines.len)
		out += "&nbsp;&nbsp;Nothing needed upgrading<BR>"
	for(var/line in lines)
		out += "&nbsp;&nbsp;[line]<BR>"
	out += "<BR>"
	return out.Join()

//Swaps every stock part in a machine for the best one of its kind and refreshes it, returns how many were replaced.
//If a list is passed as changes, every swap is recorded in it as "old part -> new part" with a count
/proc/hippie_upgrade_machine_parts(obj/machinery/M, list/best_parts, cell_type, best_charge, list/changes)
	. = 0
	var/list/to_replace = list()
	for(var/obj/item/stock_parts/P in M.component_parts)
		var/new_type
		if(istype(P, /obj/item/stock_parts/cell))
			var/obj/item/stock_parts/cell/C = P
			if(hippie_cell_upgradable(C, best_charge))
				new_type = cell_type
		else
			for(var/family in best_parts)
				if(!istype(P, family))
					continue
				var/obj/item/stock_parts/candidate = best_parts[family]
				if(P.rating < initial(candidate.rating))
					new_type = best_parts[family]
				break
		if(new_type)
			to_replace[P] = new_type
	if(!to_replace.len)
		return
	var/obj/machinery/power/smes/S = M
	var/smes_fraction = istype(S) && S.capacity ? S.charge / S.capacity : 0 //an SMES keeps the same fraction of charge it had
	for(var/obj/item/stock_parts/P in to_replace)
		var/new_type = to_replace[P]
		var/obj/item/stock_parts/N = new new_type(null)
		if(("cell" in M.vars) && M.vars["cell"] == P) //some machines also keep their cell in a var of its own
			M.vars["cell"] = N
		if(changes)
			changes["[P.name] -&gt; [N.name]"]++
		M.component_parts -= P
		M.component_parts += N
		qdel(P)
		.++
	M.RefreshParts()
	if(istype(S))
		S.charge = smes_fraction * S.capacity

/proc/hippie_swap_cell(atom/holder, obj/item/stock_parts/cell/old_cell, cell_type)
	var/fraction = old_cell && old_cell.maxcharge ? old_cell.charge / old_cell.maxcharge : 1
	if(old_cell)
		qdel(old_cell)
	var/obj/item/stock_parts/cell/new_cell = new cell_type(holder)
	new_cell.charge = fraction * new_cell.maxcharge
	return new_cell

/obj/mecha
	var/admin_upgraded = FALSE //so upgrading the mech again doesn't stack its bonuses

//Every machine on the station gets the best stock parts and cells, APCs, mechs and cyborgs included, returns a summary of what changed.
//If a list is passed as report it's filled with "machines", "apcs", "mechs" and "borgs" lists of lines describing each thing that
//was upgraded, "totals" listing every kind of part swap and how many there were, and "explanations", a plain english line for
//each kind of machine saying what upgrading it does
/proc/hippie_upgrade_all_station_machines(list/report)
	var/list/machine_lines = list()
	var/list/apc_lines = list()
	var/list/mech_lines = list()
	var/list/borg_lines = list()
	var/list/totals = list()
	var/list/entries = hippie_machine_entries()
	var/list/groups = list() //machines that were upgraded, grouped by kind, with their stats from before and after
	var/list/others = list() //upgraded machines there is no description for
	var/list/apc_old = list() //how much charge the cells that were replaced could hold
	var/list/mech_old = list()
	var/list/borg_old = list()
	var/list/best_parts = list()
	for(var/family in list(/obj/item/stock_parts/capacitor, /obj/item/stock_parts/scanning_module, /obj/item/stock_parts/manipulator, /obj/item/stock_parts/micro_laser, /obj/item/stock_parts/matter_bin))
		best_parts[family] = hippie_best_stock_part(family)
	var/cell_type = /obj/item/stock_parts/cell/bluespace
	var/obj/item/stock_parts/cell/cell_ref = cell_type
	var/best_charge = initial(cell_ref.maxcharge)
	var/machines = 0
	var/parts = 0
	var/apcs = 0
	var/mechs = 0
	var/borgs = 0

	for(var/obj/machinery/M in GLOB.machines)
		var/turf/T = get_turf(M)
		if(!T || !is_station_level(T.z))
			continue
		if(length(M.component_parts))
			var/list/entry = hippie_find_machine_entry(M, entries)
			var/list/before = entry ? hippie_read_stats(M, entry) : null
			var/list/changes = list()
			var/replaced = hippie_upgrade_machine_parts(M, best_parts, cell_type, best_charge, changes)
			if(replaced)
				machines++
				parts += replaced
				machine_lines += "[html_encode(M.name)] [ADMIN_VERBOSEJMP(M)]: [hippie_format_changes(changes)]"
				for(var/change in changes)
					totals[change] += changes[change]
				hippie_note_machine(groups, others, M, entry, before)
		if(istype(M, /obj/machinery/power/apc))
			var/obj/machinery/power/apc/A = M
			if(hippie_cell_upgradable(A.cell, best_charge))
				var/old_cell = A.cell ? "[A.cell.name] ([A.cell.maxcharge])" : "no cell"
				apc_old += A.cell ? A.cell.maxcharge : 0
				A.cell = hippie_swap_cell(A, A.cell, cell_type)
				A.cell_type = cell_type
				A.chargecount = 0
				A.update_icon()
				apcs++
				apc_lines += "[html_encode(A.name)] [ADMIN_VERBOSEJMP(A)]: [html_encode(old_cell)] -&gt; [A.cell.name] ([A.cell.maxcharge])"
		CHECK_TICK

	for(var/obj/mecha/M in GLOB.mechas_list)
		var/turf/T = get_turf(M)
		if(!T || !is_station_level(T.z))
			continue
		var/upgraded = FALSE
		var/list/notes = list()
		if(hippie_cell_upgradable(M.cell, best_charge))
			var/old_cell = M.cell ? "[M.cell.name] ([M.cell.maxcharge])" : "no cell"
			mech_old += M.cell ? M.cell.maxcharge : 0
			M.cell = hippie_swap_cell(M, M.cell, cell_type)
			M.diag_hud_set_mechcell()
			notes += "[html_encode(old_cell)] -&gt; [M.cell.name] ([M.cell.maxcharge])"
			upgraded = TRUE
		if(!M.admin_upgraded) //the same bonuses a best-tier scanning module and capacitor give a mech when it's built
			M.admin_upgraded = TRUE
			var/old_drain = M.normal_step_energy_drain
			M.normal_step_energy_drain = min(old_drain, 0)
			if(M.step_energy_drain == old_drain)
				M.step_energy_drain = M.normal_step_energy_drain
			M.armor = M.armor.modifyRating(energy = 20)
			notes += "step energy drain [old_drain] -&gt; [M.normal_step_energy_drain]"
			notes += "energy armor +20"
			upgraded = TRUE
		if(upgraded)
			mechs++
			mech_lines += "[html_encode(M.name)] [ADMIN_VERBOSEJMP(M)]: [notes.Join(", ")]"
			if(M.occupant)
				to_chat(M.occupant, "<span class='notice'>Your exosuit's systems hum as they're upgraded.</span>")
		CHECK_TICK

	for(var/mob/living/silicon/robot/R in GLOB.silicon_mobs)
		var/turf/T = get_turf(R)
		if(!T || !is_station_level(T.z))
			continue
		if(hippie_cell_upgradable(R.cell, best_charge))
			var/old_cell = R.cell ? "[R.cell.name] ([R.cell.maxcharge])" : "no cell"
			borg_old += R.cell ? R.cell.maxcharge : 0
			R.cell = hippie_swap_cell(R, R.cell, cell_type)
			R.diag_hud_set_borgcell()
			borgs++
			borg_lines += "[html_encode(R.name)] [ADMIN_VERBOSEJMP(R)]: [html_encode(old_cell)] -&gt; [R.cell.name] ([R.cell.maxcharge])"
		CHECK_TICK

	if(report)
		var/list/explanations = hippie_machine_explanations(groups, others)
		if(apcs)
			explanations += "<B>APCs</B> ([apcs] upgraded): Now run on bluespace power cells, so every area stays powered much longer (cell capacity [hippie_format_range(apc_old, "num")] -&gt; [best_charge])."
		if(mechs)
			var/mech_text = "<B>Mechs</B> ([mechs] upgraded): Walking no longer costs any power, they resist EMPs and energy attacks better"
			if(mech_old.len)
				mech_text += ", and their bluespace cells let them run much longer (cell capacity [hippie_format_range(mech_old, "num")] -&gt; [best_charge])"
			explanations += "[mech_text]."
		if(borgs)
			explanations += "<B>Cyborgs</B> ([borgs] upgraded): Now run on bluespace power cells, so they last much longer between recharges (cell capacity [hippie_format_range(borg_old, "num")] -&gt; [best_charge])."
		report["machines"] = machine_lines
		report["apcs"] = apc_lines
		report["mechs"] = mech_lines
		report["borgs"] = borg_lines
		report["totals"] = totals
		report["explanations"] = explanations
	return "[machines] machines ([parts] parts), [apcs] APCs, [mechs] mechs and [borgs] cyborgs"

/datum/admins/proc/UpgradeAllMachinesSecret()
	var/list/report = list()
	var/summary = hippie_upgrade_all_station_machines(report)
	SSblackbox.record_feedback("nested tally", "admin_secrets_fun_used", 1, list("Upgrade All Machines"))
	log_admin("[key_name(usr)] upgraded all station machines: [summary]", 1)
	message_admins("<span class='adminnotice'>[key_name_admin(usr)] upgraded all station machines: [summary]</span>")

	var/list/totals = report["totals"]
	var/list/total_lines = list()
	for(var/change in totals)
		total_lines += "[change] x[totals[change]]"
	var/list/explanations = report["explanations"]

	to_chat(usr, "<span class='notice'>Upgraded [summary].</span>")
	if(explanations.len)
		to_chat(usr, "<span class='notice'>What the upgrades do, biggest groups first:</span>")
		for(var/i in 1 to min(explanations.len, 10)) //the rest are in the report window
			to_chat(usr, "<span class='notice'>&nbsp;&nbsp;[explanations[i]]</span>")
		if(explanations.len > 10)
			to_chat(usr, "<span class='notice'>&nbsp;&nbsp;...and [explanations.len - 10] more kinds of machine, in the report window.</span>")
	to_chat(usr, "<span class='notice'>The full list of what was upgraded, with jump links, is in the report window.</span>")

	var/list/dat = list("<B>Station upgrade report</B><BR>[summary]<HR>")
	dat += "<B>What the upgrades do</B><BR>"
	for(var/explanation in explanations)
		dat += "&nbsp;&nbsp;[explanation]<BR><BR>"
	if(!explanations.len)
		dat += "&nbsp;&nbsp;Nothing needed upgrading<BR><BR>"
	dat += hippie_report_section("Parts replaced, by kind", total_lines)
	dat += hippie_report_section("Machines", report["machines"])
	dat += hippie_report_section("APCs", report["apcs"])
	dat += hippie_report_section("Mechs", report["mechs"])
	dat += hippie_report_section("Cyborgs", report["borgs"])
	usr << browse(dat.Join(), "window=upgrade_report;size=800x650")

//Adds plasma to every floor tile on the station levels that isn't out in space, at room temperature and with nothing lit
/datum/admins/proc/PlasmaFloodSecret(moles)
	var/tiles = 0
	for(var/thing in GLOB.station_turfs)
		var/turf/open/floor/T = thing //the list also holds walls, which the check below skips
		if(!isfloorturf(T) || !T.air || T.blocks_air || istype(get_area(T), /area/space))
			continue
		T.atmos_spawn_air("plasma=[moles];TEMP=[T20C]")
		tiles++
		CHECK_TICK
	SSblackbox.record_feedback("nested tally", "admin_secrets_fun_used", 1, list("Plasma Flood"))
	log_admin("[key_name(usr)] flooded the station with plasma, [moles] moles on each of [tiles] tiles", 1)
	message_admins("<span class='adminnotice'>[key_name_admin(usr)] flooded the station with plasma, [moles] moles on each of [tiles] tiles</span>")
