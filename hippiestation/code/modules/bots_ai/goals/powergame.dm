// Powergaming (the user's ask, 2026-11-09: "I want to see bots power gaming (getting all access, guns, super heal chems, mutations,
// viruses, rnd stuff all as priorities, maybe even have a drone to back them up, I want bots who become insanely powerful and rely
// on these.)").
//
// A powergamer (bot_personality.dm, or anybody on the power pursuit, bot_pursuits.dm) works up a ladder a rung at a time, the way a
// player goes about it, between whatever else it's doing:
//  1. Access. To the HoP's window, card down, and asks for maintenance and the departments the good stuff's in. A strict HoP gives
//     the one place, an easygoing one the lot (the HoP's own nature, bot_asks.dm); all access and the armory nobody gets.
//  2. Powers. A mutator off a gene Genetics has stored (genetics.dm), printed at the console itself if its card gets it in there,
//     asked for on the radio if not, and the Geneticist prints one and brings it over. Injected on the spot.
//  3. Heals. Brute and burn patches off a NanoMed, a couple of each, for the fights to come.
//  4. A gun. Printed at a lathe its card gets it to, the best the station's researched that the lathe will make.
// And it relies on them: hurt in a fight it slaps a patch on and fights on instead of running while it's got one, and it shoots
// with whatever it printed (try_shoot_at(), bot_fighting.dm).

/// Before a rung it couldn't manage is tried again.
#define BOT_POWER_RUNG_REST (8 MINUTES)
/// The HoP isn't asked again for a while, yes or no.
#define BOT_POWER_ACCESS_REST (20 MINUTES)
/// Between patches slapped on mid-fight.
#define BOT_POWER_HEAL_GAP (12 SECONDS)
/// How long it waits for the Geneticist to bring an activator over.
#define BOT_POWER_WAIT_FOR_GENES (3 MINUTES)
/// Patches of each kind it likes to have on it.
#define BOT_POWER_PATCHES 2

/// Where a powergamer wants to get into, in the order it asks: words the HoP knows (GLOB.bot_access_words).
GLOBAL_LIST_INIT(bot_power_access_wants, list("maintenance", "research", "robotics", "medbay", "genetics", "chemistry", "tech storage", "engineering"))
/// The guns it would print, the best first (design ids).
GLOBAL_LIST_INIT(bot_power_gun_designs, list("xray_laser", "nuclear_gun", "gaussrifle", "beamrifle", "xcomrifle", "ioncarbine", "largecrossbow", "stunrevolver", "temp_gun"))
/// The powers it's after, the best first. Any good one will do once these are had or not going.
GLOBAL_LIST_INIT(bot_power_mutations, list(/datum/mutation/human/hulk, /datum/mutation/human/thermal, /datum/mutation/human/telekinesis,
	/datum/mutation/human/insulated, /datum/mutation/human/strong, /datum/mutation/human/laser_eyes, /datum/mutation/human/space_adaptation,
	/datum/mutation/human/shock, /datum/mutation/human/cryokinesis, /datum/mutation/human/chameleon, /datum/mutation/human/firebreath))

/datum/bot_brain
	/// Rung -> when it's next worth trying.
	var/list/power_rests
	var/next_power_heal = 0

/datum/bot_brain/proc/is_powergamer()
	return playstyle == BOT_STYLE_POWERGAMER

/datum/bot_duty/power_ladder
	name = "powergaming"
	priority = 16 //before stocking up: the kit's the bottom rung
	interval_min = 1 MINUTES
	interval_max = 2 MINUTES

/datum/bot_duty/power_ladder/try_start(datum/bot_brain/bot)
	if(!bot.is_powergamer())
		return FALSE
	return bot.climb_power_ladder()

