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

// The Orion Trail. Its screens are the game's own HTML (each event writes its own, links and all), shown in the window; a link
// clicked there comes back through ui_act to the game's Topic(). The screen is worked out once a move by orion_screen(), the
// old ui_interact() body, since losing an emagged game hurts you while drawing the game-over screen.

// The game's states (code/game/machinery/computer/arcade.dm undefines them at its end)
#define ORION_STATUS_START		1
#define ORION_STATUS_NORMAL		2
#define ORION_STATUS_GAMEOVER	3

/obj/machinery/computer/arcade/orion_trail
	/// The screen as last drawn, for the window
	var/orion_screen_html = ""

/// The old window's page, without opening it: the same checks and game-over effects, run once each time the game moves
/obj/machinery/computer/arcade/orion_trail/proc/orion_screen(mob/user)
	if(fuel <= 0 || food <=0 || settlers.len == 0)
		gameStatus = ORION_STATUS_GAMEOVER
		event = null
	var/dat = ""
	if(gameStatus == ORION_STATUS_GAMEOVER)
		dat = "<center><h1>Game Over</h1></center>"
		dat += "Like many before you, your crew never made it to Orion, lost to space... <br><b>Forever</b>."
		if(!settlers.len)
			dat += "<br>Your entire crew died, and your ship joins the fleet of ghost-ships littering the galaxy."
		else
			if(food <= 0)
				dat += "<br>You ran out of food and starved."
				if(obj_flags & EMAGGED)
					user.set_nutrition(0) //yeah you pretty hongry
					to_chat(user, "<span class='userdanger'>Your body instantly contracts to that of one who has not eaten in months. Agonizing cramps seize you as you fall to the floor.</span>")
			if(fuel <= 0)
				dat += "<br>You ran out of fuel, and drift, slowly, into a star."
				if(obj_flags & EMAGGED)
					var/mob/living/M = user
					M.adjust_fire_stacks(5)
					M.IgniteMob() //flew into a star, so you're on fire
					to_chat(user, "<span class='userdanger'>You feel an immense wave of heat emanate from the arcade machine. Your skin bursts into flames.</span>")

		if(obj_flags & EMAGGED)
			to_chat(user, "<span class='userdanger'>You're never going to make it to Orion...</span>")
			user.death()
			obj_flags &= ~EMAGGED //removes the emagged status after you lose
			gameStatus = ORION_STATUS_START
			name = "The Orion Trail"
			desc = "Learn how our ancestors got to Orion, and have fun in the process!"

		dat += "<P ALIGN=Right><a href='byond://?src=[REF(src)];menu=1'>May They Rest In Peace</a></P>"
	else if(event)
		dat = eventdat
	else if(gameStatus == ORION_STATUS_NORMAL)
		var/title = stops[turns]
		var/subtext = stopblurbs[turns]
		dat = "<center><h1>[title]</h1></center>"
		dat += "[subtext]"
		dat += "<h3><b>Crew:</b></h3>"
		dat += english_list(settlers)
		dat += "<br><b>Food: </b>[food] | <b>Fuel: </b>[fuel]"
		dat += "<br><b>Engine Parts: </b>[engine] | <b>Hull Panels: </b>[hull] | <b>Electronics: </b>[electronics]"
		if(turns == 7)
			dat += "<P ALIGN=Right><a href='byond://?src=[REF(src)];pastblack=1'>Go Around</a> <a href='byond://?src=[REF(src)];blackhole=1'>Continue</a></P>"
		else
			dat += "<P ALIGN=Right><a href='byond://?src=[REF(src)];continue=1'>Continue</a></P>"
		dat += "<P ALIGN=Right><a href='byond://?src=[REF(src)];killcrew=1'>Kill a Crewmember</a></P>"
		dat += "<P ALIGN=Right><a href='byond://?src=[REF(src)];close=1'>Close</a></P>"
	else
		dat = "<center><h2>The Orion Trail</h2></center>"
		dat += "<br><center><h3>Experience the journey of your ancestors!</h3></center><br><br>"
		dat += "<center><b><a href='byond://?src=[REF(src)];newgame=1'>New Game</a></b></center>"
		dat += "<P ALIGN=Right><a href='byond://?src=[REF(src)];close=1'>Close</a></P>"
	return dat

/obj/machinery/computer/arcade/orion_trail/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, 										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	orion_screen_html = orion_screen(user)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "arcade_orion", name, 440, 620, master_ui, state)
		ui.open()

/obj/machinery/computer/arcade/orion_trail/ui_data(mob/user)
	return list("screen" = orion_screen_html, "emagged" = !!(obj_flags & EMAGGED))

/obj/machinery/computer/arcade/orion_trail/ui_act(action, list/params)
	if(..())
		return
	if(action != "link")
		return
	var/list/href = params.Copy()
	href -= "src"
	if(href["close"])
		SStgui.close_uis(src)
		return
	INVOKE_ASYNC(src, PROC_REF(orion_move), href, usr)
	return TRUE

/// A link clicked in the window: the game's move, then the screen worked out again
/obj/machinery/computer/arcade/orion_trail/proc/orion_move(list/href, mob/user)
	Topic(null, href)
	if(!QDELETED(src) && user)
		ui_interact(user)

#undef ORION_STATUS_START
#undef ORION_STATUS_NORMAL
#undef ORION_STATUS_GAMEOVER
