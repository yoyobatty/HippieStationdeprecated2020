/datum/config_entry/flag/mentors_mobname_only

/datum/config_entry/string/internet_address_to_use

/datum/config_entry/string/token_generator

/datum/config_entry/string/token_consumer

/datum/config_entry/string/tts_api

/datum/config_entry/flag/mentor_legacy_system	//Defines whether the server uses the legacy mentor system with mentors.txt or the SQL system
	protection = CONFIG_ENTRY_LOCKED

/datum/config_entry/flag/allow_vote_shuttlecall	// allow shuttle to be called via vote

/datum/config_entry/flag/enable_tts

/datum/config_entry/flag/enable_demo
	protection = CONFIG_ENTRY_LOCKED

// %I is input textfile
// %O is output wavefile
// %V is voice name
/datum/config_entry/string/tts_command
	config_entry_value = "mimic -f \"%I\" -o \"%O\" -voice \"%V\""
	protection = CONFIG_ENTRY_LOCKED

/datum/config_entry/string/tts_voice_male
	config_entry_value = "ap,kal,awb,kal16,rms"
	protection = CONFIG_ENTRY_LOCKED

/datum/config_entry/string/tts_voice_female
	config_entry_value = "slt"
	protection = CONFIG_ENTRY_LOCKED

/datum/config_entry/string/ipstack_api_key
	protection = CONFIG_ENTRY_HIDDEN | CONFIG_ENTRY_LOCKED

/datum/config_entry/number/bot_crew_target	// crew size to top up to with bot crew members, players counted first (bots_ai/bot_population.dm)
	config_entry_value = 0
	min_val = 0

/datum/config_entry/number/bot_crew_late_min	// fewest bots to arrive late on top of the crew at their posts when the round starts (bots_ai/bot_population.dm)
	config_entry_value = 5
	min_val = 0

/datum/config_entry/number/bot_crew_late_max	// most of them
	config_entry_value = 10
	min_val = 0

/datum/config_entry/number/bot_crew_traitors	// how many of the bot crew turn out to be traitors, once it has settled in
	config_entry_value = 0
	min_val = 0

/datum/config_entry/number/bot_crew_changelings	// how many of the bot crew turn out to be changelings, on top of the traitors
	config_entry_value = 0
	min_val = 0

/datum/config_entry/number/bot_crew_revolutionaries	// how many of the bot crew start a revolution, as head revolutionaries
	config_entry_value = 0
	min_val = 0

/datum/config_entry/number/bot_crew_silicons	// how many of the bot crew are silicons on top of the rest: one AI, then cyborgs (bots_ai/goals/silicon.dm)
	config_entry_value = 3
	min_val = 0

/datum/config_entry/number/bot_skill_mean	// the bot crew's skill on average, 0-100 (bots_ai/foundation/skill.dm): how well they get out of a fix, use what a room offers and read threats
	config_entry_value = 40
	min_val = 0
	max_val = 100

/datum/config_entry/number/bot_apex_share	// out of a hundred vigilante-minded bots (antag hunters, robust, paranoid), how many play at apex
	config_entry_value = 15
	min_val = 0
	max_val = 100

/datum/config_entry/number/bot_antags_apex	// 1: bot antagonists play at apex skill; 0: at what they rolled
	config_entry_value = 1
	min_val = 0
	max_val = 1

/datum/config_entry/string/player_log_ckey	// the one player whose actions get logged the way the bots' are (bots_ai/player_log.dm)
	protection = CONFIG_ENTRY_LOCKED

/datum/config_entry/flag/bot_telemetry	// write bots_ai's bot_telemetry.jsonl in a live round too (test runs always do, bots_ai/bot_telemetry.dm)

/datum/config_entry/number/bot_chaos	// how much trouble the bot crew gets up to: 0 none, 1 a normal round, 2 mayhem (bots_ai/bot_chaos.dm)
	config_entry_value = 1
	min_val = 0
	max_val = 2

/datum/config_entry/number/profile_duty	// with AUTO_PROFILE: the share of the time (%) the BYOND profiler is on; it adds ~255 ns to every proc call while it is (profiler.dm)
	config_entry_value = 10
	min_val = 1
	max_val = 100

/datum/config_entry/flag/byond_profiler	// with AUTO_PROFILE: BYOND's own profiler (world.Profile) even when hippie_prof.dll can do it (profiler.dm)
