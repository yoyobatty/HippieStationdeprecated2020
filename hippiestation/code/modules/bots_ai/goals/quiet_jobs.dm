// The jobs that used to do nothing but sit at a desk.
//
//  - The Lawyer goes down to the cells and sees whoever's in them, and takes it up with Security on the radio.
//  - The Curator reads, a book off the shelf at a time, and has opinions.
//  - The Virologist keeps an eye out for anybody sick. With the Geneticist, it's also a pair of hands in Medbay when it's needed
//    (is_medical_job(), goals/treat_patient.dm): neither has anything else that's theirs yet. Genetics and the pandemic have no bot
//    code, and a clone wouldn't have a brain to go with it.

// ---------------------------------------------------------------------------------------------
// Lawyer
// ---------------------------------------------------------------------------------------------

GLOBAL_LIST_INIT(bot_lawyer_lines, list(
	"I'm your lawyer. Don't say anything to anybody.",
	"Don't worry, I've got you. What did they tell you you did?",
	"You've got rights, whatever they told you. Sit tight.",
	"I'll see what I can do about your sentence.",
))

/datum/bot_brain
	/// The people it's already been to see.
	var/list/clients_seen
	var/books_read = 0

/// Somebody locked up that it hasn't been to see, and the timer on their cell.
/datum/bot_brain/proc/find_client()
	for(var/obj/machinery/door_timer/T as anything in bot_instances_of(/obj/machinery/door_timer))
		if(!T.timing || T.z != owner.z)
			continue
		for(var/turf/cell as anything in bot_get_cell_interior(T))
			for(var/mob/living/carbon/human/H in cell)
				if(H.stat != DEAD && !(WEAKREF(H) in clients_seen))
					return list(T, H)
	return null

/datum/bot_duty/lawyer
	name = "seeing clients"
	tier = BOT_DUTY_URGENT
	jobs = list("Lawyer")
	priority = 5
	interval_min = 300
	interval_max = 900

/datum/bot_duty/lawyer/try_start(datum/bot_brain/bot)
	var/list/found = bot.find_client()
	if(!found || !bot.can_walk_lawfully_to(found[1]))
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/see_client(found[1], found[2]))

/datum/bot_goal/see_client
	lawful = TRUE
	doing = "seeing a client"
	var/mob/living/carbon/human/client

/datum/bot_goal/see_client/New(obj/machinery/door_timer/T, mob/living/carbon/human/H)
	. = ..()
	target = T
	client = H

/datum/bot_goal/see_client/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/advise_client())
	return list(S)

/datum/bot_step/paced/advise_client
	max_clicks = 3

/datum/bot_step/paced/advise_client/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/see_client/G = bot.current_goal
	var/mob/living/carbon/human/H = G?.client
	if(QDELETED(H))
		return FALSE
	switch(clicks)
		if(0)
			LAZYADD(bot.clients_seen, WEAKREF(H))
			bot.owner.face_atom(H)
			bot_say(bot.owner, pick(GLOB.bot_lawyer_lines))
			bot_log(bot, "seeing [H] in the cells")
			bot_tally("clients seen")
		if(1)
			var/datum/bot_wanted/W = bot_get_wanted_entry(H)
			bot_say(bot.owner, ";Warden, it's the Lawyer. My client [H.real_name] is in for [W?.crime ? lowertext(W.crime) : "what, exactly"]. I'd like that looked at.")
			bot_news("the Lawyer's taken on [H.real_name]", H)
		if(2)
			return FALSE
	wait_for = 8 SECONDS
	clicks++
	return TRUE

// ---------------------------------------------------------------------------------------------
// Curator
// ---------------------------------------------------------------------------------------------

GLOBAL_LIST_INIT(bot_book_remarks, list(
	"Now this is a good one.",
	"Whoever wrote this has never been on a station.",
	"Hm. Interesting.",
	"Half these pages are missing.",
	"You know, nobody ever comes in here.",
	"I've read worse.",
	"Somebody's been folding the corners again.",
))

/datum/bot_duty/curator
	name = "reading"
	tier = BOT_DUTY_URGENT
	jobs = list("Curator")
	priority = 5
	interval_min = 1200
	interval_max = 2400

/datum/bot_duty/curator/try_start(datum/bot_brain/bot)
	var/obj/structure/bookcase/shelf = bot.find_full_shelf()
	return shelf ? bot.assign_goal(new /datum/bot_goal/read_a_book(shelf)) : FALSE

/// The nearest bookcase with anything on it, in the library.
/datum/bot_brain/proc/find_full_shelf()
	var/obj/structure/bookcase/best
	for(var/obj/structure/bookcase/B as anything in bot_instances_of(/obj/structure/bookcase))
		if(QDELETED(B) || B.z != owner.z || !istype(get_area(B), /area/library) || !(locate(/obj/item/book) in B))
			continue
		if((!best || get_dist(owner, B) < get_dist(owner, best)) && can_walk_lawfully_to(B))
			best = B
	return best

/datum/bot_goal/read_a_book
	lawful = TRUE
	doing = "reading"

/datum/bot_goal/read_a_book/New(obj/structure/bookcase/B)
	. = ..()
	target = B

/datum/bot_goal/read_a_book/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/read_book())
	return list(S)

/// Off the shelf, a while with it, and back.
/datum/bot_step/paced/read_book
	max_clicks = 3
	var/obj/item/book/book

/datum/bot_step/paced/read_book/start(datum/bot_brain/bot)
	var/obj/structure/bookcase/shelf = bot.current_goal?.target
	var/list/books = list()
	for(var/obj/item/book/B in shelf)
		books += B
	if(!length(books) || !bot.owner.Adjacent(shelf))
		return FALSE
	book = pick(books)
	bot.make_hand_free()
	book.forceMove(bot.owner.drop_location())
	shelf.update_icon()
	return bot.owner.put_in_hands(book)

/datum/bot_step/paced/read_book/do_click(datum/bot_brain/bot)
	var/obj/structure/bookcase/shelf = bot.current_goal?.target
	if(QDELETED(book) || QDELETED(shelf))
		return FALSE
	switch(clicks)
		if(0)
			bot_log(bot, "reading [book]")
			bot.books_read++
			bot_tally("books read")
			wait_for = 30 SECONDS
		if(1)
			if(prob(50))
				bot_say(bot.owner, pick(GLOB.bot_book_remarks))
			wait_for = 15 SECONDS
		if(2)
			if(bot.owner.Adjacent(shelf))
				bot.owner.temporarilyRemoveItemFromInventory(book)
				book.forceMove(shelf)
				shelf.update_icon()
			return FALSE
	clicks++
	return TRUE

// ---------------------------------------------------------------------------------------------
// Virologist
// ---------------------------------------------------------------------------------------------

GLOBAL_VAR_INIT(bot_outbreak_called, 0)

/// Somebody in sight who's visibly sick: a word with them, and word on the radio the first time. What a health analyzer would say,
/// and a Virologist has one.
/datum/bot_duty/virologist
	name = "looking out for anybody sick"
	tier = BOT_DUTY_URGENT
	jobs = list("Virologist")
	priority = 4
	interval_min = 300
	interval_max = 600

/datum/bot_duty/virologist/try_start(datum/bot_brain/bot)
	for(var/mob/living/carbon/human/H in view(BOT_SIGHT_RANGE, bot.owner))
		if(H == bot.owner || H.stat == DEAD)
			continue
		for(var/datum/disease/D as anything in H.diseases)
			if(D.visibility_flags & HIDDEN_SCANNER)
				continue
			bot_say(bot.owner, "[H.first_name()], you've got [D.name]. Come by Virology.")
			bot_log(bot, "noticed [H] has [D.name]")
			bot_tally("sick crew noticed")
			if(world.time > GLOB.bot_outbreak_called + 10 MINUTES)
				GLOB.bot_outbreak_called = world.time
				bot_say(bot.owner, ";There's something going round. Wash your hands, and come to Virology if you feel ill.")
				bot_news("there's something going round, Virology says", H)
			return FALSE
	return FALSE
