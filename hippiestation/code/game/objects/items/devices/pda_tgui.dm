// hippie -- the PDA is a tgui window with the original PDA's screens, tidied (the user's rulings, 2026-11-05): the same menu (owner,
// ID, time, General Functions, the cartridge's sections, Utilities) in the same order and words, the original messenger (ringer,
// send/receive, ringtone, the PDAs detected, the one message log) with conversations kept as a screen of their own, and every
// cartridge program (signaler, manifest, status displays, power monitor, records, supply, ore silo, custodial locator, newscaster,
// bots) as a screen of the same window. A status bar and Back/Home along the top. Dark tgui look; the old font, colour and underline
// toggles are gone.
// The screens are the PDA's own modes (PDA.dm, cart.dm) and every button goes through its own Topic() or the cartridge's, but what
// was a popup there (a message, a note, the ringtone, the status display lines, the newscaster channel and story), which is that
// Topic()'s branch here with the text typed in the window. Messages are still written to tnote for the pAI and anything else reading
// it; a ringtone that's an uplink's code still opens it.
// The window is the handheld (the user's rulings, same morning): a case in the PDA's own paint around a glowing screen, signal bars
// that are the real route a message takes, a second's boot screen the first time it's opened, a wallpaper per department, and the
// clown's and the mime's PDAs in their own looks.

#define PDA_THREAD_KEEP 100
#define PDA_LOG_KEEP 200
// The PDA's own screens beyond the original's: the conversations, one conversation, and a message being written
#define PDA_MODE_CONVERSATIONS 22
#define PDA_MODE_THREAD 23
#define PDA_MODE_COMPOSE 24

/obj/item/pda
	/// The messenger's conversations, oldest first: "Name (Job)" -> list("name", "job", "pda" = weakref, "messages", "unread")
	var/list/pda_threads
	/// The conversation on the screen
	var/pda_thread_open
	/// Every message sent and received, oldest first, for the Messages screen: list("out", "name", "job", "text", "time", "pda")
	var/list/pda_log
	/// Who a message being written is for (weakref), or "everyone"
	var/pda_compose_to
	/// Seen the log since the last message came in
	var/pda_unread = 0
	/// Opened this round: the boot screen is shown once
	var/pda_booted = FALSE
	/// The signal bars, worked out at most once a second: list("bars", "why")
	var/list/pda_signal
	var/pda_signal_at = 0

// ---------------------------------------------------------------------------------------------
// Opening it
// ---------------------------------------------------------------------------------------------

/obj/item/pda/interact(mob/user)
	if(!user.IsAdvancedToolUser())
		to_chat(user, "<span class='warning'>You don't have the dexterity to do this!</span>")
		return
	add_fingerprint(user)
	user.set_machine(src)
	user << browse(null, "window=pda")
	ui_interact(user)

/obj/item/pda/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "pda", "Personal Data Assistant", 500, 700, master_ui, state)
		ui.open()
		pda_booted = TRUE

/// The case's paint, after the PDA's own sprite (a chameleon PDA takes the look it's disguised as)
/obj/item/pda/proc/pda_theme()
	var/static/list/themes = list(
		"pda-medical" = "medical", "pda-virology" = "medical", "pda-chemistry" = "medical", "pda-genetics" = "medical", "pda-cmo" = "medical",
		"pda-engineer" = "engineering", "pda-atmos" = "engineering", "pda-ce" = "engineering",
		"pda-security" = "security", "pda-detective" = "security", "pda-warden" = "security", "pda-hos" = "security",
		"pda-science" = "science", "pda-rd" = "science", "pda-roboticist" = "science",
		"pda-cargo" = "cargo", "pda-qm" = "cargo", "pda-miner" = "cargo",
		"pda-captain" = "captain", "pda-clown" = "clown", "pda-mime" = "mime", "pda-syndi" = "syndicate",
	)
	return themes[icon_state] || "nt"

/// The signal bars: the route a message takes (broadcasting.dm send_to_receivers()), with a signal that's never sent. A subspace
/// receiver that's on and hears this level (4 bars; 2 through a relay), then a message server that's on. No bars, and why, if not.
/obj/item/pda/proc/pda_signal_now()
	if(pda_signal && world.time < pda_signal_at + 1 SECONDS)
		return pda_signal
	pda_signal_at = world.time
	pda_signal = list("bars" = 0, "why" = "Send / Receive is off")
	if(toff)
		return pda_signal
	var/turf/here = get_turf(src)
	if(!here)
		pda_signal["why"] = "No signal"
		return pda_signal
	var/datum/signal/subspace/messaging/pda/probe = new(src, list())
	var/bars = 0
	for(var/obj/machinery/telecomms/receiver/R in GLOB.telecomms_list)
		if(!R.on || !R.is_freq_listening(probe) || !R.check_receive_level(probe))
			continue
		bars = max(bars, R.z == here.z ? 4 : 2)
	for(var/obj/machinery/telecomms/allinone/A in GLOB.telecomms_list)
		if(A.on && A.is_freq_listening(probe) && (A.intercept || A.z == here.z))
			bars = 4
	if(!bars)
		pda_signal["why"] = "No signal: telecomms can't hear you here"
		return pda_signal
	for(var/obj/machinery/telecomms/message_server/S in GLOB.telecomms_list)
		if(S.on && !S.calibrating)
			pda_signal = list("bars" = bars, "why" = bars == 4 ? "Messages get through" : "Messages get through, by relay")
			return pda_signal
	pda_signal["why"] = "No signal: the message server is down"
	return pda_signal

