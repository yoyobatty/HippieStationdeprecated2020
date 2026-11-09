// The keybind panel (tgui-next KeybindPanel.js), the user's rulings of 2026-11-07: one panel in Character Setup's Keybindings tab and
// in a window of its own (the Keybindings verb, OOC), so a key can be changed mid-round without all of Character Setup. Click a key,
// press the new one; Escape clears it. A key another action already uses asks: move it here, keep both, or cancel. The mode
// (Hotkey or Classic) and its switch are at the top. Keys show as "Ctrl+Shift+E", not BYOND's "CtrlShiftE".
//
// Say, Me and OOC were fixed macros (T, M, O in SSinput); they're binds now, and a key bound to one gets a client-side macro that
// runs the verb, as the fixed ones did, so the prompt opens with no trip to the server. "Any" still fires keyDown() for a key that
// has a macro of its own (tools/keybind_check/macro_probe.dm, real client, 2026-11-07), so a talk key can also do something else.
//
// A save from before this has none of the new actions. Each gets its default key if nothing that could fire with it uses that key
// (tg's way), and the player is told once. Say, Me and OOC always get theirs: T, M and O opened them whatever else they did.

#define KB_FOR_HUMANLIKE (1<<0)
#define KB_FOR_ROBOT (1<<1)
#define KB_FOR_AI (1<<2)
#define KB_FOR_OTHER (1<<3)
#define KB_FOR_ALL (KB_FOR_HUMANLIKE|KB_FOR_ROBOT|KB_FOR_AI|KB_FOR_OTHER)
#define KB_FOR_NOT_SILICON (KB_FOR_HUMANLIKE|KB_FOR_OTHER)
/// The longest key name a capture may save: "AltCtrlShift" and a key name
#define KB_MAX_KEY_LENGTH 32

/datum/keybinding
	/// Which mobs this can fire for. Two actions on one key only clash if some mob could fire both: Q drops an item and unequips a
	/// cyborg's module, and nothing is both.
	var/applies_to = KB_FOR_ALL

/// Whether one key doing both would fire both for some mob
/proc/keybinds_clash(datum/keybinding/A, datum/keybinding/B)
	return A && B && A != B && (A.applies_to & B.applies_to)

/// The new actions, for a save that has never seen them (see add_new_keybind_defaults())
GLOBAL_LIST_INIT(keybinds_added_2026_11, list(
	"say", "me", "ooc", "radio", "pray", "whisper",
	"rest", "hold_throw_mode", "block_movement", "target_head", "target_eyes", "target_mouth", "select_left_hand", "select_right_hand",
	"quick_equip_suit_storage", "quick_equip_lpocket", "quick_equip_rpocket",
	"close_all_windows", "screenshot_save", "ai_reconnect_shell", "shell_disconnect", "deadmin", "readmin",
	))

/// Talk actions that were fixed macros: an old save gets these keys whatever else is on them
GLOBAL_LIST_INIT(keybinds_always_added, list("say", "me", "ooc"))

/// The verb each talk action's macro runs. BYOND asks for the text itself, before anything is sent.
/// Each talk action's chat bar verb and the text after it (radio is say with ";"): its key opens the bar on that verb
GLOBAL_LIST_INIT(talk_keybind_commands, list(
	"say" = list("Say", null),
	"me" = list("Me", null),
	"ooc" = list("OOC", null),
	"radio" = list("Say", ";"),
	"pray" = list("Pray", null),
	"whisper" = list("Whisper", null),
	))

