// hippie -- Secrets > Fun > "Emag or hack station machines": every machine of a chosen group on the station levels is emagged, and
// the ones whose wires do more than their emag (or have no emag at all, like the autolathe) are hacked the way a multitool or
// wirecutters would: autolathe hack wire, vending contraband + ID scan, suit storage UV + safeties. The emags run as a test dummy
// named after the admin, so the machines' own logs and messages have someone to name and the admin's chat isn't flooded.

/// The groups, first match wins: name, then the types in it. "Other" takes every machine none of them matched.
/proc/hippie_emag_groups()
	return list(
		"External airlocks" = list(/obj/machinery/door/airlock/external),
		"Airlocks" = list(/obj/machinery/door/airlock),
		"Windoors" = list(/obj/machinery/door/window),
		"Vending machines" = list(/obj/machinery/vending),
		"Autolathes" = list(/obj/machinery/autolathe),
		"Fabricators" = list(/obj/machinery/mecha_part_fabricator, /obj/machinery/limbgrower),
		"APCs" = list(/obj/machinery/power/apc),
		"Air and fire alarms" = list(/obj/machinery/airalarm, /obj/machinery/firealarm),
		"Turrets" = list(/obj/machinery/porta_turret, /obj/machinery/porta_turret_cover, /obj/machinery/turretid),
		"Consoles" = list(/obj/machinery/computer, /obj/machinery/modular_computer),
		"Medical" = list(/obj/machinery/sleeper, /obj/machinery/clonepod, /obj/machinery/autodoc, /obj/machinery/chem_dispenser, /obj/machinery/harvester, /obj/machinery/fat_sucker),
		"Suit storage units" = list(/obj/machinery/suit_storage_unit),
		"Other" = list(),
	)

/// Never touched: emagging the emergency shuttle console launches it early
/proc/hippie_emag_skipped(obj/machinery/M)
	return istype(M, /obj/machinery/computer/emergency_shuttle)

/proc/hippie_emag_group_of(obj/machinery/M, list/groups)
	for(var/name in groups)
		for(var/T in groups[name])
			if(istype(M, T))
				return name
	return "Other"

/// What wirecutters or a multitool do on top of the emag, for the machines where that's more
/proc/hippie_hack_wires(obj/machinery/M)
	if(istype(M, /obj/machinery/autolathe))
		var/obj/machinery/autolathe/A = M
		if(!A.hacked)
			A.adjust_hacked(TRUE)
	else if(istype(M, /obj/machinery/vending))
		var/obj/machinery/vending/V = M
		V.extended_inventory = TRUE
		V.scan_id = FALSE
	else if(istype(M, /obj/machinery/suit_storage_unit))
		var/obj/machinery/suit_storage_unit/SSU = M
		SSU.uv_super = TRUE
		SSU.safeties = FALSE

/datum/admins/proc/EmagMachinesSecret()
	if(!check_rights(R_FUN))
		return
	var/list/groups = hippie_emag_groups()
	var/list/counts = list()
	for(var/obj/machinery/M in GLOB.machines)
		var/turf/T = get_turf(M)
		if(!T || !is_station_level(T.z) || hippie_emag_skipped(M))
			continue
		counts[hippie_emag_group_of(M, groups)]++
	var/list/choices = list("Everything")
	for(var/name in groups)
		if(counts[name])
			choices["[name] ([counts[name]])"] = name
	var/pick = tgui_input_list(usr, "Emag (and hack the wires of) every machine of this group on the station.", "Emag Machines", choices)
	if(!pick)
		return
	var/group = pick == "Everything" ? null : choices[pick]
	var/warning = (!group || group == "External airlocks") ? " External airlocks open to space and stay open." : ""
	if(tgui_alert(usr, "Emag [group ? lowertext(group) : "every machine"] on the station?[warning]", "Emag Machines", list("Yes", "No")) != "Yes")
		return

	var/mob/living/carbon/human/dummy/D = new
	D.real_name = "[usr.key] (admin emag)"
	D.name = D.real_name
	var/done = 0
	for(var/obj/machinery/M in GLOB.machines)
		var/turf/T = get_turf(M)
		if(!T || !is_station_level(T.z) || hippie_emag_skipped(M))
			continue
		if(group && hippie_emag_group_of(M, groups) != group)
			continue
		hippie_hack_wires(M)
		INVOKE_ASYNC(M, TYPE_PROC_REF(/atom, emag_act), D) // an airlock's emag sleeps
		done++
		CHECK_TICK
	QDEL_IN(D, 5 SECONDS) // after the airlocks' emags wake

	var/what = group ? lowertext(group) : "all machines"
	SSblackbox.record_feedback("nested tally", "admin_secrets_fun_used", 1, list("Emag Machines"))
	log_admin("[key_name(usr)] emagged [what] on the station: [done] machines")
	message_admins("<span class='adminnotice'>[key_name_admin(usr)] emagged [what] on the station: [done] machines</span>")
