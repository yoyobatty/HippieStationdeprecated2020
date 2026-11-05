// hippie -- the PDA is a tgui window, phone-style (the user's ruling): a home screen of apps with the time and the owner on top, the
// messenger as conversations (chat threads, the user's ruling) typed into in place, the notes edited in place, the atmospheric scan,
// and the settings (ringer, ringtone, messenger, emergency beacon, wallpaper, ID, cartridge) on a screen of their own. A cartridge's
// own programs (records, the power monitor, the signaler and the rest) open in their old window from their app, and Return there
// comes back here.
// Everything a button does goes through the PDA's own Topic() but sending a typed message (send_message() takes the text in place of
// asking for it) and the notes and ringtone, which are that Topic()'s branches with typed text. The messages are still kept in tnote
// as well, for the pAI's messenger and anything else that reads it; a ringtone that's an uplink's code still opens it.

#define PDA_THREAD_KEEP 100

/obj/item/pda
	/// The window's screen: "home", "messenger", "thread", "contacts", "notes", "atmos" or "settings"
	var/pda_screen = "home"
	/// The messenger's conversations, oldest first: "Name (Job)" -> list("name", "job", "pda" = weakref, "messages", "unread")
	var/list/pda_threads
	/// The conversation on the screen
	var/pda_thread_open

// ---------------------------------------------------------------------------------------------
// Opening it: the window, or a cartridge program's old one
// ---------------------------------------------------------------------------------------------

/// On a cartridge's own program (mode 40 and up, and their pages), which has its old window still
/obj/item/pda/proc/pda_classic_app()
	return cartridge && mode >= 40

/obj/item/pda/interact(mob/user)
	if(pda_classic_app())
		return ..() //the old window (PDA.dm), whose ui_interact() call below shuts this one
	if(!user.IsAdvancedToolUser())
		to_chat(user, "<span class='warning'>You don't have the dexterity to do this!</span>")
		return
	add_fingerprint(user)
	user.set_machine(src)
	user << browse(null, "window=pda")
	ui_interact(user)

/obj/item/pda/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(pda_classic_app())
		SStgui.close_user_uis(user, src)
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "pda", "Personal Data Assistant", 360, 600, master_ui, state)
		ui.open()

// ---------------------------------------------------------------------------------------------
// The messenger's threads (hooks in send_message() and receive_message(), PDA.dm, and receive_page(), dept_pager.dm)
// ---------------------------------------------------------------------------------------------

/// The conversation with somebody, made if there isn't one, and moved up to the newest
/obj/item/pda/proc/pda_thread(name, job, obj/item/pda/other)
	var/key = "[name] ([job])"
	LAZYINITLIST(pda_threads)
	var/list/T = pda_threads[key]
	if(!T)
		T = list("name" = name, "job" = job, "pda" = null, "messages" = list(), "unread" = 0)
	if(istype(other))
		T["pda"] = WEAKREF(other)
	pda_threads -= key
	pda_threads[key] = T
	return T

/obj/item/pda/proc/pda_thread_add(list/T, list/message)
	var/list/messages = T["messages"]
	messages += list(message)
	if(length(messages) > PDA_THREAD_KEEP)
		messages.Cut(1, 2)

/// What it's just sent, in the conversation with each it went to (or "Everyone")
/obj/item/pda/proc/pda_log_sent(list/targets, message, everyone)
	var/list/line = list("out" = TRUE, "text" = html_decode(message), "time" = station_time_timestamp("hh:mm"))
	if(everyone)
		pda_thread_add(pda_thread("Everyone", "all PDAs"), line)
		return
	for(var/obj/item/pda/P in targets)
		if(P.owner && P.ownjob)
			pda_thread_add(pda_thread(P.owner, P.ownjob, P), line.Copy())

/// A message that's come in, in the conversation with whoever sent it. A page from a department pager is marked as one.
/obj/item/pda/proc/pda_log_received(datum/signal/subspace/messaging/pda/signal, page = FALSE)
	var/list/T = pda_thread(signal.data["name"], signal.data["job"], signal.source)
	var/list/line = list("out" = FALSE, "text" = html_decode(signal.data["message"]), "time" = station_time_timestamp("hh:mm"))
	if(signal.data["photo"])
		line["photo"] = TRUE
	if(page)
		line["page"] = "Page to [signal.data["page_department"]], at [signal.data["page_location"]]"
	pda_thread_add(T, line)
	T["unread"]++
	SStgui.update_uis(src)