// ---------------------------------------------------------------------------------------------
// The messages (hooks in send_message() and receive_message(), PDA.dm, and receive_page(), dept_pager.dm)
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

/obj/item/pda/proc/pda_log_add(list/entry)
	LAZYINITLIST(pda_log)
	pda_log += list(entry)
	if(length(pda_log) > PDA_LOG_KEEP)
		pda_log.Cut(1, 2)

/// What it's just sent, in the log and in the conversation with each it went to (or "Everyone")
/obj/item/pda/proc/pda_log_sent(list/targets, message, everyone)
	var/text = html_decode(message)
	var/time = station_time_timestamp("hh:mm")
	var/list/line = list("out" = TRUE, "text" = text, "time" = time)
	if(everyone)
		pda_log_add(list("out" = TRUE, "name" = "Everyone", "job" = "", "text" = text, "time" = time))
		pda_thread_add(pda_thread("Everyone", "all PDAs"), line)
		return
	for(var/obj/item/pda/P in targets)
		if(P.owner && P.ownjob)
			pda_log_add(list("out" = TRUE, "name" = P.owner, "job" = P.ownjob, "text" = text, "time" = time, "pda" = REF(P)))
			pda_thread_add(pda_thread(P.owner, P.ownjob, P), line.Copy())

/// A message that's come in, in the log and the conversation with whoever sent it. A page from a department pager is marked as one.
/obj/item/pda/proc/pda_log_received(datum/signal/subspace/messaging/pda/signal, page = FALSE)
	var/text = html_decode(signal.data["message"])
	var/time = station_time_timestamp("hh:mm")
	var/list/line = list("out" = FALSE, "text" = text, "time" = time)
	var/list/entry = list("out" = FALSE, "name" = signal.data["name"], "job" = signal.data["job"], "text" = text, "time" = time)
	if(istype(signal.source, /obj/item/pda))
		entry["pda"] = REF(signal.source)
	if(signal.data["photo"])
		line["photo"] = TRUE
		entry["photo"] = TRUE
	if(page)
		line["page"] = "Page to [signal.data["page_department"]], at [signal.data["page_location"]]"
		entry["page"] = line["page"]
	pda_log_add(entry)
	var/list/T = pda_thread(signal.data["name"], signal.data["job"], signal.source)
	pda_thread_add(T, line)
	T["unread"]++
	pda_unread++
	SStgui.update_uis(src)

/// The text of a message typed into the window, checked as msg_input() (PDA.dm) checks what's typed into its box
/obj/item/pda/proc/pda_typed_message(mob/living/user, typed)
	var/t = stripped_input_text(typed, MAX_MESSAGE_LEN)
	if(!t || toff || !user.canUseTopic(src, BE_CLOSE))
		return
	if(emped)
		t = Gibberish(t, 100)
	return t

/// Sends typed text to a PDA, or to everyone with a cartridge that can, as the old messenger's Message and Send To All did
/obj/item/pda/proc/pda_send_to(mob/living/U, target, text)
	if(!istext(text) || toff)
		return FALSE
	if(target == "everyone")
		if(!cartridge?.spam_enabled)
			return FALSE
		if(last_everyone && world.time < last_everyone + 2 MINUTES) //PDA_SPAM_DELAY
			to_chat(U, "<span class='warning'>Send To All function is still on cooldown.</span>")
			return FALSE
		send_message(U, get_viewable_pdas(), TRUE, text)
		return TRUE
	var/obj/item/pda/P = target
	if(!istype(P) || !(P in get_viewable_pdas()))
		to_chat(U, "<span class='warning'>They can't be reached.</span>")
		return FALSE
	send_message(U, list(P), FALSE, text)
	return TRUE

// ---------------------------------------------------------------------------------------------
// The menu
// ---------------------------------------------------------------------------------------------

