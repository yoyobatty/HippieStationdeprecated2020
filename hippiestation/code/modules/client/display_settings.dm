// The Display panel, the Display button on the game window. What was up in the menu bar is here: the menu bar is white, whatever
// the theme, and it took a row of the screen. The choices are the menu's own (interface/menu.dm), saved the same way.

/client
	/// The window theme now showing. The chat keeps the choice, in a cookie, and says so at login (browserOutput.dm).
	var/dark_theme = TRUE
	var/datum/display_settings/display_settings

/client/verb/display_settings()
	set name = "Display Settings"
	set category = "OOC"
	set desc = "Icon size, scaling, fullscreen and the dark theme"
	if(!display_settings)
		display_settings = new(src)
	display_settings.ui_interact(mob)

/client/verb/toggle_fullscreen()
	set name = "Toggle Fullscreen"
	set category = "OOC"
	set desc = "Fill the whole screen with the game, with no title bar"
	prefs.fullscreen_mode = !prefs.fullscreen_mode
	prefs.save_preferences()
	set_fullscreen()
	if(prefs.auto_fit_viewport)
		addtimer(CALLBACK(src, VERB_REF(fit_viewport)), 1 SECONDS) //the map's just changed shape

/client/proc/set_fullscreen()
	winset(src, "mainwindow", "is-fullscreen=[prefs.fullscreen_mode ? "true" : "false"]")

/datum/display_settings
	var/client/owner

/datum/display_settings/New(client/C)
	owner = C

/datum/display_settings/Destroy()
	owner = null
	return ..()

/datum/display_settings/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "display_settings", "Display", 400, 420, master_ui, state)
		ui.open()

/// The choices in one of the menu's groups, in the order it lists them, with the one that's picked.
/datum/display_settings/proc/group_data(menu_type)
	var/datum/verbs/menu/M = GLOB.menulist[menu_type]
	var/picked = M.Get_checked(owner)
	. = list()
	for(var/procpath/entry as anything in typesof("[menu_type]/verb"))
		. += list(list("name" = replacetext(entry.desc, "&", ""), "path" = "[entry]", "picked" = entry == picked))

/datum/display_settings/ui_data(mob/user)
	. = list()
	.["sizes"] = group_data(/datum/verbs/menu/Icon/Size)
	.["scalings"] = group_data(/datum/verbs/menu/Icon/Scaling)
	.["auto_fit"] = owner.prefs.auto_fit_viewport
	.["fullscreen"] = owner.prefs.fullscreen_mode
	.["dark"] = owner.dark_theme

/// Picks one of a menu group's entries, and it takes effect the way it does at login.
/datum/display_settings/proc/pick_entry(menu_type, path_text)
	var/verbpath = text2path(path_text)
	if(!verbpath || !(verbpath in typesof("[menu_type]/verb")))
		return
	var/datum/verbs/menu/M = GLOB.menulist[menu_type]
	M.Set_checked(owner, verbpath)
	M.Load_checked(owner)

/datum/display_settings/ui_act(action, params)
	if(..() || !owner)
		return
	switch(action)
		if("size")
			pick_entry(/datum/verbs/menu/Icon/Size, params["path"])
		if("scaling")
			pick_entry(/datum/verbs/menu/Icon/Scaling, params["path"])
		if("fit")
			owner.fit_viewport()
		if("auto_fit")
			owner.prefs.auto_fit_viewport = !owner.prefs.auto_fit_viewport
			owner.prefs.save_preferences()
			if(owner.prefs.auto_fit_viewport)
				owner.fit_viewport()
		if("fullscreen")
			owner.toggle_fullscreen()
		if("dark")
			owner << output(null, "browseroutput:swap") //the chat's own toggle: it has the cookie, and it calls back to theme the window
			owner.dark_theme = !owner.dark_theme
		if("screenshot")
			winset(owner, null, "command=.screenshot [params["ask"] ? "" : "auto"]")
	return TRUE
