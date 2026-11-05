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

// Minesweeper (hippiestation/code/game/machinery/computer/arcade.dm). Its board is table[row][column]: -10 to -1 flagged, 0 a hidden
// mine, 1 to 9 hidden and safe, 10 the mine that was hit, 11 an empty revealed square, 12 to 19 a revealed 1 to 8.

/obj/machinery/computer/arcade/minesweeper/interact(mob/user)
	if(game_status == 0)
		playsound(loc, (obj_flags & EMAGGED) ? 'hippiestation/sound/arcade/minesweeper_emag2.ogg' : 'hippiestation/sound/arcade/minesweeper_startup.ogg', 50, 0, extrarange = -3, falloff = 10)
	if(obj_flags & EMAGGED)
		do_sparks(5, 1, src)
	add_fingerprint(user)
	ui_interact(user)

/obj/machinery/computer/arcade/minesweeper/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "arcade_minesweeper", name, 620, 560, master_ui, state)
		ui.open()

/obj/machinery/computer/arcade/minesweeper/ui_data(mob/user)
	var/list/data = list()
	data["status"] = game_status
	data["emagged"] = !!(obj_flags & EMAGGED)
	data["iteration"] = randomnumber
	data["difficulty"] = difficulty
	data["mines"] = mine_placed
	data["flagging"] = flagging
	var/list/board = list()
	if(game_status != 0)
		for(var/y1 in 1 to rows - 1)
			var/list/row = list()
			for(var/x1 in 1 to columns - 1)
				row += table[y1][x1]
			board += list(row)
	data["board"] = board
	return data

/obj/machinery/computer/arcade/minesweeper/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("Easy", "Intermediate", "Hard", "Main_Menu", "Flag", "same_board")
			Topic(null, list("[action]" = 1))
		if("square", "flagsquare")
			var/y1 = text2num(params["y"])
			var/x1 = text2num(params["x"])
			if(game_status != 1 || !y1 || !x1 || y1 >= rows || x1 >= columns)
				return
			if(action == "square")
				Topic(null, list("[y1 * 100 + x1]" = 1))
			else
				// Right-click flags without the flagging mode, the same way the mode does
				playsound(loc, 'hippiestation/sound/arcade/minesweeper_boardpress.ogg', 50, 0, extrarange = -3, falloff = 10)
				if(table[y1][x1] >= 0 && table[y1][x1] < 10)
					table[y1][x1] -= 10
				else if(table[y1][x1] < 0)
					table[y1][x1] += 10
				Topic(null, list("refresh" = 1))
		if("custom")
			// The board size typed in the window, kept to the limits the old pop-ups asked for again and again
			var/new_rows = clamp(round(text2num(params["rows"])), 4, 30)
			var/new_columns = clamp(round(text2num(params["columns"])), 4, 50)
			var/grid_area = new_rows * new_columns
			var/new_mines = clamp(round(text2num(params["mines"])), round(grid_area / 6.4), round(grid_area * 0.85))
			playsound(loc, 'hippiestation/sound/arcade/minesweeper_menuselect.ogg', 50, 0, extrarange = -3, falloff = 10)
			flag_text = "OFF"
			flagging = FALSE
			game_status = 1
			difficulty = "Custom"
			rows = new_rows + 1
			columns = new_columns + 1
			mine_limit = new_mines
			mine_placed = 0
			area = new_rows * new_columns
			make_mines(TRUE)
			Topic(null, list("refresh" = 1))
	return TRUE
