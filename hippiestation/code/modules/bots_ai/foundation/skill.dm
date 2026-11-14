// The skill dial (the user's ask, 2026-11-12/13: "super clever and combat smart bots"; rulings in the plan, bots_ai/SCENARIO_BACKLOG.md).
//
// Every bot has the same foundation: it knows the map, gets itself out of a fix, uses what a room offers against somebody, and reads what's
// about to hurt it. How WELL is this dial, 0 to 1:
//  - most of the crew roll round BOT_SKILL_MEAN (config, 40 by default, give or take 20) and play like ordinary players: they try the
//    obvious, and otherwise ask for help or go round;
//  - powergamers and robust bots roll higher (BOT_SKILL_MID and up): the tricks a robust player knows;
//  - apex (BOT_SKILL_APEX and up) is every bot antagonist by default (BOT_ANTAGS_APEX), and BOT_APEX_SHARE in a hundred vigilantes:
//    everything, set up on purpose.
// What below a dial setting does exactly what it did before the dial existed.
//
// Which skill a bot plays at, first that applies: the world's (bot-skill=<0-1>, or "Every bot" in the Set Bot Skill admin verb); one an
// admin set for that bot; apex for an antagonist (bot-antags-apex=0 or BOT_ANTAGS_APEX 0 turn that off); what it rolled.

/datum/bot_brain
	/// 0-1: what it rolled. Read through get_skill().
	var/skill = 0.4
	/// 0-1 set for this bot by an admin (Set Bot Skill), over the antagonist rule and what it rolled; null for none
	var/skill_override

/// bot-skill=, or "Every bot" in Set Bot Skill: every bot at this skill, or null
GLOBAL_VAR_INIT(bot_skill_forced, isnull(world.params["bot-skill"]) ? null : clamp(text2num(world.params["bot-skill"]), 0, 1))
/// Whether antagonists play at apex: bot-antags-apex= if it's given, else BOT_ANTAGS_APEX (read once, bot_antags_apex())
GLOBAL_VAR_INIT(bot_antags_apex, isnull(world.params["bot-antags-apex"]) ? null : (world.params["bot-antags-apex"] != "0"))

/proc/bot_antags_apex()
	if(isnull(GLOB.bot_antags_apex))
		GLOB.bot_antags_apex = CONFIG_GET(number/bot_antags_apex) != 0
	return GLOB.bot_antags_apex

/// Rolled with the rest of its personality (roll_personality(), bot_personality.dm), after its playstyle.
/datum/bot_brain/proc/roll_skill(role)
	var/mean = CONFIG_GET(number/bot_skill_mean)
	skill = clamp(rand(mean - 20, mean + 20), 0, 100) / 100
	// Trained for trouble: every officer plays like a robust player, and the Warden and the Head of Security a cut above, now and then
	// apex. Rolled 40-75 they were most of them below the mid tier, and fought the user like new players (round-17.21.40).
	if(role == "Head of Security" || role == "Warden")
		skill = max(skill, rand(70, 95) / 100)
	else if(role in GLOB.security_positions)
		skill = max(skill, rand(60, 85) / 100)
	switch(playstyle)
		if(BOT_STYLE_POWERGAMER, BOT_STYLE_ROBUST)
			skill = max(skill, rand(60, 85) / 100)
		if(BOT_STYLE_HUNTER, BOT_STYLE_PARANOID)
			skill = max(skill, rand(45, 75) / 100)
	if((playstyle in list(BOT_STYLE_HUNTER, BOT_STYLE_ROBUST, BOT_STYLE_PARANOID)) && prob(CONFIG_GET(number/bot_apex_share)))
		skill = rand(90, 100) / 100

/// The skill it plays at now (above).
/datum/bot_brain/proc/get_skill()
	if(!isnull(GLOB.bot_skill_forced))
		return GLOB.bot_skill_forced
	if(!isnull(skill_override))
		return skill_override
	if(owner?.mind && length(owner.mind.antag_datums) && bot_antags_apex())
		return 1
	return skill

/datum/bot_brain/proc/skill_at_least(level)
	return get_skill() >= level

/datum/bot_brain/proc/is_apex()
	return get_skill() >= BOT_SKILL_APEX

/client/proc/admin_set_bot_skill()
	set name = "Set Bot Skill"
	set category = "Fun"
	set desc = "How well bots get out of a fix, use what a room offers and read threats: one bot's, or every bot's. 0-100, apex from 90."

	if(!check_rights(R_FUN))
		return
	var/list/choices = list()
	choices["Every bot"] = "all"
	if(!isnull(GLOB.bot_skill_forced))
		choices["Every bot back to its own"] = "own"
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(B.owner)
			choices["[B.owner.real_name], [B.owner.mind?.assigned_role || "no job"] ([round(B.get_skill() * 100)])"] = B
	var/pick = tgui_input_list(usr, "Whose skill? Under 60 plays like most players, 60 and up like a robust one, 90 and up is apex.", "Bot Skill", choices)
	if(!pick || !choices[pick])
		return
	var/target = choices[pick]
	if(target == "own")
		GLOB.bot_skill_forced = null
		message_admins("[key_name_admin(usr)] put every bot back to its own skill.")
		log_admin("[key_name(usr)] put every bot back to its own skill.")
		return
	var/value = tgui_input_number(usr, "Skill, 0-100.", "Bot Skill", 50, 100, 0)
	if(isnull(value))
		return
	value = clamp(round(value), 0, 100)
	if(target == "all")
		GLOB.bot_skill_forced = value / 100
		message_admins("[key_name_admin(usr)] set every bot's skill to [value].")
		log_admin("[key_name(usr)] set every bot's skill to [value].")
		return
	var/datum/bot_brain/B = target
	if(QDELETED(B) || !B.owner)
		return
	B.skill_override = value / 100
	message_admins("[key_name_admin(usr)] set [key_name_admin(B.owner)]'s bot skill to [value].")
	log_admin("[key_name(usr)] set [key_name(B.owner)]'s bot skill to [value].")
