// Genetics: what a Geneticist does with the DNA scanner and its console. A monkey from the pen goes in the scanner, one of its genes
// is worked out at the console a letter at a time, kept once it shows, and anything good gets an activator printed: a powergamer
// takes it themselves, anybody else offers it round Medical.
//
// The gene is read off the screen the way a player reads it: it comes in pairs that have to be A-T or G-C, with some letters hidden
// (X). One half showing gives the other away; both hidden is a guess, or the console's joker (one free reveal every 20 minutes), and
// a filled-in gene that doesn't come on means one of the guesses was wrong. Changing a letter on the console asks for it in an
// input(), which a bot has nobody to answer, so bot_edit_gene() makes the same change the menu would.

/datum/bot_duty/geneticist
	name = "genetics research"
	jobs = list("Geneticist")
	priority = 3
	interval_min = 600
	interval_max = 1200

/datum/bot_duty/geneticist/try_start(datum/bot_brain/bot)
	var/obj/machinery/computer/scan_consolenew/console = bot.find_genetics_console()
	return console ? bot.assign_goal(new /datum/bot_goal/research_genes(console)) : FALSE

/// The nearest DNA console with a scanner on it, and something to put in the scanner.
/datum/bot_brain/proc/find_genetics_console()
	var/obj/machinery/computer/scan_consolenew/best
	for(var/obj/machinery/computer/scan_consolenew/C as anything in bot_instances_of(/obj/machinery/computer/scan_consolenew))
		if(QDELETED(C) || C.z != owner.z || QDELETED(C.connected) || (C.stat & (NOPOWER|BROKEN)))
			continue
		if(!genetics_subject(C.connected) || taken_by_another(C))
			continue
		if((!best || get_dist(owner, C) < get_dist(owner, best)) && can_walk_lawfully_to(C))
			best = C
	return best

/// Who goes in the scanner: whoever's in it already while there's still something in them to work on, or the nearest monkey loose in
/// the room. Somebody worked through is let out for a fresh one: going back to them was 25-32 give-ups a shift.
/datum/bot_brain/proc/genetics_subject(obj/machinery/dna_scannernew/scanner)
	var/mob/living/carbon/inside = scanner.occupant
	if(istype(inside) && inside.stat != DEAD && bot_genes_left(inside, scanner))
		return inside
	var/list/monkeys = list()
	for(var/mob/living/carbon/monkey/M in range(10, scanner))
		if(M.stat == DEAD || M.buckled || M.pulledby || !isturf(M.loc))
			continue
		monkeys[M] = get_dist(scanner, M)
	sortTim(monkeys, GLOBAL_PROC_REF(cmp_numeric_asc), TRUE)
	for(var/mob/living/carbon/monkey/M as anything in monkeys)
		if(can_walk_lawfully_to(M)) //one behind the pen's glass from here isn't one anybody can grab (MetaStation: 29 tries in a shift)
			return M
	return null

/// Whether there's a gene in somebody still to work out: a monkey always has (it'll be made a person), a person until every gene
/// in them is showing, stored or already known to the station.
/proc/bot_genes_left(mob/living/carbon/C, obj/machinery/dna_scannernew/scanner)
	if(ismonkey(C))
		return TRUE
	var/obj/machinery/computer/scan_consolenew/console = scanner.locate_computer(/obj/machinery/computer/scan_consolenew)
	for(var/path in C.dna?.mutation_index)
		if(path == RACEMUT || C.dna.get_mutation(path) || console?.get_valid_mutation(path) || (path in console?.stored_research?.discovered_mutations))
			continue
		return TRUE
	return FALSE

/datum/bot_goal/research_genes
	lawful = TRUE
	exclusive = TRUE //one at a console: two at once fought over the scanner
	doing = "working on genes"
	var/obj/machinery/dna_scannernew/scanner
	var/mob/living/carbon/subject

/datum/bot_goal/research_genes/New(obj/machinery/computer/scan_consolenew/console)
	. = ..()
	target = console

/datum/bot_goal/research_genes/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/computer/scan_consolenew/console = target
	if(QDELETED(console) || QDELETED(console.connected))
		target = null
		return
	scanner = console.connected
	subject = bot.genetics_subject(scanner)
	if(!subject)
		target = null

/datum/bot_goal/research_genes/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list()
	if(scanner.occupant != subject)
		var/datum/bot_step/move_to/to_subject = new
		to_subject.step_target = subject
		var/datum/bot_step/move_to/to_scanner = new
		to_scanner.step_target = scanner
		S.steps += list(to_subject, new /datum/bot_step/paced/grab_subject(), to_scanner, new /datum/bot_step/load_genetics_scanner())
		if(scanner.occupant)
			S.steps.Insert(1, new /datum/bot_step/move_to(), new /datum/bot_step/empty_scanner()) //over to the console, and the one done with goes out first
	S.steps += list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/work_gene())
	return list(S)

