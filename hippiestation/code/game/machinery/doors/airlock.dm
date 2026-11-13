#define COOLDOWN_TIME 10
#define EASTEREGG_CHANCE 2

/obj/machinery/door/airlock
	doorOpen = 'hippiestation/sound/machines/airlock.ogg'
	doorClose = 'hippiestation/sound/machines/airlock.ogg'
	doorDeni = 'hippiestation/sound/machines/denied.ogg'
	var/request_cooldown = 0 //To prevent spamming requests for the AI to open
	var/easteregg_triggered = FALSE
	var/easteregg_doorOpen = 'hippiestation/sound/machines/airlockopen_doom.ogg'
	var/easteregg_doorClose = 'hippiestation/sound/machines/airlockclose_doom.ogg'

/obj/machinery/door/airlock/open(forced = 0)
	. = ..()
	if (prob(EASTEREGG_CHANCE))
		easteregg_triggered = TRUE
		doorOpen = easteregg_doorOpen
		doorClose = easteregg_doorClose

/obj/machinery/door/airlock/close(forced = 0)
	. = ..()
	// Reset the sounds
	if (easteregg_triggered)
		easteregg_triggered = FALSE
		doorOpen = initial(doorOpen)
		doorClose = initial(doorClose)

	return .

/obj/machinery/door/airlock/bananium
	doorClose = 'sound/items/bikehorn.ogg'

/obj/machinery/door/airlock/AltClick(mob/living/user)
	if(isobserver(user))
		to_chat(user, "<span class='danger'>Psst, you can't interact with the world, ghosts!</span>")
		return

	if (!user.canUseTopic(src, BE_CLOSE)) //beside the door, to press its request (the user's ruling, 2026-11-13)
		return //it's said why itself ("You can't do that right now!", "You are too far away!"): two lines saying it, in crit

	if(stat & (NOPOWER|BROKEN) || (obj_flags & EMAGGED))
		to_chat(user, "<span class='info'>The door isn't working!</span>")
		return

	if(request_cooldown > world.time)
		to_chat(user, "<span class='info'>The airlock's spam filter is blocking your request. Please wait at least 10 seconds between requests.</span>")
		return

	// A bot AI gets it too (bots_ai/goals/silicon.dm door_requested()): only AIs with a player at them did, so with the AI a bot
	// nobody's alt-click was ever answered. And "Request sent." only when there's an AI to send it to.
	var/sent = FALSE
	for(var/mob/living/silicon/ai/AI in GLOB.ai_list)
		if(AI.stat == DEAD)
			continue
		if(AI.client)
			to_chat(AI, "<span class='info'><a href='?src=[REF(AI)];track=[html_encode(user.name)]'><span class='name'>[user.name] ([user.GetJob()])</span></a> is requesting you to open [src]<a href='?src=[REF(AI)];remotedoor=[REF(src)]'>(Open)</a></span>")
			sent = TRUE
		else if(istype(AI.bot_silicon, /datum/bot_silicon/ai))
			var/datum/bot_silicon/ai/bot_ai = AI.bot_silicon
			bot_ai.door_requested(user, src)
			sent = TRUE
	request_cooldown = world.time + (COOLDOWN_TIME * 10)
	to_chat(user, sent ? "<span class='info'>Request sent.</span>" : "<span class='info'>The request goes out, and nothing answers.</span>")

#undef EASTEREGG_CHANCE