/// The panel's sections, in order, and the actions in each. Anything not listed goes under its category.
GLOBAL_LIST_INIT(keybind_sections, list(
	"Movement" = list("North", "South", "West", "East", "face_north", "face_south", "face_west", "face_east", "toggle_move_intent", "toggle_move_intent_alt", "block_movement"),
	"Talk" = list("say", "radio", "whisper", "me", "ooc", "pray"),
	"Hands" = list("swap_hands", "select_left_hand", "select_right_hand", "activate_inhand", "drop_item", "toggle_throw_mode", "hold_throw_mode", "stop_pulling", "resist", "rest"),
	"Equipment" = list("quick_equip", "quick_equipbelt", "bag_equip", "quick_equip_suit_storage", "quick_equip_lpocket", "quick_equip_rpocket", "nanosuit_menu"),
	"Intents" = list("select_help_intent", "select_disarm_intent", "select_grab_intent", "select_harm_intent", "cycle_intent_left", "cycle_intent_right"),
	"Targeting" = list("target_head_cycle", "target_head", "target_eyes", "target_mouth", "target_r_arm", "target_body_chest", "target_left_arm", "target_right_leg", "target_body_groin", "target_left_leg"),
	"Silicon" = list("module_one", "module_two", "module_three", "cycle_intent", "unequip_module", "shell_disconnect", "ai_reconnect_shell"),
	"Client" = list("admin_help", "screenshot", "screenshot_save", "toggle_fullscreen", "minimal_hud", "close_all_windows"),
	))

/// What the panel and chat call a key BYOND names differently
GLOBAL_LIST_INIT(keybind_key_labels, list(
	"North" = "Up", "South" = "Down", "West" = "Left", "East" = "Right",
	"Northwest" = "Home", "Northeast" = "Page Up", "Southwest" = "End", "Southeast" = "Page Down", "Center" = "Clear",
	"Back" = "Backspace", "Return" = "Enter", "Apps" = "Menu", "Snapshot" = "Print Screen",
	"Add" = "Num +", "Subtract" = "Num -", "Multiply" = "Num *", "Divide" = "Num /", "Decimal" = "Num .",
	))

/// Splits a saved key into its modifiers (Alt, Ctrl, Shift, in the order keyDown() puts them) and the key: list(mods, key). A key
/// that is only modifiers ("Alt", "CtrlShift") has an empty key.
/proc/keybind_split(full_key)
	var/list/mods = list()
	var/rest = full_key
	for(var/mod in list("Alt", "Ctrl", "Shift"))
		if(findtext(rest, mod) == 1)
			mods += mod
			rest = copytext(rest, length(mod) + 1)
	return list(mods, rest)

/// "CtrlShiftE" as people write it: "Ctrl+Shift+E". "North" is "Up", "Numpad8" is "Num 8".
/proc/keybind_label(full_key)
	if(!full_key || full_key == "Unbound")
		return "None"
	var/list/split = keybind_split(full_key)
	var/list/mods = split[1]
	var/key = split[2]
	var/list/parts = list()
	for(var/mod in list("Ctrl", "Alt", "Shift"))
		if(mod in mods)
			parts += mod
	if(key)
		if(findtext(key, "Numpad") == 1 && length(key) == 7)
			key = "Num [copytext(key, 7)]"
		parts += GLOB.keybind_key_labels[key] || key
	return parts.Join("+")

/// The name of BYOND's macro for a saved key: "Ctrl+Shift+E"
/proc/keybind_macro_name(full_key)
	var/list/split = keybind_split(full_key)
	var/list/parts = split[1]
	if(split[2])
		parts += split[2]
	return parts.Join("+")

// Talk macros

/client
	/// The macros made for talk actions, so a rebind can take them away (set_talk_macros())
	var/list/talk_macro_ids
	/// Block movement is held: the movement keys turn you instead (keyLoop())
	var/movement_locked = FALSE
	var/datum/keybind_menu/keybind_menu

/// One macro for each key bound to a talk action, opening the chat bar on its verb, and Tab, giving the bar the keyboard (it
/// switched to the old input bar). set_macros() wipes every macro, then calls this.
/client/proc/set_talk_macros()
	if(length(talk_macro_ids))
		var/list/erase = list()
		for(var/id in talk_macro_ids)
			erase += "[id].parent=null"
		winset(src, null, erase.Join(";"))
	talk_macro_ids = list("default-talk-tab")
	winset(src, "default-talk-tab", list2params(list("parent" = "default", "name" = "Tab", "command" = chat_bar_command())))
	if(!prefs?.key_bindings)
		return
	for(var/key in prefs.key_bindings)
		if(key == "Unbound")
			continue
		for(var/kb_name in prefs.key_bindings[key])
			var/list/bar = GLOB.talk_keybind_commands[kb_name]
			if(!bar)
				continue
			var/command = chat_bar_command(bar[1], bar[2])
			var/id = "default-talk-[length(talk_macro_ids) + 1]"
			winset(src, id, list2params(list("parent" = "default", "name" = keybind_macro_name(key), "command" = command)))
			talk_macro_ids += id
			break //a key can run one command

