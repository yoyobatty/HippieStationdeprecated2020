// Research experiments: things science can only learn from the rest of the station. A handheld experiment scanner
// (tgui-next Experiments.js) records what it's pointed at against the station's experiments: slimes, crops, ores,
// organs, alien tissue, anomalies, exotic gases, robots, and big bombs logged by the research doppler array. A finished
// experiment pays research points and halves the cost of its related tech nodes (through the techweb's boosts), and a
// few reveal hidden nodes. Nothing is gated, so research done without them (or by bots) goes on as before. The user
// left the design to me, 2026-11-06.

/// The station's experiments, made the first time anything asks
/proc/science_experiments()
	var/static/list/experiments
	if(!experiments)
		experiments = list()
		for(var/path in subtypesof(/datum/science_experiment))
			experiments += new path
	return experiments

/datum/science_experiment
	var/name = "Experiment"
	var/desc = ""
	/// How many different things it needs
	var/required = 1
	/// What's been counted: key = what to call it
	var/list/done = list()
	var/completed = FALSE
	var/reward = 5000
	/// Tech nodes it halves the cost of
	var/list/discount_nodes = list()
	/// Hidden tech nodes it reveals
	var/list/reveal_nodes = list()

/// The key a scanned thing counts under, or null if it doesn't count; what to call it goes in name_out[1]
/datum/science_experiment/proc/key_for(atom/target, list/name_out)
	return null

/// Counts a scanned thing; TRUE if it was new
/datum/science_experiment/proc/record(atom/target, mob/user)
	if(completed)
		return FALSE
	var/list/name_out = list(null)
	var/key = key_for(target, name_out)
	if(!key || done[key])
		return FALSE
	done[key] = name_out[1] || "[target]"
	if(length(done) >= required)
		complete(user)
	return TRUE

/datum/science_experiment/proc/complete(mob/user)
	completed = TRUE
	var/datum/techweb/web = SSresearch.science_tech
	if(!web)
		return
	web.add_point_type(TECHWEB_POINT_TYPE_GENERIC, reward)
	for(var/id in discount_nodes)
		var/datum/techweb_node/node = SSresearch.techweb_node_by_id(id)
		if(!node)
			continue
		var/cost = node.research_costs[TECHWEB_POINT_TYPE_GENERIC]
		LAZYINITLIST(web.boosted_nodes[id])
		web.boosted_nodes[id][TECHWEB_POINT_TYPE_GENERIC] = max(web.boosted_nodes[id][TECHWEB_POINT_TYPE_GENERIC], round(cost / 2))
		web.update_node_status(node)
	for(var/id in reveal_nodes)
		var/datum/techweb_node/node = SSresearch.techweb_node_by_id(id)
		if(node)
			web.hidden_nodes -= id
			web.update_node_status(node)
	log_game("Experiment [name] completed[user ? " by [key_name(user)]" : ""]")

/datum/science_experiment/proc/node_names()
	. = list()
	for(var/id in discount_nodes + reveal_nodes)
		var/datum/techweb_node/node = SSresearch.techweb_node_by_id(id)
		if(node)
			. += node.display_name

/datum/science_experiment/slimes
	name = "Slime Survey"
	desc = "Scan living slimes of different colours."
	required = 4
	reward = 7500
	discount_nodes = list("bio_process", "adv_biotech")

/datum/science_experiment/slimes/key_for(atom/target, list/name_out)
	var/mob/living/simple_animal/slime/S = target
	if(!istype(S) || S.stat == DEAD)
		return null
	name_out[1] = "[S.colour] slime"
	return S.colour

/datum/science_experiment/botany
	name = "Botanical Survey"
	desc = "Scan different crops of potency 30 or more."
	required = 3
	reward = 7500
	discount_nodes = list("botany")

