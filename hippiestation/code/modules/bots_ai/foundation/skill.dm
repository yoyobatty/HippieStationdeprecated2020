// The skill dial (the user's ask, 2026-11-12/13: "super clever and combat smart bots"; rulings in the plan, bots_ai/SCENARIO_BACKLOG.md).
//
// Every bot has the same foundation: it knows the map, gets itself out of a fix, uses what a room offers against somebody, and reads what's
// about to hurt it. How WELL is this dial, 0 to 1:
//  - most of the crew roll 0.2-0.6 and play like ordinary players: they try the obvious, and otherwise ask for help or go round;
//  - powergamers and robust bots roll higher (BOT_SKILL_MID and up): the tricks a robust player knows;
//  - apex (BOT_SKILL_APEX and up) is every bot antagonist by default, and the odd vigilante: everything, set up on purpose.
// What below a dial setting does exactly what it did before the dial existed.
//
// World params: bot-skill=<0-1> puts every bot at that skill (Bot Gym and Bot Shift A/B); bot-antags-apex=0 leaves antagonists at what they
// rolled.

/// Out of a hundred, how many vigilante-minded bots (antag hunters, robust, paranoid) are apex
#define BOT_APEX_VIGILANTE_SHARE 15

/datum/bot_brain
	/// 0-1: how well it uses the foundation (above). Read through get_skill().
	var/skill = 0.4

/// bot-skill=: every bot at this skill, or null
GLOBAL_VAR_INIT(bot_skill_forced, isnull(world.params["bot-skill"]) ? null : clamp(text2num(world.params["bot-skill"]), 0, 1))
/// bot-antags-apex=0: antagonists keep the skill they rolled
GLOBAL_VAR_INIT(bot_antags_apex, world.params["bot-antags-apex"] != "0")

/// Rolled with the rest of its personality (roll_personality(), bot_personality.dm), after its playstyle.
/datum/bot_brain/proc/roll_skill(role)
	skill = rand(20, 60) / 100
	if(role in GLOB.security_positions)
		skill = max(skill, rand(40, 75) / 100) //trained for trouble
	switch(playstyle)
		if(BOT_STYLE_POWERGAMER, BOT_STYLE_ROBUST)
			skill = max(skill, rand(60, 85) / 100)
		if(BOT_STYLE_HUNTER, BOT_STYLE_PARANOID)
			skill = max(skill, rand(45, 75) / 100)
	if((playstyle in list(BOT_STYLE_HUNTER, BOT_STYLE_ROBUST, BOT_STYLE_PARANOID)) && prob(BOT_APEX_VIGILANTE_SHARE))
		skill = rand(90, 100) / 100

/// The skill it plays at now: the world's, if one's set; an antagonist's is apex; otherwise what it rolled.
/datum/bot_brain/proc/get_skill()
	if(!isnull(GLOB.bot_skill_forced))
		return GLOB.bot_skill_forced
	if(GLOB.bot_antags_apex && owner?.mind && length(owner.mind.antag_datums))
		return 1
	return skill

/datum/bot_brain/proc/skill_at_least(level)
	return get_skill() >= level

/datum/bot_brain/proc/is_apex()
	return get_skill() >= BOT_SKILL_APEX

#undef BOT_APEX_VIGILANTE_SHARE