/mob/verb/radio_verb(message as text)
	set name = "Radio"
	set category = "IC"
	set hidden = TRUE
	if(!length(message))
		return
	say_verb(";[message]")

// The standalone window

/client/verb/keybindings_menu()
	set name = "Keybindings"
	set category = "OOC"
	set desc = "Change which keys do what"
	if(!prefs)
		return
	if(!keybind_menu)
		keybind_menu = new(src)
	keybind_menu.ui_interact(mob)

/datum/keybind_menu
	var/client/owner

/datum/keybind_menu/New(client/C)
	owner = C

/datum/keybind_menu/Destroy()
	owner = null
	return ..()

/datum/keybind_menu/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "keybindings", "Keybindings", 560, 720, master_ui, state)
		ui.set_autoupdate(FALSE)
		ui.open()

/datum/keybind_menu/ui_status(mob/user, datum/ui_state/state)
	return (owner && user.client == owner) ? UI_INTERACTIVE : UI_CLOSE

/datum/keybind_menu/ui_data(mob/user)
	return owner?.prefs?.keybind_panel_data(user) || list()

/datum/keybind_menu/ui_act(action, list/params)
	if(..())
		return
	if(!owner || usr.client != owner)
		return
	return owner.prefs.keybind_act(action, params, usr)

// The panel

/datum/preferences
	/// Every action this save has seen, so one added later can be given its default key once (add_new_keybind_defaults())
	var/list/known_keybinds
	/// A key the player pressed that's already in use, waiting on "move it here, keep both or cancel": list(id, old key, new key)
	var/list/keybind_pending

/// What's bound to what, for KeybindPanel.js
/datum/preferences/proc/keybind_panel_data(mob/user)
	var/list/keys_of = list() //action -> its keys
	for(var/key in key_bindings)
		if(key == "Unbound")
			continue
		for(var/kb_name in key_bindings[key])
			keys_of[kb_name] += list(key)
	var/show_admin = parent && (parent.holder || GLOB.deadmins[parent.ckey])
	var/list/placed = list()
	var/list/sections = list()
	for(var/section in GLOB.keybind_sections)
		var/list/binds = list()
		for(var/kb_name in GLOB.keybind_sections[section])
			var/datum/keybinding/kb = GLOB.keybindings_by_name[kb_name]
			if(!kb)
				continue
			placed[kb_name] = TRUE
			binds += list(keybind_row(kb, keys_of))
		if(length(binds))
			sections += list(list("name" = section, "binds" = binds))
	var/list/by_category = list()
	for(var/kb_name in GLOB.keybindings_by_name)
		if(placed[kb_name])
			continue
		var/datum/keybinding/kb = GLOB.keybindings_by_name[kb_name]
		if(kb.category == CATEGORY_ADMIN && !show_admin)
			continue
		var/section = capitalize(lowertext(kb.category))
		if(kb.category == CATEGORY_EMOTE)
			section = "Emotes"
		by_category[section] += list(keybind_row(kb, keys_of))
	for(var/section in by_category)
		sections += list(list("name" = section, "binds" = by_category[section]))
	. = list()
	.["hotkeys"] = hotkeys
	.["sections"] = sections
	.["maxKeys"] = MAX_KEYS_PER_KEYBIND
	if(keybind_pending)
		var/datum/keybinding/kb = GLOB.keybindings_by_name[keybind_pending[1]]
		var/new_key = keybind_pending[3]
		var/list/others = list()
		for(var/other in keybind_clashes(kb, new_key))
			var/datum/keybinding/O = GLOB.keybindings_by_name[other]
			others += O.full_name
		.["pending"] = list("id" = kb.name, "name" = kb.full_name, "label" = keybind_label(new_key), "others" = others)

