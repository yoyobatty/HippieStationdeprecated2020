// Space Law: what the crew goes by, from the guide this server's players use (wiki.beestation13.com/view/Space_Law).
//
//  - Every charge a bot can bring has a code and a time in a cell (GLOB.bot_space_law): 5, 10 or 15 minutes, or capital.
//  - Somebody has to be in charge: the Captain if there's one alive and aboard. Failing that a head fills in, the HoP first and
//    then the HoS, and says so on the radio. That's who a capital case goes to, and the one other person who can hold the
//    Captain's ID without it being Grand Larceny.
//  - A capital charge doesn't end when a timer runs out. The prisoner is held while whoever's in charge rules on it, on the
//    radio: the Prison Wing as a rule, a lethal injection from a harsh one. There's no trial. The Warden or the HoS sees to it.
//    With nobody in command at all Security can lock somebody up for good, and that's all it can do.
//  - Nobody else decides that anybody dies. Crew put people on the floor and keep them there for Security (hold_for_security,
//    bot_playstyles.dm). In a fight that's gone bad a hunter or a paranoid bot may mean it, within the cases Space Law allows
//    (bot_may_use_lethal_force()), and it still stops when they're down.

/// How long whoever's in charge takes to answer for a prisoner.
#define BOT_CASE_THINKING (20 SECONDS)
/// How long a player in charge is left to make the call, before Security does what it can by itself.
#define BOT_CASE_PLAYER_TIME (3 MINUTES)
/// Weapon force that makes somebody armed and dangerous.
#define BOT_ARMED_AND_DANGEROUS_FORCE 15
/// People going at it at once that make it being mobbed.
#define BOT_MOBBED_BY 3

/// What the bots call a charge -> its code in Space Law and how long in a cell. A capital charge is held for as long as a timer
/// goes while it's decided: that's its severity (BOT_CRIME_MURDER), not this.
GLOBAL_LIST_INIT(bot_space_law, list(
	"Assault" = list(101, 5 MINUTES),
	"Vandalism" = list(103, 5 MINUTES),
	"Vigilantism" = list(104, 5 MINUTES),
	"Trespassing" = list(109, 5 MINUTES),
	"Breaking and Entering" = list(110, 5 MINUTES),
	"Aggravated Assault" = list(201, 10 MINUTES),
	"Assault with a Deadly Weapon" = list(201, 10 MINUTES),
	"Assaulting an Officer" = list(201, 10 MINUTES),
	"Kidnapping" = list(201, 10 MINUTES),
	"Theft" = list(202, 10 MINUTES),
	"Major Vandalism" = list(203, 10 MINUTES),
	"Possession of Contraband" = list(206, 10 MINUTES),
	"Trespassing in a Dangerous Area" = list(209, 10 MINUTES),
	"Breaking into a Dangerous Area" = list(210, 10 MINUTES),
	"Murder" = list(301, 15 MINUTES),
	"Larceny" = list(302, 15 MINUTES),
	"Sabotage" = list(303, 15 MINUTES),
	"Possession of Dangerous Equipment" = list(306, 15 MINUTES),
	"Trespassing in a High Security Area" = list(309, 15 MINUTES),
	"Breaking into a High Security Area" = list(310, 15 MINUTES),
	"Grand Larceny" = list(402, 15 MINUTES),
	"Grand Sabotage" = list(403, 15 MINUTES),
	"Subversion of the Chain of Command" = list(407, 15 MINUTES),
))

/// Who takes over, in order.
GLOBAL_LIST_INIT(bot_chain_of_command, list("Captain", "Head of Personnel", "Head of Security", "Research Director", "Chief Engineer", "Chief Medical Officer"))

/// Things nobody on the crew has a reason to be seen with, by type.
GLOBAL_LIST_INIT(bot_contraband, typecacheof(list(
	/obj/item/melee/transforming/energy/sword,
	/obj/item/card/emag,
	/obj/item/clothing/suit/space/syndicate,
	/obj/item/clothing/head/helmet/space/syndicate,
	/obj/item/clothing/suit/space/hardsuit/syndi,
	/obj/item/clothing/head/helmet/space/hardsuit/syndi,
	/obj/item/gun/ballistic/automatic/pistol,
	/obj/item/gun/ballistic/automatic/c20r,
	/obj/item/gun/ballistic/shotgun/bulldog,
	/obj/item/grenade/syndieminibomb,
)))

