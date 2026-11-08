// hippie -- the pAI's old HTML windows in tgui: the pAI OS (interfaces/PaiOs.js), a ghost's pAI personality (PaiRecruit), and the
// personalities on offer, now listed in the pAI card's own window (PaiCard in MechMedicalPai.js). Every button goes through what the
// old page's link did: the pAI's Topic() (software=..., sub=..., and the rest), SSpai.Topic() for a download, and the same
// sanitizing for the personality's fields. paiInterface() opens the window wherever the old code redrew the page (Topic(), the
// door jack's progress, the HUD's software button).

// ---------------------------------------------------------------------------------------------
// The pAI OS
// ---------------------------------------------------------------------------------------------

/mob/living/silicon/pai
	var/datum/pai_os_window/os_window

/mob/living/silicon/pai/paiInterface()
	set_machine(src)
	if(!os_window)
		os_window = new(src)
	os_window.ui_interact(src)
	SStgui.update_uis(os_window)

/mob/living/silicon/pai/Destroy()
	QDEL_NULL(os_window)
	return ..()

/datum/pai_os_window
	var/mob/living/silicon/pai/pai

/datum/pai_os_window/New(mob/living/silicon/pai/owner)
	pai = owner

/datum/pai_os_window/Destroy()
	SStgui.close_uis(src)
	pai = null
	return ..()

/datum/pai_os_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	if(user != pai)
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "pai_os", "pAI OS", 680, 520, master_ui, state)
		ui.open()

/datum/pai_os_window/ui_status(mob/user, datum/ui_state/state)
	return user == pai ? UI_INTERACTIVE : UI_CLOSE

/datum/pai_os_window/ui_static_data(mob/user)
	var/list/shop = list()
	for(var/s in pai.available_software)
		shop += list(list("name" = s, "cost" = pai.available_software[s]))
	return list("shop" = shop, "faces" = list("Happy", "Cat", "Extremely Happy", "Face", "Laugh", "Off", "Sad", "Angry", "What"))