/datum/preferences/proc/keybind_row(datum/keybinding/kb, list/keys_of)
	var/list/keys = list()
	for(var/key in keys_of[kb.name])
		var/list/clashes = list()
		for(var/other in keybind_clashes(kb, key))
			var/datum/keybinding/O = GLOB.keybindings_by_name[other]
			clashes += O.full_name
		keys += list(list("key" = key, "label" = keybind_label(key), "clashes" = clashes))
	var/list/defaults = keybind_defaults(kb)
	var/list/default_labels = list()
	for(var/key in defaults)
		default_labels += keybind_label(key)
	var/list/mine = keys_of[kb.name] || list()
	var/is_default = length(mine) == length(defaults)
	if(is_default)
		for(var/key in mine)
			if(!(key in defaults))
				is_default = FALSE
				break
	return list("id" = kb.name, "name" = kb.full_name, "keys" = keys, "defaults" = default_labels.Join(", "), "isDefault" = is_default)

/// This mode's default keys for an action, leaving out the "Unbound" placeholder
/datum/preferences/proc/keybind_defaults(datum/keybinding/kb)
	. = list()
	for(var/key in (hotkeys ? kb.hotkey_keys : kb.classic_keys))
		if(key != "Unbound")
			. += key

/// The other actions on a key that would fire alongside this one
/datum/preferences/proc/keybind_clashes(datum/keybinding/kb, key)
	. = list()
	for(var/other in key_bindings[key])
		if(keybinds_clash(kb, GLOB.keybindings_by_name[other]))
			. += other

/datum/preferences/proc/keybind_unbind(kb_name, key)
	if(!key || !key_bindings[key])
		return
	key_bindings[key] -= kb_name
	if(!length(key_bindings[key]))
		key_bindings -= key

/datum/preferences/proc/keybind_bind(kb_name, key)
	if(kb_name in key_bindings[key])
		return
	key_bindings[key] += list(kb_name)
	key_bindings[key] = sortList(key_bindings[key])

/// A key the capture sent, as keyDown() will name it: the modifiers held, then the key (see the old keybindings_set)
/proc/keybind_from_capture(list/params)
	var/new_key = byond_key_name(params["key"], params["code"])
	var/alt = text2num(params["alt"]) ? "Alt" : ""
	var/ctrl = text2num(params["ctrl"]) ? "Ctrl" : ""
	var/shift = text2num(params["shift"]) ? "Shift" : ""
	switch(new_key)
		if("Alt")
			. = "Alt[ctrl][shift]"
		if("Ctrl")
			. = "[alt]Ctrl[shift]"
		if("Shift")
			. = "[alt][ctrl]Shift"
		else
			. = "[alt][ctrl][shift][new_key]"
	// A key is one character or a name made of letters and digits ("F11", "Numpad8", "North"): nothing else reaches keyDown()
	var/static/regex/named = regex(@"^[A-Za-z0-9]+$")
	var/static/regex/one_char = regex(@"^[\-=\[\]\\;',./`]$")
	var/bare = keybind_split(.)[2]
	if(!new_key || length(.) > KB_MAX_KEY_LENGTH || (bare && !named.Find(bare) && !one_char.Find(bare)))
		return null