/// The case of each prisoner on a capital charge, this round.
GLOBAL_LIST_EMPTY(bot_cases)
/// Weakref to whoever last took charge.
GLOBAL_VAR(bot_in_command)

/mob/living/carbon/human
	/// Put to death by order: nobody's to bring them back.
	var/bot_executed = FALSE
	/// Sentenced for good: stays in the Prison Wing.
	var/bot_life_sentence = FALSE

/proc/bot_charge_code(crime)
	var/list/charge = GLOB.bot_space_law[crime]
	return charge?[1]

/// What a charge reads as on the radio: "301, murder".
/proc/bot_charge_line(crime)
	var/code = bot_charge_code(crime)
	return code ? "[code], [lowertext(crime)]" : lowertext(crime)

/proc/bot_sentence_for(crime, severity)
	var/list/charge = GLOB.bot_space_law[crime]
	if(charge)
		return charge[2]
	return severity >= BOT_CRIME_MAJOR ? 15 MINUTES : 5 MINUTES

// ---------------------------------------------------------------------------------------------
// Who's in charge
// ---------------------------------------------------------------------------------------------

/// Whether somebody can give orders: alive, aboard and not in cuffs.
/proc/bot_fit_to_command(mob/living/carbon/human/H)
	var/turf/T = get_turf(H)
	return T && H.stat != DEAD && !H.handcuffed && !H.bot_life_sentence && (is_station_level(T.z) || H.bot_brain?.gym_run)

/// The Captain, or the head filling in. Null if there's no command staff left aboard. Bot Gym: whoever's asking only knows their own arena.
/proc/bot_find_in_command(mob/living/carbon/human/asking)
	var/list/by_job = list()
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.mind && (H.mind.assigned_role in GLOB.bot_chain_of_command) && bot_fit_to_command(H))
			if(H.bot_brain?.gym_run && asking && get_area(H) != get_area(asking))
				continue
			by_job[H.mind.assigned_role] = H
	for(var/job in GLOB.bot_chain_of_command)
		if(by_job[job])
			return by_job[job]
	return null

/// The head who's next in line says so on the radio, once.
/datum/bot_duty/chain_of_command
	name = "seeing who's in charge"
	tier = BOT_DUTY_URGENT
	interval_min = 200
	interval_max = 400

/datum/bot_duty/chain_of_command/applies_to(datum/bot_brain/bot)
	return bot.work_role() in GLOB.bot_chain_of_command

/datum/bot_duty/chain_of_command/try_start(datum/bot_brain/bot)
	var/mob/living/carbon/human/boss = bot_find_in_command(bot.owner)
	var/datum/weakref/last_ref = GLOB.bot_in_command
	if(boss != bot.owner || last_ref?.resolve() == boss)
		return FALSE
	GLOB.bot_in_command = WEAKREF(boss)
	if(bot.owner.mind.assigned_role == "Captain")
		if(last_ref)
			bot_say(bot.owner, ";This is the Captain. I'm back in command.")
	else
		bot_say(bot.owner, pick(";No word from the Captain. I'm acting captain until we hear otherwise.", ";With the Captain gone, I'm taking command. I'm acting captain."))
		bot_tally("took command")
	bot_log(bot, "in command now")
	return FALSE

// ---------------------------------------------------------------------------------------------
// The Captain's ID
// ---------------------------------------------------------------------------------------------

/proc/bot_is_captains_id(obj/item/card/id/C)
	return istype(C, /obj/item/card/id/captains_spare) || (istype(C) && C.assignment == "Captain")

/// The Captain's own, the spare, on somebody who has no right to it. An acting captain does.
/proc/bot_has_stolen_captains_id(mob/living/carbon/human/H)
	if(!bot_is_captains_id(H.get_idcard(TRUE)) || H.mind?.assigned_role == "Captain")
		return FALSE
	return H != bot_find_in_command()

// ---------------------------------------------------------------------------------------------
// Force
// ---------------------------------------------------------------------------------------------

/// Whether they've got something in their hands that kills. Tools don't count, unless they're the size of a fire axe.
/proc/bot_armed_and_dangerous(mob/living/carbon/human/H)
	for(var/obj/item/I in H.held_items)
		if(istype(I, /obj/item/gun) || bot_weapon_force(I) >= BOT_ARMED_AND_DANGEROUS_FORCE)
			return TRUE
	return FALSE