/datum/bot_goal/research_genes/on_give_up(datum/bot_brain/bot)
	if(bot.owner.pulling == subject)
		bot.owner.stop_pulling()

/// Hold of the monkey, after it round the pen for a few seconds if it won't keep still: they wander off a tile as you get there.
/datum/bot_step/paced/grab_subject
	max_clicks = 8

/datum/bot_step/paced/grab_subject/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/research_genes/G = bot.current_goal
	var/mob/living/carbon/C = G?.subject
	if(!istype(G) || QDELETED(C) || C.stat == DEAD || bot.owner.pulling == C)
		return FALSE
	wait_for = 4
	clicks++
	if(bot.owner.Adjacent(C))
		bot.owner.start_pulling(C)
		return bot.owner.pulling != C //start_pulling() returns nothing useful (treat_patient.dm): look, and try again if not
	if(get_dist(bot.owner, C) > 4)
		return FALSE
	var/turf/next = get_step_towards(bot.owner, C)
	if(next)
		bot.owner.Move(next, get_dir(bot.owner, next))
	return TRUE

/datum/bot_step/paced/grab_subject/finish(datum/bot_brain/bot)
	var/datum/bot_goal/research_genes/G = bot.current_goal
	return istype(G) && bot.owner.pulling == G.subject ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// The scanner opened from its console on somebody done with: they step out of it.
/datum/bot_step/empty_scanner/execute(datum/bot_brain/bot)
	var/datum/bot_goal/research_genes/G = bot.current_goal
	var/obj/machinery/computer/scan_consolenew/console = G?.target
	var/obj/machinery/dna_scannernew/S = G?.scanner
	if(!istype(G) || QDELETED(S) || QDELETED(console))
		return GOAL_STEP_FAIL
	if(!S.occupant || S.occupant == G.subject)
		return GOAL_STEP_SUCCESS
	if(!bot.owner.Adjacent(S) && !bot.owner.Adjacent(console))
		return GOAL_STEP_FAIL
	S.open_machine()
	bot_log(bot, "let the last one out of [S]")
	return S.occupant ? GOAL_STEP_FAIL : GOAL_STEP_SUCCESS

/datum/bot_step/load_genetics_scanner/execute(datum/bot_brain/bot)
	var/datum/bot_goal/research_genes/G = bot.current_goal
	var/obj/machinery/dna_scannernew/S = G?.scanner
	var/mob/living/carbon/C = G?.subject
	if(!istype(G) || QDELETED(S) || QDELETED(C))
		return GOAL_STEP_FAIL
	if(S.occupant)
		return S.occupant == C ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(S) || (bot.owner.pulling != C && !bot.owner.Adjacent(C)))
		return GOAL_STEP_FAIL
	if(!S.state_open)
		S.open_machine()
	S.MouseDrop_T(C, bot.owner) //the drag onto it a player does
	bot.owner.stop_pulling()
	if(S.occupant != C)
		return GOAL_STEP_FAIL
	bot_log(bot, "put [C] in [S]")
	return GOAL_STEP_SUCCESS

/// At the console: one gene off the subject, a letter a click. Only a person can carry a gene here (on_acquiring() wants a human), so
/// a monkey is made one first, the way geneticists do it: its monkey gene broken, and the scanner opened and shut on what climbs out.
/datum/bot_step/paced/work_gene
	max_clicks = 50
	var/obj/machinery/computer/scan_consolenew/console
	var/mutation
	/// Pairs with both letters hidden, by the position of their first letter as text -> which of the four it's trying (1 to 4)
	var/list/guessed
	var/stored = FALSE

/datum/bot_step/paced/work_gene/start(datum/bot_brain/bot)
	console = bot.current_goal?.target
	var/datum/bot_goal/research_genes/G = bot.current_goal
	if(!istype(console) || !istype(G) || !bot.owner.Adjacent(console) || console.get_viable_occupant() != G.subject)
		return FALSE
	stored = FALSE
	if(ismonkey(G.subject))
		mutation = RACEMUT
		bot_log(bot, "making [G.subject] a person to work on")
		return TRUE
	return pick_gene(bot)