/datum/science_experiment/botany/key_for(atom/target, list/name_out)
	var/obj/item/reagent_containers/food/snacks/grown/G = target
	if(!istype(G) || !G.seed || G.seed.potency < 30)
		return null
	name_out[1] = G.seed.plantname
	return "[G.seed.type]"

/datum/science_experiment/geology
	name = "Geological Survey"
	desc = "Scan different kinds of ore."
	required = 5
	reward = 7500
	discount_nodes = list("basic_mining", "adv_mining")

/datum/science_experiment/geology/key_for(atom/target, list/name_out)
	if(!istype(target, /obj/item/stack/ore))
		return null
	name_out[1] = "[initial(target.name)]"
	return "[target.type]"

/datum/science_experiment/anatomy
	name = "Comparative Anatomy"
	desc = "Scan different organs: heart, lungs, liver, stomach, eyes, tongue."
	required = 4
	reward = 7500
	discount_nodes = list("adv_surgery", "cyber_organs")

/datum/science_experiment/anatomy/key_for(atom/target, list/name_out)
	var/obj/item/organ/O = target
	if(!istype(O) || istype(O, /obj/item/organ/alien) || !O.slot)
		return null
	if(!(O.slot in list(ORGAN_SLOT_HEART, ORGAN_SLOT_LUNGS, ORGAN_SLOT_LIVER, ORGAN_SLOT_STOMACH, ORGAN_SLOT_EYES, ORGAN_SLOT_TONGUE)))
		return null
	name_out[1] = O.slot
	return O.slot

/datum/science_experiment/xenoanatomy
	name = "Xenoanatomy"
	desc = "Scan an alien organ."
	required = 1
	reward = 15000
	discount_nodes = list("alien_surgery")
	reveal_nodes = list("alien_bio")

/datum/science_experiment/xenoanatomy/key_for(atom/target, list/name_out)
	if(!istype(target, /obj/item/organ/alien))
		return null
	name_out[1] = "[target]"
	return "alien"

/datum/science_experiment/anomalous
	name = "Anomalous Matter"
	desc = "Scan an anomaly core or a bluespace crystal."
	required = 1
	reward = 10000
	discount_nodes = list("anomaly_research", "bluespace_travel")

/datum/science_experiment/anomalous/key_for(atom/target, list/name_out)
	if(istype(target, /obj/item/assembly/signaler/anomaly) || istype(target, /obj/item/stack/ore/bluespace_crystal))
		name_out[1] = "[target]"
		return "[target.type]"
	return null

/datum/science_experiment/gases
	name = "Exotic Gases"
	desc = "Scan tanks or canisters holding different exotic gases: tritium, BZ, nitryl, stimulum, pluoxium, hyper-noblium."
	required = 2
	reward = 10000
	discount_nodes = list("adv_plasma")

/datum/science_experiment/gases/key_for(atom/target, list/name_out)
	var/datum/gas_mixture/air
	if(istype(target, /obj/item/tank))
		var/obj/item/tank/T = target
		air = T.air_contents
	else if(istype(target, /obj/machinery/portable_atmospherics))
		var/obj/machinery/portable_atmospherics/P = target
		air = P.air_contents
	if(!air)
		return null
	for(var/gas in list(/datum/gas/tritium, /datum/gas/bz, /datum/gas/nitryl, /datum/gas/stimulum, /datum/gas/pluoxium, /datum/gas/hypernoblium))
		if(air.moles[gas] >= 1 && !done["[gas]"])
			name_out[1] = GAS_META[META_GAS_NAME][gas]
			return "[gas]"
	return null

/datum/science_experiment/robotics
	name = "Robotics Survey"
	desc = "Scan a cyborg and an exosuit."
	required = 2
	reward = 7500
	discount_nodes = list("adv_robotics", "adv_mecha")

/datum/science_experiment/robotics/key_for(atom/target, list/name_out)
	if(iscyborg(target))
		name_out[1] = "cyborg"
		return "cyborg"
	if(istype(target, /obj/mecha))
		name_out[1] = "exosuit"
		return "mech"
	return null