/datum/preferences/proc/keybind_act(action, list/params, mob/user)
	var/datum/keybinding/kb = GLOB.keybindings_by_name[params["id"]]
	switch(action)
		if("kb_capture")
			if(!kb)
				return
			keybind_pending = null
			var/old_key = params["old"]
			if(old_key && !(kb.name in key_bindings[old_key]))
				old_key = null
			if(text2num(params["clear"]))
				keybind_unbind(kb.name, old_key)
				return keybind_changed()
			var/new_key = keybind_from_capture(params)
			if(!new_key)
				return TRUE
			if(!old_key && length(keybind_keys_of(kb.name)) >= MAX_KEYS_PER_KEYBIND)
				return TRUE
			if(length(keybind_clashes(kb, new_key)) && !(kb.name in key_bindings[new_key]))
				keybind_pending = list(kb.name, old_key, new_key)
				keybind_refresh()
				return TRUE
			keybind_unbind(kb.name, old_key)
			keybind_bind(kb.name, new_key)
			return keybind_changed()
		if("kb_resolve")
			var/list/pending = keybind_pending
			keybind_pending = null
			if(!pending || params["choice"] == "cancel")
				keybind_refresh()
				return TRUE
			kb = GLOB.keybindings_by_name[pending[1]]
			var/new_key = pending[3]
			if(params["choice"] == "move")
				for(var/other in keybind_clashes(kb, new_key))
					keybind_unbind(other, new_key)
			keybind_unbind(kb.name, pending[2])
			keybind_bind(kb.name, new_key)
			return keybind_changed()
		if("kb_reset")
			if(!kb)
				return
			keybind_pending = null
			for(var/key in keybind_keys_of(kb.name))
				keybind_unbind(kb.name, key)
			for(var/key in keybind_defaults(kb))
				keybind_bind(kb.name, key)
			return keybind_changed()
		if("kb_reset_all")
			keybind_pending = null
			key_bindings = deepCopyList(hotkeys ? GLOB.hotkey_keybinding_list_by_key : GLOB.classic_keybinding_list_by_key)
			return keybind_changed()
		if("kb_mode")
			var/want = params["mode"] == "hotkey"
			if(want != hotkeys)
				hotkeys = want
				parent?.chat_bar_hotkey_mode()
			return keybind_changed()

/datum/preferences/proc/keybind_keys_of(kb_name)
	. = list()
	for(var/key in key_bindings)
		if(key != "Unbound" && (kb_name in key_bindings[key]))
			. += key

/datum/preferences/proc/keybind_changed()
	save_preferences()
	if(parent)
		parent.update_movement_keys()
		parent.set_talk_macros()
	keybind_refresh()
	return TRUE

/// Both places the panel shows
/datum/preferences/proc/keybind_refresh()
	SStgui.update_uis(src)
	if(parent?.keybind_menu)
		SStgui.update_uis(parent.keybind_menu)

/// A save that hasn't seen some actions gets their default keys where nothing that could fire with them is on the key. Called once
/// the save's binds are loaded (hippie_pref_load()).
/datum/preferences/proc/add_new_keybind_defaults()
	var/list/known = known_keybinds
	if(!islist(known)) //saved before the panel: everything but this change's actions was there
		known = list()
		for(var/kb_name in GLOB.keybindings_by_name)
			if(!(kb_name in GLOB.keybinds_added_2026_11))
				known += kb_name
	var/list/added = list()
	var/list/taken = list()
	for(var/kb_name in GLOB.keybindings_by_name)
		if(kb_name in known)
			continue
		known += kb_name
		var/datum/keybinding/kb = GLOB.keybindings_by_name[kb_name]
		for(var/key in keybind_defaults(kb))
			if(kb_name in key_bindings[key])
				continue
			if(length(keybind_clashes(kb, key)) && !(kb_name in GLOB.keybinds_always_added))
				taken += "[kb.full_name] ([keybind_label(key)] is in use)"
				continue
			keybind_bind(kb_name, key)
			added += "[kb.full_name] ([keybind_label(key)])"
	known_keybinds = known
	if(!length(added) && !length(taken))
		return FALSE
	if(parent)
		var/msg = "<span class='notice'>New keybinds: [length(added) ? added.Join(", ") : "none"].</span>"
		if(length(taken))
			msg += "<br><span class='notice'>Left unbound: [taken.Join(", ")].</span>"
		msg += "<br><span class='notice'>Change them in Keybindings (OOC tab).</span>"
		to_chat(parent, msg)
	return TRUE

// The new actions

