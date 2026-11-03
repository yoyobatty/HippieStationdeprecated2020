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

/// GLOB.player_list, the mobs with a client, and the bot crew, who have none (bot_identity.dm keeps them out of it): for the round's own
/// judgements of who's about, which ought to count them.
/proc/bot_counted_players()
	. = GLOB.player_list.Copy()
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(B.owner)
			. |= B.owner

/// The same judgement as emergency.dm's, with the bots counted as well: a shuttle full of bot crew read as empty, and a bot hijacker was
/// never aboard (goals/traitor_objectives.dm).
/obj/docking_port/mobile/emergency/is_hijacked()
	var/list/everyone = bot_counted_players()
	var/has_people = FALSE
	var/hijacker_present = FALSE
	for(var/mob/living/player in everyone)
		if(!player.mind || player.stat == DEAD || issilicon(player) || isanimal(player) || isbrain(player))
			continue
		if(!shuttle_areas[get_area(player)])
			continue
		has_people = TRUE
		var/location = get_turf(player.mind.current)
		if(!(player.mind.has_antag_datum(/datum/antagonist)) && !istype(location, /turf/open/floor/plasteel/shuttle/red) && !istype(location, /turf/open/floor/mineral/plastitanium/red/brig))
			return FALSE
		var/prevent = FALSE
		for(var/datum/antagonist/A in player.mind.antag_datums)
			if(A.can_hijack == HIJACK_HIJACKER)
				hijacker_present = TRUE
				prevent = FALSE
				break
			else if(A.can_hijack == HIJACK_PREVENT)
				prevent = TRUE
		if(prevent)
			return FALSE
	return has_people && hijacker_present