/// The home screen, in the old menu's order and words: list(list("title", "items" = list(list("key", "name", "icon", "on")...)))
/obj/item/pda/proc/pda_menu()
	var/list/general = list()
	general += list(list("key" = "1", "name" = "Notekeeper", "icon" = "sticky-note"))
	general += list(list("key" = "2", "name" = "Messenger", "icon" = "envelope", "badge" = pda_unread))
	if(R)
		general += list(list("key" = "record_eject", "name" = "Eject record disk", "icon" = "compact-disc"))
		general += list(list("key" = "record_play", "name" = "Play record disk", "icon" = "play"))
		general += list(list("key" = "record_stop", "name" = "Stop record disk", "icon" = "stop"))
	var/list/sections = list()
	var/list/utilities = list()
	if(cartridge)
		var/flags = cartridge.access
		if(flags & CART_CLOWN)
			general += list(list("key" = "honk", "name" = "Honk Synthesizer", "icon" = "bullhorn"))
			general += list(list("key" = "trombone", "name" = "Sad Trombone", "icon" = "sad-tear"))
		if(flags & CART_MANIFEST)
			general += list(list("key" = "41", "name" = "View Crew Manifest", "icon" = "users"))
		if(flags & CART_STATUS_DISPLAY)
			general += list(list("key" = "42", "name" = "Set Status Display", "icon" = "tv"))
		if(flags & CART_ENGINE)
			sections += list(list("title" = "Engineering Functions", "items" = list(list("key" = "43", "name" = "Power Monitor", "icon" = "bolt"))))
		if(flags & CART_MEDICAL)
			sections += list(list("title" = "Medical Functions", "items" = list(
				list("key" = "44", "name" = "Medical Records", "icon" = "notes-medical"),
				list("key" = "scan_medical", "name" = "[scanmode == 1 ? "Disable" : "Enable"] Medical Scanner", "icon" = "heartbeat", "on" = scanmode == 1),
			)))
		if(flags & CART_SECURITY)
			sections += list(list("title" = "Security Functions", "items" = list(list("key" = "45", "name" = "Security Records", "icon" = "shield-alt"))))
		if(flags & CART_QUARTERMASTER)
			sections += list(list("title" = "Quartermaster Functions", "items" = list(
				list("key" = "47", "name" = "Supply Records", "icon" = "box"),
				list("key" = "48", "name" = "Ore Silo Logs", "icon" = "gem"),
			)))
		if(cartridge.bot_access_flags)
			utilities += list(list("key" = "54", "name" = "Bots Access", "icon" = "robot"))
		if(flags & CART_JANITOR)
			utilities += list(list("key" = "49", "name" = "Custodial Locator", "icon" = "broom"))
		if(istype(cartridge.radio))
			utilities += list(list("key" = "40", "name" = "Signaler System", "icon" = "broadcast-tower"))
		if(flags & CART_NEWSCASTER)
			utilities += list(list("key" = "53", "name" = "Newscaster Access", "icon" = "newspaper"))
		if(flags & CART_REAGENT_SCANNER)
			utilities += list(list("key" = "scan_reagent", "name" = "[scanmode == 3 ? "Disable" : "Enable"] Reagent Scanner", "icon" = "flask", "on" = scanmode == 3))
		if(flags & CART_ENGINE)
			utilities += list(list("key" = "scan_halogen", "name" = "[scanmode == 4 ? "Disable" : "Enable"] Halogen Counter", "icon" = "radiation", "on" = scanmode == 4))
		if(flags & CART_ATMOS)
			utilities += list(list("key" = "scan_gas", "name" = "[scanmode == 5 ? "Disable" : "Enable"] Gas Scanner", "icon" = "cloud", "on" = scanmode == 5))
		if(flags & CART_REMOTE_DOOR)
			utilities += list(list("key" = "door", "name" = "Toggle Remote Door", "icon" = "door-open"))
		if(flags & CART_DRONEPHONE)
			utilities += list(list("key" = "drone", "name" = "Drone Phone", "icon" = "phone"))
	utilities += list(list("key" = "3", "name" = "Atmospheric Scan", "icon" = "wind"))
	utilities += list(list("key" = "light", "name" = "[fon ? "Disable" : "Enable"] Flashlight", "icon" = "lightbulb", "on" = fon))
	if(pai && pai.loc == src)
		utilities += list(list("key" = "pai_config", "name" = "pAI Device Configuration", "icon" = "microchip"))
		utilities += list(list("key" = "pai_eject", "name" = "Eject pAI Device", "icon" = "eject"))
	. = list(list("title" = "General Functions", "items" = general))
	. += sections
	. += list(list("title" = "Utilities", "items" = utilities))

/// The cartridge programs the menu offers, by mode: only those can be opened
/obj/item/pda/proc/pda_cart_modes()
	. = list()
	if(!cartridge)
		return
	var/flags = cartridge.access
	if(istype(cartridge.radio))
		. += 40
	if(flags & CART_MANIFEST)
		. += 41
	if(flags & CART_STATUS_DISPLAY)
		. += 42
	if(flags & CART_ENGINE)
		. += 43
	if(flags & CART_MEDICAL)
		. += 44
	if(flags & CART_SECURITY)
		. += 45
	if(flags & CART_QUARTERMASTER)
		. += list(47, 48)
	if(flags & CART_JANITOR)
		. += 49
	if(flags & CART_NEWSCASTER)
		. += 53
	if(cartridge.bot_access_flags)
		. += 54

