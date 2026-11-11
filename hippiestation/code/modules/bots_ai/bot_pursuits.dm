// What a bot wants out of its shift. Everybody playing has something they're after beyond the job, and it depends how they feel:
// some shifts it's powergaming science and genetics to be robust enough for the traitors, some it's the bar and a chat, some it's
// keeping the place tidy and in working order, some it's seeing what's out there. That's the user's description of playing, and
// their ruling: pick one to suit the personality, keep at it until it's done or boring (15 to 30 minutes), then another; a scare
// changes minds. The job still gets done: this is what the bot does with the time around it, and how it leans.
//
//  - job      the job, and nothing else much (the diligent, heads, Security, Medical)
//  - power    powergaming: plays as a powergamer would for a while (bot_playstyles.dm), the genes, the stims, the good gear
//  - upkeep   keeps the station nice: picks up the litter and bins it (tidy_up), mends windows if it can
//  - explore  goes and has a look round: maintenance and what's off the station (goals/exploring.dm)
//  - social   the bar, the arcade, a drink and a chat, before work rather than after
//  - careful  shaken up, by an attack or a body: keeps out of trouble and ready for it (is_paranoid())
//
// It says what it's up to now and then, the way people do: "gonna go get some genes done", "this shift is cursed".

/datum/bot_brain
	/// What it's after this part of the shift (BOT_PURSUIT_*), and until when.
	var/pursuit = BOT_PURSUIT_JOB
	var/pursuit_until = 0
	/// The playstyle it had before powergaming for a while, to go back to.
	var/playstyle_before_pursuit
	var/next_pursuit_mention = 0

/// Bots a test run has made explorers so far (bot-explorers=N on a Bot Shift).
GLOBAL_VAR_INIT(bot_explorers_made, 0)

/datum/bot_brain/New(mob/living/carbon/human/new_owner)
	. = ..()
	pursuit_until = world.time + rand(30 SECONDS, 2 MINUTES) //settled in first
	var/explorers = text2num(world.params["bot-explorers"])
	if(explorers && GLOB.bot_explorers_made < explorers && !is_security_job() && !(work_role() in GLOB.command_positions))
		GLOB.bot_explorers_made++
		addtimer(CALLBACK(src, PROC_REF(set_pursuit), BOT_PURSUIT_EXPLORE, 60 MINUTES, "the test run"), 1 MINUTES)

/// How much it fancies each, by who it is and what it does.
/datum/bot_brain/proc/pursuit_weights()
	var/role = work_role()
	var/list/W = list()
	W[BOT_PURSUIT_JOB] = 25 + 40 * diligence + ((role in GLOB.command_positions) || is_security_job() || is_medical_job() ? 30 : 0)
	W[BOT_PURSUIT_POWER] = playstyle == BOT_STYLE_POWERGAMER ? 60 : (playstyle == BOT_STYLE_ROBUST ? 30 : 15 * nerve * (0.5 + competence))
	W[BOT_PURSUIT_UPKEEP] = 10 + 30 * (1 - temper) * diligence + (role in list("Janitor", "Station Engineer", "Assistant") ? 10 : 0)
	W[BOT_PURSUIT_EXPLORE] = max(0, 40 * (nerve - 0.3)) + (role in list("Assistant", "Shaft Miner", "Explorer")) * 20 + (playstyle == BOT_STYLE_HOPPER || playstyle == BOT_STYLE_HUNTER) * 10
	W[BOT_PURSUIT_SOCIAL] = 5 + 40 * sociability + (role in list("Bartender", "Clown", "Cook", "Mime", "Assistant")) * 10
	if(is_security_job() || (role in GLOB.command_positions))
		W[BOT_PURSUIT_EXPLORE] = 0 //they've a station to look after
	if(hardened)
		W[BOT_PURSUIT_CAREFUL] = 40 * (1 - nerve)
	return W

/// Picks what it's after next, and says so now and then.
/datum/bot_brain/proc/pick_pursuit(reason)
	var/list/W = pursuit_weights()
	if(pursuit != BOT_PURSUIT_JOB)
		W[pursuit] = W[pursuit] / 3 //bored of it
	set_pursuit(pickweight(W), rand(15 MINUTES, 30 MINUTES), reason)

