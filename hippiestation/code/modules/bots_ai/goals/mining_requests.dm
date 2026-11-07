// Mining asked for something: "Mining, we need materials", "Mining, science needs silver". The user asked both over the radio in their
// CE round (2026-11-05) and nobody answered: there was a call for Science and for Cargo, and none for the miners. A miner hears it,
// says what it'll do (or that the silo has plenty already), and digs that first: the same list the lathes add to when they run short
// (GLOB.bot_wanted_minerals, goals/mining.dm), which the miners' scanner sorts its seams by.

/// What people call each material, to the material.
GLOBAL_LIST_INIT(bot_material_words, list(
	"silver" = MAT_SILVER, "gold" = MAT_GOLD, "diamond" = MAT_DIAMOND, "diamonds" = MAT_DIAMOND, "uranium" = MAT_URANIUM,
	"plasma" = MAT_PLASMA, "titanium" = MAT_TITANIUM, "metal" = MAT_METAL, "iron" = MAT_METAL, "glass" = MAT_GLASS, "sand" = MAT_GLASS,
	"bluespace" = MAT_BLUESPACE, "bananium" = MAT_BANANIUM,
))
/// Asking for anything at all.
GLOBAL_LIST_INIT(bot_any_material_words, list("materials", "mats", "minerals", "ore", "ores", "sheets", "resources"))

/datum/bot_request_kind/mining
	name = "mining"
	jobs = list("Shaft Miner")
	role_words = list("mining", "miner", "miners")
	walks_there = FALSE
	needs_place = FALSE
	precedence = 9
	doing = "digging what somebody asked for"

/datum/bot_request_kind/mining/matches(lower_msg, named, turf/near)
	if(!bot_text_has_any(lower_msg, GLOB.bot_any_material_words) && !length(bot_materials_named(lower_msg)))
		return FALSE
	return named || bot_text_has_any(lower_msg, role_words)

/// The materials a line asks for by name: material -> TRUE.
/proc/bot_materials_named(lower_msg)
	. = list()
	for(var/word in GLOB.bot_material_words)
		if(bot_text_has_any(lower_msg, list(word)))
			.[GLOB.bot_material_words[word]] = TRUE

/datum/bot_request_kind/mining/read_details(datum/bot_request/R, lower_msg)
	var/list/mats = bot_materials_named(lower_msg)
	if(!length(mats)) //just "materials": what the lathes go through first
		mats = list(MAT_METAL = TRUE, MAT_GLASS = TRUE, MAT_SILVER = TRUE, MAT_GOLD = TRUE)
	R.detail = mats

/datum/bot_request_kind/mining/ack_for(datum/bot_brain/bot, datum/bot_request/R)
	var/list/short = bot.materials_short_in_silo(R.detail)
	if(!length(short))
		return pick("There's plenty in the silo already, check the lathe.", "Silo's got loads of that, it should print.", "We're stocked on that, the lathe can use it.")
	var/names = english_list(bot.material_names(short))
	if(bot.on_lavaland())
		return pick("On it, I'll dig [names] first.", "I'm on the rock, I'll look for [names].", "Got it, [names] next.")
	return pick("Heading down, I'll get you [names].", "Will do, [names] when I'm down there.", "Sure, I'll bring up [names].")

/datum/bot_request_kind/mining/attend(datum/bot_brain/bot, datum/bot_request/R)
	var/list/short = bot.materials_short_in_silo(R.detail)
	for(var/mat in short)
		GLOB.bot_wanted_minerals[mat] = world.time
	if(length(short))
		bot_log(bot, "asked to dig [english_list(bot.material_names(short))] - first on the scanner now")

/// Of these, the ones the silo's short of (goals/mining.dm's measure of enough).
/datum/bot_brain/proc/materials_short_in_silo(list/mats)
	. = list()
	var/datum/component/material_container/stores = GLOB.ore_silo_default?.GetComponent(/datum/component/material_container)
	for(var/mat in mats)
		if(!stores || stores.amount(mat) < 30 * MINERAL_MATERIAL_AMOUNT)
			. += mat

/datum/bot_brain/proc/material_names(list/mats)
	. = list()
	for(var/mat in mats)
		. += lowertext(CallMaterialName(mat))