/datum/pai_os_window/ui_data(mob/user)
	. = list()
	var/mob/living/silicon/pai/P = pai
	.["dead"] = P.stat == DEAD
	.["screen"] = P.screen || "main"
	.["subscreen"] = P.subscreen || 0
	.["ram"] = P.ram
	.["software"] = P.software.Copy()
	.["notice"] = P.temp
	.["sec_hud"] = !!P.secHUD
	.["med_hud"] = !!P.medHUD
	.["encrypt"] = !!P.encryptmod
	var/datum/language_holder/H = P.get_language_holder()
	.["translator"] = !!H?.omnitongue
	.["name"] = P.name
	switch(P.screen)
		if("directives")
			.["master"] = P.master
			.["master_dna"] = P.master_dna
			.["zeroth"] = P.laws?.zeroth
			var/list/supplied = list()
			for(var/law in P.laws?.supplied)
				if(length(law))
					supplied += law
			.["supplied"] = supplied
			.["carried"] = iscarbon(P.card?.loc)
		if("pdamessage")
			var/obj/item/pda/PDA = P.aiPDA
			if(PDA)
				.["pda_on"] = !PDA.toff
				.["ringer"] = !PDA.silent
				var/list/pdas = list()
				if(!PDA.toff)
					for(var/obj/item/pda/other in sortNames(get_viewable_pdas()))
						if(other != PDA)
							pdas += list(list("name" = "[other]", "ref" = REF(other)))
				.["pdas"] = pdas
				.["log"] = pai_pda_log(PDA)
		if("manifest")
			var/list/manifest = GLOB.crew_manifest_window.ui_data(user)
			.["departments"] = manifest["departments"]
		if("medicalrecord", "securityrecord")
			var/medical = P.screen == "medicalrecord"
			var/list/records = list()
			for(var/datum/data/record/R in sortRecord(GLOB.data_core.general))
				records += list(list("id" = R.fields["id"], "name" = R.fields["name"], "rank" = R.fields["rank"]))
			.["records"] = records
			var/datum/data/record/R1 = medical ? P.medicalActive1 : P.securityActive1
			var/datum/data/record/R2 = medical ? P.medicalActive2 : P.securityActive2
			if(P.subscreen == 1 && (R1 in GLOB.data_core.general))
				var/list/general = list()
				for(var/field in list("name", "id", "gender", "age", "rank", "fingerprint", "p_stat", "m_stat"))
					general[field] = "[R1.fields[field]]"
				.["record"] = general
				var/list/detail = list()
				var/list/fields = medical ? list("blood_type" = "Blood type", "b_dna" = "DNA", "mi_dis" = "Minor disabilities", "mi_dis_d" = "Details", \
					"ma_dis" = "Major disabilities", "ma_dis_d" = "Details", "alg" = "Allergies", "alg_d" = "Details", "cdi" = "Current diseases", \
					"cdi_d" = "Details", "notes" = "Important notes") \
					: list("criminal" = "Criminal status", "mi_crim" = "Minor crimes", "mi_crim_d" = "Details", "ma_crim" = "Major crimes", \
					"ma_crim_d" = "Details", "notes" = "Important notes")
				if(R2 in (medical ? GLOB.data_core.medical : GLOB.data_core.security))
					for(var/field in fields)
						detail += list(list("label" = fields[field], "value" = comm_plain_text("[R2.fields[field]]")))
				.["detail"] = detail
		if("atmosensor")
			var/turf/T = get_turf(P.loc)
			var/datum/gas_mixture/environment = T?.return_air()
			if(environment)
				.["pressure"] = round(environment.return_pressure(), 0.1)
				.["temperature"] = round(environment.temperature - T0C)
				var/total = environment.total_moles()
				var/list/gases = list()
				if(total)
					for(var/id, value in environment.moles)
						var/level = value / total
						if(level > 0.01)
							gases += list(list("name" = GLOB.meta_gas_info[META_GAS_NAME][id], "percent" = round(level * 100)))
				.["gases"] = gases
		if("doorjack")
			.["cable"] = !P.cable ? "retracted" : (!P.cable.machine ? "extended" : "connected")
			.["door"] = istype(P.cable?.machine, /obj/machinery/door)
			.["hacking"] = !!P.hackdoor
			.["progress"] = P.hackprogress
		if("signaller")
			.["frequency"] = P.signaler ? format_frequency(P.signaler.frequency) : null
			.["code"] = P.signaler?.code
		if("hostscan")
			.["scan_chems"] = !!P.hostscan?.scanmode
			.["verbose"] = !!P.hostscan?.mode
		if("loudness")
			.["instrument"] = P.internal_instrument ? "[P.internal_instrument.name]" : null

/// The PDA's message log, newest last (pda_tgui.dm keeps it), for the messenger screens
/proc/pai_pda_log(obj/item/pda/PDA)
	var/list/out = list()
	for(var/list/entry in PDA.pda_log)
		out += list(list("out" = entry["out"], "name" = entry["name"], "job" = entry["job"], "text" = entry["text"], "time" = entry["time"]))
	return out

