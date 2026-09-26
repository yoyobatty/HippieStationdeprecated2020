/client/cmd_admin_rejuvenate(mob/living/M in GLOB.mob_list)
	..()
	M.unascend_animation()
	M.visible_message("<span class='warning bold'>[M] was healed by divine intervention!</span>")

/client/proc/admin_disable_shuttle()
	set category = "Admin"
	set name = "Disable Shuttle"
	if(!check_rights(R_ADMIN))	return

	if(SSshuttle.emergency.mode == SHUTTLE_DISABLED)
		to_chat(usr, "<span class='warning'>Error, shuttle is already disabled.</span>", confidential = TRUE)
		return

	if(alert(src, "You sure?", "Confirm", "Yes", "No") != "Yes") return

	message_admins("<span class='adminnotice'>[key_name_admin(usr)] disabled the shuttle.</span>")

	SSshuttle.lastMode = SSshuttle.emergency.mode
	SSshuttle.lastCallTime = SSshuttle.emergency.timeLeft(1)
	SSshuttle.adminEmergencyNoRecall = TRUE
	SSshuttle.emergency.setTimer(null)
	SSshuttle.emergency.mode = SHUTTLE_DISABLED
	priority_announce("Warning: Emergency Shuttle uplink failure, shuttle disabled until further notice.", "Emergency Shuttle Uplink Alert", 'sound/misc/announce_dig.ogg')

/client/proc/admin_enable_shuttle()
	set category = "Admin"
	set name = "Enable Shuttle"
	if(!check_rights(R_ADMIN))	return

	if(SSshuttle.emergency.mode != SHUTTLE_DISABLED)
		to_chat(usr, "<span class='warning'>Error, shuttle not disabled.</span>", confidential = TRUE)
		return

	if(alert(src, "You sure?", "Confirm", "Yes", "No") != "Yes") return

	message_admins("<span class='adminnotice'>[key_name_admin(usr)] enabled the emergency shuttle.</span>")
	SSshuttle.adminEmergencyNoRecall = FALSE
	SSshuttle.emergencyNoRecall = FALSE
	if(SSshuttle.lastMode == SHUTTLE_DISABLED) //If everything goes to shit, fix it.
		SSshuttle.lastMode = SHUTTLE_IDLE

	SSshuttle.emergency.mode = SSshuttle.lastMode
	if(SSshuttle.lastCallTime < 100 && SSshuttle.lastMode != SHUTTLE_IDLE)
		SSshuttle.lastCallTime = 100 //Make sure no insta departures.

	SSshuttle.emergency.setTimer(SSshuttle.lastCallTime)
	priority_announce("Warning: Emergency Shuttle uplink reestablished, shuttle enabled.", "Emergency Shuttle Uplink Alert", 'sound/misc/announce_dig.ogg')

/client/proc/admin_call_shuttle()
	set category = "Admin"
	set name = "Call Shuttle"

	if(EMERGENCY_AT_LEAST_DOCKED)
		return

	if(!check_rights(R_ADMIN))	return

	var/confirm = alert(src, "You sure?", "Confirm", "Yes", "Yes (No Recall)", "No")
	if(confirm == "No")
		return

	if(confirm == "Yes (No Recall)")
		SSshuttle.adminEmergencyNoRecall = TRUE
		SSshuttle.emergency.mode = SHUTTLE_IDLE

	SSshuttle.emergency.request()
	SSblackbox.record_feedback("tally", "admin_verb", 1, "Call Shuttle") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	log_admin("[key_name(usr)] admin-called the emergency shuttle.")
	if(confirm == "Yes (No Recall)")
		message_admins("<span class='adminnotice'>[key_name_admin(usr)] admin-called the emergency shuttle (non-recallable).</span>")
	else
		message_admins("<span class='adminnotice'>[key_name_admin(usr)] admin-called the emergency shuttle.</span>")
	return

/client/proc/admin_cancel_shuttle()
	set category = "Admin"
	set name = "Cancel Shuttle"
	if(!check_rights(0))
		return
	if(alert(src, "You sure?", "Confirm", "Yes", "No") != "Yes")
		return

	if(SSshuttle.adminEmergencyNoRecall)
		SSshuttle.adminEmergencyNoRecall = FALSE

	if(EMERGENCY_AT_LEAST_DOCKED)
		return

	SSshuttle.emergency.cancel()
	SSblackbox.record_feedback("tally", "admin_verb", 1, "Cancel Shuttle") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	log_admin("[key_name(usr)] admin-recalled the emergency shuttle.")
	message_admins("<span class='adminnotice'>[key_name_admin(usr)] admin-recalled the emergency shuttle.</span>")

	return