/datum/keybinding/client/communication
	category = "TALK"
	applies_to = KB_FOR_ALL

/// The client's macro for this key runs the verb (set_talk_macros()): keyDown() has nothing left to do
/datum/keybinding/client/communication/down(client/user)
	return FALSE

/datum/keybinding/client/communication/say
	hotkey_keys = list("T")
	name = "say"
	full_name = "Say"

/datum/keybinding/client/communication/radio
	hotkey_keys = list("Y")
	name = "radio"
	full_name = "Radio (;)"

/datum/keybinding/client/communication/whisper
	hotkey_keys = list("Unbound")
	name = "whisper"
	full_name = "Whisper"

/datum/keybinding/client/communication/me
	hotkey_keys = list("M")
	name = "me"
	full_name = "Me (emote)"

/datum/keybinding/client/communication/ooc
	hotkey_keys = list("O")
	name = "ooc"
	full_name = "OOC"

/datum/keybinding/client/communication/pray
	hotkey_keys = list("P")
	name = "pray"
	full_name = "Pray"

/datum/keybinding/client/screenshot_save
	hotkey_keys = list("ShiftF2")
	name = "screenshot_save"
	full_name = "Screenshot (save as)"

/datum/keybinding/client/screenshot_save/down(client/user)
	winset(user, null, "command=.screenshot")
	return TRUE

/datum/keybinding/client/close_all_windows
	hotkey_keys = list("Unbound")
	name = "close_all_windows"
	full_name = "Close all windows"

/datum/keybinding/client/close_all_windows/down(client/user)
	SStgui.close_user_uis(user.mob)
	return TRUE

/datum/keybinding/living/rest
	hotkey_keys = list("U")
	name = "rest"
	full_name = "Rest"
	applies_to = KB_FOR_HUMANLIKE

/datum/keybinding/living/rest/can_use(client/user)
	return isliving(user.mob) && (/mob/living/proc/lay_down in user.mob.verbs)

/datum/keybinding/living/rest/down(client/user)
	INVOKE_ASYNC(user.mob, TYPE_PROC_REF(/mob/living, lay_down)) //getting up takes a second, and the key press mustn't wait
	return TRUE

/datum/keybinding/carbon/hold_throw_mode
	hotkey_keys = list("Space")
	name = "hold_throw_mode"
	full_name = "Throw mode (hold)"

/datum/keybinding/carbon/hold_throw_mode/down(client/user)
	var/mob/living/carbon/C = user.mob
	C.throw_mode_on()
	return TRUE

/datum/keybinding/carbon/hold_throw_mode/up(client/user)
	var/mob/living/carbon/C = user.mob
	if(!iscarbon(C))
		return FALSE
	C.throw_mode_off()
	return TRUE

/datum/keybinding/carbon/select_left_hand
	hotkey_keys = list("Unbound")
	name = "select_left_hand"
	full_name = "Left hand"

/datum/keybinding/carbon/select_left_hand/down(client/user)
	var/mob/living/carbon/C = user.mob
	if(C.active_hand_index != 1)
		C.swap_hand(1)
	return TRUE

/datum/keybinding/carbon/select_right_hand
	hotkey_keys = list("Unbound")
	name = "select_right_hand"
	full_name = "Right hand"

/datum/keybinding/carbon/select_right_hand/down(client/user)
	var/mob/living/carbon/C = user.mob
	if(C.active_hand_index != 2 && length(C.held_items) >= 2)
		C.swap_hand(2)
	return TRUE

/datum/keybinding/mob/block_movement
	hotkey_keys = list("Unbound")
	name = "block_movement"
	full_name = "Block movement (hold)"

/datum/keybinding/mob/block_movement/down(client/user)
	user.movement_locked = TRUE
	return TRUE

/datum/keybinding/mob/block_movement/up(client/user)
	if(!user.movement_locked)
		return FALSE
	user.movement_locked = FALSE
	return TRUE

/datum/keybinding/mob/target_zone
	applies_to = KB_FOR_HUMANLIKE
	var/zone

