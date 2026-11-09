// The game menu (tgui-next GameMenu.js): one window with the places players otherwise hunt for in the stat panel's tabs.
// The user's rulings (2026-11-07, making the game easier to get around): Esc opens it when the chat bar is empty (Esc still
// clears the bar first), and a Menu button in the stat panel does too. In it: Character Setup, Keybindings, Preferences, Ask for
// help, Who, Rules, Wiki, Changelog, Disconnect.

/client/var/datum/game_menu/game_menu

/// Esc (the default macro, SSinput) on the map opens the menu. In the chat bar Esc is the bar's own: it clears it and gives the
/// map the keyboard back.
/client/verb/escape_key()
	set name = "Escape-Key"
	set hidden = TRUE
	set instant = TRUE
	open_game_menu()

/client/verb/game_menu_verb()
	set name = "Game-Menu"
	set hidden = TRUE
	open_game_menu()

/client/proc/open_game_menu()
	if(!game_menu)
		game_menu = new
		game_menu.owner = src
	game_menu.ui_interact(mob)

/datum/game_menu
	var/client/owner
	/// Disconnect was pressed once: the next press quits
	var/disconnect_armed = FALSE

/datum/game_menu/Destroy()
	owner = null
	return ..()

/datum/game_menu/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		disconnect_armed = FALSE
		ui = new(user, src, ui_key, "game_menu", "Menu", 300, 430, master_ui, state)
		ui.open()

/datum/game_menu/ui_data(mob/user)
	var/datum/admin_help/AH = owner?.current_ticket
	var/datum/help_question/Q = owner?.current_question
	return list(
		"disconnect_armed" = disconnect_armed,
		"has_ticket" = (AH && AH.state == AHELP_ACTIVE) || (Q && Q.open),
		"has_rules" = !!CONFIG_GET(string/rulesurl),
		"has_wiki" = !!CONFIG_GET(string/wikiurl),
		"admin" = !!owner?.holder,
	)

/datum/game_menu/ui_act(action, list/params, datum/tgui/ui)
	if(..())
		return
	var/client/C = owner
	if(!C || usr.client != C)
		return
	if(action != "disconnect")
		disconnect_armed = FALSE
	switch(action)
		if("setup")
			C.prefs.current_tab = 0
			C.prefs.ShowChoices(C.mob)
		if("preferences")
			C.prefs.current_tab = 1
			C.prefs.ShowChoices(C.mob)
		if("keybindings")
			C.keybindings_menu()
		if("help")
			C.open_help_window()
		if("hub")
			if(C.holder)
				C.open_admin_hub()
		if("who")
			C.who()
		if("rules")
			var/url = CONFIG_GET(string/rulesurl)
			if(url)
				C << link(url)
		if("wiki")
			var/url = CONFIG_GET(string/wikiurl)
			if(url)
				C << link(url)
		if("changelog")
			C.changelog()
		if("disconnect")
			if(!disconnect_armed)
				disconnect_armed = TRUE
				return TRUE
			winset(C, null, "command=.quit")
			return
	ui?.close()

// The stat panel's tab, kept across rounds (the user's ruling, 2026-11-07)
/datum/preferences
	var/last_stat_tab

/// A tab picked: kept with their preferences a little later (saving writes the whole file)
/client/proc/remember_stat_tab(tab)
	if(!prefs || prefs.last_stat_tab == tab)
		return
	prefs.last_stat_tab = tab
	addtimer(CALLBACK(prefs, TYPE_PROC_REF(/datum/preferences, save_preferences)), 10 SECONDS, TIMER_UNIQUE | TIMER_OVERRIDE)