/// The text of a message typed into the window, checked as msg_input() (PDA.dm) checks what's typed into its box
/obj/item/pda/proc/pda_typed_message(mob/living/user, typed)
	var/t = stripped_input_text(typed, MAX_MESSAGE_LEN)
	if(!t || toff || !user.canUseTopic(src, BE_CLOSE))
		return
	if(emped)
		t = Gibberish(t, 100)
	return t

// ---------------------------------------------------------------------------------------------
// The window
// ---------------------------------------------------------------------------------------------

/// The home screen's apps, in the old menu's order: what's built in, then what the cartridge adds
/obj/item/pda/proc/pda_apps()
	var/list/apps = list()
	var/unread = 0
	for(var/key in pda_threads)
		var/list/T = pda_threads[key]
		unread += T["unread"]
	apps += list(list("key" = "messenger", "name" = "Messenger", "icon" = "comment-dots", "badge" = unread))
	apps += list(list("key" = "notes", "name" = "Notes", "icon" = "sticky-note"))
	apps += list(list("key" = "atmos", "name" = "Atmos Scan", "icon" = "wind"))
	apps += list(list("key" = "light", "name" = "Flashlight", "icon" = "lightbulb", "on" = fon))
	if(cartridge)
		var/flags = cartridge.access
		if(flags & CART_MANIFEST)
			apps += list(list("key" = "41", "name" = "Crew Manifest", "icon" = "users"))
		if(flags & CART_STATUS_DISPLAY)
			apps += list(list("key" = "42", "name" = "Status Display", "icon" = "tv"))
		if(flags & CART_ENGINE)
			apps += list(list("key" = "43", "name" = "Power Monitor", "icon" = "bolt"))
		if(flags & CART_MEDICAL)
			apps += list(list("key" = "44", "name" = "Medical Records", "icon" = "notes-medical"))
			apps += list(list("key" = "scan_medical", "name" = "Health Scanner", "icon" = "heartbeat", "on" = scanmode == 1))
		if(flags & CART_SECURITY)
			apps += list(list("key" = "45", "name" = "Security Records", "icon" = "shield-alt"))
		if(flags & CART_QUARTERMASTER)
			apps += list(list("key" = "47", "name" = "Supply Records", "icon" = "box"))
			apps += list(list("key" = "48", "name" = "Ore Silo Logs", "icon" = "gem"))
		if(cartridge.bot_access_flags)
			apps += list(list("key" = "54", "name" = "Bots", "icon" = "robot"))
		if(flags & CART_JANITOR)
			apps += list(list("key" = "49", "name" = "Custodial Locator", "icon" = "broom"))
		if(istype(cartridge.radio))
			apps += list(list("key" = "40", "name" = "Signaler", "icon" = "broadcast-tower"))
		if(flags & CART_NEWSCASTER)
			apps += list(list("key" = "53", "name" = "Newscaster", "icon" = "newspaper"))
		if(flags & CART_REAGENT_SCANNER)
			apps += list(list("key" = "scan_reagent", "name" = "Reagent Scanner", "icon" = "flask", "on" = scanmode == 3))
		if(flags & CART_ENGINE)
			apps += list(list("key" = "scan_halogen", "name" = "Halogen Counter", "icon" = "radiation", "on" = scanmode == 4))
		if(flags & CART_ATMOS)
			apps += list(list("key" = "scan_gas", "name" = "Gas Scanner", "icon" = "cloud", "on" = scanmode == 5))
		if(flags & CART_CLOWN)
			apps += list(list("key" = "honk", "name" = "Honk", "icon" = "bullhorn"))
			apps += list(list("key" = "trombone", "name" = "Sad Trombone", "icon" = "sad-tear"))
		if(flags & CART_REMOTE_DOOR)
			apps += list(list("key" = "door", "name" = "Remote Door", "icon" = "door-open"))
		if(flags & CART_DRONEPHONE)
			apps += list(list("key" = "drone", "name" = "Drone Phone", "icon" = "phone"))
	if(R)
		apps += list(list("key" = "record_play", "name" = "Play Record", "icon" = "play"))
		apps += list(list("key" = "record_stop", "name" = "Stop Record", "icon" = "stop"))
		apps += list(list("key" = "record_eject", "name" = "Eject Record", "icon" = "compact-disc"))
	if(pai && pai.loc == src)
		apps += list(list("key" = "pai_config", "name" = "pAI", "icon" = "microchip"))
		apps += list(list("key" = "pai_eject", "name" = "Eject pAI", "icon" = "eject"))
	apps += list(list("key" = "settings", "name" = "Settings", "icon" = "cog"))
	return apps

