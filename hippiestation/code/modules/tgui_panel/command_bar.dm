// hippie -- tg's command bar under the chat (tgui6/packages/tgui-panel/verbs). It suggests verbs as you type and has
// Say/Me/OOC modes. tg describes every verb's arguments for it (SSverbs); this server can't read a verb's arguments, so
// only the chat verbs below get theirs (the bar's modes type into them). Any other verb runs as if typed into the input
// bar, and BYOND asks for whatever it needs, as it always has.

/// The chat verbs, by name, and their one text argument's name. By name: the verbs list holds an override as a path
/// of its own (/client/ooc beside /client/verb/ooc), so paths don't tell them apart.
GLOBAL_LIST_INIT(command_bar_text_verbs, list(
	"Say" = "message",
	"Me" = "message",
	"Whisper" = "message",
	"OOC" = "msg",
	"Pray" = "msg",
))

/// Hidden in the stat panel, so added here
GLOBAL_LIST_INIT(command_bar_chat_paths, list(
	/mob/verb/say_verb,
	/mob/verb/me_verb,
	/mob/verb/whisper_verb,
	/client/verb/ooc,
	/mob/verb/pray,
))

/// The client-side command that opens the chat bar with the keyboard in it: on `verb_name` (with `prefill` after it) if given. A
/// macro runs it in the client (the page's update() gets the message), so the bar opens with no trip to the server. It's in place
/// of the old input bar under the chat, which talk keys typed `say "` into (2026-11-08: the user saw both bars and kept this one).
/// `typed` is the letter the key types: a talk key pressed again just after the bar opened was a letter typed before the keyboard
/// got there (the O in "ok" landed on the map as the OOC key and switched the bar to OOC), and the bar puts it in as text.
/proc/chat_bar_command(verb_name, prefill, typed)
	var/list/payload = list()
	if(verb_name)
		payload["verb"] = verb_name
	if(prefill)
		payload["prefill"] = prefill
	if(typed)
		payload["typed"] = typed
	return ".output browseroutput:update [url_encode(json_encode(list("type" = "verbs/focus", "payload" = payload)))]"

/// The chat bar takes the keyboard, sent from the server (classic mode's clicks and typing)
/client/proc/focus_chat_bar(prefill)
	var/list/payload = list()
	if(prefill)
		payload["prefill"] = prefill
	chatOutput?.panel_send("verbs/focus", payload)

/// Hotkey or classic mode changed: the bar keeps the keyboard in classic mode
/client/proc/chat_bar_hotkey_mode()
	chatOutput?.panel_send("verbs/hotkey_mode", list("hotkeys" = prefs?.hotkeys ? 1 : 0))

#define COMMAND_BAR_ARG_TEXT (1<<0) // common/verb-constants.ts ARG_TYPE_TEXT

/// Command bar messages from the page (verbs/...)
/datum/chatOutput/proc/on_panel_verbs(type, list/payload)
	switch(type)
		if("verbs/request_verbs")
			send_command_bar_verbs()
		if("verbs/invoke")
			command_bar_invoke(payload)

/// Name -> the verb: the stat panel's verbs plus the chat verbs, one per name (the /verb/ path over an override's)
/datum/chatOutput/proc/command_bar_verbs_by_name()
	var/list/procs = owner.stat_panel_verbs()
	for(var/path in GLOB.command_bar_chat_paths)
		if((path in owner.verbs) || (owner.mob && (path in owner.mob.verbs)))
			procs |= path
	. = list()
	for(var/procpath/P as anything in procs)
		var/name = P.name
		var/procpath/had = .[name]
		if(had && findtext("[had]", "/verb/"))
			continue
		.[name] = P

/datum/chatOutput/proc/send_command_bar_verbs()
	if(!loaded || !owner)
		return
	var/list/verbs = list()
	var/list/by_name = command_bar_verbs_by_name()
	for(var/name in by_name)
		var/procpath/P = by_name[name]
		var/list/arguments = list()
		var/arg_name = GLOB.command_bar_text_verbs[name]
		if(arg_name)
			arguments += list(list("name" = arg_name, "arg_type" = COMMAND_BAR_ARG_TEXT, "source" = null))
		verbs += list(list("type" = "[P]", "name" = name, "args" = arguments))
	panel_send("verbs/init", list("verbs" = verbs))
	panel_send("verbs/hotkey_mode", list("hotkeys" = owner.prefs?.hotkeys ? 1 : 0))

/datum/chatOutput/proc/command_bar_invoke(list/payload)
	var/wanted = payload?["verb_type"]
	if(!istext(wanted))
		return
	var/procpath/P
	var/list/by_name = command_bar_verbs_by_name()
	for(var/name in by_name)
		if("[by_name[name]]" == wanted)
			P = by_name[name]
			break
	if(!P)
		return
	var/arg_name = GLOB.command_bar_text_verbs[P.name]
	var/list/arguments = payload["args"]
	if(arg_name)
		// A chat verb sent empty does nothing: run bare, BYOND would ask for its text in a popup (there's no input bar to fill now)
		var/text = (islist(arguments) && istext(arguments[arg_name])) ? arguments[arg_name] : null
		if(length(trim(text)))
			var/target = (P in owner.verbs) ? owner : owner.mob
			call(target, P)(text)
		return
	// anything else runs as if typed into the input bar
	winset(owner, null, "command=[replacetext(P.name, " ", "-")]")

/// The bar's verbs follow the stat panel's: a new mob, admin rights and so on
/client/init_verbs()
	. = ..()
	chatOutput?.send_command_bar_verbs()

#undef COMMAND_BAR_ARG_TEXT
