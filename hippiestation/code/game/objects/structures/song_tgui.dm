// The instrument song editor moved off its old HTML window (tgui-next SongEditor.js): playback with repeats, the tempo in
// BPM, each line typed in place, a song pasted in whole, and the old help folded away. The buttons run the song's own
// Topic(); the lines and the import, which were pop-ups, come from the window with the same limits. The window belongs to
// the song, a datum, so its reach is the instrument's.

/datum/song/interact(mob/user)
	ui_interact(user)

/datum/song/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
						datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(!instrumentObj)
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "song_editor", instrumentObj.name, 560, 600, master_ui, state)
		ui.open()

/datum/song/ui_status(mob/user, datum/ui_state/state)
	return instrumentObj ? instrumentObj.ui_status(user, state) : UI_CLOSE

/datum/song/ui_data(mob/user)
	var/list/data = list()
	data["name"] = name
	data["lines"] = lines
	data["playing"] = playing
	data["repeat"] = repeat
	data["max_repeats"] = max_repeats
	data["bpm"] = round(600 / tempo)
	data["max_lines"] = MUSIC_MAXLINES
	data["max_chars"] = MUSIC_MAXLINECHARS
	return data

/datum/song/ui_act(action, list/params)
	if(..())
		return
	if(!usr.canUseTopic(instrumentObj, BE_CLOSE, FALSE, NO_TK))
		return
	switch(action)
		if("play")
			Topic(null, list("play" = "1"))
			return TRUE
		if("stop")
			Topic(null, list("stop" = "1"))
			return TRUE
		if("repeat")
			var/target = clamp(round(text2num(params["repeat"])), 0, max_repeats)
			Topic(null, list("repeat" = "[target - repeat]"))
			return TRUE
		if("bpm")
			var/bpm = clamp(round(text2num(params["bpm"])), 1, 600)
			Topic(null, list("tempo" = "[sanitize_tempo(600 / bpm) - tempo]"))
			return TRUE
		if("newsong")
			Topic(null, list("newsong" = "1"))
			return TRUE
		if("deleteline")
			Topic(null, list("deleteline" = "[params["line"]]"))
			return TRUE
		// The old window asked for these with pop-ups
		if("addline", "editline")
			var/text = html_encode(params["text"])
			if(!length(text))
				return
			if(length_char(text) > MUSIC_MAXLINECHARS)
				text = copytext_char(text, 1, MUSIC_MAXLINECHARS)
			if(action == "addline")
				if(lines.len > MUSIC_MAXLINES)
					return
				lines.Add(text)
			else
				var/num = round(text2num(params["line"]))
				if(num < 1 || num > lines.len)
					return
				lines[num] = text
			return TRUE
		if("import")
			var/text = html_encode(params["text"])
			if(length(text) > MUSIC_MAXLINES * MUSIC_MAXLINECHARS)
				text = copytext(text, 1, MUSIC_MAXLINES * MUSIC_MAXLINECHARS)
			ParseSong(text)
			return TRUE
