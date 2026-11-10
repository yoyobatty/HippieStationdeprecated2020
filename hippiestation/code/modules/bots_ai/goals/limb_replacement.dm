// An arm lost, and put back on. Arms go in explosions and to axes often enough (ten to twenty-six limbs a shift in the chaos batches),
// and the bot an arm came off went on one-handed for the rest of the shift. A player picks the arm up (it lands a few tiles off), climbs
// on to an operating table, lies down and asks Medbay to put it back on, and a doctor or a roboticist does it the way it's done in the
// game: incision, clamps, retractor and then the limb itself (prosthetic_replacement.dm). A robot arm lying about does as well as the
// arm that came off. Legs aren't here: without one a bot can't get up on the table, and a doctor dragging it there is another job.

/// How long it lies on the table for somebody to come.
#define BOT_LIMB_WAIT (3 MINUTES)
/// How long it lies there with nobody saying they're coming, before it gets up.
#define BOT_LIMB_ANSWER (40 SECONDS)
/// How long after a try that came to nothing before the next.
#define BOT_LIMB_RETRY (5 MINUTES)
/// How far it goes for a limb.
#define BOT_LIMB_RANGE 40

GLOBAL_LIST_INIT(bot_limb_jobs, list("Medical Doctor", "Chief Medical Officer", "Roboticist"))

/datum/bot_brain
	/// When it next looks at getting a lost arm put back on.
	var/next_limb_try = 0

/// An arm it's lost, that could be put back on.
/datum/bot_brain/proc/missing_arm_zone()
	var/list/missing = owner.get_missing_limbs()
	for(var/zone in list(BODY_ZONE_R_ARM, BODY_ZONE_L_ARM))
		if(zone in missing)
			return zone
	return null

/// Whether a loose limb would go on H where it's missing one (add_prosthetic): the right arm or leg, robotic or of H's own kind.
/proc/bot_limb_fits(obj/item/bodypart/L, mob/living/carbon/human/H, zone)
	if(QDELETED(L) || L.owner || L.body_zone != zone || L.animal_origin)
		return FALSE
	return L.status == BODYPART_ROBOTIC || L.species_id == H.dna?.species?.id

/// An arm lying by somebody on an operating table that would go on where they've lost one, or null.
/proc/bot_limb_beside(mob/living/carbon/human/patient)
	if(!(locate(/obj/structure/table/optable) in patient.loc))
		return null
	var/list/missing = patient.get_missing_limbs()
	for(var/place in list(BODY_ZONE_R_ARM, BODY_ZONE_L_ARM))
		if(!(place in missing))
			continue
		for(var/obj/item/bodypart/L in range(1, patient))
			if(isturf(L.loc) && bot_limb_fits(L, patient, place))
				return L
	return null

/// A limb for that place: one it's carrying, or the nearest lying about that it knows of and can walk to.
/datum/bot_brain/proc/find_limb_for(zone)
	for(var/obj/item/bodypart/L in owner.GetAllContents())
		if(bot_limb_fits(L, owner, zone))
			return L
	glance_at_items()
	var/list/near = list()
	for(var/obj/item/bodypart/L as anything in bot_instances_of(/obj/item/bodypart))
		if(!isturf(L.loc) || L.z != owner.z || !bot_limb_fits(L, owner, zone) || taken_by_another(L) || !knows_of(L))
			continue
		var/dist = get_dist(owner, L)
		if(dist <= BOT_LIMB_RANGE && (!gym_run || get_area(L) == get_area(owner)))
			near[L] = dist
	while(length(near)) //nearest first, a route search each
		var/obj/item/bodypart/best
		for(var/obj/item/bodypart/L as anything in near)
			if(!best || near[L] < near[best])
				best = L
		if(can_walk_lawfully_to(best))
			return best
		near -= best
	return null

/datum/bot_duty/new_limb
	name = "getting an arm put back on"
	tier = BOT_DUTY_URGENT
	priority = 25
	interval_min = 100
	interval_max = 200

/datum/bot_duty/new_limb/try_start(datum/bot_brain/bot)
	if(world.time < bot.next_limb_try)
		return FALSE
	var/zone = bot.missing_arm_zone()
	if(!zone)
		return FALSE
	var/mob/living/carbon/human/H = bot.owner
	if(H.handcuffed || H.bot_life_sentence || bot.is_in_active_cell(H) || !bot_on_duty(GLOB.bot_limb_jobs, H))
		return FALSE
	bot.next_limb_try = world.time + BOT_LIMB_RETRY
	var/obj/item/bodypart/L = bot.find_limb_for(zone)
	if(!L)
		bot_log(bot, "lost my [parse_zone(zone)], and there's none about to have put back on")
		return FALSE
	var/obj/structure/table/optable/table = bot.find_limb_table()
	if(!table)
		bot_log(bot, "lost my [parse_zone(zone)], and there's no operating table free where somebody could see to it")
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/get_limb_back(zone, L, table))