/// The gene to work on: one it was in the middle of first, then the one with the fewest pairs to guess at, what anybody looking at
/// the screen picks by. One it filled in wrong and lost track of (called away mid-gene, before this was kept) is left alone: it reads
/// as all there and won't come on, and it went back to one of those every minute.
/datum/bot_step/paced/work_gene/proc/pick_gene(datum/bot_brain/bot)
	var/datum/bot_goal/research_genes/G = bot.current_goal
	mutation = null
	guessed = null
	var/datum/dna/D = G.subject.dna
	var/fewest
	var/list/easiest = list()
	for(var/path in D.mutation_index)
		if(path == RACEMUT || D.get_mutation(path) || console.get_valid_mutation(path) || (path in console.stored_research?.discovered_mutations))
			continue //one showing is done, one stored has been, one the station knows already has been worked out
		var/sequence = D.mutation_index[path]
		var/list/remembered = LAZYACCESS(bot.gene_guesses, "[REF(G.subject)]|[path]")
		var/hidden = bot_gene_hidden(sequence)
		if(!hidden && !remembered)
			continue
		var/blind = bot_gene_blind_pairs(sequence)
		var/score = remembered ? -1 : blind * 100 + hidden //the fewest guesses, then the fewest letters to fill
		if(blind > 2)
			score += 10000 //64 combinations and up: only if there's nothing else
		if(isnull(fewest) || score < fewest)
			fewest = score
			easiest = list(path)
		else if(score == fewest)
			easiest += path
	if(!length(easiest))
		return FALSE
	mutation = pick(easiest)
	var/key = "[REF(G.subject)]|[mutation]"
	guessed = LAZYACCESS(bot.gene_guesses, key)
	if(!guessed)
		guessed = list()
		LAZYSET(bot.gene_guesses, key, guessed) //the same list: what it guesses from here is kept if it's called away
	bot_log(bot, "[fewest < 0 ? "back on" : "working out"] a gene on [G.subject], [bot_gene_blind_pairs(D.mutation_index[mutation])] pair\s to guess at")
	return TRUE

/datum/bot_brain
	/// "[REF(subject)]|[gene]" -> the pairs guessed at on it (work_gene's guessed), kept across being called away
	var/list/gene_guesses

/// A monkey's monkey gene broken: it climbs out of itself a person, inside the scanner but not in it as the console sees it, so the
/// scanner is opened and shut on it.
/datum/bot_step/paced/work_gene/proc/humanize_click(datum/bot_brain/bot)
	var/datum/bot_goal/research_genes/G = bot.current_goal
	var/obj/machinery/dna_scannernew/S = console.connected
	if(ismonkey(G.subject) && !QDELETED(G.subject))
		if(G.subject.dna.is_gene_active(RACEMUT)) //and not broken already, mid-change: a second edit would put it back
			var/sequence = G.subject.dna.mutation_index[RACEMUT]
			console.bot_edit_gene(bot.owner, RACEMUT, 1, bot_gene_complement(copytext(sequence, 1, 2))) //any wrong letter breaks it
		return TRUE
	var/mob/living/carbon/human/person = locate() in S
	if(!person)
		person = locate() in get_turf(S)
	if(!person || person.stat == DEAD)
		return FALSE
	usr = bot.owner
	if(S.state_open)
		console.Topic(null, list("task" = "toggleopen"))
	else
		console.Topic(null, list("task" = "toggleopen")) //out
		console.Topic(null, list("task" = "toggleopen")) //and in
	if(S.occupant != person)
		return FALSE
	G.subject = person
	bot_log(bot, "[person] is a person now")
	bot_tally("monkeys made people")
	return pick_gene(bot)

GLOBAL_LIST_INIT(bot_gene_pairs, list("AT", "TA", "GC", "CG"))

/// Letters hidden in a gene.
/proc/bot_gene_hidden(sequence)
	. = 0
	for(var/i in 1 to length(sequence))
		if(copytext(sequence, i, i + 1) == "X")
			.++

/// Pairs in a gene with both letters hidden.
/proc/bot_gene_blind_pairs(sequence)
	. = 0
	for(var/i in 1 to length(sequence) step 2)
		if(copytext(sequence, i, i + 2) == "XX")
			.++

