// Master multitool: the Chief Engineer's multitool. Everything a multitool does, plus:
// - three buffer slots instead of one, to switch between (each machine that links via the buffer uses the active slot)
// - remote wire links: clip a link probe to up to four machines' wiring while their maintenance panel is open, then pulse
//   their wires from its screen from up to REMOTE_WIRE_RANGE tiles away. Pulse only: cutting and attaching still need
//   hands on the wires, and a probe only works while the panel it's behind is open. Anyone looking into an open panel
//   sees the probe. Remote pulses are logged.

/// How many buffer slots it has
#define MASTER_MULTITOOL_SLOTS 3
/// How many machines it can be linked to at once
#define MASTER_MULTITOOL_LINKS 4
/// How far away it can pulse a linked machine's wires from
#define REMOTE_WIRE_RANGE 16

/obj/item/multitool/master
	name = "master multitool"
	desc = "The Chief Engineer's multitool. It keeps three buffers, and its link probes let it pulse the wiring of up to four machines from across the room, while their maintenance panels are open."
	icon = 'hippiestation/icons/obj/dept_gear.dmi'
	icon_state = "master_multitool"
	item_state = "master_multitool"
	lefthand_file = 'hippiestation/icons/mob/inhands/dept_gear_lefthand.dmi'
	righthand_file = 'hippiestation/icons/mob/inhands/dept_gear_righthand.dmi'
	toolspeed = 0.5
	/// Weak references to what each buffer slot holds; the active slot's is kept in the regular buffer var while it's active
	var/list/datum/weakref/buffer_slots
	/// Which slot is active
	var/active_slot = 1
	/// Weak references to the machines it has link probes on
	var/list/datum/weakref/links = list()
	/// The link whose wires its screen is showing
	var/datum/weakref/selected_link
	/// Set from its screen: the next machine it's used on gets a link probe
	var/linking = FALSE

/obj/item/multitool/master/Initialize()
	. = ..()
	buffer_slots = new /list(MASTER_MULTITOOL_SLOTS)

/obj/item/multitool/master/Destroy()
	for(var/datum/weakref/link as anything in links)
		var/obj/machinery/M = link.resolve()
		if(M)
			UnregisterSignal(M, list(COMSIG_PARENT_EXAMINE, COMSIG_PARENT_QDELETING))
	links = null
	selected_link = null
	buffer_slots = null
	buffer = null
	return ..()

/obj/item/multitool/master/examine(mob/user)
	. = ..()
	sync_buffer()
	for(var/i in 1 to MASTER_MULTITOOL_SLOTS)
		var/datum/weakref/slot = buffer_slots[i]
		var/atom/held = slot?.resolve()
		. += "<span class='notice'>Buffer [i][i == active_slot ? " (active)" : ""]: [held ? held.name : "empty"].</span>"
	. += "<span class='notice'>It has link probes on [length(get_links())] of [MASTER_MULTITOOL_LINKS] machines. Use it in hand to open its screen.</span>"

/obj/item/multitool/master/attack_self(mob/user)
	ui_interact(user)

// Linking: with linking armed from the screen, the next machine it's used on gets a probe instead of the usual multitool
// use. This goes ahead of the whole attack chain, since plenty of machines take a multitool in their tool_act().
/obj/item/multitool/master/melee_attack_chain(mob/user, atom/target, params)
	if(!linking || !istype(target, /obj/machinery))
		return ..()
	linking = FALSE
	SStgui.update_uis(src)
	var/obj/machinery/M = target
	if(!M.wires)
		to_chat(user, "<span class='warning'>[M] has no wiring to clip a probe to.</span>")
		return
	if(!remote_wires_exposed(M))
		to_chat(user, "<span class='warning'>[M]'s wiring is behind its closed maintenance panel.</span>")
		return
	if(M in get_links())
		to_chat(user, "<span class='notice'>[src] already has a probe on [M].</span>")
		return
	if(length(get_links()) >= MASTER_MULTITOOL_LINKS)
		to_chat(user, "<span class='warning'>[src] has no free link probes. Unlink a machine first.</span>")
		return
	add_link(M)
	play_tool_sound(M, 20)
	to_chat(user, "<span class='notice'>You clip a link probe to [M]'s wiring.</span>")

/// Whether a machine's wires can be reached right now: the same rule its wires' interactable() uses, without the shock
/obj/item/multitool/master/proc/remote_wires_exposed(obj/machinery/M)
	if(istype(M, /obj/machinery/power/apc))
		var/obj/machinery/power/apc/apc = M
		return apc.panel_open && !apc.opened
	return M.panel_open

/obj/item/multitool/master/proc/add_link(obj/machinery/M)
	links += WEAKREF(M)
	RegisterSignal(M, COMSIG_PARENT_EXAMINE, PROC_REF(on_linked_examine))
	RegisterSignal(M, COMSIG_PARENT_QDELETING, PROC_REF(on_linked_deleted))
	if(!selected_link?.resolve())
		selected_link = WEAKREF(M)

/obj/item/multitool/master/proc/remove_link(obj/machinery/M)
	// M's own weakref: WEAKREF() gives null for something mid-deletion, which is when on_linked_deleted() calls this
	var/datum/weakref/link = M.weak_reference
	links -= link
	UnregisterSignal(M, list(COMSIG_PARENT_EXAMINE, COMSIG_PARENT_QDELETING))
	if(link && selected_link == link)
		selected_link = null

/obj/item/multitool/master/proc/on_linked_examine(obj/machinery/source, mob/user, list/examine_list)
	if(remote_wires_exposed(source))
		examine_list += "<span class='notice'>A small link probe is clipped to its wiring.</span>"

/obj/item/multitool/master/proc/on_linked_deleted(obj/machinery/source)
	remove_link(source)