/// The next rung it hasn't got and can try for. TRUE if it's off after one.
/datum/bot_brain/proc/climb_power_ladder()
	if(owner.incapacitated() || gone_loud() || bot_shuttle_boarding())
		return FALSE
	inject_activators()
	for(var/rung in list("access", "genes", "heals", "gun"))
		if(LAZYACCESS(power_rests, rung) > world.time)
			continue
		var/started = FALSE
		switch(rung)
			if("access")
				started = try_power_access()
			if("genes")
				started = try_power_genes()
			if("heals")
				started = try_power_heals()
			if("gun")
				started = try_power_gun()
		if(started)
			bot_tally("powergaming: [rung]")
			telemetry_event("powergaming", list("rung" = rung))
			return TRUE
	return FALSE

// ---------------------------------------------------------------------------------------------
// Access
// ---------------------------------------------------------------------------------------------

/// The places it wants into that its card doesn't open, in the order it asks.
/datum/bot_brain/proc/power_access_missing()
	. = list()
	var/obj/item/card/id/card = route_card()
	var/list/have = card?.access || list()
	for(var/word in GLOB.bot_power_access_wants)
		for(var/a in GLOB.bot_access_words[word])
			if(!(a in have))
				. += word
				break

/datum/bot_brain/proc/try_power_access()
	var/list/missing = power_access_missing()
	if(!length(missing) || !card_in_reach())
		return FALSE
	var/mob/living/carbon/human/hop = bot_find_hop(owner)
	if(!hop && !gym_run)
		LAZYSET(power_rests, "access", world.time + BOT_POWER_RUNG_REST)
		return FALSE
	LAZYSET(power_rests, "access", world.time + BOT_POWER_ACCESS_REST)
	// What the HoP will give: a strict one the one place, an easygoing one all of it, anybody else a few.
	var/strict = hop?.bot_brain ? hop.bot_brain.strictness : 0.5
	var/count = strict >= 0.6 ? 1 : (strict < 0.3 ? length(missing) : min(3, length(missing))) //bot_asks.dm's by-the-book and easygoing
	var/list/names = missing.Copy(1, count + 1)
	var/list/accesses = list()
	for(var/word in names)
		accesses |= GLOB.bot_access_words[word]
	return assign_goal(new /datum/bot_goal/job_transfer/access/power(accesses, english_list(names)))

/// Whether it has a card to put down.
/datum/bot_brain/proc/card_in_reach()
	return !!owner.get_idcard(FALSE)

/datum/bot_goal/job_transfer/access/power
	doing = "asking the HoP for more access"

/datum/bot_goal/job_transfer/access/power/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/await_transfer/access/power(add_access, access_names))
	return list(S)

/datum/bot_step/paced/await_transfer/access/power/start(datum/bot_brain/bot)
	var/obj/item/card/id/card = bot.card_in_hand()
	if(!card || !bot.owner.dropItemToGround(card))
		return FALSE
	transfer = new(card, null, bot.owner)
	transfer.add_access = add_access
	transfer.access_names = access_names
	give_up_at = world.time + 3 MINUTES
	var/who = bot_find_hop(bot.owner) ? "HoP" : "Captain"
	bot_say(bot.owner, pick(";[who], could I get [access_names] access? Card's at your window.", ";[who], any chance of [access_names] access? My ID's on your desk.", ";[who], I need [access_names] access for a project. Card's at the door."))
	bot_log(bot, "POWER: left [card] for the HoP, for [access_names] access")
	return TRUE

// ---------------------------------------------------------------------------------------------
// Powers
// ---------------------------------------------------------------------------------------------

// An activator only switches on a gene somebody already carries, asleep (dna_injector.dm's activate_mutation()); a mutator puts it
// in whatever they carry. Genetics prints mutators off the genes its console has stored (dna_console.dm's "mutator"). So: a mutator,
// or an activator for a gene this bot has asleep. A powergamer with Genetics' access prints its own at the console; one without asks
// the Geneticist, who prints one and brings it over.

/// The good powers it has.
/datum/bot_brain/proc/power_mutations_had()
	. = 0
	if(!owner.has_dna())
		return
	for(var/datum/mutation/human/M as anything in owner.dna.mutations)
		if(M.quality == POSITIVE)
			.++

