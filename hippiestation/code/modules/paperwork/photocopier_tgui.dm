// hippie -- the photocopier as a tgui window (tgui-next interfaces/Photocopier.js): what's on the glass, with the start of a paper's
// text, how many copies with - and +, the toner as a bar, colour or greyscale for a photo, and Copy. The old page's copy count never
// made more than one: each copy sets the copier busy, and its loop stopped at the next. From the window they come out one at a time
// until they're all done, through the old page's own Copy.

/obj/machinery/photocopier
	/// Copies still to come out of a run started from the window
	var/copies_left = 0

/obj/machinery/photocopier/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "photocopier", name, 400, 380, master_ui, state)
		ui.open()

/obj/machinery/photocopier/ui_data(mob/user)
	var/list/data = list()
	var/kind
	var/enough = FALSE
	if(copy)
		kind = "paper"
		data["what"] = copy.name
		var/static/regex/tags = regex(@"<[^>]*>", "g")
		data["preview"] = copytext(html_decode(tags.Replace(replacetext(copy.info, "<br>", "\n"), "")), 1, 400)
		enough = toner > 0
	else if(photocopy)
		kind = "photo"
		data["what"] = photocopy.name
		enough = toner >= 5
	else if(doccopy)
		kind = "documents"
		data["what"] = doccopy.name
		enough = toner > 5
	else if(ass && ass.loc == loc)
		kind = "ass"
		data["what"] = "[ass]"
		data["clothed"] = !check_ass()
		enough = toner >= 5
	data["kind"] = kind
	data["enough"] = enough
	data["copies"] = copies
	data["max_copies"] = maxcopies
	data["toner"] = toner
	data["max_toner"] = initial(toner)
	data["greyscale"] = greytoggle == "Greyscale"
	data["busy"] = busy || copies_left > 0
	data["copies_left"] = copies_left
	data["ai"] = isAI(user)
	return data

/obj/machinery/photocopier/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("copy")
			if(!copies_left)
				copies_left = copies
				copy_next(usr)
		if("remove")
			Topic(null, list("remove" = "1"))
		if("copies")
			var/list/step = list()
			step[text2num(params["by"]) > 0 ? "add" : "min"] = "1"
			Topic(null, step)
		if("colour")
			if((params["greyscale"] == "1") != (greytoggle == "Greyscale"))
				Topic(null, list("colortoggle" = "1"))
		if("aipic")
			Topic(null, list("aipic" = "1"))
	return TRUE

/// One copy of the run through the old page's Copy, then the next once it's out. A run stops when nothing comes out: out of toner,
/// the glass emptied, or whoever started it has walked off.
/obj/machinery/photocopier/proc/copy_next(mob/user)
	if(QDELETED(src) || copies_left <= 0)
		copies_left = 0
		return
	if(busy) // the last one's still coming out
		addtimer(CALLBACK(src, PROC_REF(copy_next), user), 5)
		return
	var/had_toner = toner
	var/count = copies
	copies = 1
	usr = user
	Topic(null, list("copy" = "1"))
	copies = count
	copies_left--
	if(toner == had_toner && !busy)
		copies_left = 0
	if(copies_left > 0)
		addtimer(CALLBACK(src, PROC_REF(copy_next), user), 16)
	SStgui.update_uis(src)