// ---------------------------------------------------------------------------------------------
// The window's data
// ---------------------------------------------------------------------------------------------

/obj/item/pda/ui_data(mob/user)
	var/list/data = list()
	if(pai && pai.loc != src)
		pai = null
	// A cartridge program with no cartridge (ejected meanwhile): back to the menu, as Return did
	if(mode >= 40 && mode != 99 && !cartridge)
		mode = 0
	data["mode"] = mode
	data["owner"] = owner
	data["job"] = ownjob
	data["time"] = station_time_timestamp("hh:mm:ss")
	data["date"] = "[time2text(world.realtime, "MMM DD")] [GLOB.year_integer + 540]"
	data["id"] = id ? "[id.registered_name], [id.assignment]" : null
	data["holding_id"] = istype(user.get_active_held_item(), /obj/item/card/id)
	data["cartridge"] = cartridge ? cartridge.name : null
	data["light"] = fon
	data["unread"] = pda_unread
	data["theme"] = pda_theme()
	data["signal"] = pda_signal_now()
	data["boot"] = !pda_booted
	switch(mode)
		if(0)
			data["menu"] = pda_menu()
		if(1)
			data["note"] = notescanned ? comm_plain_text(note) : html_decode(note)
			data["note_scanned"] = notescanned
		if(2)
			data += pda_messenger_data()
		if(21)
			var/list/log = list()
			for(var/i in length(pda_log) to 1 step -1)
				log += list(pda_log[i])
			data["log"] = log
			if(pda_unread)
				pda_unread = 0
				update_icon() //the message light goes off, as it did on opening the old Messages
		if(PDA_MODE_CONVERSATIONS)
			var/list/threads = list()
			for(var/i in length(pda_threads) to 1 step -1)
				var/key = pda_threads[i]
				var/list/T = pda_threads[key]
				var/list/messages = T["messages"]
				var/list/last = length(messages) ? messages[length(messages)] : null
				threads += list(list("key" = key, "name" = T["name"], "job" = T["job"], "unread" = T["unread"], "last" = last ? (last["out"] ? "You: " : "") + last["text"] : "", "time" = last ? last["time"] : ""))
			data["threads"] = threads
			data["toff"] = toff
		if(PDA_MODE_THREAD)
			var/list/T = LAZYACCESS(pda_threads, pda_thread_open)
			if(!T)
				mode = PDA_MODE_CONVERSATIONS
				return ui_data(user)
			if(T["unread"]) // read here, they're read in the log too
				pda_unread = max(0, pda_unread - T["unread"])
				data["unread"] = pda_unread
				T["unread"] = 0
				update_icon()
			var/datum/weakref/ref = T["pda"]
			var/obj/item/pda/other = ref?.resolve()
			data["thread"] = list("key" = pda_thread_open, "name" = T["name"], "job" = T["job"], "messages" = T["messages"])
			data["can_reply"] = !toff && ((T["name"] == "Everyone") ? cartridge?.spam_enabled : (other && (other in get_viewable_pdas())))
			data["toff"] = toff
		if(PDA_MODE_COMPOSE)
			var/datum/weakref/ref = pda_compose_to
			var/obj/item/pda/P = istype(ref) ? ref.resolve() : null
			if(pda_compose_to == "everyone")
				data["compose_to"] = "everyone"
			else if(P)
				data["compose_to"] = "[P.owner] ([P.ownjob])"
			else
				mode = 2
				return ui_data(user)
		if(3)
			data["atmos"] = pda_atmos_data(user)
		if(40 to 999) // the cartridge's, and their pages (433, 441, 451)
			data += pda_cart_data(user)
	return data

/obj/item/pda/proc/pda_messenger_data()
	var/list/data = list()
	data["silent"] = silent
	data["toff"] = toff
	data["ringtone"] = ttone
	data["beacon"] = mandown_enabled
	var/list/contacts = list()
	if(!toff)
		for(var/obj/item/pda/P in sortNames(get_viewable_pdas()))
			if(P != src)
				contacts += list(list("ref" = REF(P), "name" = "[P]"))
	data["contacts"] = contacts
	data["can_send_all"] = !!cartridge?.spam_enabled
	var/obj/item/cartridge/virus/V = cartridge
	data["virus_charges"] = istype(V) ? V.charges : null
	return data