/datum/science_experiment/explosives
	name = "Explosive Yield"
	desc = "Log a blast of light radius 20 or more on the research doppler array."
	required = 1
	reward = 5000
	discount_nodes = list("explosive_weapons")

/obj/machinery/doppler_array/research/sense_explosion(datum/source, turf/epicenter, devastation_range, heavy_impact_range, light_impact_range, \
		took, orig_dev_range, orig_heavy_range, orig_light_range)
	. = ..()
	if(!. || orig_light_range < 20)
		return
	for(var/datum/science_experiment/explosives/E in science_experiments())
		if(!E.completed)
			E.done["blast"] = "radius [orig_light_range] blast"
			E.complete(null)

// The scanner

/obj/item/experi_scanner
	name = "experiment scanner"
	desc = "Records slimes, crops, ores, organs, anomalies, gases and robots for the station's research experiments."
	icon = 'icons/obj/device.dmi'
	icon_state = "adv_spectrometer"
	item_state = "analyzer"
	lefthand_file = 'icons/mob/inhands/equipment/tools_lefthand.dmi'
	righthand_file = 'icons/mob/inhands/equipment/tools_righthand.dmi'
	w_class = WEIGHT_CLASS_SMALL
	flags_1 = CONDUCT_1
	slot_flags = ITEM_SLOT_BELT
	materials = list(MAT_METAL = 300, MAT_GLASS = 200)

/obj/item/experi_scanner/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	. = ..()
	if(!proximity_flag && !isliving(target)) // living things can be scanned from a step away, like a health analyzer
		return
	if(!proximity_flag && get_dist(user, target) > 1)
		return
	var/list/counted = list()
	var/list/finished = list()
	for(var/datum/science_experiment/E in science_experiments())
		var/was = E.completed
		if(E.record(target, user))
			counted += E.name
			if(!was && E.completed)
				finished += E
	if(!counted.len)
		to_chat(user, "<span class='notice'>[src] finds nothing new in [target].</span>")
		return
	playsound(src, 'sound/machines/ping.ogg', 20, TRUE)
	to_chat(user, "<span class='notice'>[src] records [target] for [counted.Join(", ")].</span>")
	for(var/datum/science_experiment/E in finished)
		say("Experiment complete: [E.name]. [E.reward] research points.")

/obj/item/experi_scanner/attack_self(mob/user)
	ui_interact(user)

/obj/item/experi_scanner/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
									datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "experiment_scanner", name, 480, 560, master_ui, state)
		ui.open()

/// The experiments as the windows show them
/proc/science_experiments_data()
	var/list/out = list()
	for(var/datum/science_experiment/E in science_experiments())
		var/list/done_names = list()
		for(var/key in E.done)
			done_names += E.done[key]
		out += list(list(
			"name" = E.name,
			"desc" = E.desc,
			"required" = E.required,
			"count" = length(E.done),
			"done" = done_names,
			"completed" = E.completed,
			"reward" = E.reward,
			"nodes" = E.node_names(),
		))
	return out

/obj/item/experi_scanner/ui_data(mob/user)
	return list("experiments" = science_experiments_data())

// Printable at any protolathe from the start, and scientists carry one

/datum/design/experi_scanner
	name = "Experiment Scanner"
	desc = "Records things for the station's research experiments."
	id = "experi_scanner"
	build_type = PROTOLATHE
	materials = list(MAT_METAL = 300, MAT_GLASS = 200)
	build_path = /obj/item/experi_scanner
	category = list("Tool Designs")
	departmental_flags = DEPARTMENTAL_FLAG_SCIENCE

/datum/techweb_node/base/New()
	. = ..()
	design_ids += "experi_scanner"

/datum/outfit/job/scientist
	backpack_contents = list(/obj/item/experi_scanner = 1)