/// A free operating table it can get to, in a department with somebody on duty who'd put an arm on: Medbay's for the doctors, Robotics'
/// for a roboticist. The nearest was taken, and a scientist lay on Robotics' table and called four times over, with the one doctor who
/// heard having no way into Robotics.
/datum/bot_brain/proc/find_limb_table()
	var/doctors = bot_on_duty(list("Medical Doctor", "Chief Medical Officer"), owner)
	var/roboticists = bot_on_duty(list("Roboticist"), owner)
	var/list/tables = list()
	for(var/obj/structure/table/optable/T as anything in bot_instances_of(/obj/structure/table/optable))
		if(QDELETED(T) || T.z != owner.z || (gym_run && get_area(T) != get_area(owner)))
			continue
		if(!gym_run)
			var/department = bot_department_of(get_area(T))
			if(!((department == "medical" && doctors) || (department == "science" && roboticists)))
				continue
		var/occupied = FALSE
		for(var/mob/living/L in T.loc)
			if(L.stat != DEAD)
				occupied = TRUE
				break
		if(!occupied)
			tables[T] = get_dist(owner, T)
	for(var/tries in 1 to 3) //nearest first, a route search each
		var/obj/structure/table/optable/nearest
		for(var/obj/structure/table/optable/T as anything in tables)
			if(!nearest || tables[T] < tables[nearest])
				nearest = T
		if(!nearest)
			return null
		if(can_walk_lawfully_to(nearest))
			return nearest
		tables -= nearest
	return null

/// The arm picked up, on to the table, lying down with the arm beside it, and a call for somebody to come and put it on.
/datum/bot_goal/get_limb_back
	lawful = TRUE
	exclusive = TRUE
	doing = "getting an arm put back on"
	var/zone
	var/obj/item/bodypart/limb
	var/obj/structure/table/optable/table

/datum/bot_goal/get_limb_back/New(zone, obj/item/bodypart/L, obj/structure/table/optable/T)
	. = ..()
	src.zone = zone
	limb = L
	table = T

/datum/bot_goal/get_limb_back/resolve_target(datum/bot_brain/bot)
	if(!(zone in bot.owner.get_missing_limbs()) || QDELETED(table))
		return
	if(QDELETED(limb) || (!bot.is_carried(limb) && !isturf(limb.loc)))
		limb = bot.find_limb_for(zone)
	if(limb)
		target = table

/datum/bot_goal/get_limb_back/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/get_limb_back/S = new
	S.steps = list(new /datum/bot_step/limb_in_hand(), new /datum/bot_step/move_to(), new /datum/bot_step/paced/wait_on_table())
	return list(S)

/datum/bot_goal/get_limb_back/on_success(datum/bot_brain/bot)
	bot.get_up_off_table()

/datum/bot_goal/get_limb_back/on_give_up(datum/bot_brain/bot)
	bot.get_up_off_table()

/datum/bot_strategy/get_limb_back/is_feasible(datum/bot_brain/bot)
	var/datum/bot_goal/get_limb_back/G = bot.current_goal
	return istype(G) && !QDELETED(G.table) && !QDELETED(G.limb)

/// Put down where it is and left there: out of the hands and off the list of things knocked out of them, and of things set down for
/// a moment (bot_items.dm), so nothing has it picked up again.
/datum/bot_brain/proc/set_down_for_good(obj/item/I)
	if(QDELETED(I))
		return
	if(is_carried(I) && ready_in_hand(I))
		owner.dropItemToGround(I)
	for(var/datum/weakref/W as anything in knocked_away)
		if(W.resolve() == I)
			LAZYREMOVE(knocked_away, W)
	LAZYREMOVE(set_down_items, I)

/// Up off the table, if it's lying on it.
/datum/bot_brain/proc/get_up_off_table()
	if(owner.resting)
		owner.set_resting(FALSE, TRUE)

/datum/bot_step/limb_in_hand
	var/tries = 0

/datum/bot_step/limb_in_hand/execute(datum/bot_brain/bot)
	var/datum/bot_goal/get_limb_back/G = bot.current_goal
	if(!istype(G) || QDELETED(G.limb))
		return GOAL_STEP_FAIL
	if(bot.is_carried(G.limb))
		return GOAL_STEP_SUCCESS
	if(++tries > 2)
		return GOAL_STEP_FAIL
	return bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(G.limb)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/// Up on the table, the arm down beside it, lying down, and a call to Medbay. Then it waits.
/datum/bot_step/paced/wait_on_table
	max_clicks = 120
	var/until = 0
	var/called_at = 0
	var/climbed = FALSE