/obj/item/pda/proc/pda_atmos_data(mob/user)
	var/turf/T = get_turf(user)
	var/datum/gas_mixture/environment = T?.return_air()
	if(!environment)
		return null
	var/total = environment.total_moles()
	var/list/gases = list()
	if(total)
		for(var/id, value in environment.moles)
			if(value / total > 0)
				gases += list(list("name" = GLOB.meta_gas_info[META_GAS_NAME][id], "percent" = round(value / total * 100, 0.01)))
	return list("pressure" = round(environment.return_pressure(), 0.1), "temperature" = round(environment.temperature - T0C), "gases" = gases)

/// A cartridge program's screen: what generate_menu() (cart.dm) put on the page, as data
/obj/item/pda/proc/pda_cart_data(mob/user)
	var/list/data = list()
	var/obj/item/cartridge/C = cartridge
	if(!C)
		return data
	switch(mode)
		if(40)
			if(istype(C.radio))
				data["signal"] = list("frequency" = format_frequency(C.radio.frequency), "code" = C.radio.code)
		if(41)
			var/list/crew = list()
			for(var/datum/data/record/t in sortRecord(GLOB.data_core.general))
				crew += list(list("name" = t.fields["name"], "rank" = t.fields["rank"]))
			data["manifest"] = crew
		if(42)
			data["status"] = list("line1" = C.message1, "line2" = C.message2)
		if(43)
			C.powmonitor = null
			C.powermonitors = list()
			var/turf/pda_turf = get_turf(src)
			var/list/monitors = list()
			for(var/obj/machinery/computer/monitor/pMon in GLOB.machines)
				if((pMon.stat & (NOPOWER|BROKEN)) || pda_turf?.z != pMon.z || pMon.is_secret_monitor)
					continue
				C.powermonitors += pMon
				monitors += list(list("index" = length(C.powermonitors), "name" = capitalize(pMon.name), "area" = get_area_name(pMon, TRUE)))
			data["monitors"] = monitors
		if(433)
			var/datum/powernet/net = C.powmonitor?.get_powernet()
			if(net)
				var/list/apcs = list()
				var/static/list/states = list("Off", "Auto off", "On", "Auto on")
				var/static/list/charging = list("not charging", "charging", "full")
				for(var/obj/machinery/power/terminal/term in net.nodes)
					var/obj/machinery/power/apc/A = term.master
					if(!istype(A))
						continue
					apcs += list(list(
						"area" = A.area ? A.area.name : "[A]",
						"equipment" = states[A.equipment + 1],
						"lighting" = states[A.lighting + 1],
						"environ" = states[A.environ + 1],
						"load" = DisplayPower(A.lastused_total),
						"cell" = A.cell ? round(A.cell.percent()) : null,
						"charging" = charging[A.charging + 1],
					))
				data["power"] = list("location" = get_area_name(C.powmonitor, TRUE), "available" = DisplayPower(net.viewavail), "load" = DisplayPower(net.viewload), "apcs" = apcs)
		if(44, 45)
			var/list/records = list()
			for(var/datum/data/record/R in sortRecord(GLOB.data_core.general))
				records += list(list("id" = R.fields["id"], "name" = R.fields["name"]))
			data["records"] = records
		if(441, 451)
			if(C.active1 in GLOB.data_core.general)
				var/list/f = C.active1.fields
				data["general"] = list("name" = f["name"], "id" = f["id"], "gender" = f["gender"], "age" = f["age"], "rank" = f["rank"], "fingerprint" = f["fingerprint"], "p_stat" = f["p_stat"], "m_stat" = f["m_stat"])
			if(mode == 441 && (C.active2 in GLOB.data_core.medical))
				var/list/f = C.active2.fields
				data["medical"] = list("blood_type" = f["blood_type"], "mi_dis" = f["mi_dis"], "mi_dis_d" = f["mi_dis_d"], "ma_dis" = f["ma_dis"], "ma_dis_d" = f["ma_dis_d"], "alg" = f["alg"], "alg_d" = f["alg_d"], "cdi" = f["cdi"], "cdi_d" = f["cdi_d"], "notes" = comm_plain_text(f["notes"]))
			if(mode == 451 && (C.active3 in GLOB.data_core.security))
				var/list/f = C.active3.fields
				var/list/minor = list()
				for(var/datum/data/crime/c in f["mi_crim"])
					minor += list(list("name" = c.crimeName, "details" = c.crimeDetails, "author" = c.author, "time" = c.time))
				var/list/major = list()
				for(var/datum/data/crime/c in f["ma_crim"])
					major += list(list("name" = c.crimeName, "details" = c.crimeDetails, "author" = c.author, "time" = c.time))
				data["security"] = list("criminal" = f["criminal"], "minor" = minor, "major" = major, "notes" = comm_plain_text(f["notes"]))
		if(47)
			var/obj/docking_port/mobile/supply/S = SSshuttle.supply
			var/where = "Unknown"
			if(S)
				if(S.mode == SHUTTLE_CALL)
					where = "Moving to [is_station_level(S.z) ? "CentCom" : "station"] ([S.timeLeft(600)] Mins)"
				else
					where = "At [is_station_level(S.z) ? "station" : "CentCom"]"
			var/list/approved = list()
			for(var/datum/supply_order/SO in SSshuttle.shoppinglist)
				approved += list(list("id" = SO.id, "pack" = SO.pack.name, "orderer" = SO.orderer, "approved_by" = SO.approved_by, "reason" = SO.reason))
			var/list/requests = list()
			for(var/datum/supply_order/SO in SSshuttle.requestlist)
				requests += list(list("id" = SO.id, "pack" = SO.pack.name, "orderer" = SO.orderer))
			var/list/shipped = list()
			for(var/list/entry in cargo_order_ledger(10)) //hippiestation/code/modules/cargo/order_ledger.dm
				shipped += list(list("id" = entry["id"], "text" = "[entry["object"]] for [entry["orderer"]] ([entry["orderer_rank"]]), [entry["cost"]] cr from [entry["paid_by"]][entry["approved_by"] ? ", approved by [entry["approved_by"]]" : ""], [entry["delivery"]] at [entry["shipped_at"]]"))
			data["supply"] = list("where" = where, "approved" = approved, "requests" = requests, "shipped" = shipped)
		if(48)
			if(GLOB.ore_silo_default)
				var/list/logs = GLOB.silo_access_logs[REF(GLOB.ore_silo_default)]
				var/list/entries = list()
				var/len = LAZYLEN(logs)
				var/i = 0
				for(var/datum/ore_silo_log/entry as anything in logs)
					if(++i > 30)
						break
					entries += list(list("index" = len - i, "text" = comm_plain_text(entry.formatted)))
				data["silo"] = list("entries" = entries, "more" = len > 30)
		if(49)
			var/turf/here = get_turf(src)
			if(here)
				var/list/mops = list()
				for(var/obj/item/mop/M as anything in bot_instances_of(/obj/item/mop))
					var/turf/T = get_turf(M)
					if(T && T.z == here.z)
						mops += list(list("x" = T.x, "y" = T.y, "dir" = uppertext(dir2text(get_dir(here, T)) || "here"), "state" = M.reagents?.total_volume ? "Wet" : "Dry"))
				var/list/carts = list()
				for(var/obj/structure/janitorialcart/B as anything in bot_instances_of(/obj/structure/janitorialcart))
					var/turf/T = get_turf(B)
					if(T && T.z == here.z)
						carts += list(list("x" = T.x, "y" = T.y, "dir" = uppertext(dir2text(get_dir(here, T)) || "here"), "state" = "Water level: [B.reagents?.total_volume]/100"))
				var/list/bots = list()
				for(var/mob/living/simple_animal/bot/cleanbot/B in GLOB.alive_mob_list)
					var/turf/T = get_turf(B)
					if(T && T.z == here.z)
						bots += list(list("x" = T.x, "y" = T.y, "dir" = uppertext(dir2text(get_dir(here, T)) || "here"), "state" = B.on ? "Online" : "Offline"))
				data["janitor"] = list("x" = here.x, "y" = here.y, "mops" = mops, "carts" = carts, "bots" = bots)
		if(53)
			var/list/channels = list()
			var/datum/newscaster/feed_channel/current
			for(var/datum/newscaster/feed_channel/chan in GLOB.news_network.network_channels)
				channels += chan.channel_name
				if(chan.channel_name == C.current_channel)
					current = chan
			var/list/stories = list()
			if(current)
				for(var/datum/newscaster/feed_message/msg in current.messages)
					var/list/comments = list()
					for(var/datum/newscaster/feed_comment/comment in msg.comments)
						comments += list(list("body" = comm_plain_text(comment.body), "author" = comment.author, "time" = comment.time_stamp))
					stories += list(list("body" = comm_plain_text(msg.returnBody(-1)), "author" = msg.returnAuthor(-1), "comments" = comments))
			data["news"] = list("channel" = C.current_channel, "channels" = channels, "found" = !!current, "stories" = stories)
		if(54)
			data["bots"] = pda_bots_data(user)
	return data

