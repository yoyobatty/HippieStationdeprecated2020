// tgui prompts: drop-in replacements for BYOND's input() and alert().
//
// Same contract as the native ones, so a call can be swapped without
// touching the code around it:
//  - the proc sleeps until the player answers, closes the window or the
//    timeout runs out (closing or timing out gives null, as Cancel does);
//  - a mob with no client gets the native no-client answer at once:
//    lists and text/number prompts give their default, alert() its first
//    button. Bots therefore behave exactly as before.
//  - a pick list returns the list element itself (the key of an
//    associative list, the atom of a list of atoms), not its display name.
//
// Better than native: the list can be searched and is fast with thousands
// of entries, nothing steals focus from the game window, it follows the
// tgui theme, Enter/Escape/arrows work everywhere, prompts can time out,
// and a prompt tied to a source object (the `source` argument) closes by
// itself when the player can no longer use it, so an answer can't be
// "saved up" and given from across the station.

#define TGUI_PROMPT_ALERT "alert"
#define TGUI_PROMPT_LIST "list"
#define TGUI_PROMPT_TEXT "text"
#define TGUI_PROMPT_MESSAGE "message"
#define TGUI_PROMPT_NUM "num"

/// The mob a prompt goes to: native input() takes a mob or a client. Anything else (an old `input(src, ...)` in a
/// /datum/admins proc) means whoever is acting, as `usr`.
/proc/tgui_prompt_mob(target)
	if(ismob(target))
		return target
	if(istype(target, /client))
		var/client/C = target
		return C.mob
	if(ismob(usr))
		return usr
	return null

/**
 * alert() in tgui. Returns the text of the button pressed, or null if the
 * window was closed or timed out.
 *
 * buttons: up to any number of choices, shown left to right; the first is
 * the default (Enter) and what a mob without a client gets.
 */
/proc/tgui_alert(mob/user, message = "", title, list/buttons = list("Ok"), timeout = 0, datum/source)
	user = tgui_prompt_mob(user)
	if(!length(buttons))
		buttons = list("Ok")
	if(!user)
		return null
	if(!user.client)
		return buttons[1]
	var/datum/tgui_prompt/P = new(user, TGUI_PROMPT_ALERT, message, title, timeout, source)
	P.allow_cancel = FALSE // a native alert has no Cancel; plenty of callers read anything but "No" as yes
	for(var/b in buttons)
		P.choices += "[b]"
	return P.wait()

/**
 * input() as anything in list, in tgui. Returns the chosen element, or null.
 *
 * allow_cancel: FALSE for native `as anything in` (no Cancel button);
 * closing the window still gives null, as native disconnects do.
 */
/proc/tgui_input_list(mob/user, message = "", title, list/items, default, timeout = 0, allow_cancel = TRUE, datum/source)
	user = tgui_prompt_mob(user)
	if(!user || !islist(items))
		return null
	if(!user.client)
		return default
	if(!length(items))
		return null
	var/datum/tgui_prompt/P = new(user, TGUI_PROMPT_LIST, message, title, timeout, source)
	P.items = items.Copy()
	P.allow_cancel = allow_cancel
	var/default_index = 0
	for(var/i in 1 to length(P.items))
		var/item = P.items[i]
		P.choices += tgui_prompt_item_name(item)
		if(!default_index && !isnull(default) && item == default)
			default_index = i
	P.default_index = default_index
	return P.wait()

/// `input() as mob in L`: native only offers the elements of that type.
/proc/tgui_list_of_type(list/L, path)
	. = list()
	for(var/x in L)
		if(istype(x, path))
			. += x

/// How an element of a pick list is shown: atoms by their name, the rest as text.
/proc/tgui_prompt_item_name(item)
	if(isatom(item))
		var/atom/A = item
		return "[A.name]"
	return "[item]"

/**
 * input() as text / as message, in tgui. Returns the text as typed (no
 * sanitising, same as native), or null.
 */
/proc/tgui_input_text(mob/user, message = "", title, default, max_length = 0, multiline = FALSE, timeout = 0, allow_cancel = TRUE, datum/source)
	user = tgui_prompt_mob(user)
	if(!user)
		return null
	if(!user.client)
		return default
	var/datum/tgui_prompt/P = new(user, multiline ? TGUI_PROMPT_MESSAGE : TGUI_PROMPT_TEXT, message, title, timeout, source)
	P.default_value = isnull(default) ? "" : "[default]"
	P.max_length = max_length
	P.allow_cancel = allow_cancel
	return P.wait()

/**
 * input() as num, in tgui. Returns a number, or null.
 * min_value/max_value are optional bounds (null = none, like native).
 */
/proc/tgui_input_number(mob/user, message = "", title, default, max_value = null, min_value = null, timeout = 0, allow_cancel = TRUE, datum/source)
	user = tgui_prompt_mob(user)
	if(!user)
		return null
	if(!user.client)
		return default
	var/datum/tgui_prompt/P = new(user, TGUI_PROMPT_NUM, message, title, timeout, source)
	P.default_value = isnull(default) ? null : default
	P.min_value = min_value
	P.max_value = max_value
	P.allow_cancel = allow_cancel
	. = P.wait()
	if(!isnull(.))
		if(!isnull(min_value))
			. = max(., min_value)
		if(!isnull(max_value))
			. = min(., max_value)