/datum/bot_step/paced/wait_on_table/start(datum/bot_brain/bot)
	until = world.time + BOT_LIMB_WAIT
	return TRUE

/datum/bot_step/paced/wait_on_table/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/get_limb_back/G = bot.current_goal
	if(!istype(G) || QDELETED(G.table) || world.time > until)
		return FALSE
	var/mob/living/carbon/human/H = bot.owner
	if(!(G.zone in H.get_missing_limbs()))
		return FALSE //back on
	if(H.loc != G.table.loc)
		if(climbed || !H.Adjacent(G.table))
			return FALSE //moved off it, or never got there
		climbed = TRUE
		bot_log(bot, "climbing on to [G.table]")
		G.table.climb_structure(H) //yields while it climbs
		wait_for = G.table.climb_stun + 5
		return TRUE
	// The arm down on the table beside it, for whoever comes. The climb's stun shakes it out of the hand as a rule, and the bot's
	// reflex for what's knocked out of its hands (bot_reflexes.dm) had it straight back up: the doctor found nothing to put on, and
	// would have been held to have taken it.
	bot.set_down_for_good(G.limb)
	if(!H.resting)
		H.set_resting(TRUE, TRUE)
		G.table.check_patient()
		bot_log(bot, "lying on [G.table] for somebody to put my [parse_zone(G.zone)] back on")
		wait_for = 1 SECONDS
		return TRUE
	if(!called_at)
		called_at = world.time
		var/where = get_area_name(G.table, TRUE)
		var/limb_name = parse_zone(G.zone)
		if(!bot.call_for(/datum/bot_request_kind/limb, pick("Could somebody put my [limb_name] back on? I'm on the operating table in [where].", "Lost my [limb_name]. I've got it here, on the table in [where] - can somebody put it back on?", "Medbay, I need my [limb_name] back on. On the table in [where].")))
			bot_log(bot, "nobody to call to put my [limb_name] back on")
			return FALSE
		wait_for = 3 SECONDS
		return TRUE
	if(world.time > called_at + BOT_LIMB_ANSWER && !bot.call_answered(/datum/bot_request_kind/limb)) //goals/powergame.dm
		bot_log(bot, "nobody's coming to put my [parse_zone(G.zone)] back on")
		return FALSE
	wait_for = 2 SECONDS
	return TRUE

/datum/bot_step/paced/wait_on_table/finish(datum/bot_brain/bot)
	var/datum/bot_goal/get_limb_back/G = bot.current_goal
	return (istype(G) && !(G.zone in bot.owner.get_missing_limbs())) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// "Could somebody put my arm back on? I'm on the table in Surgery.": a doctor or a roboticist comes with the tools.
/datum/bot_request_kind/limb
	name = "limb"
	jobs = list("Medical Doctor", "Chief Medical Officer", "Roboticist")
	strong_words = list("arm back on", "leg back on", "reattach my", "new arm", "new leg", "prosthetic")
	ack_lines = list("Coming, stay on the table.", "On my way with the tools.", "Be right there, hold still.")
	walks_there = FALSE //the tools first (goals/surgery.dm)
	doing = "putting somebody's arm back on"
	precedence = 2

/// Only while they're on the table with the arm beside them, and by somebody with a way to that table: a doctor who said "on my way"
/// with no arm to put on, or no way into Robotics where they lay, didn't come, and the call was spent.
/datum/bot_request_kind/limb/answered_by(datum/bot_brain/bot, datum/bot_request/R)
	var/mob/living/carbon/human/who = R.caller_ref?.resolve()
	if(!..() || !istype(who) || !bot_limb_beside(who))
		return FALSE
	var/obj/structure/table/optable/table = locate() in who.loc
	return table && bot.can_walk_lawfully_to(table)

/datum/bot_request_kind/limb/attend(datum/bot_brain/bot, datum/bot_request/R)
	var/mob/living/carbon/human/who = R.caller_ref?.resolve()
	if(!istype(who) || who == bot.owner)
		return
	if(bot.state == BOT_STATE_GOAL && !bot.current_goal?.exclusive)
		bot.drop_goals("somebody's on the table waiting for an arm")
	if(bot.state != BOT_STATE_WANDER || !bot.assign_goal(new /datum/bot_goal/operate/limb(who)))
		R.taken_by = null //for somebody else
		LAZYOR(R.failed_by, bot)

/// The prosthetic replacement on somebody lying on an operating table with the limb beside them.
/datum/bot_goal/operate/limb
	doing = "putting somebody's arm back on"
	var/datum/weakref/patient_ref
	var/zone
	var/obj/item/bodypart/limb

/datum/bot_goal/operate/limb/New(mob/living/carbon/human/patient)
	. = ..()
	patient_ref = WEAKREF(patient)