/// Space Law's cases for lethal force, as far as a bot in a fight can tell. A greytider with a toolbox is none of them.
/datum/bot_brain/proc/bot_may_use_lethal_force(mob/living/foe)
	if(GLOB.security_level >= SEC_LEVEL_RED)
		return TRUE
	if(!ishuman(foe))
		return TRUE
	if(bot_armed_and_dangerous(foe))
		return TRUE
	// A Syndicate combat suit is a weapon worn. Four officers fired twenty disabler shots at one, which it shrugs off, while it beat an
	// engineer and then all of them.
	if(bot_in_nanosuit(foe))
		return TRUE
	if(owner.health < owner.maxHealth * 0.4)
		return TRUE
	if(bot_fighters_against(owner) >= BOT_MOBBED_BY)
		return TRUE
	var/datum/bot_wanted/W = bot_get_wanted_entry(foe)
	return W?.severity >= BOT_CRIME_MURDER

// ---------------------------------------------------------------------------------------------
// Capital cases
// ---------------------------------------------------------------------------------------------

/datum/bot_case
	var/datum/weakref/prisoner_ref
	var/datum/weakref/cell_ref
	var/crime
	var/opened_at = 0
	/// BOT_VERDICT_*, once somebody's ruled.
	var/verdict
	var/ruled_by
	/// The officer on its way to see to it, as a weakref, and whether that's done with.
	var/datum/weakref/officer_ref
	var/closed = FALSE

/datum/bot_case/proc/prisoner()
	return prisoner_ref?.resolve()

/datum/bot_case/proc/cell()
	return cell_ref?.resolve()

/proc/bot_case_of(mob/living/carbon/human/P)
	for(var/datum/bot_case/C as anything in GLOB.bot_cases)
		if(C.prisoner() == P)
			return C
	return null

/// Over to whoever's in charge. From start_sentence() (goals/security_patrol.dm), with the prisoner behind the door.
/proc/bot_open_case(mob/living/carbon/human/P, crime, obj/machinery/door_timer/T, datum/bot_brain/officer)
	var/datum/bot_case/C = bot_case_of(P)
	if(C)
		return C
	C = new
	C.prisoner_ref = WEAKREF(P)
	C.cell_ref = WEAKREF(T)
	C.crime = crime
	C.opened_at = world.time
	GLOB.bot_cases += C
	var/mob/living/carbon/human/boss = bot_find_in_command()
	bot_say(officer.owner, ":s [boss ? boss.name : "Warden"], [P.name] is in [T.name] on a capital charge: [lowertext(crime)]. What do you want done?")
	bot_log(officer, "capital case opened: [P], [crime]")
	bot_tally("capital cases")
	return C

/// Whoever rules on this. A bot in charge does; a player in charge gets a while to say so; after that, or with no command
/// staff left, it's Security's to do what it can.
/datum/bot_case/proc/who_rules()
	var/mob/living/carbon/human/boss = bot_find_in_command()
	if(boss?.bot_brain)
		return boss.bot_brain
	if(boss && world.time < opened_at + BOT_CASE_PLAYER_TIME)
		return null
	for(var/datum/bot_brain/B as anything in GLOB.bot_security_brains)
		if(B.owner.stat == CONSCIOUS && !B.owner.handcuffed)
			return B
	return null

/// Whether there's anybody who could open the lethal injections locker, and a locker to open.
/datum/bot_case/proc/can_be_injected()
	return length(bot_instances_of(/obj/structure/closet/secure_closet/injection)) && !!bot_executioner()

/// The HoS, or failing that whoever's in charge: nobody else has the access for that locker.
/datum/bot_case/proc/bot_executioner()
	var/mob/living/carbon/human/boss = bot_find_in_command()
	var/datum/bot_brain/fallback
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(B.owner.stat != CONSCIOUS || B.owner.handcuffed || !bot_fit_to_command(B.owner))
			continue
		if(B.work_role() == "Head of Security")
			return B
		if(B.owner == boss)
			fallback = B
	return fallback

/// Who takes them to the Prison Wing: the Warden, the HoS, or an officer if there's neither.
/datum/bot_case/proc/bot_warden()
	var/list/order = list("Warden", "Head of Security", "Security Officer")
	for(var/job in order)
		for(var/datum/bot_brain/B as anything in GLOB.bot_security_brains)
			if(B.work_role() == job && B.owner.stat == CONSCIOUS && !B.owner.handcuffed)
				return B
	return null

/datum/bot_case/proc/who_carries_out()
	return verdict == BOT_VERDICT_INJECTION ? bot_executioner() : bot_warden()