/// Bots Interlink (cart.dm bot_control()): the bots this cartridge reaches, or the one being controlled
/obj/item/pda/proc/pda_bots_data(mob/user)
	var/obj/item/cartridge/C = cartridge
	var/mob/living/simple_animal/bot/B = C.active_bot
	if(B && !QDELETED(B))
		var/list/bot = list("ref" = REF(B), "name" = B.name, "model" = B.model, "location" = get_area_name(B, TRUE)) + pda_bot_mode(B)
		if(B.allow_pai)
			bot["pai"] = (B.paicard && B.paicard.pai) ? B.paicard.pai.name : "none"
			bot["can_eject_pai"] = B.paicard && B.paicard.pai && B.bot_core.allowed(user)
		var/mob/living/simple_animal/bot/mulebot/M = B
		if(istype(M))
			var/atom/load = M.load
			bot["mule"] = list("load" = load ? load.name : null, "destination" = M.destination, "id" = M.suffix, "power" = M.cell ? M.cell.percent() : 0, "home" = M.home_destination, "report" = M.report_delivery, "autoret" = M.auto_return, "autopick" = M.auto_pickup)
		return list("active" = bot)
	var/list/found = list()
	var/turf/here = get_turf(src)
	for(var/mob/living/simple_animal/bot/Bot as anything in GLOB.bots_list)
		if(!Bot.on || Bot.z != here?.z || Bot.remote_disabled || !(C.bot_access_flags & Bot.bot_type))
			continue
		found += list(list("ref" = REF(Bot), "name" = Bot.name) + pda_bot_mode(Bot))
	return list("list" = found)