/obj/item/pda/ui_data(mob/user)
	var/list/data = list()
	if(pai && pai.loc != src)
		pai = null
	data["owner"] = owner
	data["job"] = ownjob
	data["screen"] = pda_screen
	data["time"] = station_time_timestamp("hh:mm")
	data["date"] = "[time2text(world.realtime, "MMM DD")] [GLOB.year_integer + 540]"
	data["color"] = background_color
	data["id"] = id ? "[id.registered_name], [id.assignment]" : null
	data["holding_id"] = istype(user.get_active_held_item(), /obj/item/card/id)
	data["cartridge"] = cartridge ? cartridge.name : null
	data["apps"] = pda_apps()
	data["silent"] = silent
	data["toff"] = toff
	data["ringtone"] = ttone
	data["beacon"] = mandown_enabled
	switch(pda_screen)
		if("messenger")
			var/list/threads = list()
			for(var/i in length(pda_threads) to 1 step -1) //newest first
				var/key = pda_threads[i]
				var/list/T = pda_threads[key]
				var/list/messages = T["messages"]
				var/list/last = length(messages) ? messages[length(messages)] : null
				threads += list(list("key" = key, "name" = T["name"], "job" = T["job"], "unread" = T["unread"], "last" = last ? (last["out"] ? "You: " : "") + last["text"] : "", "time" = last ? last["time"] : ""))
			data["threads"] = threads
		if("thread")
			var/list/T = LAZYACCESS(pda_threads, pda_thread_open)
			if(!T)
				pda_screen = "messenger"
				return ui_data(user)
			T["unread"] = 0
			var/datum/weakref/ref = T["pda"]
			var/obj/item/pda/other = ref?.resolve()
			data["thread"] = list("key" = pda_thread_open, "name" = T["name"], "job" = T["job"], "messages" = T["messages"])
			data["can_reply"] = !toff && ((T["name"] == "Everyone") ? cartridge?.spam_enabled : (other && !other.toff && !other.hidden && other.owner))
		if("contacts")
			var/list/contacts = list()
			if(!toff)
				for(var/obj/item/pda/P in sortNames(get_viewable_pdas()))
					if(P != src)
						contacts += list(list("ref" = REF(P), "name" = "[P.owner] ([P.ownjob])"))
			data["contacts"] = contacts
			data["can_send_all"] = !!cartridge?.spam_enabled
			var/obj/item/cartridge/virus/V = cartridge
			data["virus_charges"] = istype(V) ? V.charges : null
		if("notes")
			data["note"] = notescanned ? comm_plain_text(note) : html_decode(note)
			data["note_scanned"] = notescanned
		if("atmos")
			var/turf/T = get_turf(user)
			var/datum/gas_mixture/environment = T?.return_air()
			if(environment)
				var/total = environment.total_moles()
				var/list/gases = list()
				if(total)
					for(var/id, value in environment.moles)
						if(value / total > 0)
							gases += list(list("name" = GLOB.meta_gas_info[META_GAS_NAME][id], "percent" = round(value / total * 100, 0.01)))
				data["atmos"] = list("pressure" = round(environment.return_pressure(), 0.1), "temperature" = round(environment.temperature - T0C), "gases" = gases)
	return data

