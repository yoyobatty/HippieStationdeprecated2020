// hippie -- the library's computers as tgui windows (tgui-next interfaces/Library.js), redesigned where it helps (the user's ruling,
// 2026-11-05). The librarian's console: tabs for the inventory, what's checked out (with the check-out form in place, overdue in red),
// the External Archive with one search over every book in it and Order buttons, uploading a scanned book or posting it to the
// newscasters, and the printer. The visitor console searches the Archive in place. The book scanner says what it has. The old pages
// were a numbered menu with a popup for every title, name and category, and the Archive in pages of 250.
// Every button goes through the console's own Topic() where it had no popup; where it had one, its branch is here with what was typed.

/obj/machinery/computer/libraryconsole
	/// What the last search turned up: list(list("author", "title", "category", "id"))
	var/list/search_results
	var/searched = FALSE

/obj/machinery/computer/libraryconsole/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "library_visitor", name, 600, 560, master_ui, state)
		ui.open()

/obj/machinery/computer/libraryconsole/ui_data(mob/user)
	return list(
		"title" = title,
		"author" = author,
		"category" = category,
		"categories" = list("Any", "Fiction", "Non-Fiction", "Adult", "Reference", "Religion"),
		"searched" = searched,
		"results" = search_results,
		"connected" = SSdbcore.IsConnected(),
	)

// TRUE only for its own action: the librarian's console is one of these, and its ui_act() stops at a TRUE from here
/obj/machinery/computer/libraryconsole/ui_act(action, params)
	if(..())
		return
	if(action == "search") // the old page's filters, typed in place, and Start Search
		title = sanitize(stripped_input_text(params["title"], MAX_NAME_LEN))
		author = sanitize(stripped_input_text(params["author"], MAX_NAME_LEN))
		var/new_category = params["category"]
		category = (new_category in list("Any", "Fiction", "Non-Fiction", "Adult", "Reference", "Religion")) ? new_category : "Any"
		library_search()
		return TRUE

/// The old page's search, run once: what it found is kept for the window. The filters are kept as typed and quoted here, for the
/// query: quoting needs the database, and gives nothing without one.
/obj/machinery/computer/libraryconsole/proc/library_search()
	searched = TRUE
	search_results = null
	if(!SSdbcore.Connect())
		return
	var/query = "SELECT author, title, category, id FROM [format_table_name("library")] WHERE isnull(deleted) AND author LIKE '%[sanitizeSQL(author)]%' AND title LIKE '%[sanitizeSQL(title)]%'"
	if(category != "Any")
		query += " AND category='[sanitizeSQL(category)]'"
	var/datum/DBQuery/query_library_list_books = SSdbcore.NewQuery(query)
	search_results = list()
	if(query_library_list_books.Execute())
		while(query_library_list_books.NextRow() && length(search_results) < 200)
			search_results += list(list(
				"author" = query_library_list_books.item[1],
				"title" = query_library_list_books.item[2],
				"category" = query_library_list_books.item[3],
				"id" = query_library_list_books.item[4],
			))
	qdel(query_library_list_books)

// The librarian's console

/obj/machinery/computer/libraryconsole/bookmanagement/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "library_console", name, 720, 600, master_ui, state)
		ui.open()

/obj/machinery/computer/libraryconsole/bookmanagement/ui_static_data(mob/user)
	load_library_db_to_cache()
	var/list/books = list()
	for(var/datum/cachedbook/C in GLOB.cachedbooks)
		books += list(list("id" = C.id, "author" = C.author, "title" = C.title, "category" = C.category))
	return list(
		"archive" = GLOB.cachedbooks ? books : null,
		"upload_categories" = list("Fiction", "Non-Fiction", "Adult", "Reference", "Religion", "Technical"),
	)

/obj/machinery/computer/libraryconsole/bookmanagement/ui_data(mob/user)
	var/list/data = list()
	var/list/books = list()
	for(var/obj/item/book/B in inventory)
		books += list(list("ref" = REF(B), "name" = B.name))
	data["inventory"] = books
	var/list/out = list()
	for(var/datum/borrowbook/b in checkouts)
		out += list(list(
			"ref" = REF(b),
			"book" = b.bookname,
			"who" = b.mobname,
			"taken" = round((world.time - b.getdate) / 600),
			"due" = round((b.duedate - world.time) / 600),
			"overdue" = b.duedate <= world.time,
		))
	data["checkouts"] = out
	data["buffer_book"] = buffer_book
	data["buffer_mob"] = buffer_mob
	data["period"] = checkoutperiod
	if(!scanner)
		scanner = findscanner(9)
	data["scanner"] = !!scanner
	data["scanned"] = scanner?.cache ? list("title" = scanner.cache.title || scanner.cache.name, "author" = scanner.cache.author || "Anonymous") : null
	data["upload_category"] = upload_category
	data["cooldown"] = max(0, round((cooldown - world.time) / 10))
	data["emagged"] = !!(obj_flags & EMAGGED)
	data["connected"] = SSdbcore.IsConnected()
	return data