/// What a search turns up on somebody being brigged: a charge for whatever they'd rather nobody had seen. It's evidence, so it goes
/// in the cell locker with the rest of what's taken off them.
/// What comes off a prisoner going into a cell: all but the jumpsuit and shoes, in the order they come off a person.
/datum/bot_brain/proc/everything_but_clothes(mob/living/carbon/human/P)
	. = list()
	for(var/obj/item/I in P.held_items)
		. += I
	for(var/obj/item/I in list(P.s_store, P.back, P.belt, P.l_store, P.r_store, P.wear_id, P.ears, P.gloves, P.wear_mask, P.glasses, P.head, P.wear_suit, P.wear_neck))
		if(I && !HAS_TRAIT(I, TRAIT_NODROP))
			. |= I
	// Hidden on them: every officer goes through pockets, bag and belt (they're in the locker already), the thorough and the
	// paranoid have a look up the back as well, which is where people keep the things they don't want found.
	if(strictness >= 0.6 || is_paranoid() || bot_too_dangerous(P))
		var/obj/item/organ/butt/B = P.getorgan(/obj/item/organ/butt)
		var/datum/component/storage/S = B?.GetComponent(/datum/component/storage)
		if(S)
			bot_log(src, "searching [P]'s butt")
			for(var/obj/item/I in S.contents())
				. |= I

/// Out of somewhere it was hidden on them (the butt's storage), to drop. FALSE if it wasn't hidden.
/proc/bot_take_from_hiding(mob/living/carbon/human/P, obj/item/I, turf/drop)
	var/obj/item/organ/butt/B = I.loc
	if(!istype(B) || B.owner != P)
		return FALSE
	var/datum/component/storage/S = B.GetComponent(/datum/component/storage)
	return S && S.remove_from_storage(I, drop)

/// One piece of the prison outfit on them from the locker, the jumpsuit and then the shoes, what they had on going in with the rest.
/// TRUE while there's still something to do.
/datum/bot_brain/proc/dress_in_orange(mob/living/carbon/human/P, turf/locker_turf)
	var/list/outfit = list(/obj/item/clothing/under/rank/prisoner = ITEM_SLOT_ICLOTHING, /obj/item/clothing/shoes/sneakers/orange = ITEM_SLOT_FEET)
	for(var/path in outfit)
		var/slot = outfit[path]
		var/obj/item/worn = P.get_item_by_slot(slot)
		if(istype(worn, path))
			continue
		var/obj/item/clothing/orange = locate(path) in locker_turf
		if(!orange)
			for(var/obj/structure/closet/C in locker_turf)
				orange = locate(path) in C
				if(orange)
					break
		if(!orange)
			continue //somebody's had them: what they've got on will do
		if(worn)
			if(HAS_TRAIT(worn, TRAIT_NODROP) || !P.transferItemToLoc(worn, locker_turf))
				continue
			var/obj/structure/closet/locker = locate() in locker_turf
			bot_note_confiscated(P, worn, slot, locker) //goals/released_prisoner.dm: back on when they're let out
			return TRUE
		// Picked up, and put on them by the strip menu, as an officer does it: it takes a few seconds, and they're stood there for it.
		// It used to go from the locker straight on to them, which no player can do.
		if(!owner.Adjacent(orange) || !owner.Adjacent(P))
			return FALSE
		human_pause(orange)
		make_hand_free()
		if(QDELETED(orange) || !owner.Adjacent(orange) || !owner.put_in_hands(orange))
			return FALSE
		owner.stripPanelEquip(orange, P, slot)
		if(P.get_item_by_slot(slot) != orange)
			if(orange.loc == owner)
				owner.dropItemToGround(orange)
			return FALSE //it won't go on them: leave it there, rather than trying for ever
		bot_log(src, "dressed [P] in [orange]")
		return TRUE
	return FALSE

/datum/bot_brain/proc/search_prisoner(mob/living/carbon/human/P, datum/bot_step/process_prisoner/step)
	for(var/obj/item/I in P.GetAllContents())
		if(bot_is_captains_id(I) && P.mind?.assigned_role != "Captain" && P != bot_find_in_command())
			step.to_confiscate |= I
			file_crime(P, "Grand Larceny", "Found with the Captain's ID on them.", BOT_CRIME_MURDER)
		else if(is_type_in_typecache(I, GLOB.bot_contraband))
			step.to_confiscate |= I
			file_crime(P, "Possession of Dangerous Equipment", "Found with [I.name] on them.", BOT_CRIME_MAJOR)
		else if(istype(I, /obj/item/disk/nuclear) && P.mind?.assigned_role != "Captain")
			step.to_confiscate |= I //the officer keeps that one on them (process_prisoner): a nuclear operative was sat in a cell with it