/datum/pai_os_window/ui_act(action, list/params)
	if(..())
		return
	var/mob/living/silicon/pai/P = pai
	if(usr != P)
		return
	P.temp = null
	switch(action)
		if("screen")
			var/static/list/screens = list("main", "directives", "pdamessage", "buy", "manifest", "medicalrecord", "securityrecord", \
				"encryptionkeys", "translator", "atmosensor", "securityhud", "medicalhud", "doorjack", "signaller", "loudness", "hostscan")
			var/screen = params["screen"]
			if(screen in screens)
				P.Topic(null, list("software" = screen, "sub" = "0"))
		if("radio", "news", "camzoom")
			P.Topic(null, list("software" = action, "sub" = "0"))
		if("face")
			var/index = text2num(params["index"])
			if(index >= 1 && index <= 9 && P.card)
				P.card.setEmotion(index)
		if("buy")
			P.Topic(null, list("software" = "buy", "sub" = "1", "buy" = "[params["name"]]"))
		if("getdna")
			P.Topic(null, list("software" = "directive", "getdna" = "1"))
		if("pda_toggle")
			P.Topic(null, list("software" = "pdamessage", "toggler" = "1"))
		if("pda_ringer")
			P.Topic(null, list("software" = "pdamessage", "ringer" = "1"))
		if("pda_send")
			P.Topic(null, list("software" = "pdamessage", "target" = params["ref"]))
		if("record")
			var/medical = P.screen == "medicalrecord"
			P.Topic(null, list("software" = P.screen, "sub" = "1", "[medical ? "med_rec" : "sec_rec"]" = params["id"]))
		if("record_back")
			P.Topic(null, list("software" = P.screen, "sub" = "0"))
		if("toggle")
			// The HUDs, the encryption ports and the translator: switches on the screen they're on
			if(P.screen in list("securityhud", "medicalhud", "encryptionkeys", "translator", "hostscan"))
				P.Topic(null, list("software" = P.screen, "sub" = "0", "toggle" = "1"))
		if("verbosity")
			P.Topic(null, list("software" = "hostscan", "sub" = "0", "toggle2" = "1"))
		if("cable")
			P.Topic(null, list("software" = "doorjack", "sub" = "0", "cable" = "1"))
		if("jack")
			P.Topic(null, list("software" = "doorjack", "sub" = "0", "jack" = "1"))
		if("jack_cancel")
			P.Topic(null, list("software" = "doorjack", "sub" = "0", "cancel" = "1"))
		if("freq")
			P.Topic(null, list("software" = "signaller", "freq" = "[text2num(params["by"])]"))
		if("code")
			P.Topic(null, list("software" = "signaller", "code" = "[text2num(params["by"])]"))
		if("signal")
			P.Topic(null, list("software" = "signaller", "send" = "1"))
		if("synth")
			P.Topic(null, list("software" = "loudness", "sub" = "1"))
		if("synth_type")
			P.Topic(null, list("software" = "loudness", "sub" = "2"))
	return TRUE

// ---------------------------------------------------------------------------------------------
// A silicon's PDA message log (the AI's and pAI's HUD button)
// ---------------------------------------------------------------------------------------------

/mob/living/silicon
	var/datum/silicon_pda_log_window/pda_log_window

/mob/living/silicon/cmd_show_message_log(mob/user)
	if(incapacitated())
		return
	if(isnull(aiPDA))
		to_chat(user, "<span class='warning'>You do not have a PDA! You should make an issue report about this.</span>")
		return
	if(!pda_log_window)
		pda_log_window = new(src)
	pda_log_window.ui_interact(user)

/datum/silicon_pda_log_window
	var/datum/weakref/owner_ref

/datum/silicon_pda_log_window/New(mob/living/silicon/owner)
	owner_ref = WEAKREF(owner)

/datum/silicon_pda_log_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	if(user != owner_ref?.resolve())
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "silicon_pda_log", "PDA Message Log", 440, 480, master_ui, state)
		ui.open()

/datum/silicon_pda_log_window/ui_data(mob/user)
	var/mob/living/silicon/S = owner_ref?.resolve()
	. = list()
	if(S?.aiPDA)
		.["log"] = pai_pda_log(S.aiPDA)
		.["pda_on"] = !S.aiPDA.toff
		.["ringer"] = !S.aiPDA.silent

/datum/silicon_pda_log_window/ui_act(action, list/params)
	if(..())
		return
	var/mob/living/silicon/S = owner_ref?.resolve()
	if(!S || usr != S || !S.aiPDA || S.stat == DEAD)
		return
	switch(action)
		if("send")
			S.cmd_send_pdamesg(S)
		if("pda_toggle")
			S.aiPDA.toff = !S.aiPDA.toff
		if("pda_ringer")
			S.aiPDA.silent = !S.aiPDA.silent
	return TRUE