/// Whether a power's one this bot could do with: good, and not had already.
/proc/bot_power_wanted_by(mob/living/carbon/human/H, path)
	var/datum/mutation/human/M = GET_INITIALIZED_MUTATION(path)
	return istype(M) && M.quality == POSITIVE && H.has_dna() && !H.dna.get_mutation(path)

/// What an injector would give `who` that they haven't got: the mutation's type, or null.
/proc/bot_injector_gives(obj/item/dnainjector/activator/I, mob/living/carbon/human/who)
	if(!istype(I) || I.used || !who.has_dna())
		return null
	for(var/entry in I.add_mutations)
		var/datum/mutation/human/M = entry
		var/path = istype(M) ? M.type : entry
		if(!ispath(path, /datum/mutation/human) || !bot_power_wanted_by(who, path))
			continue
		if((path in who.dna.mutation_index) || (I.doitanyway && bot_power_stable_with(who, path)))
			return path
	return null

/// Whether a mutator for this leaves them stable: a forced gene costs genetic stability (dna.dm's update_instability()), and under
/// nothing it starts doing them harm. A powergamer keeps a margin.
/proc/bot_power_stable_with(mob/living/carbon/human/who, path)
	var/datum/mutation/human/M = GET_INITIALIZED_MUTATION(path)
	return istype(M) && who.dna.stability - M.instability >= 20

/datum/bot_brain/proc/activator_gives(obj/item/dnainjector/activator/I)
	return bot_injector_gives(I, owner)

/// Every injector it's carrying that would give it something, into its own arm.
/datum/bot_brain/proc/inject_activators()
	if(!owner.has_dna())
		return FALSE
	for(var/obj/item/dnainjector/activator/I in owner.GetAllContents())
		var/path = activator_gives(I)
		if(!path)
			continue
		if(!(I in owner.held_items))
			make_hand_free()
			if(!owner.put_in_hands(I))
				continue
		var/datum/mutation/human/A = GET_INITIALIZED_MUTATION(path)
		I.attack(owner, owner)
		if(owner.dna.get_mutation(path))
			bot_log(src, "POWER: injected [A.name]")
			bot_tally("powergaming: injected a power")
			telemetry_event("power_gained", list("power" = A.name))
			if(prob(50))
				bot_say(owner, pick("Oh yeah. [A.name].", "Now we're talking.", "That's more like it."))
		if(I.used && !QDELETED(I) && (I in owner.held_items))
			owner.dropItemToGround(I) //spent
		return TRUE
	return FALSE

/// The nearest injector lying about (Genetics leaves them by the console) with something in it for `who`.
/proc/bot_injector_for(mob/living/carbon/human/who, datum/bot_brain/looking)
	var/obj/item/dnainjector/activator/best
	var/best_score
	for(var/obj/item/dnainjector/activator/I as anything in bot_instances_of(/obj/item/dnainjector/activator))
		if(QDELETED(I) || !isturf(I.loc) || I.z != who.z || looking.taken_by_another(I))
			continue
		if(looking.gym_run && get_area(I) != get_area(looking.owner))
			continue
		var/path = bot_injector_gives(I, who)
		if(!path)
			continue
		var/wanted = GLOB.bot_power_mutations.Find(path)
		var/score = (wanted ? wanted : 50) * 100 + get_dist(who, I)
		if(!best || score < best_score)
			best = I
			best_score = score
	return best

