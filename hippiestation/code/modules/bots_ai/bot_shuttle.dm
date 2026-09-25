// The arrivals shuttle only sails back in once it thinks someone's aboard
// (PersonCheck(), which reads GLOB.player_list - "mobs with clients attached").
// Bots deliberately aren't in that list (see bot_identity.dm - SSinput.fire() and
// friends assume every entry there has a live client), so give the shuttle its own
// bot-aware check instead of leaning on a list that means something more specific.
/obj/docking_port/mobile/arrivals/PersonCheck()
	. = ..()
	if(.)
		return

	for(var/mob/living/carbon/human/H in GLOB.bot_crew_members)
		if((get_area(H) in areas) && H.stat != DEAD)
			return TRUE
