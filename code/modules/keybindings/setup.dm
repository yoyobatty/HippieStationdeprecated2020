/client
	/// A rolling buffer of any keys held currently
	var/list/keys_held = list()
	///used to keep track of the current rolling buffer position
	var/current_key_address = 0
	/// These next two vars are to apply movement for keypresses and releases made while move delayed.
	/// Because discarding that input makes the game less responsive.
 	/// On next move, add this dir to the move that would otherwise be done
	var/next_move_dir_add
 	/// On next move, subtract this dir from the move that would otherwise be done
	var/next_move_dir_sub
	/// The move intent to go back to when the hold-to-walk key comes up, while it's down.
	var/held_move_intent
	/// Set while watch_held_keys() is going.
	var/watching_held_keys = FALSE
	/// Where the keyboard's focus was, while watch_held_keys() lets go of the keys it decided were lost there (for the player log).
	var/held_keys_lost_to

// Set a client's focus to an object and override these procs on that object to let it handle keypresses

/datum/proc/key_down(key, client/user) // Called when a key is pressed down initially
	return
/datum/proc/key_up(key, client/user) // Called when a key is released
	return
/datum/proc/keyLoop(client/user) // Called once every frame
	set waitfor = FALSE
	return

/// Whether a key let go now would reach keyUp(), going by winget(client, null, "focus"). The one place known to swallow releases
/// is a browser control that isn't a tgui window (a browse() popup, the chat pane, the stat panel, the preferences page): their
/// pages don't pass keys on. Everything else hears keys through the macros. That includes "mainwindow" and "", which is all BYOND
/// says while the say prompt is open and also with the window minimised (is-minimized, pos and size read the same as normal, 516),
/// so a minimised window can't be told apart and isn't tried. Asking "is it the map or the chat bar" instead let go of keys
/// still held 43 times in 7 of the user's rounds (2026-11-02..05) and caught a lost release 0 times: they stopped dead in the
/// middle of walking. tgui windows pass keys on and let them go themselves (tgui-next/packages/tgui/hotkeys.js).
/client/proc/focus_hears_keys(focused)
	if(!findtext(focused, "browser"))
		return TRUE
	for(var/datum/tgui/ui as anything in mob?.open_uis)
		if(findtext(focused, ui.window_id) == 1)
			return TRUE
	return FALSE

/// Lets go of every key the game thinks is held, as if it had been released.
/client/proc/reset_held_keys()
	for(var/i in 1 to HELD_KEY_BUFFER_LENGTH)
		var/key = keys_held[i]
		if(key)
			keyUp(key)

/// BYOND tells nobody when a window loses the keyboard, so while something's held, ask. Otherwise a key let go after an Alt-Tab
/// stays down for good: running on by itself, every hotkey read as Alt+key, or stuck walking. A second is about as long as a
/// person takes to notice, and it only costs anything while a key is down.
/client/proc/watch_held_keys()
	set waitfor = FALSE
	if(watching_held_keys)
		return
	watching_held_keys = TRUE
	while(src && any_key_held())
		sleep(1 SECONDS)
		if(!src)
			return
		var/focused = winget(src, null, "focus")
		if(!src)
			return
		if(!focus_hears_keys(focused))
			held_keys_lost_to = focused
			reset_held_keys()
			held_keys_lost_to = null
	if(src)
		watching_held_keys = FALSE

/client/proc/any_key_held()
	for(var/i in 1 to HELD_KEY_BUFFER_LENGTH)
		if(keys_held[i])
			return TRUE
	return FALSE

/// Every click says which modifiers are really down: one that isn't, and the game thinks is, had its release lost.
/client/proc/check_modifiers_against(list/click_params)
	for(var/mod in list("Alt", "Ctrl", "Shift"))
		if(keys_held[mod] && !click_params[lowertext(mod)])
			keyUp(mod)

// removes all the existing macros
/client/proc/erase_all_macros()
	var/erase_output = ""
	var/list/macro_set = params2list(winget(src, "default.*", "command")) // The third arg doesnt matter here as we're just removing them all
	for(var/k in 1 to length(macro_set))
		var/list/split_name = splittext(macro_set[k], ".")
		var/macro_name = "[split_name[1]].[split_name[2]]" // [3] is "command"
		erase_output = "[erase_output];[macro_name].parent=null"
	winset(src, null, erase_output)

/client/proc/set_macros()
	set waitfor = FALSE

	//Reset and populate the rolling buffer
	keys_held.Cut()
	for(var/i in 1 to HELD_KEY_BUFFER_LENGTH)
		keys_held += null

	erase_all_macros()

	var/list/macro_set = SSinput.macro_set
	for(var/k in 1 to length(macro_set))
		var/key = macro_set[k]
		var/command = macro_set[key]
		winset(src, "default-[REF(key)]", "parent=default;name=[key];command=[command]")
	talk_macro_ids = null // hippie -- erase_all_macros() took those too
	set_talk_macros() // hippie -- say, me, ooc and the rest on whatever keys they're bound to

	chat_bar_hotkey_mode() // hippie -- the chat bar has the keyboard in classic mode (the old input bar is gone)