/// A DNA console with a good power stored on it that `who` hasn't got, and a scanner to print with: list(console, mutation type).
/proc/bot_power_console_for(mob/living/carbon/human/who, datum/bot_brain/looking)
	var/list/best
	var/best_rank
	for(var/obj/machinery/computer/scan_consolenew/C as anything in bot_instances_of(/obj/machinery/computer/scan_consolenew))
		if(QDELETED(C) || C.z != who.z || QDELETED(C.connected) || (C.stat & (NOPOWER|BROKEN)))
			continue
		if(looking.gym_run && get_area(C) != get_area(looking.owner))
			continue
		for(var/datum/mutation/human/A in C.stored_mutations)
			if(!bot_power_wanted_by(who, A.type) || (!(A.type in who.dna.mutation_index) && !bot_power_stable_with(who, A.type)))
				continue
			var/rank = GLOB.bot_power_mutations.Find(A.type) || 50
			if(!best || rank < best_rank)
				best = list(C, A.type)
				best_rank = rank
	return best

/datum/bot_brain/proc/try_power_genes()
	if(!owner.has_dna() || power_mutations_had() >= 3)
		return FALSE
	LAZYSET(power_rests, "genes", world.time + BOT_POWER_RUNG_REST)
	var/obj/item/dnainjector/activator/I = bot_injector_for(owner, src)
	if(I && (gym_run || can_walk_lawfully_to(I)))
		return assign_goal(new /datum/bot_goal/power_injector(owner, I))
	var/list/at_console = bot_power_console_for(owner, src)
	var/obj/machinery/computer/scan_consolenew/C = at_console?[1]
	if(C && (gym_run || can_walk_lawfully_to(C)))
		return assign_goal(new /datum/bot_goal/power_injector(owner, null, C, at_console[2]))
	if(!I && !C)
		return FALSE
	// Behind a door it can't open: the Geneticist's asked, and it waits where it is.
	var/datum/mutation/human/A = GET_INITIALIZED_MUTATION(I ? activator_gives(I) : at_console[2])
	var/where = get_area_name(owner, TRUE)
	if(!call_for(/datum/bot_request_kind/genes, pick(";Genetics, could I get a [A.name] mutator? I'm in [where].", ";Genetics, any chance of [A.name]? I'll be in [where].", ";Genetics, could you sort me out with [A.name]? I'm in [where].")))
		return FALSE
	return assign_goal(new /datum/bot_goal/await_activator)

/// Stood where it said it'd be, for the Geneticist: an injector put down beside it is picked up and used.
/datum/bot_goal/await_activator
	lawful = TRUE
	doing = "waiting for Genetics"

/datum/bot_goal/await_activator/resolve_target(datum/bot_brain/bot)
	target = get_turf(bot.owner)

/datum/bot_goal/await_activator/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/paced/await_activator())
	return list(S)

/datum/bot_step/paced/await_activator
	max_clicks = 3
	var/give_up_at = 0
	var/had = 0

/datum/bot_step/paced/await_activator/start(datum/bot_brain/bot)
	give_up_at = world.time + BOT_POWER_WAIT_FOR_GENES
	had = bot.power_mutations_had()
	return TRUE

/datum/bot_step/paced/await_activator/do_click(datum/bot_brain/bot)
	if(world.time > give_up_at)
		return FALSE
	for(var/obj/item/dnainjector/activator/I in range(1, bot.owner))
		if(isturf(I.loc) && bot.activator_gives(I))
			bot.try_pickup_target(I)
			if(bot.is_carried(I))
				bot.inject_activators()
				return FALSE
	if(bot.inject_activators())
		return FALSE
	wait_for = 2 SECONDS
	return TRUE

/datum/bot_step/paced/await_activator/finish(datum/bot_brain/bot)
	return bot.power_mutations_had() > had ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// "Genetics, could I get Hulk?": the Geneticist takes an injector over, one lying about or one it prints.
/datum/bot_request_kind/genes
	name = "genes"
	jobs = list("Geneticist")
	strong_words = list("activator", "mutator", "superpowers", "hulk", "x-ray", "xray", "telekinesis")
	role_words = list("genetics", "geneticist")
	ack_lines = list("Sure, bringing it over.", "Yeah, I'll bring one.", "Give me a minute, I'll bring it.")
	walks_there = FALSE
	needs_place = FALSE
	doing = "taking somebody a power"
	precedence = 1