/// A test can have a capital case come out one way or the other.
GLOBAL_VAR(bot_law_drill_verdict)

/// The harsh ones order an injection. Most never do. Security on its own can't: only the Captain, or whoever's acting, can order that.
/datum/bot_brain/proc/rule_on(datum/bot_case/C)
	var/mob/living/carbon/human/P = C.prisoner()
	if(!P || P.stat == DEAD)
		C.closed = TRUE
		return
	var/may_order_death = owner == bot_find_in_command()
	C.verdict = BOT_VERDICT_PERMABRIG
	if(may_order_death && prob(temper >= 0.7 ? 60 : 5) && C.can_be_injected())
		C.verdict = BOT_VERDICT_INJECTION
	if(GLOB.bot_law_drill_verdict)
		C.verdict = GLOB.bot_law_drill_verdict
	C.ruled_by = owner.real_name
	bot_tally(C.verdict)
	bot_log(src, "ruled on [P], [C.crime]: [C.verdict]")
	log_game("BOT LAW: [owner.real_name] ruled [C.verdict] for [P.real_name], [C.crime]")
	if(C.verdict == BOT_VERDICT_INJECTION)
		bot_say(owner, ":s [P.name]: [bot_charge_line(C.crime)]. Lethal injection, on my authority.")
	else
		bot_say(owner, ":s [P.name]: [bot_charge_line(C.crime)]. Permanent confinement. Prison Wing.")

/// Somebody in charge who isn't a bot saying what's to be done: "permabrig them", "execute Sam".
/datum/bot_brain/proc/on_heard_ruling(atom/movable/speaker, raw_message)
	if(!length(GLOB.bot_cases) || !is_security_job())
		return
	var/mob/living/L = speaker
	if(istype(speaker, /atom/movable/virtualspeaker))
		var/atom/movable/virtualspeaker/V = speaker
		L = V.source
	if(!isliving(L) || !L.client || L != bot_find_in_command())
		return
	var/lower = lowertext(raw_message)
	var/verdict
	if(findtext(lower, "perma") || findtext(lower, "prison wing"))
		verdict = BOT_VERDICT_PERMABRIG
	else if(findtext(lower, "execute") || findtext(lower, "lethal") || findtext(lower, "injection"))
		verdict = BOT_VERDICT_INJECTION
	if(!verdict)
		return
	for(var/datum/bot_case/C as anything in GLOB.bot_cases)
		if(C.verdict || C.closed)
			continue
		var/mob/living/carbon/human/P = C.prisoner()
		if(P && (length(GLOB.bot_cases) == 1 || findtext(lower, lowertext(P.first_name()))))
			C.verdict = verdict
			C.ruled_by = L.real_name
			bot_tally(verdict)
			log_game("BOT LAW: [L.real_name] ruled [verdict] for [P.real_name], [C.crime]")
			return

/// Rulings, on the radio: no walking involved.
/datum/bot_duty/capital_cases
	name = "ruling on a prisoner"
	tier = BOT_DUTY_URGENT
	interval_min = 60
	interval_max = 150

/datum/bot_duty/capital_cases/applies_to(datum/bot_brain/bot)
	return (bot.work_role() in GLOB.bot_chain_of_command) || bot.is_security_job()

/datum/bot_duty/capital_cases/try_start(datum/bot_brain/bot)
	for(var/datum/bot_case/C as anything in GLOB.bot_cases)
		if(C.closed || C.verdict || world.time < C.opened_at + BOT_CASE_THINKING || C.who_rules() != bot)
			continue
		bot.rule_on(C)
	return FALSE

/// The ruling, carried out.
/datum/bot_duty/carry_out_verdict
	name = "carrying out a sentence"
	tier = BOT_DUTY_URGENT
	priority = 20
	interval_min = 50
	interval_max = 120

/datum/bot_duty/carry_out_verdict/applies_to(datum/bot_brain/bot)
	return (bot.work_role() in GLOB.bot_chain_of_command) || bot.is_security_job()