/client/proc/cmd_admin_fiery_explosion()
	set category = "Special Verbs"
	set name = "Fiery Explosion"
	set desc = "Cause a flame front that races outwards through open turfs with enough oxygen at your location, leaving CO2 behind."

	if(!check_rights(R_FUN))
		return

	var/range = input("Range of the flame front, 1 to [FIERY_EXPLOSION_MAX_RANGE]", text("Input"), 6) as num|null
	if(isnull(range))
		return
	range = clamp(round(range), 1, FIERY_EXPLOSION_MAX_RANGE)
	var/power = input("Power of the blast wave behind the flames. 0 for flames only, 1 is light, 3 breaks windows, 5+ devastates", text("Input"), 2) as num|null
	if(isnull(power))
		return
	power = max(power, 0)
	var/burn_damage = input("Burn damage to mobs at the centre, falling off towards the edge", text("Input"), 20) as num|null
	if(isnull(burn_damage))
		return
	burn_damage = max(burn_damage, 0)

	var/turf/epicenter = get_turf(mob) //we need to get this after the prompts as they may have moved
	if(!epicenter)
		return
	fiery_explosion(epicenter, range, power, burn_damage = burn_damage)
	message_admins("[ADMIN_LOOKUPFLW(usr)] created a fiery explosion (range [range], power [power], damage [burn_damage]) at [epicenter.loc].")
	log_admin("[key_name(usr)] created a fiery explosion (range [range], power [power], damage [burn_damage]) at [AREACOORD(epicenter)].")
	SSblackbox.record_feedback("tally", "admin_verb", 1, "Fiery Explosion") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/client/proc/cmd_admin_repair_machine(atom/O as obj|mob|turf in world)
	set category = "Special Verbs"
	set name = "Repair Machine"
	set desc = "Fully repairs a damaged obj: restores its integrity and clears broken/EMPed/maintenance states."

	if(!check_rights(R_FUN))
		return
	if(!isobj(O))
		to_chat(usr, "<span class='warning'>[O] isn't an object.</span>")
		return
	var/obj/target = O
	if(isnull(target.obj_integrity))
		to_chat(usr, "<span class='warning'>[target] has no integrity to repair.</span>")
		return

	var/was_damaged = (target.obj_integrity < target.max_integrity) || (target.resistance_flags & ON_FIRE)
	target.obj_integrity = target.max_integrity
	target.extinguish() // clears ON_FIRE and its overlay, which just resetting obj_integrity/stat doesn't touch

	if(istype(target, /obj/machinery))
		var/obj/machinery/M = target
		var/was_broken = (M.stat & (BROKEN|EMPED|MAINT))
		M.stat &= ~(BROKEN|EMPED|MAINT)
		M.update_icon()
		M.power_change() // re-checks its area's power and clears NOPOWER if it's actually got some
		was_damaged = was_damaged || was_broken
	else
		target.update_icon()

	if(!was_damaged)
		to_chat(usr, "<span class='notice'>[target] didn't need repairing.</span>")
		return

	log_admin("[key_name(usr)] repaired [target] at [AREACOORD(target)]")
	message_admins("[key_name_admin(usr)] repaired [ADMIN_VERBOSEJMP(target)]")
	SSblackbox.record_feedback("tally", "admin_verb", 1, "Repair Machine") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

// Surfaces Repair Machine in the View Variables dropdown too, the same way mob/vv_get_dropdown() surfaces "Toggle Godmode":
// just calls the existing admin verb directly rather than duplicating its logic.
/obj/vv_get_dropdown()
	. = ..()
	if(!isnull(obj_integrity))
		VV_DROPDOWN_OPTION(VV_HK_REPAIR_MACHINE, "Repair Machine")

/obj/vv_do_topic(list/href_list)
	. = ..()
	if(href_list[VV_HK_REPAIR_MACHINE])
		if(!check_rights(R_FUN))
			return
		usr.client.cmd_admin_repair_machine(src)