/datum/bot_request_kind/genes/attend(datum/bot_brain/bot, datum/bot_request/R)
	var/mob/living/carbon/human/who = R.caller_ref?.resolve()
	if(!istype(who) || who == bot.owner || bot.state != BOT_STATE_WANDER)
		return
	var/obj/item/dnainjector/activator/I = bot_injector_for(who, bot)
	if(I && bot.can_walk_lawfully_to(I))
		bot.assign_goal(new /datum/bot_goal/power_injector(who, I))
		return
	var/list/at_console = bot_power_console_for(who, bot)
	if(at_console && bot.can_walk_lawfully_to(at_console[1]))
		bot.assign_goal(new /datum/bot_goal/power_injector(who, null, at_console[1], at_console[2]))

/// An injector for somebody, this bot or another: picked up where it lies, or printed at a console off a stored gene, and then
/// injected, or taken over to them.
/datum/bot_goal/power_injector
	lawful = TRUE
	doing = "getting somebody some powers"
	var/obj/item/dnainjector/activator/injector
	var/obj/machinery/computer/scan_consolenew/console
	var/mutation
	var/datum/weakref/for_ref

/datum/bot_goal/power_injector/New(mob/living/carbon/human/who, obj/item/dnainjector/activator/I, obj/machinery/computer/scan_consolenew/C, path)
	. = ..()
	for_ref = WEAKREF(who)
	injector = I
	console = C
	mutation = path

/datum/bot_goal/power_injector/resolve_target(datum/bot_brain/bot)
	var/mob/living/carbon/human/who = for_ref?.resolve()
	if(!who || who.stat == DEAD)
		target = null
	else if(injector)
		target = (QDELETED(injector) || injector.used || !isturf(injector.loc)) ? null : injector
	else
		target = (QDELETED(console) || (console.stat & (NOPOWER|BROKEN))) ? null : console

/datum/bot_goal/power_injector/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/move_to(), injector ? new /datum/bot_step/pick_up_litter() : new /datum/bot_step/paced/print_mutator())
	S.steps += for_ref?.resolve() == bot.owner ? new /datum/bot_step/inject_power() : new /datum/bot_step/paced/hand_over_injector()
	return list(S)

/// The console's "mutator" button, with the stored gene: a short wait if it printed one in the last ten seconds, then it's picked up.
/datum/bot_step/paced/print_mutator
	max_clicks = 3

/datum/bot_step/paced/print_mutator/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/power_injector/G = bot.current_goal
	var/obj/machinery/computer/scan_consolenew/C = G?.console
	if(!istype(G) || QDELETED(C) || !bot.owner.Adjacent(C) || G.injector)
		return FALSE
	if(C.injectorready >= world.time)
		wait_for = C.injectorready - world.time + 5
		return TRUE
	var/list/before = list()
	for(var/obj/item/dnainjector/activator/I in C.loc)
		before += I
	bot.human_pause(C)
	usr = bot.owner
	bot.telemetry_ui_action(C, "mutator")
	C.Topic(null, list("task" = "mutator", "path" = "[G.mutation]"))
	for(var/obj/item/dnainjector/activator/I in C.loc)
		if(!(I in before))
			G.injector = I
	if(!G.injector)
		return FALSE
	bot.try_pickup_target(G.injector)
	var/datum/mutation/human/A = GET_INITIALIZED_MUTATION(G.mutation)
	bot_log(bot, "POWER: printed a [A.name] mutator")
	bot_tally("mutators printed")
	return FALSE

/datum/bot_step/paced/print_mutator/finish(datum/bot_brain/bot)
	var/datum/bot_goal/power_injector/G = bot.current_goal
	return istype(G) && G.injector && bot.is_carried(G.injector) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/datum/bot_step/inject_power/execute(datum/bot_brain/bot)
	return bot.inject_activators() ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// Over to whoever asked (they may have moved), and down at their feet with a word.
/datum/bot_step/paced/hand_over_injector
	max_clicks = 60