/datum/bot_duty/carry_out_verdict/try_start(datum/bot_brain/bot)
	for(var/datum/bot_case/C as anything in GLOB.bot_cases)
		if(C.closed || !C.verdict)
			continue
		var/mob/living/carbon/human/P = C.prisoner()
		if(!P || P.stat == DEAD)
			C.closed = TRUE
			continue
		var/datum/weakref/ref = C.officer_ref
		var/mob/living/carbon/human/officer = ref?.resolve()
		if(officer && officer != bot.owner && officer.stat == CONSCIOUS)
			continue
		// The HoS died with an injection ordered: the Prison Wing's the next best thing.
		if(C.verdict == BOT_VERDICT_INJECTION && !C.can_be_injected())
			C.verdict = BOT_VERDICT_PERMABRIG
		if(C.who_carries_out() != bot)
			continue
		var/datum/bot_goal/seeing_to = C.verdict == BOT_VERDICT_INJECTION ? new /datum/bot_goal/lethal_injection(C) : new /datum/bot_goal/collect_prisoner(C)
		if(bot.assign_goal(seeing_to))
			C.officer_ref = WEAKREF(bot.owner)
			return TRUE
	return FALSE

/// The Stop button on a cell's timer, once nobody's left in it to fall down the trapdoor that opens on the Hippie map. An officer's ID
/// opens a cell's door with the timer running, so there's no need for it any sooner.
/datum/bot_step/stop_timer
	var/datum/bot_case/case

/datum/bot_step/stop_timer/New(datum/bot_case/C)
	. = ..()
	case = C

/datum/bot_step/stop_timer/execute(datum/bot_brain/bot)
	var/obj/machinery/door_timer/T = case.cell()
	if(QDELETED(T) || !T.timing || !bot.owner.Adjacent(T) || !T.allowed(bot.owner))
		return GOAL_STEP_SUCCESS //the timer will see to itself
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	T.timer_end(forced = TRUE)
	GLOB.bot_brig_sentences -= T
	return GOAL_STEP_SUCCESS

/// To the cell: the prisoner comes out the way anybody's arrested, in cuffs, and brig_prisoner takes them on to the Prison Wing because
/// of what the case says (goals/security_patrol.dm).
/datum/bot_goal/collect_prisoner
	exclusive = TRUE
	doing = "taking somebody to the Prison Wing"
	var/datum/bot_case/case

/datum/bot_goal/collect_prisoner/New(datum/bot_case/C)
	. = ..()
	case = C

/datum/bot_goal/collect_prisoner/resolve_target(datum/bot_brain/bot)
	target = case.cell() || case.prisoner()

/datum/bot_goal/collect_prisoner/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/move_to())
	return list(S)

/datum/bot_strategy/case_work/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_goal/collect_prisoner/on_success(datum/bot_brain/bot)
	var/mob/living/carbon/human/P = case.prisoner()
	if(P)
		bot.file_crime(P, case.crime, "To the Prison Wing, by order of [case.ruled_by].", BOT_CRIME_MURDER)
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, begin_arrest), P))

/datum/bot_goal/collect_prisoner/on_give_up(datum/bot_brain/bot)
	case.officer_ref = null

/// Where a lifer ends up: the room with the Prison Wing's own vending machine in it. There's one on every map.
/proc/bot_prison_spot()
	for(var/obj/machinery/vending/sustenance/V as anything in bot_instances_of(/obj/machinery/vending/sustenance))
		if(!istype(get_area(V), /area/security/prison))
			continue
		var/list/spots = list()
		for(var/turf/open/T in range(3, V))
			if(istype(T.loc, /area/security/prison) && !is_blocked_turf(T, TRUE) && (T in view(3, V)))
				spots += T
		if(length(spots))
			return pick(spots)
	return null

/// A brig locker in the Prison Wing, for what a lifer came in with.
/proc/bot_prison_locker(turf/near)
	var/obj/structure/closet/secure_closet/brig/best
	for(var/obj/structure/closet/secure_closet/brig/L in GLOB.areas_by_type[/area/security/prison])
		if(!best || get_dist(L, near) < get_dist(best, near))
			best = L
	return best

/// Prisoner in hand: by way of a locker, for everything they own, and on to the room they'll be staying in.
/datum/bot_strategy/take_to_prison
	var/datum/bot_goal/brig_prisoner/goal

/datum/bot_strategy/take_to_prison/New(datum/bot_goal/brig_prisoner/G)
	. = ..()
	goal = G
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/grab_patient())
	var/datum/bot_case/case = bot_case_of(G.prisoner)
	if(case?.cell())
		var/datum/bot_step/move_to/to_timer = new()
		to_timer.step_target = case.cell()
		steps += to_timer
		steps += new /datum/bot_step/stop_timer(case)
	if(G.prison_locker)
		var/datum/bot_step/move_to/to_locker = new()
		to_locker.step_target = G.prison_locker
		steps += to_locker
		steps += new /datum/bot_step/paced/strip_prisoner(G)
	var/datum/bot_step/move_to/to_room = new()
	to_room.step_target = G.deep_turf
	steps += to_room
	steps += new /datum/bot_step/paced/leave_in_prison(G)

