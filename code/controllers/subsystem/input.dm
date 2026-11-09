SUBSYSTEM_DEF(input)
	name = "Input"
	wait = 1 //SS_TICKER means this runs every tick
	init_order = INIT_ORDER_INPUT
	flags = SS_TICKER
	priority = FIRE_PRIORITY_INPUT
	runlevels = RUNLEVELS_DEFAULT | RUNLEVEL_LOBBY

	var/list/macro_set

/datum/controller/subsystem/input/Initialize()
	setup_default_macro_sets()

	initialized = TRUE

	refresh_client_macro_sets()

	return ..()

// This is for when macro sets are eventualy datumized
/datum/controller/subsystem/input/proc/setup_default_macro_sets()
	macro_set = list(
	"Any" = "\"KeyDown \[\[*\]\]\"",
	"Any+UP" = "\"KeyUp \[\[*\]\]\"",
	// hippie -- O, T and M (ooc, say, me) are keybinds now, with a macro for whatever key each is on (client/set_talk_macros())
	// hippie -- Back and Tab worked the old input bar under the chat, which is gone; Tab opens the chat bar (set_talk_macros())
	"Escape" = "Escape-Key") // hippie -- clears the chat bar, or with nothing in it opens the menu (game_menu.dm)

// Badmins just wanna have fun ♪
/datum/controller/subsystem/input/proc/refresh_client_macro_sets()
	var/list/clients = GLOB.clients
	for(var/i in 1 to clients.len)
		var/client/user = clients[i]
		user.set_macros()
		user.update_movement_keys()

/datum/controller/subsystem/input/fire()
	for(var/mob/user as anything in GLOB.player_list)
		user.focus?.keyLoop(user.client)