/datum/bot_step/paced/hand_over_injector/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/power_injector/G = bot.current_goal
	var/mob/living/who = G?.for_ref?.resolve()
	var/obj/item/dnainjector/activator/I = G?.injector
	if(!istype(G) || !who || QDELETED(I) || !bot.is_carried(I) || who.z != bot.owner.z)
		return FALSE
	if(get_dist(bot.owner, who) > 1)
		if(bot.pursuing_kind != "hand_over" || bot.pursue_target != who)
			bot.pursue(who, "hand_over", force = TRUE)
		wait_for = 1 SECONDS
		return TRUE
	bot.stop_pursuit()
	if(!bot.ready_in_hand(I))
		return FALSE
	bot.human_pause(who)
	bot.owner.dropItemToGround(I)
	bot_say(bot.owner, pick("There you go, [who.name].", "Here you are, [who.name]. Mind the radiation.", "One [I.name]. Don't do anything stupid with it."))
	bot_log(bot, "brought [who] [I]")
	bot_tally("injectors handed over")
	G.injector = null
	return FALSE

/datum/bot_step/paced/hand_over_injector/finish(datum/bot_brain/bot)
	var/datum/bot_goal/power_injector/G = bot.current_goal
	return istype(G) && !G.injector ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Heals
// ---------------------------------------------------------------------------------------------

/// Brute and burn patches it has on it, as list(brute, burn).
/datum/bot_brain/proc/power_patches()
	var/brute = 0
	var/burn = 0
	for(var/obj/item/reagent_containers/pill/patch/P in owner.GetAllContents())
		if(istype(P, /obj/item/reagent_containers/pill/patch/styptic))
			brute++
		else if(istype(P, /obj/item/reagent_containers/pill/patch/silver_sulf))
			burn++
		else if(istype(P, /obj/item/reagent_containers/pill/patch/synthflesh))
			brute++
			burn++
	return list(brute, burn)

/datum/bot_brain/proc/try_power_heals()
	var/list/have = power_patches()
	if(have[1] >= BOT_POWER_PATCHES && have[2] >= BOT_POWER_PATCHES)
		return FALSE
	var/obj/machinery/vending/V = find_nanomed()
	if(!V || !can_afford_from(V, /obj/item/reagent_containers/pill/patch/styptic)) //bot_knowledge.dm: the Plus charges, and broke is broke
		LAZYSET(power_rests, "heals", world.time + BOT_POWER_RUNG_REST)
		return FALSE
	LAZYSET(power_rests, "heals", world.time + BOT_POWER_RUNG_REST / 2)
	return assign_goal(new /datum/bot_goal/patch_up/power(V))

/datum/bot_goal/patch_up/power
	doing = "stocking up on patches"
	var/obj/machinery/vending/vendor

/datum/bot_goal/patch_up/power/New(obj/machinery/vending/V)
	. = ..()
	vendor = V

/datum/bot_goal/patch_up/power/resolve_target(datum/bot_brain/bot)
	target = QDELETED(vendor) ? null : vendor

/datum/bot_goal/patch_up/power/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/patch_up/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/vend_patches/power())
	return list(S)

/datum/bot_goal/patch_up/power/on_success(datum/bot_brain/bot)
	return

/// A couple of each kind the NanoMed has, up to what it likes to carry.
/datum/bot_step/vend_patches/power/execute(datum/bot_brain/bot)
	var/obj/machinery/vending/V = bot.current_goal?.target
	if(!istype(V) || !bot.owner.Adjacent(V))
		return GOAL_STEP_FAIL
	var/got = 0
	var/list/have = bot.power_patches()
	for(var/kind in list(/obj/item/reagent_containers/pill/patch/styptic, /obj/item/reagent_containers/pill/patch/silver_sulf))
		var/want = BOT_POWER_PATCHES - (kind == /obj/item/reagent_containers/pill/patch/styptic ? have[1] : have[2])
		for(var/i in 1 to want)
			var/obj/item/patch = bot.vend_from(V, kind)
			if(!patch || !bot.try_pickup_target(patch))
				break
			bot.put_away(patch, allow_equip = FALSE)
			got++
	bot_log(bot, "POWER: got [got] patches out of [V]")
	return got ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// Hurt in a fight with a patch on it: a step out of it, the patch on (three seconds, self_delay), and back in when they come on again,
