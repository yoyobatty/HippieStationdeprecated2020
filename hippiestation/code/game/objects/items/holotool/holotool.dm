/obj/item/holotool
	name = "experimental holotool"
	desc = "A highly experimental holographic tool projector."
	icon = 'hippiestation/icons/obj/holotool.dmi'
	icon_state = "holotool"
	slot_flags = ITEM_SLOT_BELT
	usesound = 'sound/items/pshoom.ogg'
	lefthand_file = 'hippiestation/icons/mob/inhands/lefthand.dmi'
	righthand_file = 'hippiestation/icons/mob/inhands/righthand.dmi'
	actions_types = list(/datum/action/item_action/change_tool, /datum/action/item_action/change_ht_color)
	resistance_flags = FIRE_PROOF | ACID_PROOF

	var/datum/holotool_mode/current_tool
	/// Every mode it has, made once (modes.dm).
	var/list/modes
	/// The ones it can be set to as it is: mode name -> mode.
	var/list/mode_names
	var/list/radial_modes
	var/current_color = "#48D1CC" //mediumturquoise
	/// The multitool it is in that mode. A machine that links through a multitool's buffer wants a multitool and nothing else
	/// (multitool_check_buffer()), so the holo one could pulse wires and couldn't link a thing: clicks go through this one.
	var/obj/item/multitool/holotool/buffer_tool

/obj/item/multitool/holotool
	name = "holo-multitool"
	desc = "A multitool, as a holotool projects it."
	toolspeed = 0.125
	usesound = 'sound/items/rped.ogg'

/obj/item/holotool/Initialize()
	. = ..()
	modes = list()
	for(var/path in subtypesof(/datum/holotool_mode))
		modes += new path
	buffer_tool = new(src)

/obj/item/holotool/Destroy()
	current_tool = null
	modes = null
	mode_names = null
	radial_modes = null
	QDEL_NULL(buffer_tool)
	return ..()

/obj/item/holotool/examine(mob/user)
	. = ..()
	. += "<span class='notice'>It is currently set to [current_tool ? current_tool.name : "'off'"] mode.</span>"
	. += "<span class='notice'>Use it in hand or Ctrl+Click it to pick a tool. Alt+Click switches it off.</span>"
	if(current_tool?.hands_to_buffer_tool && buffer_tool.buffer)
		. += "<span class='notice'>Its buffer holds [buffer_tool.buffer].</span>"

/// What it can be set to as it is: an emagged one has more.
/obj/item/holotool/proc/update_listing()
	mode_names = list()
	radial_modes = list()
	for(var/datum/holotool_mode/M as anything in modes)
		if(!M.can_be_used(src))
			continue
		mode_names[M.name] = M
		var/image/holotool_img = image(icon = icon, icon_state = "holotool")
		var/image/tool_img = image(icon = icon, icon_state = M.name)
		tool_img.color = current_color
		holotool_img.overlays += tool_img
		radial_modes[M.name] = holotool_img
	if(current_tool)
		radial_modes["off"] = image(icon = icon, icon_state = "holotool")

/obj/item/holotool/proc/check_menu(mob/living/user)
	if(!istype(user))
		return FALSE
	if(user.incapacitated() || !user.Adjacent(src))
		return FALSE
	return TRUE

/obj/item/holotool/proc/open_menu(mob/user)
	if(!check_menu(user))
		return
	update_listing()
	var/chosen = show_radial_menu(user, src, radial_modes, custom_check = CALLBACK(src, PROC_REF(check_menu), user))
	if(!chosen || !check_menu(user))
		return
	switch_tool(user, chosen == "off" ? null : mode_names[chosen])

/// To this mode, or off with none.
/obj/item/holotool/proc/switch_tool(mob/user, datum/holotool_mode/mode)
	if(mode == current_tool || (mode && !istype(mode)))
		return
	if(current_tool)
		current_tool.on_unset(src)
	current_tool = mode
	if(current_tool)
		current_tool.on_set(src)
	playsound(loc, 'sound/items/rped.ogg', get_clamped_volume(), 1, -1)
	update_icon()
	if(user)
		user.regenerate_icons()

/obj/item/holotool/attack_self(mob/user)
	open_menu(user)

/obj/item/holotool/CtrlClick(mob/user)
	if(!check_menu(user))
		return ..()
	open_menu(user)

/obj/item/holotool/AltClick(mob/user)
	if(!current_tool || !check_menu(user))
		return ..()
	switch_tool(user, null)
	to_chat(user, "<span class='notice'>You switch [src] off.</span>")

// The two buttons: the tool, and its colour. They were one proc written twice, the second over the first, so both opened the tool
// menu and nothing changed the colour.
/obj/item/holotool/ui_action_click(mob/user, datum/action/action)
	if(!istype(action, /datum/action/item_action/change_ht_color))
		open_menu(user)
		return
	var/C = input(user, "Select Color", "Select color", current_color) as null|color
	if(!C || QDELETED(src) || !check_menu(user))
		return
	current_color = C
	update_icon()
	user.regenerate_icons()

/obj/item/holotool/update_icon()
	cut_overlays()
	if(current_tool)
		var/mutable_appearance/holo_item = mutable_appearance(icon, current_tool.name)
		holo_item.color = current_color
		item_state = current_tool.name
		add_overlay(holo_item)
		set_light(3, null, current_color)
	else
		item_state = "holotool"
		icon_state = "holotool"
		set_light(0)

	for(var/datum/action/A in actions)
		A.UpdateButtonIcon()

/// A click with it goes through the multitool inside it in that mode, so whatever asks for a multitool gets one.
/obj/item/holotool/melee_attack_chain(mob/user, atom/target, params)
	if(current_tool?.hands_to_buffer_tool && buffer_tool)
		return buffer_tool.melee_attack_chain(user, target, params)
	return ..()

/obj/item/holotool/emag_act(mob/user)
	if(obj_flags & EMAGGED)
		return
	to_chat(user, "<span class='danger'>ZZT- ILLEGAL BLUEPRINT UNLOCKED- CONTACT !#$@^%$# NANOTRASEN SUPPORT-@*%$^%!</span>")
	do_sparks(5, 0, src)
	obj_flags |= EMAGGED


// Spawn in RD closet
/obj/structure/closet/secure_closet/RD/PopulateContents()
	. = ..()
	new /obj/item/holotool(src)