// ---------------------------------------------------------------------------------------------
// A ghost's pAI personality
// ---------------------------------------------------------------------------------------------

/datum/controller/subsystem/pai/recruitWindow(mob/M)
	var/datum/paiCandidate/candidate
	for(var/datum/paiCandidate/c in candidates)
		if(c.key == M.key)
			candidate = c
	if(!candidate)
		candidate = new /datum/paiCandidate()
		candidate.key = M.key
		candidates.Add(candidate)
	candidate.ui_interact(M)

/datum/paiCandidate/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.observer_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "pai_recruit", "pAI Personality", 480, 560, master_ui, state)
		ui.open()

/datum/paiCandidate/ui_status(mob/user, datum/ui_state/state)
	if(!isobserver(user) || user.key != key)
		return UI_CLOSE
	return UI_INTERACTIVE

/datum/paiCandidate/ui_data(mob/user)
	return list("name" = name, "description" = description, "role" = role, "comments" = comments, "ready" = !!ready)

/datum/paiCandidate/ui_act(action, list/params)
	if(..())
		return
	if(usr.key != key)
		return
	switch(action)
		if("set")
			// The old Edit prompts' cleaning, on the text from the window
			var/text = "[params["value"]]"
			switch(params["field"])
				if("name")
					var/t = sanitize_name(stripped_input_text(text, MAX_NAME_LEN))
					if(t)
						name = t
				if("description")
					var/t = stripped_input_text(text, MAX_MESSAGE_LEN, TRUE)
					if(t)
						description = t
				if("role")
					var/t = stripped_input_text(text, MAX_MESSAGE_LEN)
					if(t)
						role = t
				if("comments")
					var/t = stripped_input_text(text, MAX_MESSAGE_LEN, TRUE)
					if(t)
						comments = t
		if("save", "load", "submit")
			SSpai.Topic(null, list("new" = "1", "candidate" = REF(src), "option" = action))
			if(action == "submit")
				to_chat(usr, "<span class='notice'>Your personality is on offer. Any empty pAI card can download you now.</span>")
	return TRUE

// ---------------------------------------------------------------------------------------------
// The personalities on offer, in the pAI card's window
// ---------------------------------------------------------------------------------------------

/obj/item/paicard
	/// Asked for a personality (the ghosts have been told): its window lists those on offer
	var/pai_searching = FALSE

/datum/controller/subsystem/pai/findPAI(obj/item/paicard/p, mob/user)
	if(!ghost_spam)
		ghost_spam = TRUE
		for(var/mob/dead/observer/G in GLOB.player_list)
			if(!G.key || !G.client)
				continue
			if(!(ROLE_PAI in G.client.prefs.be_special))
				continue
			to_chat(G, "<span class='ghostalert'>[user] is requesting a pAI personality! Use the pAI button to submit yourself as one.</span>")
		addtimer(CALLBACK(src, PROC_REF(spam_again)), spam_delay)
	p.pai_searching = TRUE
	p.ui_interact(user)
	SStgui.update_uis(p)

/obj/item/paicard/ui_data(mob/user)
	. = ..()
	if(pai)
		return
	.["searching"] = pai_searching
	var/list/offered = list()
	if(pai_searching)
		for(var/datum/paiCandidate/c in SSpai.candidates)
			if(SSpai.check_ready(c))
				offered += list(list("ref" = REF(c), "name" = c.name, "description" = c.description, "role" = c.role, "comments" = c.comments))
	.["candidates"] = offered

/obj/item/paicard/ui_act(action, list/params)
	if(action == "download")
		if(pai || usr.stat || !usr.canUseTopic(src, BE_CLOSE))
			return
		SSpai.Topic(null, list("download" = "1", "candidate" = params["ref"], "device" = REF(src)))
		if(pai)
			pai_searching = FALSE
		return TRUE
	return ..()