/datum/bot_strategy/take_to_prison/is_feasible(datum/bot_brain/bot)
	return !QDELETED(goal.prisoner) && goal.deep_turf

/// Space Law: lifers are stripped and dressed in orange, and keep nothing. Everything goes in the locker.
/datum/bot_step/paced/strip_prisoner
	max_clicks = 25
	optional = TRUE
	var/datum/bot_goal/brig_prisoner/goal
	var/list/to_take

/datum/bot_step/paced/strip_prisoner/New(datum/bot_goal/brig_prisoner/G)
	. = ..()
	goal = G

/datum/bot_step/paced/strip_prisoner/start(datum/bot_brain/bot)
	var/obj/structure/closet/locker = goal.prison_locker
	if(QDELETED(locker) || !bot.owner.Adjacent(locker))
		return FALSE
	if(locker.locked)
		locker.togglelock(bot.owner, TRUE)
	if(!locker.opened)
		locker.open(bot.owner)
	to_take = goal.prisoner.get_equipped_items(TRUE)
	to_take -= goal.prisoner.handcuffed
	return TRUE

/datum/bot_step/paced/strip_prisoner/do_click(datum/bot_brain/bot)
	var/mob/living/carbon/human/P = goal.prisoner
	var/obj/structure/closet/locker = goal.prison_locker
	if(QDELETED(P) || QDELETED(locker) || !length(to_take))
		return FALSE
	var/obj/item/I = to_take[1]
	to_take.Cut(1, 2)
	if(!QDELETED(I) && (I in P.GetAllContents()) && P.transferItemToLoc(I, get_turf(locker), TRUE))
		P.visible_message("<span class='warning'>[bot.owner] takes [I] off [P].</span>")
	wait_for = 8
	return TRUE

/datum/bot_step/paced/strip_prisoner/finish(datum/bot_brain/bot)
	var/mob/living/carbon/human/P = goal.prisoner
	var/obj/structure/closet/locker = goal.prison_locker
	if(QDELETED(P) || QDELETED(locker))
		return GOAL_STEP_SUCCESS
	var/obj/item/clothing/under/rank/prisoner/orange = locate() in get_turf(locker)
	if(orange)
		P.equip_to_slot_or_del(orange, ITEM_SLOT_ICLOTHING)
	var/obj/item/clothing/shoes/sneakers/orange/shoes = locate() in get_turf(locker)
	if(shoes)
		P.equip_to_slot_or_del(shoes, ITEM_SLOT_FEET)
	locker.close(bot.owner)
	return GOAL_STEP_SUCCESS

/// Cuffs off and out of the door. That's them, for the rest of the round.
/datum/bot_step/paced/leave_in_prison
	max_clicks = 3
	var/datum/bot_goal/brig_prisoner/goal

/datum/bot_step/paced/leave_in_prison/New(datum/bot_goal/brig_prisoner/G)
	. = ..()
	goal = G

/datum/bot_step/paced/leave_in_prison/do_click(datum/bot_brain/bot)
	var/mob/living/carbon/human/P = goal.prisoner
	if(QDELETED(P))
		return FALSE
	bot.owner.stop_pulling()
	var/obj/item/restraints/handcuffs/cuffs = P.handcuffed
	if(cuffs)
		P.uncuff()
		P.visible_message("<span class='notice'>[bot.owner] removes [P]'s restraints.</span>")
		if(!QDELETED(cuffs) && isturf(cuffs.loc) && !istype(cuffs, /obj/item/restraints/handcuffs/cable/zipties/used))
			bot.try_pickup_target(cuffs)
	return FALSE

/datum/bot_step/paced/leave_in_prison/finish(datum/bot_brain/bot)
	var/mob/living/carbon/human/P = goal.prisoner
	if(QDELETED(P))
		return GOAL_STEP_FAIL
	P.bot_life_sentence = TRUE
	P.bot_brain?.drop_goals("serving life")
	bot_clear_wanted(P)
	bot_set_criminal_status(P, "Incarcerated")
	var/datum/bot_case/C = bot_case_of(P)
	if(C)
		C.closed = TRUE
	bot_tally("permabrigged")
	bot_log(bot, "left [P] in the Prison Wing for good")
	log_game("BOT LAW: [bot.owner.real_name] permabrigged [P.real_name]")
	bot_say(bot.owner, ":s [P.name] is in the Prison Wing, permanent confinement.")
	return GOAL_STEP_SUCCESS