/datum/tgui_prompt
	var/mob/user
	var/kind
	var/message
	var/title
	/// Deciseconds; 0 = wait for ever, like native.
	var/timeout = 0
	var/end_time = 0
	/// The object the prompt is about; the prompt closes when the user can no longer use it.
	var/datum/source
	var/allow_cancel = TRUE
	/// Display text of each button (alert) or row (list).
	var/list/choices = list()
	/// The real elements behind a list's rows.
	var/list/items
	var/default_index = 0
	var/default_value
	var/max_length = 0
	var/min_value
	var/max_value
	var/done = FALSE
	var/result
	/// Its own window name: refs come back after a qdel, and two prompts one after the other would otherwise share a
	/// window while the first is still closing (a key meant for one reached the next).
	var/prompt_key

GLOBAL_VAR_INIT(tgui_prompt_count, 0)

/datum/tgui_prompt/New(mob/user, kind, message, title, timeout, datum/source)
	..()
	src.user = user
	src.kind = kind
	src.message = isnull(message) ? "" : "[message]"
	src.title = title ? "[title]" : (kind == TGUI_PROMPT_ALERT ? "Alert" : "Input")
	src.timeout = max(0, timeout)
	if(src.timeout)
		end_time = world.time + src.timeout
	src.source = source

/datum/tgui_prompt/Destroy(force, ...)
	SStgui.close_uis(src)
	user = null
	source = null
	items = null
	return ..()

/// Opens the window and sleeps until an answer; returns it and deletes the prompt.
/datum/tgui_prompt/proc/wait()
	prompt_key = "prompt[++GLOB.tgui_prompt_count]"
	ui_interact(user, prompt_key)
	while(!done)
		if(QDELETED(user) || !user.client)
			break
		if(end_time && world.time >= end_time)
			break
		if(source && (QDELETED(source) || source.ui_status(user, GLOB.default_state) < UI_INTERACTIVE))
			break
		stoplag(1)
	. = done ? result : null
	qdel(src)

/datum/tgui_prompt/proc/finish(value)
	if(done)
		return
	result = value
	done = TRUE

/datum/tgui_prompt/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		var/w = 360
		var/h = 160
		switch(kind)
			if(TGUI_PROMPT_LIST)
				w = 340
				h = 420
			if(TGUI_PROMPT_MESSAGE)
				w = 440
				h = 300
			if(TGUI_PROMPT_ALERT)
				// about 48 characters a line at this width, plus the message's own line breaks
				var/lines = CEILING(length(message) / 48, 1) + length(splittext(message, "\n")) - 1
				h = 102 + 18 * clamp(lines, 1, 14)
				w = max(320, min(520, 110 * length(choices) + 40))
		ui = new(user, src, ui_key, "tgui_prompt", title, w, h, master_ui, state)
		// No Cancel natively (every alert, `as anything in` without null): no close button either, so the caller always
		// gets one of the answers it was written for. A null still comes from disconnects, timeouts and `source`.
		ui.no_close = !allow_cancel
		ui.open()
		if(user.client)
			winset(user, ui.window_id, "focus=true")

/datum/tgui_prompt/ui_status(mob/user, datum/ui_state/state)
	if(user != src.user || done)
		return UI_CLOSE
	return UI_INTERACTIVE

/datum/tgui_prompt/ui_static_data(mob/user)
	var/list/data = list()
	data["kind"] = kind
	data["message"] = message
	data["choices"] = choices
	data["default_index"] = default_index
	data["default_value"] = default_value
	data["max_length"] = max_length
	data["min_value"] = min_value
	data["max_value"] = max_value
	data["allow_cancel"] = allow_cancel
	return data

/datum/tgui_prompt/ui_data(mob/user)
	var/list/data = list()
	data["time_left"] = end_time ? max(0, round((end_time - world.time) / 10)) : null
	return data

/datum/tgui_prompt/ui_act(action, list/params)
	if(..() || done)
		return
	switch(action)
		if("cancel")
			if(allow_cancel)
				finish(null)
		if("submit")
			switch(kind)
				if(TGUI_PROMPT_ALERT)
					var/i = text2num(params["index"])
					if(i >= 1 && i <= length(choices))
						finish(choices[i])
				if(TGUI_PROMPT_LIST)
					var/i = text2num(params["index"])
					if(i >= 1 && i <= length(items))
						finish(items[i])
				if(TGUI_PROMPT_TEXT, TGUI_PROMPT_MESSAGE)
					var/t = params["value"]
					if(!istext(t))
						t = ""
					if(max_length && length(t) > max_length)
						t = copytext(t, 1, max_length + 1)
					finish(t)
				if(TGUI_PROMPT_NUM)
					var/n = text2num(params["value"])
					if(!isnull(n))
						finish(n)
	if(done)
		SStgui.close_uis(src)
	return TRUE

/// Closing the window answers null, like Cancel (prompts without Cancel have no close button; this is the server closing it).
/datum/tgui_prompt/ui_close(mob/user)
	if(!done)
		finish(null)

#undef TGUI_PROMPT_ALERT
#undef TGUI_PROMPT_LIST
#undef TGUI_PROMPT_TEXT
#undef TGUI_PROMPT_MESSAGE
#undef TGUI_PROMPT_NUM
