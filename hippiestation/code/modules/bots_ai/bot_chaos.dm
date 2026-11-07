// Chaos - how much trouble the crew gets up to by itself, and something to stir it up. Set with BOT_CHAOS in
// hippiestation_config.txt: 0 nothing, 1 a normal round, 2 mayhem. Headless test runs have it off, so what they measure
// stays comparable, unless a run asks for it with bot-chaos=<level>.
//
// Every few minutes the director picks something to go wrong, from what's actually happening in the round: two people in
// a room fall out, a fight starts in a crowded bar, someone gets their pocket picked, the assistants riot. Nobody is
// told what to do beyond that: the fight goes the way fights go (bot_reflexes.dm, bot_fighting.dm, bot_witness.dm).

/// The gap between incidents at chaos 1. Halved at chaos 2.
#define BOT_CHAOS_GAP_MIN (3 MINUTES)
#define BOT_CHAOS_GAP_MAX (7 MINUTES)
/// How long into the round before anything's arranged.
#define BOT_CHAOS_SETTLE_IN (6 MINUTES)
/// How long somebody is sore enough at somebody for a quarrel to go on being a quarrel.
#define BOT_QUARREL_LENGTH (40 SECONDS)

/// How much trouble the crew gets up to, this round.
GLOBAL_VAR_INIT(bot_chaos_level, 0)
GLOBAL_DATUM_INIT(bot_chaos, /datum/bot_chaos, new)

GLOBAL_LIST_INIT(bot_quarrel_openers, list(
	"What did you just say to me?",
	"You've been at my stuff again, haven't you?",
	"Who do you think you're looking at?",
	"I know it was you.",
	"You owe me credits.",
	"Say that again, I dare you.",
	"You're the reason this station's a mess.",
	"That's my seat.",
))

GLOBAL_LIST_INIT(bot_quarrel_comebacks, list(
	"You want to do this? Right here?",
	"Make me.",
	"Oh, get over yourself.",
	"Back off, I mean it.",
	"You and whose army?",
	"I don't have time for you.",
))

/proc/bot_read_chaos_level()
	if(!isnull(world.params["bot-chaos"]))
		return clamp(text2num(world.params["bot-chaos"]), 0, 2)
	if((BOT_GYM_PARAMETER in world.params) || (BOT_SHIFT_PARAMETER in world.params))
		return 0
	return CONFIG_GET(number/bot_chaos)

/datum/bot_chaos
	var/running = FALSE
	/// What's been arranged: incident -> how many times. What's been done about it: bot_tally() -> how many times. For the Bot Shift report.
	var/list/incidents = list()
	var/list/tallies = list()

/proc/bot_tally(what)
	GLOB.bot_chaos.tallies[what]++

/datum/bot_chaos/proc/report()
	var/list/parts = list()
	for(var/incident in incidents)
		parts += "[incident] x[incidents[incident]]"
	var/list/done = list()
	for(var/what in tallies)
		done += "[what] [tallies[what]]"
	var/smashed = 0
	var/looted = 0
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		smashed += B.things_smashed
		looted += B.things_looted
	return "level [GLOB.bot_chaos_level], [length(parts) ? english_list(parts) : "nothing arranged"]; [smashed] things smashed, [looted] looted[length(done) ? "; [jointext(done, ", ")]" : ""]"

/datum/bot_chaos/proc/round_started()
	GLOB.bot_chaos_level = bot_read_chaos_level()
	if(GLOB.bot_chaos_level >= 1 && !running)
		running = TRUE
		addtimer(CALLBACK(src, PROC_REF(next_incident)), BOT_CHAOS_SETTLE_IN + rand(0, 2 MINUTES))

/datum/bot_chaos/proc/next_incident()
	if(!SSticker.IsRoundInProgress() || !EMERGENCY_IDLE_OR_RECALLED)
		running = FALSE
		return
	addtimer(CALLBACK(src, PROC_REF(next_incident)), rand(BOT_CHAOS_GAP_MIN, BOT_CHAOS_GAP_MAX) / GLOB.bot_chaos_level)
	var/list/menu = list("quarrel" = 5, "brawl" = 3, "pickpocket" = 3, "riot" = 2, "mouth off" = 3)
	if(GLOB.bot_chaos_level >= 2) //goals/sabotage_accidents.dm: the user's ruling, mayhem has its accidents too
		menu += list("slime out" = 1, "chem mishap" = 1)
	while(length(menu))
		var/incident = pickweight(menu)
		menu -= incident
		var/happened = FALSE
		switch(incident)
			if("quarrel")
				happened = start_quarrel()
			if("brawl")
				happened = start_brawl()
			if("pickpocket")
				happened = start_pickpocket()
			if("riot")
				happened = bot_call_riot()
			if("mouth off")
				happened = start_mouthing_off()
			if("slime out")
				happened = accident_slime_out()
			if("chem mishap")
				happened = accident_chem_mishap()
		if(happened)
			incidents[incident]++
			log_game("BOT CHAOS: [incident]")
			return

/// A bot with nothing pressing on, and able to get into trouble.
/proc/bot_at_a_loose_end(datum/bot_brain/B)
	return B.owner.stat == CONSCIOUS && !B.owner.incapacitated() && B.state != BOT_STATE_COMBAT && B.state != BOT_STATE_ARREST && !B.is_security_job() \
		&& !istype(B.current_goal, /datum/bot_goal/evacuate) && !istype(B.current_goal, /datum/bot_goal/treat_patient)

/// Two crew in a room, one of them with a temper: it starts with words.
/datum/bot_chaos/proc/start_quarrel()
	var/list/hotheads = list()
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(bot_at_a_loose_end(B))
			hotheads[B] = 1 + round(B.temper * 4) //whole numbers: pickweight() can come back with nothing given fractions
	while(length(hotheads))
		var/datum/bot_brain/B = pickweight(hotheads)
		hotheads -= B
		for(var/mob/living/carbon/human/H in view(5, B.owner))
			if(H != B.owner && H.bot_brain && bot_at_a_loose_end(H.bot_brain))
				B.pick_a_quarrel(H)
				return TRUE
	return FALSE

/// A word, a comeback, and then it's up to the two of them. Whichever has the shorter temper shoves first.
/datum/bot_brain/proc/pick_a_quarrel(mob/living/carbon/human/other)
	trouble_until = world.time + BOT_QUARREL_LENGTH
	stand_still_until = world.time + 6 SECONDS
	owner.face_atom(other)
	bot_say(owner, pick(GLOB.bot_quarrel_openers))
	other.bot_brain.stand_still_until = world.time + 6 SECONDS
	addtimer(CALLBACK(other.bot_brain, PROC_REF(answer_back), WEAKREF(owner)), rand(15, 35))
	addtimer(CALLBACK(src, PROC_REF(lose_it_with), WEAKREF(other)), rand(40, 70))

/datum/bot_brain/proc/answer_back(datum/weakref/who)
	var/mob/living/M = who?.resolve()
	if(M && !QDELETED(owner) && owner.stat == CONSCIOUS)
		owner.face_atom(M)
		bot_say(owner, pick(GLOB.bot_quarrel_comebacks))

/// Over to it: walks up and shoves them, or if it's really angry takes a swing.
/datum/bot_brain/proc/lose_it_with(datum/weakref/who)
	var/mob/living/carbon/human/M = who?.resolve()
	if(!M || QDELETED(owner) || owner.incapacitated() || state == BOT_STATE_COMBAT || state == BOT_STATE_ARREST || !M.bot_brain)
		return
	trouble_until = world.time + BOT_QUARREL_LENGTH
	if(state == BOT_STATE_WANDER && !current_goal)
		var/datum/bot_goal/tide/harass/shoving = new(M)
		shoving.shoves = 8
		assign_goal(shoving)

/// Somewhere with a crowd and drink taken: a fight in the bar, or wherever three or more are gathered.
/datum/bot_chaos/proc/start_brawl()
	for(var/datum/bot_brain/B as anything in shuffle(GLOB.bot_brains.Copy()))
		if(!bot_at_a_loose_end(B))
			continue
		var/list/crowd = list()
		for(var/mob/living/carbon/human/H in view(5, B.owner))
			if(H != B.owner && H.bot_brain && bot_at_a_loose_end(H.bot_brain))
				crowd += H.bot_brain
		if(length(crowd) < 2)
			continue
		var/datum/bot_brain/other = pick(crowd)
		B.trouble_until = world.time + BOT_QUARREL_LENGTH
		other.trouble_until = world.time + BOT_QUARREL_LENGTH
		bot_say(B.owner, pick(GLOB.bot_quarrel_openers))
		B.step_in_against(other.owner)
		return TRUE
	return FALSE

/// Somebody helps themselves to what's in somebody's pocket, and if they get caught at it, that's a fight.
/datum/bot_chaos/proc/start_pickpocket()
	for(var/datum/bot_brain/B as anything in shuffle(GLOB.bot_brains.Copy()))
		if(!bot_at_a_loose_end(B) || B.current_goal || !(B.greytider || B.temper > 0.5))
			continue
		var/mob/living/carbon/human/mark = B.find_mark()
		if(!mark)
			continue
		if(B.assign_goal(new /datum/bot_goal/tide/pickpocket(mark)))
			return TRUE
	return FALSE

/datum/bot_goal/tide/pickpocket/New(mob/living/carbon/human/mark)
	. = ..()
	target = mark

/datum/bot_goal/tide/pickpocket/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/tide/pickpocket/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/tide/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/pickpocket())
	return list(S)

/// The strip menu, on whatever's in their pockets, or failing that their hands.
/datum/bot_step/pickpocket/execute(datum/bot_brain/bot)
	var/mob/living/carbon/human/mark = bot.current_goal?.target
	if(QDELETED(mark) || !bot.owner.Adjacent(mark))
		return GOAL_STEP_FAIL
	bot.trouble_until = world.time + 30 SECONDS
	var/list/slots = list() //what's there -> the strip menu's name for where
	for(var/slot in list(ITEM_SLOT_LPOCKET, ITEM_SLOT_RPOCKET, ITEM_SLOT_BELT, ITEM_SLOT_ID))
		var/obj/item/worn = mark.get_item_by_slot(slot)
		if(worn)
			slots[worn] = slot
	var/obj/item/held = mark.get_active_held_item()
	if(held)
		slots[held] = list("hand", mark.active_hand_index)
	if(!length(slots))
		return GOAL_STEP_FAIL
	var/obj/item/I = pick(slots)
	var/where = slots[I]
	bot.human_pause(mark)
	if(QDELETED(mark) || QDELETED(I) || !bot.owner.Adjacent(mark) || bot.owner.incapacitated())
		return GOAL_STEP_FAIL
	bot.owner.face_atom(mark)
	bot.free_hand_for(null)
	bot.telemetry_clicked(mark)
	bot.owner.stripPanelUnequip(I, mark, where)
	if(bot.is_carried(I))
		bot.put_away(I, allow_equip = FALSE)
		bot.things_looted++
		bot_log(bot, "lifted [I] off [mark]")
		return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

/datum/bot_chaos/proc/start_mouthing_off()
	for(var/datum/bot_brain/B as anything in shuffle(GLOB.bot_brains.Copy()))
		if(B.greytider && bot_at_a_loose_end(B))
			B.mouth_off()
			return TRUE
	return FALSE

/datum/controller/subsystem/ticker/Initialize(timeofday)
	. = ..()
	OnRoundstart(CALLBACK(GLOB.bot_chaos, TYPE_PROC_REF(/datum/bot_chaos, round_started)))

#undef BOT_CHAOS_GAP_MIN
#undef BOT_CHAOS_GAP_MAX
#undef BOT_CHAOS_SETTLE_IN
#undef BOT_QUARREL_LENGTH