/// One of the five syringes from the locker in the execution room, the cell opened, and in with them.
/datum/bot_goal/lethal_injection
	exclusive = TRUE
	lawful = TRUE
	doing = "seeing to a prisoner"
	var/datum/bot_case/case

/datum/bot_goal/lethal_injection/New(datum/bot_case/C)
	. = ..()
	case = C

/datum/bot_goal/lethal_injection/resolve_target(datum/bot_brain/bot)
	if(bot.find_carried_tool(/obj/item/reagent_containers/syringe/lethal/execution))
		target = case.prisoner()
		return
	for(var/obj/structure/closet/secure_closet/injection/L as anything in bot_instances_of(/obj/structure/closet/secure_closet/injection))
		if(L.z == bot.owner.z && (locate(/obj/item/reagent_containers/syringe/lethal/execution) in L) && bot.can_walk_lawfully_to(L))
			target = L
			return

/datum/bot_goal/lethal_injection/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list()
	if(istype(target, /obj/structure/closet))
		S.steps += new /datum/bot_step/move_to()
		S.steps += new /datum/bot_step/interact()
		S.steps += new /datum/bot_step/pickup_from_target(/obj/item/reagent_containers/syringe/lethal/execution)
	var/datum/bot_step/move_to/to_timer = new()
	to_timer.step_target = case.cell()
	S.steps += to_timer
	S.steps += new /datum/bot_step/paced/inject_prisoner(case)
	var/datum/bot_step/move_to/back_to_timer = new()
	back_to_timer.step_target = case.cell()
	S.steps += back_to_timer
	S.steps += new /datum/bot_step/stop_timer(case)
	return list(S)

/datum/bot_goal/lethal_injection/on_give_up(datum/bot_brain/bot)
	case.officer_ref = null
	bot_log(bot, "couldn't carry out the injection on [case.prisoner()]")

/// Walks in, gets them still if they aren't, and it's done.
/datum/bot_step/paced/inject_prisoner
	max_clicks = 40
	var/datum/bot_case/case
	var/injected = FALSE

/datum/bot_step/paced/inject_prisoner/New(datum/bot_case/C)
	. = ..()
	case = C

/datum/bot_step/paced/inject_prisoner/do_click(datum/bot_brain/bot)
	var/mob/living/carbon/human/P = case.prisoner()
	var/obj/item/reagent_containers/syringe/lethal/execution/syringe = bot.find_carried_tool(/obj/item/reagent_containers/syringe/lethal/execution)
	if(QDELETED(P) || P.stat == DEAD || !syringe)
		return FALSE
	if(!bot.owner.Adjacent(P))
		if(bot.pursuing_kind != "follow" || bot.pursue_target != P)
			bot.pursue(P, "follow", force = TRUE)
		wait_for = 8
		clicks++ //no click, but it isn't to go on for ever
		return TRUE
	bot.stop_pursuit()
	if(!P.handcuffed && !bot.is_subdued(P))
		bot.melee_subdue(P)
		wait_for = CLICK_CD_MELEE
		clicks++
		return TRUE
	bot.use_item_on(syringe, P)
	if(!QDELETED(syringe) && syringe.reagents.total_volume)
		wait_for = CLICK_CD_MELEE
		clicks++
		return TRUE
	injected = TRUE
	return FALSE

/datum/bot_step/paced/inject_prisoner/finish(datum/bot_brain/bot)
	bot.stop_pursuit()
	if(!injected)
		return GOAL_STEP_FAIL
	var/mob/living/carbon/human/P = case.prisoner()
	case.closed = TRUE
	if(P)
		P.bot_executed = TRUE
		bot_clear_wanted(P)
		bot_set_criminal_status(P, "Incarcerated")
		bot_tally("executed")
		log_game("BOT LAW: [bot.owner.real_name] carried out a lethal injection on [P.real_name]")
		bot_log(bot, "carried out the injection on [P]")
		bot_say(bot.owner, ":s Sentence carried out on [P.name].")
	return GOAL_STEP_SUCCESS

#undef BOT_CASE_THINKING
#undef BOT_CASE_PLAYER_TIME
#undef BOT_ARMED_AND_DANGEROUS_FORCE
#undef BOT_MOBBED_BY