/datum/bot_brain/proc/set_pursuit(what, how_long, reason)
	var/was = pursuit
	pursuit = what
	pursuit_until = world.time + how_long
	if(was == what)
		return
	// Powergaming for a while is playing as a powergamer does; it goes back to its own way after.
	if(was == BOT_PURSUIT_POWER && playstyle_before_pursuit)
		set_playstyle(playstyle_before_pursuit)
		playstyle_before_pursuit = null
	if(what == BOT_PURSUIT_POWER && playstyle != BOT_STYLE_POWERGAMER && playstyle != BOT_STYLE_ROBUST)
		playstyle_before_pursuit = playstyle
		set_playstyle(BOT_STYLE_POWERGAMER)
	else
		duties = null //what it takes on has changed (tidy_up, maint_crawl for explorers): worked out again
	bot_log(src, "now after [what] ([reason]), for [round(how_long / (1 MINUTES))] minutes")
	telemetry_event("pursuit", list("pursuit" = what, "was" = was, "why" = reason))
	if(prob(25 + 50 * sociability))
		next_pursuit_mention = 0
		mention_pursuit()

/// What people say about what they're up to.
GLOBAL_LIST_INIT(bot_pursuit_lines, list(
	BOT_PURSUIT_POWER = list("Gonna go get some genes done.", "Anyone got spare insuls?", "Time to get robust.", "Think I'll go see what science has printed.", "Need some better gear for this shift."),
	BOT_PURSUIT_UPKEEP = list("This place is a mess.", "Someone's got to keep this station running.", "Gonna tidy up a bit.", "Who keeps leaving their rubbish everywhere?"),
	BOT_PURSUIT_EXPLORE = list("Anyone want to go exploring?", "Think I'll go have a poke around maint.", "Wonder what's out there today.", "Gonna go see what I can find."),
	BOT_PURSUIT_SOCIAL = list("Anyone at the bar?", "Who wants a drink?", "Bored. Anyone up for some arcade?", "Bar, anyone?"),
	BOT_PURSUIT_CAREFUL = list("This shift is cursed.", "I'm staying out of trouble today.", "Not going anywhere alone, not after that.", "Keep your eyes open, people."),
))

/datum/bot_brain/proc/mention_pursuit()
	// With the bodies piling up nobody's asking who's up for arcade: a CE asked where the killer was last, and forty seconds later
	// "Bored. Anyone up for some arcade?" (2026-11-10)
	var/list/lines = GLOB.bot_pursuit_lines[bot_shift_gone_bad() && !gym_run ? BOT_PURSUIT_CAREFUL : pursuit]
	if(!length(lines) || world.time < next_pursuit_mention || owner.stat != CONSCIOUS || gone_loud() || state == BOT_STATE_COMBAT || state == BOT_STATE_ARREST)
		return
	next_pursuit_mention = world.time + rand(6 MINUTES, 14 MINUTES)
	bot_say(owner, (prob(35) ? ";" : "") + pick(lines))

/// Once a wander: bored of it yet, and a word about it now and then.
/datum/bot_brain/proc/mind_pursuit()
	if(world.time >= pursuit_until)
		pick_pursuit("bored of it")
	else if(world.time >= next_pursuit_mention && prob(10 * sociability))
		mention_pursuit()

/// A scare (attacked, a body): the nervous go careful for a while, whatever they were at.
/datum/bot_brain/proc/shaken(why)
	if(nerve < 0.55 && pursuit != BOT_PURSUIT_CAREFUL)
		set_pursuit(BOT_PURSUIT_CAREFUL, rand(10 MINUTES, 20 MINUTES), why)

// ---------------------------------------------------------------------------------------------
// Keeping the station nice
// ---------------------------------------------------------------------------------------------

/// Litter: what people drop and somebody tidy picks up. Banana peels too: one in a hallway was stepped round 45 times in a shift and
/// left where it was (bot_hazards.dm mind_the_footing()).
GLOBAL_LIST_INIT(bot_litter_types, typecacheof(list(/obj/item/trash, /obj/item/cigbutt, /obj/item/reagent_containers/food/drinks/soda_cans, /obj/item/paper/crumpled, /obj/item/grown/bananapeel)))

/datum/bot_duty/tidy_up
	name = "tidying up"
	tier = BOT_DUTY_WORK
	interval_min = 150
	interval_max = 400