/datum/bot_step/paced/work_gene/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/research_genes/G = bot.current_goal
	if(!istype(G) || QDELETED(console) || !bot.owner.Adjacent(console))
		return FALSE
	wait_for = rand(12, 24) //a letter at a time through the console's menu
	clicks++
	bot.owner.face_atom(console)
	bot.telemetry_event("click", list("target" = "[console]", "target_type" = "scan_consolenew")) //a click like any other (Bot Shift took a minute of them for standing still)
	if(mutation == RACEMUT)
		return humanize_click(bot)
	if(console.get_viable_occupant() != G.subject)
		return FALSE
	var/datum/dna/D = G.subject.dna
	if(D.get_mutation(mutation)) //it's come on
		var/datum/mutation/human/A = GET_INITIALIZED_MUTATION(mutation)
		if(!stored)
			console.discover(mutation) //what looking at it on the screen does
			usr = bot.owner
			console.Topic(null, list("task" = "savemut", "path" = "[mutation]"))
			stored = TRUE
			LAZYREMOVE(bot.gene_guesses, "[REF(G.subject)]|[mutation]")
			bot_log(bot, "found [A.name] and stored it")
			bot_tally("genes worked out")
			return TRUE
		if(A.quality == POSITIVE)
			bot.print_activator(console, mutation)
		return FALSE
	var/sequence = D.mutation_index[mutation]
	var/at = findtext(sequence, "X")
	if(!at)
		// Filled in and not on: one of the guesses is wrong. Through them in order, like counting, a pair a click.
		var/carry = TRUE
		for(var/key in guessed)
			if(!carry)
				break
			guessed[key] = guessed[key] % 4 + 1
			carry = guessed[key] == 1
			bot_set_gene_pair(bot, text2num(key), GLOB.bot_gene_pairs[guessed[key]])
		if(carry)
			bot_log(bot, "tried every guess at [GET_INITIALIZED_MUTATION(mutation)] and it won't come on")
			LAZYREMOVE(bot.gene_guesses, "[REF(G.subject)]|[mutation]")
			return FALSE
		return TRUE
	var/partner = (at % 2) ? at + 1 : at - 1
	var/other = copytext(sequence, partner, partner + 1)
	if(other != "X")
		console.bot_edit_gene(bot.owner, mutation, at, bot_gene_complement(other))
		return TRUE
	var/first = min(at, partner)
	if(console.jokerready < world.time)
		var/truth = GET_SEQUENCE(mutation)
		console.jokerready = world.time + 12000 - 1800 * (console.connected.precision_coeff - 1) //JOKER_TIMEOUT, JOKER_UPGRADE
		bot_log(bot, "used the joker on a pair")
		bot_set_gene_pair(bot, first, copytext(truth, first, first + 2))
		return TRUE
	guessed["[first]"] = 1 //by text: a number would be a place in the list
	bot_set_gene_pair(bot, first, GLOB.bot_gene_pairs[1])
	return TRUE

/datum/bot_step/paced/work_gene/proc/bot_set_gene_pair(datum/bot_brain/bot, first, pair)
	console.bot_edit_gene(bot.owner, mutation, first, copytext(pair, 1, 2))
	console.bot_edit_gene(bot.owner, mutation, first + 1, copytext(pair, 2, 3))

/datum/bot_step/paced/work_gene/finish(datum/bot_brain/bot)
	return stored ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/proc/bot_gene_complement(letter)
	switch(letter)
		if("A")
			return "T"
		if("T")
			return "A"
		if("G")
			return "C"
		if("C")
			return "G"

/// An activator for a good gene: a powergamer takes it, anybody else offers it round.
/datum/bot_brain/proc/print_activator(obj/machinery/computer/scan_consolenew/console, mutation)
	if(console.injectorready >= world.time)
		return
	var/list/before = list()
	for(var/obj/item/dnainjector/activator/I in console.loc)
		before += I
	usr = owner
	console.Topic(null, list("task" = "activator", "path" = "[mutation]"))
	var/obj/item/dnainjector/activator/made
	for(var/obj/item/dnainjector/activator/I in console.loc)
		if(!(I in before))
			made = I
	if(!made)
		return
	var/datum/mutation/human/A = GET_INITIALIZED_MUTATION(mutation)
	bot_log(src, "printed a [A.name] activator")
	if(playstyle == BOT_STYLE_POWERGAMER && owner.has_dna())
		make_hand_free()
		if(owner.put_in_hands(made))
			made.attack(owner, owner)
			bot_tally("geneticists who took a power")
			bot_say(owner, pick("Oh, that's good.", "Now we're talking.", "Don't mind if I do."))
		return
	bot_say(owner, ":m Got a [A.name] activator in Genetics, if anybody wants it.")

/// The console's "pulsegene" edit with the letter chosen for it: its menu asks in an input(), and a bot has nobody to answer that. The
/// same change, the same bit of radiation, the same check that a gene has come on.
/obj/machinery/computer/scan_consolenew/proc/bot_edit_gene(mob/user, path, num, new_gene)
	var/mob/living/carbon/occupant = get_viable_occupant()
	if(!occupant || !connected || !(path in occupant.dna.mutation_index))
		return FALSE
	var/sequence = GET_GENE_STRING(path, occupant.dna)
	sequence = copytext_char(sequence, 1, num) + new_gene + copytext_char(sequence, num + 1)
	occupant.dna.mutation_index[path] = sequence
	occupant.radiation += 1 / connected.damage_coeff //RADIATION_STRENGTH_MULTIPLIER
	occupant.domutcheck()
	add_fingerprint(user)
	return TRUE
