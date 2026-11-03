// Bot Gym scenarios for Genetics (goals/genetics.dm).
//
// Layout letters used here: Y a DNA scanner, G its console (placed after the scanner, which it finds next to it as it starts),
// q a monkey.

/datum/bot_scenario/duty/genetics
	duty_type = /datum/bot_duty/geneticist
	job = "Geneticist"
	time_limit = 240 SECONDS

/datum/bot_scenario/duty/genetics/setup()
	for(var/turf/T in markers["Y"])
		place("Y", new /obj/machinery/dna_scannernew(T))
	for(var/turf/T in markers["G"])
		var/obj/machinery/computer/scan_consolenew/C = new(T)
		C.jokerready = world.time + 20 MINUTES //no joker: the pairs are worked out and guessed at
		place("G", C)
	for(var/turf/T in markers["q"])
		place("q", new /mob/living/carbon/monkey(T))

/datum/bot_scenario/duty/genetics/gene
	name = "geneticist works out a gene"
	desc = "A DNA scanner and its console, and a monkey loose in the room. The geneticist puts the monkey in the scanner, makes it a person (only a person carries a gene here) and fills in a gene's hidden letters at the console a click at a time - the half of a pair that shows gives the other away, a pair with both hidden is a guess - and stores the gene once it comes on."
	layout = list(
		"##########",
		"#B.......#",
		"#..YG....#",
		"#.....q..#",
		"##########")

/datum/bot_scenario/duty/genetics/gene/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/machinery/computer/scan_consolenew/C = locate() in arena_area
	var/obj/machinery/dna_scannernew/S = locate() in arena_area
	if(!C || !S)
		fail_reason = "the console or the scanner is gone"
		return BOT_GYM_FAIL
	if(!LAZYLEN(C.stored_mutations))
		return BOT_GYM_PENDING
	if(!ishuman(S.occupant))
		fail_reason = "a gene stored with no person in the scanner"
		return BOT_GYM_FAIL
	var/datum/mutation/human/stored = C.stored_mutations[1]
	if(stored.type == RACEMUT)
		fail_reason = "it stored the monkey gene"
		return BOT_GYM_FAIL
	if(world.time - start_time < 10 SECONDS)
		fail_reason = "a gene in [(world.time - start_time) / 10]s: too quick to have been clicked through"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS
