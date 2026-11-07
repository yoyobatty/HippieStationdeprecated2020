// The sentient disease's Adaptation Menu in tgui (interfaces/DiseaseMenu.js): the disease's stats and cure, its points and
// cooldown, every adaptation as a card (bought, buyable, locked) with its details, and the hosts to follow. Buying, refunding
// and following still go through the disease's Topic(), which ends by calling adaptation_menu(): that brings the window up to date.

/mob/camera/disease/adaptation_menu()
	if(!disease_template)
		return
	ui_interact(src)
	browser_open = TRUE

/mob/camera/disease/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	if(user != src)
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "disease_menu", "Adaptation Menu", 900, 640, master_ui, state)
		ui.open()

/mob/camera/disease/ui_close(mob/user)
	browser_open = FALSE

/// Each adaptation's fixed facts, once: its symptoms' stats and threshold notes, its words without their HTML
GLOBAL_LIST_EMPTY(disease_ability_facts)

/proc/disease_ability_facts(datum/disease_ability/A)
	var/list/facts = GLOB.disease_ability_facts[A.type]
	if(facts)
		return facts
	var/static/regex/tags = regex("<\[^>]*>", "g")
	var/list/stats = list("resistance" = 0, "stealth" = 0, "stage_speed" = 0, "transmittable" = 0)
	for(var/T in A.symptoms)
		var/datum/symptom/S = T
		stats["resistance"] += initial(S.resistance)
		stats["stealth"] += initial(S.stealth)
		stats["stage_speed"] += initial(S.stage_speed)
		stats["transmittable"] += initial(S.transmittable)
	var/list/thresholds = list()
	for(var/entry in A.threshold_block)
		thresholds += list(list("name" = html_decode(tags.Replace("[entry]", "")), "desc" = html_decode(tags.Replace("[A.threshold_block[entry]]", ""))))
	facts = list(
		"long_desc" = html_decode(tags.Replace(replacetext(A.long_desc, "<br>", " "), "")),
		"short_desc" = html_decode(tags.Replace(A.short_desc, "")),
		"symptom" = length(A.symptoms) ? TRUE : FALSE,
		"stats" = length(A.symptoms) ? stats : null,
		"thresholds" = thresholds,
	)
	GLOB.disease_ability_facts[A.type] = facts
	return facts

/mob/camera/disease/ui_data(mob/user)
	var/list/data = list()
	var/datum/disease/advance/sentient_disease/DT = disease_template
	data["name"] = DT ? DT.name : name
	data["stats"] = DT ? list(
		"resistance" = DT.totalResistance(),
		"stealth" = DT.totalStealth(),
		"stage_speed" = DT.totalStageSpeed(),
		"transmittable" = DT.totalTransmittable()) : null
	data["cure"] = DT?.cure_text
	data["points"] = points
	data["total_points"] = total_points
	data["cooldown"] = max(0, round((next_adaptation_time - world.time) / 10))
	var/list/abilities = list()
	for(var/datum/disease_ability/A as anything in GLOB.disease_ability_singletons)
		var/list/facts = disease_ability_facts(A)
		var/bought = purchased_abilities[A] ? TRUE : FALSE
		abilities += list(list(
			"ref" = REF(A),
			"name" = A.name,
			"cost" = A.cost,
			"unlock" = A.required_total_points,
			"category" = A.category,
			"short_desc" = facts["short_desc"],
			"long_desc" = facts["long_desc"],
			"stats" = facts["stats"],
			"thresholds" = facts["thresholds"],
			"bought" = bought,
			"can_buy" = bought ? FALSE : A.CanBuy(src),
			"can_refund" = bought ? A.CanRefund(src) : FALSE,
		))
	data["abilities"] = abilities
	var/list/host_list = list()
	for(var/mob/living/L as anything in hosts)
		host_list += list(list("ref" = REF(L), "name" = L.real_name, "following" = (L == following_host)))
	data["hosts"] = host_list
	return data

/mob/camera/disease/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("buy")
			Topic(null, list("buy_ability" = params["ref"]))
		if("refund")
			Topic(null, list("refund_ability" = params["ref"]))
		if("follow")
			Topic(null, list("follow_instance" = params["ref"]))
		else
			return
	return TRUE