/obj/machinery/computer/libraryconsole/bookmanagement/ui_act(action, params)
	if(..())
		return
	var/mob/user = usr
	switch(action)
		if("delbook")
			Topic(null, list("delbook" = params["ref"]))
		if("checkin")
			Topic(null, list("checkin" = params["ref"]))
		if("checkout") // "Edit" book and recipient, typed in place, then Commit Entry
			var/book = stripped_input_text(params["book"], MAX_NAME_LEN * 2)
			var/who = stripped_input_text(params["who"], MAX_NAME_LEN)
			if(book && who)
				buffer_book = book
				buffer_mob = who
				Topic(null, list("checkout" = "1"))
		if("period")
			var/list/step = list()
			step[text2num(params["by"]) > 0 ? "increasetime" : "decreasetime"] = "1"
			Topic(null, step)
		if("order")
			Topic(null, list("targetid" = "[params["id"]]"))
		if("author") // the upload's author, typed in place
			var/new_author = stripped_input_text(params["author"], MAX_NAME_LEN)
			if(new_author && scanner?.cache)
				scanner.cache.author = new_author
		if("category")
			if(params["category"] in list("Fiction", "Non-Fiction", "Adult", "Reference", "Religion", "Technical"))
				upload_category = params["category"]
		if("upload") // "Upload", confirmed in the window
			library_upload(user)
		if("newspost") // "Post", without its alerts
			library_newspost(user)
		if("printbible")
			Topic(null, list("printbible" = "1"))
		if("printposter")
			Topic(null, list("printposter" = "1"))
		if("forbidden") // the Forbidden Lore Vault's "Yes."
			if(obj_flags & EMAGGED)
				print_forbidden_lore(user)
		if("refresh_archive")
			GLOB.cachedbooks = null
			libcomp_menu = null
			load_library_db_to_cache()
			update_static_data(user)
	return TRUE

/// The old Upload, without its popups: says how it went
/obj/machinery/computer/libraryconsole/bookmanagement/proc/library_upload(mob/user)
	if(!scanner?.cache)
		return
	if(!SSdbcore.Connect())
		say("Connection to the Archive has been severed. Aborting.")
		return
	var/sqltitle = sanitizeSQL(scanner.cache.name)
	var/sqlauthor = sanitizeSQL(scanner.cache.author || "Anonymous")
	var/sqlcontent = sanitizeSQL(scanner.cache.dat)
	var/sqlcategory = sanitizeSQL(upload_category)
	var/sqlckey = sanitizeSQL(user.ckey)
	var/datum/DBQuery/query_library_upload = SSdbcore.NewQuery("INSERT INTO [format_table_name("library")] (author, title, content, category, ckey, datetime, round_id_created) VALUES ('[sqlauthor]', '[sqltitle]', '[sqlcontent]', '[sqlcategory]', '[sqlckey]', Now(), '[GLOB.round_id]')")
	if(!query_library_upload.Execute())
		say("Database error uploading to the Archive.")
	else
		log_game("[key_name(user)] has uploaded the book titled [scanner.cache.name], [length(scanner.cache.dat)] signs")
		say("Upload complete. The title will be unavailable for printing for a short while.")
	qdel(query_library_upload)

/// The old Post to Newscaster, without its alerts
/obj/machinery/computer/libraryconsole/bookmanagement/proc/library_newspost(mob/user)
	if(!scanner?.cache)
		return
	if(!GLOB.news_network)
		say("No news network found on the station. Aborting.")
		return
	var/exists = FALSE
	for(var/datum/newscaster/feed_channel/FC in GLOB.news_network.network_channels)
		if(FC.channel_name == "Nanotrasen Book Club")
			exists = TRUE
			break
	if(!exists)
		GLOB.news_network.CreateFeedChannel("Nanotrasen Book Club", "Library", null)
	GLOB.news_network.SubmitArticle(scanner.cache.dat, "[scanner.cache.name]", "Nanotrasen Book Club", null)
	say("Upload complete. [scanner.cache.name] is now on the station's newscasters.")

// The book scanner

/obj/machinery/libraryscanner/attack_hand(mob/user) // the base hand without the old page after it: can_interact(), then the window
	add_fingerprint(user)
	return _try_interact(user)

/obj/machinery/libraryscanner/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "library_scanner", name, 360, 220, master_ui, state)
		ui.open()

/obj/machinery/libraryscanner/ui_data(mob/user)
	var/obj/item/book/inside = locate() in contents
	return list(
		"cache" = cache ? list("title" = cache.name, "author" = cache.author || "Anonymous") : null,
		"inside" = inside ? inside.name : null,
	)

/obj/machinery/libraryscanner/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("scan")
			Topic(null, list("scan" = "1"))
		if("clear")
			Topic(null, list("clear" = "1"))
		if("eject")
			Topic(null, list("eject" = "1"))
	return TRUE
