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
))

/// Hidden in the stat panel, so added here
GLOBAL_LIST_INIT(command_bar_chat_paths, list(
	/mob/verb/say_verb,
	/mob/verb/me_verb,
	/mob/verb/whisper_verb,
	/client/verb/ooc,
))

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
	if(arg_name && islist(arguments) && istext(arguments[arg_name]))
		var/target = (P in owner.verbs) ? owner : owner.mob
		call(target, P)(arguments[arg_name])
		return
	// anything else runs as if typed into the input bar
	winset(owner, null, "command=[replacetext(P.name, " ", "-")]")

/// The bar's verbs follow the stat panel's: a new mob, admin rights and so on
/client/init_verbs()
	. = ..()
	chatOutput?.send_command_bar_verbs()

#undef COMMAND_BAR_ARG_TEXT