/datum/keybinding/mob/target_zone/down(client/user)
	if(!user.check_has_body_select())
		return FALSE
	var/obj/screen/zone_sel/selector = user.mob.hud_used.zone_select
	selector.set_selected_zone(zone, user.mob)
	return TRUE

/datum/keybinding/mob/target_zone/head
	hotkey_keys = list("Unbound")
	name = "target_head"
	full_name = "Target: Head"
	zone = BODY_ZONE_HEAD

/datum/keybinding/mob/target_zone/eyes
	hotkey_keys = list("Numpad7")
	name = "target_eyes"
	full_name = "Target: Eyes"
	zone = BODY_ZONE_PRECISE_EYES

/datum/keybinding/mob/target_zone/mouth
	hotkey_keys = list("Numpad9")
	name = "target_mouth"
	full_name = "Target: Mouth"
	zone = BODY_ZONE_PRECISE_MOUTH

/datum/keybinding/human/quick_equip_slot
	var/slot
	var/slot_name

/datum/keybinding/human/quick_equip_slot/down(client/user)
	var/mob/living/carbon/human/H = user.mob
	H.smart_equip_slot(slot, slot_name)
	return TRUE

/datum/keybinding/human/quick_equip_slot/suit_storage
	hotkey_keys = list("ShiftQ")
	name = "quick_equip_suit_storage"
	full_name = "Quick equip suit storage"
	slot = ITEM_SLOT_SUITSTORE
	slot_name = "suit storage"

/datum/keybinding/human/quick_equip_slot/left_pocket
	hotkey_keys = list("Ctrl1")
	name = "quick_equip_lpocket"
	full_name = "Quick equip left pocket"
	slot = ITEM_SLOT_LPOCKET
	slot_name = "left pocket"

/datum/keybinding/human/quick_equip_slot/right_pocket
	hotkey_keys = list("Ctrl2")
	name = "quick_equip_rpocket"
	full_name = "Quick equip right pocket"
	slot = ITEM_SLOT_RPOCKET
	slot_name = "right pocket"

/// smart_equipbelt() for any slot: put the held thing there (or in it, if it holds things), or take out what's there (or what went in
/// last). Suit storage and the pockets, as tg's.
/mob/living/carbon/human/proc/smart_equip_slot(slot, slot_name)
	if(incapacitated())
		return
	var/obj/item/thing = get_active_held_item()
	var/obj/item/equipped = get_item_by_slot(slot)
	if(!equipped)
		if(!thing)
			to_chat(src, "<span class='warning'>There's nothing in your [slot_name]!</span>")
			return
		if(equip_to_slot_if_possible(thing, slot))
			update_inv_hands()
		return
	if(!SEND_SIGNAL(equipped, COMSIG_CONTAINS_STORAGE))
		if(!thing)
			equipped.attack_hand(src)
		else
			to_chat(src, "<span class='warning'>Your [slot_name] is full!</span>")
		return
	if(thing)
		if(!SEND_SIGNAL(equipped, COMSIG_TRY_STORAGE_INSERT, thing, src))
			to_chat(src, "<span class='warning'>You can't fit anything in!</span>")
		return
	if(!equipped.contents.len)
		to_chat(src, "<span class='warning'>There's nothing in [equipped] to take out!</span>")
		return
	var/obj/item/stored = equipped.contents[equipped.contents.len]
	if(!stored || stored.on_found(src))
		return
	stored.attack_hand(src)

/datum/keybinding/robot/shell_disconnect
	hotkey_keys = list("=")
	name = "shell_disconnect"
	full_name = "Disconnect from shell"

/datum/keybinding/robot/shell_disconnect/can_use(client/user)
	var/mob/living/silicon/robot/R = user.mob
	return iscyborg(R) && R.shell && R.deployed

/datum/keybinding/robot/shell_disconnect/down(client/user)
	var/mob/living/silicon/robot/R = user.mob
	R.undeploy()
	return TRUE