/// A bot's get_mode() is a coloured span: its words, and its colour for the window
/obj/item/pda/proc/pda_bot_mode(mob/living/simple_animal/bot/B)
	var/raw = B.get_mode()
	var/static/regex/span_class = new("class='(\\w+)'")
	return list("mode" = comm_plain_text(raw), "mode_color" = span_class.Find(raw) ? span_class.group[1] : null)

// ---------------------------------------------------------------------------------------------
// The buttons
// ---------------------------------------------------------------------------------------------

/obj/item/pda/ui_act(action, params)
	if(..())
		return
	var/mob/living/U = usr
	if(!istype(U) || !U.canUseTopic(src, BE_CLOSE, FALSE, NO_TK))
		return
	switch(action)
		if("home")
			Topic(null, list("choice" = "0"))
		if("back")
			if(mode == PDA_MODE_THREAD)
				mode = PDA_MODE_CONVERSATIONS
			else if(mode == PDA_MODE_CONVERSATIONS || mode == PDA_MODE_COMPOSE)
				mode = 2
			else if(mode == 99)
				mode = 53
			else
				Topic(null, list("choice" = "Return"))
		if("open") // a menu entry: the old menu's link
			pda_open(U, "[params["key"]]")
		if("conversations")
			mode = PDA_MODE_CONVERSATIONS
			update_icon()
		if("thread")
			if(LAZYACCESS(pda_threads, params["key"]))
				pda_thread_open = params["key"]
				mode = PDA_MODE_THREAD
		if("delete_thread")
			LAZYREMOVE(pda_threads, params["key"])
			mode = PDA_MODE_CONVERSATIONS
		if("compose") // a name in Detected PDAs, a Reply in the log, or Send To All
			if(params["everyone"])
				if(cartridge?.spam_enabled)
					pda_compose_to = "everyone"
					mode = PDA_MODE_COMPOSE
			else
				var/obj/item/pda/P = locate(params["ref"]) in get_viewable_pdas()
				if(P && P != src)
					pda_compose_to = WEAKREF(P)
					mode = PDA_MODE_COMPOSE
		if("send")
			if(mode == PDA_MODE_COMPOSE)
				var/datum/weakref/ref = pda_compose_to
				var/target = (pda_compose_to == "everyone") ? "everyone" : (istype(ref) ? ref.resolve() : null)
				if(target && pda_send_to(U, target, params["text"]))
					mode = 2
			else if(mode == PDA_MODE_THREAD)
				var/list/T = LAZYACCESS(pda_threads, pda_thread_open)
				if(T)
					var/datum/weakref/ref = T["pda"]
					pda_send_to(U, (T["name"] == "Everyone") ? "everyone" : ref?.resolve(), params["text"])
		if("virus")
			if(istype(cartridge, /obj/item/cartridge/virus) && (locate(params["ref"]) in GLOB.PDAs))
				Topic(null, list("choice" = "cart", "special" = "virus", "target" = params["ref"]))
		if("clear")
			Topic(null, list("choice" = "Clear"))
			pda_log = null
			pda_threads = null
			pda_unread = 0
		if("save_note") // the Topic() branch "Edit", with the typed note
			var/n = stripped_input_text(params["text"], MAX_MESSAGE_LEN * 4, TRUE)
			if(n && mode == 1)
				note = n
				notehtml = parsemarkdown(n, U)
				notescanned = FALSE
		if("ringtone") // likewise "Ringtone": an uplink's code opens it and keeps the old tone
			var/t = stripped_input_text(params["text"], 20)
			if(t && in_range(src, U) && loc == U)
				if(SEND_SIGNAL(src, COMSIG_PDA_CHANGE_RINGTONE, U, t) & COMPONENT_STOP_RINGTONE_CHANGE)
					SStgui.close_user_uis(U, src)
					return
				ttone = t
		if("toggle")
			var/static/list/toggles = list("ringer" = "Toggle Ringer", "messenger" = "Toggle Messenger", "beacon" = "Toggle Mandown")
			if(toggles[params["what"]])
				Topic(null, list("choice" = toggles[params["what"]]))
		if("id")
			var/obj/item/card/id/I = U.get_active_held_item()
			if(!owner && istype(I))
				attackby(I, U) // no owner yet: swiped, as attackby() does it
			else
				Topic(null, list("choice" = "Authenticate"))
		if("update_info")
			if(id)
				Topic(null, list("choice" = "UpdateInfo"))
		if("eject_cart")
			Topic(null, list("choice" = "Eject"))
		if("cart")
			pda_cart_act(U, params)
	return TRUE