/// instead of running for Medbay. The run's for when the patches are gone. try_run_for_it()'s TRUE is "the fight's off for now".
/datum/bot_brain/try_run_for_it()
	if(is_powergamer() && attacker && world.time >= next_power_heal && owner.health <= owner.maxHealth * health_to_run_at() && owner.health > HEALTH_THRESHOLD_CRIT + 20 && pick_treatment_item(owner, TRUE))
		next_power_heal = world.time + BOT_POWER_HEAL_GAP
		var/mob/living/from = attacker
		state_before_combat = null
		drop_goals("patching up")
		disengage_combat("patching up mid-fight")
		bot_log(src, "POWER: patching up in the middle of a fight with [from]")
		bot_tally("powergaming: patched up mid-fight")
		telemetry_event("power_heal", list("against" = "[from]"))
		assign_goal(new /datum/bot_goal/self_heal())
		return TRUE
	return ..()

// ---------------------------------------------------------------------------------------------
// A gun
// ---------------------------------------------------------------------------------------------

/datum/bot_brain/proc/try_power_gun()
	if(find_carried_tool(/obj/item/gun))
		return FALSE
	LAZYSET(power_rests, "gun", world.time + BOT_POWER_RUNG_REST)
	var/datum/techweb/station = SSresearch.science_tech
	for(var/id in GLOB.bot_power_gun_designs)
		if(!station?.researched_designs[id])
			continue
		var/datum/design/D = SSresearch.techweb_design_by_id(id)
		if(!D)
			continue
		var/obj/machinery/rnd/production/L = lathe_for(D)
		if(L)
			return assign_goal(new /datum/bot_goal/print_design/power(L, D, 1))
	return FALSE

/// A lathe it can walk to that will make this, with the materials in it.
/datum/bot_brain/proc/lathe_for(datum/design/D)
	for(var/obj/machinery/rnd/production/L as anything in bot_instances_of(/obj/machinery/rnd/production))
		if(QDELETED(L) || L.z != owner.z || (L.stat & (BROKEN|NOPOWER)) || L.busy || !(D.build_type & L.allowed_buildtypes))
			continue
		if(!isnull(L.allowed_department_flags) && !(D.departmental_flags & L.allowed_department_flags))
			continue
		if(L.requires_console && !L.linked_console)
			continue
		var/datum/component/material_container/stores = L.materials?.mat_container
		if(!stores || !stores.has_materials(D.materials))
			continue
		if(gym_run ? get_area(L) == get_area(owner) : can_walk_lawfully_to(L))
			return L
	return null

/datum/bot_goal/print_design/power
	doing = "printing myself something"
	chain_duty = null

/datum/bot_goal/print_design/power/on_success(datum/bot_brain/bot)
	var/obj/machinery/rnd/production/L = target
	for(var/obj/item/gun/G in get_turf(L))
		if(istype(G, design.build_path))
			bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, take_print), G))
			return

/datum/bot_goal/print_design/power/on_give_up(datum/bot_brain/bot)
	return

/datum/bot_brain/proc/take_print(obj/item/I)
	if(!QDELETED(I) && isturf(I.loc) && assign_goal(new /datum/bot_goal/take_item/exact(I)))
		bot_log(src, "POWER: printed [I], picking it up")
		bot_tally("powergaming: printed a gun")

#undef BOT_POWER_RUNG_REST
#undef BOT_POWER_ACCESS_REST
#undef BOT_POWER_HEAL_GAP
#undef BOT_POWER_WAIT_FOR_GENES
#undef BOT_POWER_PATCHES