/datum/keybinding/ai_reconnect_shell
	hotkey_keys = list("-")
	name = "ai_reconnect_shell"
	full_name = "Reconnect to last shell"
	category = CATEGORY_ROBOT
	weight = WEIGHT_ROBOT
	applies_to = KB_FOR_AI

/datum/keybinding/ai_reconnect_shell/can_use(client/user)
	return isAI(user.mob)

/datum/keybinding/ai_reconnect_shell/down(client/user)
	var/mob/living/silicon/ai/AI = user.mob
	AI.redeploy_action?.Trigger()
	return TRUE

/datum/keybinding/admin/deadmin
	hotkey_keys = list("Unbound")
	name = "deadmin"
	full_name = "Deadmin"

/datum/keybinding/admin/deadmin/down(client/user)
	user.deadmin()
	return TRUE

/datum/keybinding/admin/readmin
	hotkey_keys = list("Unbound")
	name = "readmin"
	full_name = "Readmin"

/datum/keybinding/admin/readmin/can_use(client/user)
	return !user.holder && GLOB.deadmins[user.ckey]

/datum/keybinding/admin/readmin/down(client/user)
	user.readmin()
	return TRUE

// Who each old action fires for, and names that read alike

/datum/keybinding/carbon
	applies_to = KB_FOR_HUMANLIKE

/datum/keybinding/human
	applies_to = KB_FOR_HUMANLIKE

/datum/keybinding/robot
	applies_to = KB_FOR_ROBOT

/datum/keybinding/mob/drop_item
	applies_to = KB_FOR_NOT_SILICON
	full_name = "Drop item"

/datum/keybinding/mob/target_head_cycle
	applies_to = KB_FOR_HUMANLIKE
	full_name = "Target: Cycle head"

/datum/keybinding/mob/target_r_arm
	applies_to = KB_FOR_HUMANLIKE
	full_name = "Target: Right arm"

/datum/keybinding/mob/target_body_chest
	applies_to = KB_FOR_HUMANLIKE

/datum/keybinding/mob/target_left_arm
	applies_to = KB_FOR_HUMANLIKE
	full_name = "Target: Left arm"

/datum/keybinding/mob/target_right_leg
	applies_to = KB_FOR_HUMANLIKE

/datum/keybinding/mob/target_body_groin
	applies_to = KB_FOR_HUMANLIKE

/datum/keybinding/mob/target_left_leg
	applies_to = KB_FOR_HUMANLIKE
	full_name = "Target: Left leg"

// Facing on Ctrl+arrows only: Ctrl+S is Scream's (the user's ruling, 2026-11-07), and Ctrl+W/A/D go with it. Old saves lose them
// once (update_preferences(), version 29).
/datum/keybinding/mob/face_north
	hotkey_keys = list("CtrlNorth")

/datum/keybinding/mob/face_south
	hotkey_keys = list("CtrlSouth")

/datum/keybinding/mob/face_west
	hotkey_keys = list("CtrlWest")

/datum/keybinding/mob/face_east
	hotkey_keys = list("CtrlEast")

/datum/keybinding/mob/cycle_intent_right
	full_name = "Cycle intent right"

/datum/keybinding/mob/cycle_intent_left
	full_name = "Cycle intent left"

/datum/keybinding/mob/swap_hands
	full_name = "Swap hands"

/datum/keybinding/mob/toggle_move_intent
	full_name = "Walk/run (hold)"

/datum/keybinding/mob/toggle_move_intent_alternative
	full_name = "Walk/run"

/datum/keybinding/human/quick_equip
	full_name = "Quick equip"

/datum/keybinding/human/bag_equip
	full_name = "Quick equip bag"

/datum/keybinding/admin/deadsay
	full_name = "Dead say"

/datum/keybinding/admin/mentor_say
	full_name = "Mentor say"

#undef KB_FOR_HUMANLIKE
#undef KB_FOR_ROBOT
#undef KB_FOR_AI
#undef KB_FOR_OTHER
#undef KB_FOR_ALL
#undef KB_FOR_NOT_SILICON
#undef KB_MAX_KEY_LENGTH