/datum/bot_goal/operate/limb/resolve_target(datum/bot_brain/bot)
	var/mob/living/carbon/human/patient = patient_ref?.resolve()
	if(!istype(patient) || patient.stat == DEAD)
		return
	table = locate(/obj/structure/table/optable) in patient.loc
	if(!table)
		bot_log_verbose(bot, "[patient] isn't on an operating table")
		return
	var/list/missing = patient.get_missing_limbs()
	if(!limb || !bot.is_carried(limb) || !(zone in missing))
		limb = bot_limb_beside(patient)
		zone = limb?.body_zone
	if(!limb)
		bot_log_verbose(bot, "no limb by [patient] that would go on (missing [english_list(missing)])")
	else if(bot.can_walk_lawfully_to(table)) //the table, not them: a route doesn't end on a table, and they're lying on it
		target = patient
	else
		bot_log_verbose(bot, "no way to [patient] on [table]")

/datum/bot_goal/operate/limb/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/operate/S = new
	S.steps = list(new /datum/bot_step/surgery_tools(), new /datum/bot_step/move_to(), new /datum/bot_step/take_limb(), new /datum/bot_step/move_to(), new /datum/bot_step/paced/attach_limb())
	return list(S)

/// The limb off the table and into its hands.
/datum/bot_step/take_limb
	var/tries = 0

/datum/bot_step/take_limb/execute(datum/bot_brain/bot)
	var/datum/bot_goal/operate/limb/G = bot.current_goal
	if(!istype(G) || QDELETED(G.limb))
		return GOAL_STEP_FAIL
	if(bot.is_carried(G.limb))
		return GOAL_STEP_SUCCESS
	if(++tries > 2)
		return GOAL_STEP_FAIL
	if(bot.take_in_hand(G.limb)) //goals/take_item.dm
		return GOAL_STEP_SUCCESS
	return bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(G.limb)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/// Each step of the prosthetic replacement with the right thing in hand, the limb last.
/datum/bot_step/paced/attach_limb
	max_clicks = 40
	var/datum/surgery/procedure

/datum/bot_step/paced/attach_limb/start(datum/bot_brain/bot)
	var/datum/bot_goal/operate/limb/G = bot.current_goal
	var/mob/living/carbon/human/patient = G?.target
	if(!istype(patient) || QDELETED(patient) || !G.zone || !(G.zone in patient.get_missing_limbs()))
		return FALSE
	for(var/datum/surgery/S as anything in patient.surgeries) //somebody's made a start on it: carried on from there
		if(S.location == G.zone)
			procedure = S
			break
	if(!procedure)
		procedure = new /datum/surgery/prosthetic_replacement(patient, G.zone, null)
	procedure.ignore_clothes = TRUE //as for wounds (goals/surgery.dm): nobody's stripped for it
	bot.telemetry_action = "putting [patient]'s [parse_zone(G.zone)] back on"
	log_combat(bot.owner, patient, "operated on", null, "(OPERATION TYPE: [procedure.name]) (TARGET AREA: [procedure.location])")
	return TRUE

/datum/bot_step/paced/attach_limb/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/operate/limb/G = bot.current_goal
	var/mob/living/carbon/human/patient = G?.target
	if(QDELETED(procedure) || QDELETED(patient) || patient.stat == DEAD || !bot.owner.Adjacent(patient) || !isturf(patient.loc))
		return FALSE
	var/datum/surgery_step/step = procedure.get_surgery_step()
	var/obj/item/tool = istype(step, /datum/surgery_step/add_prosthetic) ? G.limb : bot.tool_for_surgery_step(step)
	if(QDELETED(tool) || !bot.ready_in_hand(tool))
		bot_log(bot, "nothing to [step.name] with")
		return FALSE
	bot.owner.a_intent = INTENT_HELP
	bot.owner.zone_selected = G.zone
	bot_log_verbose(bot, "[step.name] with [tool]")
	bot.use_item_on(tool, patient)
	wait_for = 3
	return TRUE

/datum/bot_step/paced/attach_limb/finish(datum/bot_brain/bot)
	bot.telemetry_action = null
	var/datum/bot_goal/operate/limb/G = bot.current_goal
	var/mob/living/carbon/human/patient = G?.target
	if(istype(patient) && G.zone && !(G.zone in patient.get_missing_limbs()))
		bot_log(bot, "put [patient]'s [parse_zone(G.zone)] back on")
		return GOAL_STEP_SUCCESS
	if(!QDELETED(procedure))
		bot_log(bot, "had to stop operating on [patient]")
		QDEL_NULL(procedure)
	return GOAL_STEP_FAIL

#undef BOT_LIMB_WAIT
#undef BOT_LIMB_ANSWER
#undef BOT_LIMB_RETRY
#undef BOT_LIMB_RANGE
