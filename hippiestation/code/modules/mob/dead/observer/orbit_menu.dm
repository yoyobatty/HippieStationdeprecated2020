// Orbit menu: the ghost's Orbit verb as a searchable window, split into the living, bots and NPCs, points of interest,
// the dead and other ghosts, instead of one long list picker. Admins also get an antagonists section. The list is built
// when the window opens and on Refresh, not every tick - it walks every mob.
/mob/dead/observer
	var/datum/orbit_menu/orbit_menu

/mob/dead/observer/Destroy()
	QDEL_NULL(orbit_menu)
	return ..()

/datum/orbit_menu
	var/mob/dead/observer/owner

/datum/orbit_menu/New(mob/dead/observer/new_owner)
	owner = new_owner

/datum/orbit_menu/Destroy()
	SStgui.close_uis(src)
	owner = null
	return ..()

/datum/orbit_menu/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
								datum/tgui/master_ui = null, datum/ui_state/state = GLOB.observer_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "orbit", "Orbit", 480, 600, master_ui, state)
		ui.set_autoupdate(FALSE)
		ui.open()

/datum/orbit_menu/ui_data(mob/user)
	var/list/alive = list()
	var/list/antagonists = list()
	var/list/npcs = list()
	var/list/misc = list()
	var/list/dead = list()
	var/list/ghosts = list()
	var/show_antags = check_rights_for(user.client, R_ADMIN)
	var/list/pois = getpois(skip_mindless = TRUE)
	for(var/name in pois)
		var/atom/movable/target = pois[name]
		if(target == user)
			continue
		var/list/entry = list("name" = name, "ref" = REF(target))
		if(!ismob(target))
			misc += list(entry)
			continue
		var/mob/M = target
		if(isobserver(M))
			ghosts += list(entry)
		else if(M.stat == DEAD)
			dead += list(entry)
		else if(!M.mind && !M.ckey) // bots, megafauna and cameras that getpois keeps anyway
			npcs += list(entry)
		else if(show_antags && length(M.mind?.antag_datums))
			var/list/roles = list()
			for(var/datum/antagonist/A in M.mind.antag_datums)
				roles += A.name
			entry["antag"] = english_list(roles)
			antagonists += list(entry)
		else
			alive += list(entry)
	return list(
		"antagonists" = antagonists,
		"alive" = alive,
		"npcs" = npcs,
		"misc" = misc,
		"dead" = dead,
		"ghosts" = ghosts,
	)

/datum/orbit_menu/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("orbit")
			var/atom/movable/target = locate(params["ref"])
			// only what the menu could have offered: a mob or a point of interest
			if(!istype(target) || QDELETED(target) || !(ismob(target) || (target in GLOB.poi_list)))
				to_chat(usr, "<span class='warning'>That's not there anymore.</span>")
				return TRUE
			owner.ManualFollow(target)
			return TRUE
		if("refresh")
			return TRUE