/datum/bot_duty/tidy_up/applies_to(datum/bot_brain/bot)
	return bot.pursuit == BOT_PURSUIT_UPKEEP && bot.work_role() != "Janitor"

/datum/bot_duty/tidy_up/try_start(datum/bot_brain/bot)
	if(bot.pursuit != BOT_PURSUIT_UPKEEP)
		return FALSE
	var/obj/item/litter
	for(var/obj/item/I in view(5, bot.owner))
		if(isturf(I.loc) && is_type_in_typecache(I, GLOB.bot_litter_types) && !bot.taken_by_another(I) && (!istype(I, /obj/item/reagent_containers) || !I.reagents?.total_volume))
			litter = I
			break
	if(!litter)
		return FALSE
	var/obj/machinery/disposal/bin/B = bot.nearest_bin(litter)
	if(!B)
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/tidy_litter(litter, B))

/// The nearest bin to `near` that the bot can walk to by doors its own ID opens. The nearest of all was often behind a counter or
/// a door it has no access to (the kitchen's, the bar's): an assistant picked up a plate, set off for the kitchen's bin, found no
/// way to it and gave up, ten times in a shift, still holding the plate.
/datum/bot_brain/proc/nearest_bin(atom/near)
	var/list/by_dist = list()
	for(var/obj/machinery/disposal/bin/B as anything in bot_instances_of(/obj/machinery/disposal/bin))
		if(QDELETED(B) || B.z != owner.z || (B.stat & BROKEN))
			continue
		var/dist = get_dist(near, B)
		if(dist <= 12)
			by_dist[B] = dist
	sortTim(by_dist, GLOBAL_PROC_REF(cmp_numeric_asc), TRUE)
	var/tries = 0
	for(var/obj/machinery/disposal/bin/B as anything in by_dist)
		if(can_walk_lawfully_to(B))
			return B
		if(++tries >= 3)
			break
	return null

/datum/bot_goal/tidy_litter
	lawful = TRUE
	exclusive = TRUE
	doing = "tidying up"
	var/obj/machinery/disposal/bin/bin

/datum/bot_goal/tidy_litter/New(obj/item/litter, obj/machinery/disposal/bin/B)
	. = ..()
	target = litter
	bin = B

/datum/bot_goal/tidy_litter/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target) || !isturf(target.loc) || QDELETED(bin))
		target = null

/datum/bot_goal/tidy_litter/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/tidy_litter/S = new
	var/datum/bot_step/move_to/to_bin = new
	to_bin.step_target = bin
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/pick_up_litter(), to_bin, new /datum/bot_step/bin_litter(bin))
	return list(S)

/datum/bot_strategy/tidy_litter/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// On it somewhere, the bag included (is_carried()): with its pockets full a pick-up goes in the bag, and "in its hands or pockets"
/// called that a failure. It picked the litter up, gave up, and walked off with a bag of cigarette butts and plates, about sixty
/// times in twelve shifts.
/datum/bot_step/pick_up_litter/execute(datum/bot_brain/bot)
	var/obj/item/I = bot.current_goal?.target
	if(QDELETED(I))
		return GOAL_STEP_FAIL
	if(bot.is_carried(I))
		return GOAL_STEP_SUCCESS
	if(!isturf(I.loc) || !bot.owner.Adjacent(I))
		return GOAL_STEP_FAIL
	bot.try_pickup_target(I)
	return bot.is_carried(I) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/datum/bot_step/bin_litter
	var/obj/machinery/disposal/bin/bin

/datum/bot_step/bin_litter/New(obj/machinery/disposal/bin/B)
	. = ..()
	bin = B

/datum/bot_step/bin_litter/execute(datum/bot_brain/bot)
	var/obj/item/I = bot.current_goal?.target
	if(QDELETED(I) || QDELETED(bin) || !bot.is_carried(I) || !bot.owner.Adjacent(bin))
		return GOAL_STEP_FAIL
	bot.use_item_on(I, bin) //out of the bag and into the hand first, if that's where it went
	if(bot.is_carried(I))
		return GOAL_STEP_FAIL
	bot_tally("litter binned")
	return GOAL_STEP_SUCCESS

/// An explorer goes through maintenance, whatever its job (goals/assistant.dm).
/datum/bot_duty/maint_crawl/applies_to(datum/bot_brain/bot)
	return ..() || bot.pursuit == BOT_PURSUIT_EXPLORE