/// The machines it still has probes on, dropping any that are gone
/obj/item/multitool/master/proc/get_links()
	. = list()
	for(var/datum/weakref/link as anything in links.Copy())
		var/obj/machinery/M = link.resolve()
		if(M)
			. += M
		else
			links -= link

/// Keeps the active slot in step with the buffer var, which machines write to directly
/obj/item/multitool/master/proc/sync_buffer()
	buffer_slots[active_slot] = buffer ? WEAKREF(buffer) : null

/obj/item/multitool/master/proc/select_slot(slot)
	if(slot < 1 || slot > MASTER_MULTITOOL_SLOTS)
		return
	sync_buffer()
	active_slot = slot
	var/datum/weakref/stored = buffer_slots[slot]
	buffer = stored?.resolve()

/// Why a linked machine's wires can't be pulsed from where the user is, or null if they can
/obj/item/multitool/master/proc/remote_problem(obj/machinery/M, mob/user)
	var/turf/here = get_turf(user)
	var/turf/there = get_turf(M)
	if(!here || !there || here.z != there.z)
		return "out of range"
	if(get_dist(here, there) > REMOTE_WIRE_RANGE)
		return "out of range"
	if(!remote_wires_exposed(M))
		return "panel closed"
	return null

/obj/item/multitool/master/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.hands_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "master_multitool", name, 420, 560, master_ui, state)
		ui.open()

/obj/item/multitool/master/ui_data(mob/user)
	var/list/data = list()
	sync_buffer()
	data["slots"] = list()
	for(var/i in 1 to MASTER_MULTITOOL_SLOTS)
		var/datum/weakref/slot = buffer_slots[i]
		var/atom/held = slot?.resolve()
		data["slots"] += list(list("index" = i, "name" = held ? "[held.name] ([get_area_name(held, TRUE)])" : null, "active" = i == active_slot))
	data["linking"] = linking
	data["max_links"] = MASTER_MULTITOOL_LINKS
	var/obj/machinery/selected = selected_link?.resolve()
	data["links"] = list()
	for(var/obj/machinery/M as anything in get_links())
		var/turf/here = get_turf(user)
		var/turf/there = get_turf(M)
		data["links"] += list(list(
			"ref" = REF(M),
			"name" = M.name,
			"area" = get_area_name(M, TRUE),
			"distance" = (here && there && here.z == there.z) ? get_dist(here, there) : null,
			"problem" = remote_problem(M, user),
			"selected" = M == selected
		))
	data["selected"] = null
	if(selected && selected.wires)
		var/datum/wires/W = selected.wires
		var/list/wires = list()
		for(var/color in W.colors)
			wires += list(list("color" = color, "cut" = W.is_color_cut(color), "attached" = W.is_attached(color)))
		data["selected"] = list(
			"name" = selected.name,
			"problem" = remote_problem(selected, user),
			"wires" = wires,
			"status" = W.get_status()
		)
	return data

/obj/item/multitool/master/ui_act(action, params)
	if(..())
		return
	var/mob/living/user = usr
	switch(action)
		if("select_slot")
			select_slot(text2num(params["slot"]))
			. = TRUE
		if("clear_slot")
			var/slot = text2num(params["slot"])
			if(slot >= 1 && slot <= MASTER_MULTITOOL_SLOTS)
				buffer_slots[slot] = null
				if(slot == active_slot)
					buffer = null
				. = TRUE
		if("toggle_linking")
			linking = !linking
			if(linking)
				to_chat(user, "<span class='notice'>Use [src] on a machine with its maintenance panel open to clip a link probe to it.</span>")
			. = TRUE
		if("select_link")
			var/obj/machinery/M = locate(params["ref"]) in get_links()
			if(M)
				selected_link = WEAKREF(M)
				. = TRUE
		if("unlink")
			var/obj/machinery/M = locate(params["ref"]) in get_links()
			if(M)
				remove_link(M)
				to_chat(user, "<span class='notice'>[src] releases its link probe on [M].</span>")
				. = TRUE
		if("pulse")
			var/obj/machinery/M = selected_link?.resolve()
			if(!M?.wires)
				return
			var/problem = remote_problem(M, user)
			if(problem)
				to_chat(user, "<span class='warning'>Can't reach [M]'s wiring: [problem].</span>")
				return
			var/color = params["wire"]
			if(!(color in M.wires.colors))
				return
			var/wire = M.wires.get_wire(color)
			M.wires.pulse_color(color, user)
			playsound(src, usesound, 20, TRUE)
			playsound(M, 'sound/machines/click.ogg', 15, TRUE, -3)
			log_game("[key_name(user)] remotely pulsed the [wire] wire ([color]) of [M] at [AREACOORD(M)] with [src] from [AREACOORD(user)].")
			M.investigate_log("had its [wire] wire remotely pulsed by [key_name(user)] with [src].", INVESTIGATE_WIRES)
			. = TRUE

// A closer look (examine it twice): how to use it
/obj/item/multitool/master/examine_more(mob/user)
	. = ..()
	. += "<span class='notice'>It works as a normal multitool, with [MASTER_MULTITOOL_SLOTS] buffers you switch between on its screen. Whatever links through a multitool buffer uses the active one.</span>"
	. += "<span class='notice'>To pulse wires from a distance, arm linking on its screen, then use it on a machine with its maintenance panel open to clip a probe to the wiring. It has [MASTER_MULTITOOL_LINKS] probes. From its screen you can then pulse a linked machine's wires from up to [REMOTE_WIRE_RANGE] tiles away, as long as that panel stays open. Cutting and mending wires still needs your hands.</span>"


#undef MASTER_MULTITOOL_SLOTS
#undef MASTER_MULTITOOL_LINKS
#undef REMOTE_WIRE_RANGE
