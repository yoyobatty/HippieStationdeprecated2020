// The arcade machines in tgui windows (tgui-next Arcade.js), where they were old browser pages. The user, 2026-11-05: "redo in
// tgui" and "clicking does nothing" in play. The games' moves are their own Topic() calls, so the rules, sounds and prizes stay.

/// A move made in the window, as the old page's link
/obj/machinery/computer/arcade/proc/arcade_move(list/href)
	Topic(null, href)

// Space Villain 2000

/obj/machinery/computer/arcade/battle/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "arcade_battle", name, 420, 380, master_ui, state)
		ui.open()

/obj/machinery/computer/arcade/battle/ui_data(mob/user)
	var/list/data = list()
	data["enemyName"] = enemy_name
	data["message"] = temp
	data["playerHp"] = player_hp
	data["playerMp"] = player_mp
	data["enemyHp"] = enemy_hp
	data["enemyMp"] = enemy_mp
	data["gameover"] = gameover
	data["blocked"] = blocked
	data["emagged"] = !!(obj_flags & EMAGGED)
	return data

/obj/machinery/computer/arcade/battle/ui_act(action, params)
	if(..())
		return
	if(!(action in list("attack", "heal", "charge", "newgame")))
		return
	// Topic() sleeps between your move and the enemy's: run it on its own so the window keeps updating meanwhile
	INVOKE_ASYNC(src, PROC_REF(arcade_move), list("[action]" = 1))
	return TRUE