/// A menu entry, by its key: a screen, or one of the old menu's own buttons
/obj/item/pda/proc/pda_open(mob/living/U, key)
	switch(key)
		if("1", "2", "21", "3")
			Topic(null, list("choice" = key))
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
			var/num = text2num(key)
			if(num && (num in pda_cart_modes()))
				Topic(null, list("choice" = key))

/// A cartridge program's button: the cartridge's own Topic() (cart.dm) but for what was a popup there
/obj/item/pda/proc/pda_cart_act(mob/living/U, list/params)
	var/obj/item/cartridge/C = cartridge
	if(!C)
		return
	var/list/href = list()
	switch(params["do"])
		if("record")
			if(mode == 44)
				href = list("choice" = "Medical Records", "target" = "[params["id"]]")
			else if(mode == 45)
				href = list("choice" = "Security Records", "target" = "[params["id"]]")
		if("send_signal")
			if(mode == 40)
				href = list("choice" = "Send Signal")
		if("frequency")
			if(mode == 40)
				href = list("choice" = "Signal Frequency", "sfreq" = "[clamp(text2num(params["by"]), -10, 10)]")
		if("code")
			if(mode == 40)
				href = list("choice" = "Signal Code", "scode" = "[clamp(text2num(params["by"]), -5, 5)]")
		if("status")
			if(mode == 42 && (params["what"] in list("blank", "shuttle", "message")))
				href = list("choice" = "Status", "statdisp" = params["what"])
		if("status_alert")
			if(mode == 42 && (params["alert"] in list("default", "redalert", "lockdown", "biohazard")))
				href = list("choice" = "Status", "statdisp" = "alert", "alert" = params["alert"])
		if("status_line") // "setmsg1"/"setmsg2", typed
			if(mode == 42)
				var/text = reject_bad_text(stripped_input_text(params["text"], 40), 40)
				if(text2num(params["line"]) == 1) // params come as text from the window
					C.message1 = text
				else
					C.message2 = text
		if("power_select")
			var/index = text2num(params["index"])
			if(mode == 43 && index >= 1 && index <= length(C.powermonitors))
				href = list("choice" = "Power Select", "target" = "[index]")
		if("news_channel") // "Newscaster Switch Channel", picked from the channels there are
			if(mode == 53)
				for(var/datum/newscaster/feed_channel/chan in GLOB.news_network.network_channels)
					if(chan.channel_name == params["name"])
						C.current_channel = chan.channel_name
		if("news_post") // "Newscaster Message", typed
			if(mode == 53)
				pda_news_post(U, params["text"])
		if("bot")
			var/static/list/ops = list("control", "botlist", "summon", "patroloff", "patrolon", "ejectpai")
			if(mode == 54 && (params["op"] in ops))
				href = list("op" = params["op"])
				if(params["op"] == "control")
					href["bot"] = params["ref"]
		if("mule")
			var/static/list/mule_ops = list("unload", "destination", "setid", "report", "autoret", "autopick", "stop", "go", "home")
			if(mode == 54 && (params["op"] in mule_ops))
				href = list("mule" = params["op"])
	if(length(href))
		C.Topic(null, href)

/// The cartridge's "Newscaster Message", with the story typed in the window
/obj/item/pda/proc/pda_news_post(mob/living/U, text)
	var/obj/item/cartridge/C = cartridge
	var/message = pda_typed_message(U, text)
	if(!message)
		return
	var/datum/newscaster/feed_channel/current
	for(var/datum/newscaster/feed_channel/chan in GLOB.news_network.network_channels)
		if(chan.channel_name == C.current_channel)
			current = chan
	if(!current)
		return
	var/owner_name = id ? "[id.registered_name] ([id.assignment])" : "Unknown"
	if(current.locked && current.author != owner_name)
		mode = 99
		return
	GLOB.news_network.SubmitArticle(message, owner, C.current_channel)

#undef PDA_THREAD_KEEP
#undef PDA_LOG_KEEP
#undef PDA_MODE_CONVERSATIONS
#undef PDA_MODE_THREAD
#undef PDA_MODE_COMPOSE