/obj/item/pda/ui_act(action, params)
	if(..())
		return
	var/mob/living/U = usr
	if(!istype(U) || !U.canUseTopic(src, BE_CLOSE, FALSE, NO_TK))
		return
	switch(action)
		if("home")
			pda_screen = "home"
		if("screen")
			var/screen = params["screen"]
			if(screen in list("home", "messenger", "contacts", "settings"))
				pda_screen = screen
				if(screen == "messenger")
					update_icon() //the message light goes off, as it did on opening the old messenger
		if("app")
			pda_open_app(U, params["key"])
		if("thread")
			if(LAZYACCESS(pda_threads, params["key"]))
				pda_thread_open = params["key"]
				pda_screen = "thread"
				update_icon()
		if("new_thread")
			var/obj/item/pda/P = locate(params["ref"]) in get_viewable_pdas()
			if(params["everyone"] && cartridge?.spam_enabled)
				pda_thread("Everyone", "all PDAs")
				pda_thread_open = "Everyone (all PDAs)"
				pda_screen = "thread"
			else if(P && P != src)
				var/list/T = pda_thread(P.owner, P.ownjob, P)
				pda_thread_open = "[T["name"]] ([T["job"]])"
				pda_screen = "thread"
		if("delete_thread")
			LAZYREMOVE(pda_threads, params["key"])
			pda_screen = "messenger"
		if("send")
			pda_send_typed(U, params["text"])
		if("virus")
			if(istype(cartridge, /obj/item/cartridge/virus) && (locate(params["ref"]) in GLOB.PDAs))
				Topic(null, list("choice" = "cart", "special" = "virus", "target" = params["ref"]))
		if("clear_all")
			Topic(null, list("choice" = "Clear"))
			pda_threads = null
		if("save_note")
			var/n = stripped_input_text(params["text"], MAX_MESSAGE_LEN * 4, TRUE)
			if(n)
				note = n
				notehtml = parsemarkdown(n, U)
				notescanned = FALSE
		if("ringtone") // the Topic() branch, with the typed tone: an uplink's code opens it and keeps the old tone
			var/t = stripped_input_text(params["text"], 20)
			if(t && in_range(src, U) && loc == U)
				if(SEND_SIGNAL(src, COMSIG_PDA_CHANGE_RINGTONE, U, t) & COMPONENT_STOP_RINGTONE_CHANGE)
					SStgui.close_user_uis(U, src)
					return
				ttone = t
		if("toggle")
			var/static/list/toggles = list("ringer" = "Toggle Ringer", "messenger" = "Toggle Messenger", "beacon" = "Toggle Mandown", "underline" = "Toggle_Underline")
			if(toggles[params["what"]])
				Topic(null, list("choice" = toggles[params["what"]]))
		if("color")
			Topic(null, list("choice" = "Change_Color"))
		if("id")
			Topic(null, list("choice" = "Authenticate"))
		if("register") // no owner yet: the card in hand swiped, as attackby() does it
			var/obj/item/card/id/I = U.get_active_held_item()
			if(!owner && istype(I))
				attackby(I, U)
		if("update_info")
			if(id)
				Topic(null, list("choice" = "UpdateInfo"))
		if("eject_cart")
			Topic(null, list("choice" = "Eject"))
	return TRUE

/// An app on the home screen
/obj/item/pda/proc/pda_open_app(mob/living/U, key)
	switch(key)
		if("messenger")
			pda_screen = "messenger"
			update_icon()
		if("notes", "atmos", "settings")
			pda_screen = key
		if("light")
			toggle_light()
		if("scan_medical")
			Topic(null, list("choice" = "Medical Scan"))
		if("scan_reagent")
			Topic(null, list("choice" = "Reagent Scan"))
		if("scan_halogen")
			Topic(null, list("choice" = "Halogen Counter"))
		if("scan_gas")
			Topic(null, list("choice" = "Gas Scan"))
		if("honk")
			Topic(null, list("choice" = "Honk"))
		if("trombone")
			Topic(null, list("choice" = "Trombone"))
		if("door")
			Topic(null, list("choice" = "Toggle Door"))
		if("drone")
			Topic(null, list("choice" = "Drone Phone"))
		if("record_play")
			if(R)
				playMusic(U)
		if("record_stop")
			if(R)
				stopMusic(U)
		if("record_eject") // what the old window did on its way to drawing mode 9
			if(R)
				stopMusic(U)
				R.forceMove(get_turf(src))
				playsound(src, 'hippiestation/sound/effects/plastic_click.ogg', 100, 0)
				R = null
				update_icon()
		if("pai_config")
			if(pai && pai.loc == src)
				Topic(null, list("choice" = "pai", "option" = "1"))
		if("pai_eject")
			if(pai && pai.loc == src)
				Topic(null, list("choice" = "pai", "option" = "2"))
		else
			// A cartridge's program: its old window, from the old menu's link
			var/static/list/programs = list("40", "41", "42", "43", "44", "45", "47", "48", "49", "53", "54")
			if(cartridge && (key in programs))
				Topic(null, list("choice" = key))

/// Sends what's typed in the open conversation, to whoever it's with (or everyone, with a cartridge that can)
/obj/item/pda/proc/pda_send_typed(mob/living/U, text)
	var/list/T = LAZYACCESS(pda_threads, pda_thread_open)
	if(!T || !istext(text) || toff)
		return
	if(T["name"] == "Everyone" && T["job"] == "all PDAs")
		if(!cartridge?.spam_enabled)
			return
		if(last_everyone && world.time < last_everyone + 2 MINUTES) //PDA_SPAM_DELAY
			to_chat(U, "<span class='warning'>Send To All function is still on cooldown.</span>")
			return
		send_message(U, get_viewable_pdas(), TRUE, text)
		return
	var/datum/weakref/ref = T["pda"]
	var/obj/item/pda/P = ref?.resolve()
	if(!P || !(P in get_viewable_pdas()))
		to_chat(U, "<span class='warning'>[T["name"]] can't be reached.</span>")
		return
	send_message(U, list(P), FALSE, text)

#undef PDA_THREAD_KEEP
