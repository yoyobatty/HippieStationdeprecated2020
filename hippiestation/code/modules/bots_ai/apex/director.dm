// The director (the plan's apex/director.dm, M3; the user's ruling, 2026-11-12: "director hints", the one exception to the rule that a bot
// knows only what a player in its place would). Alien Isolation's: the director always knows where the one being hunted is, and now and
// then lets the hunter have a clue of roughly where (a noise, a door, footsteps): a spot within three tiles of them, and the room it's in,
// never the tile itself. It eases off after a close call (the hunter within three tiles of them without knowing it, or having found them):
// a clue every fifteen seconds while the hunter's lost, every forty for a minute after that, so somebody who's just got away has a moment.
// Apex hunters only. What the hunter sees is still only what's in view: the clue moves its search (foundation/hunt.dm), nothing else.

#define BOT_DIRECTOR_EVERY (15 SECONDS)
#define BOT_DIRECTOR_EASED (40 SECONDS)
#define BOT_DIRECTOR_EASE_FOR (60 SECONDS)
#define BOT_DIRECTOR_SLOP 3

/// From the search, every look (foundation/hunt.dm search_for/staged_work()).
/datum/bot_brain/proc/director_clue(datum/bot_goal/search_for/S, mob/living/Q)
	if(!is_apex() || !S || !Q)
		return
	if(!S.next_clue)
		S.next_clue = world.time + 8 SECONDS //a moment's looking about first
		return
	if(world.time < S.next_clue)
		return
	var/turf/at = get_turf(Q)
	if(!at || at.z != owner.z)
		return
	var/eased = search_close_call_at && world.time - search_close_call_at < BOT_DIRECTOR_EASE_FOR
	S.next_clue = world.time + (eased ? BOT_DIRECTOR_EASED : BOT_DIRECTOR_EVERY)
	var/turf/near = bot_director_rough_turf(Q)
	S.clue = near
	S.looked_at_centre = FALSE
	S.spot_going_to = null
	S.spots_left = max(S.spots_left, 4) //worth a look in what's round it, whatever's been opened already
	var/area/A = get_area(near)
	S.belief[A] += 2
	S.visited -= A
	bot_log(src, "DIRECTOR: [pick("heard something", "footsteps", "a door, somewhere", "a locker clanging")] round [get_area_name(near, TRUE)][eased ? " (eased off)" : ""]")
	bot_tally("director clues")

/// Roughly where somebody is: a tile within BOT_DIRECTOR_SLOP of them, open floor if it can be
/proc/bot_director_rough_turf(mob/living/Q)
	var/turf/at = get_turf(Q)
	if(!at)
		return null
	for(var/i in 1 to 6)
		var/turf/near = locate(clamp(at.x + rand(-BOT_DIRECTOR_SLOP, BOT_DIRECTOR_SLOP), 1, world.maxx), clamp(at.y + rand(-BOT_DIRECTOR_SLOP, BOT_DIRECTOR_SLOP), 1, world.maxy), at.z)
		if(near && !near.density && !isspaceturf(near))
			return near
	return at //rough enough: the spots round it are what's searched, nearest the clue first

#undef BOT_DIRECTOR_EVERY
#undef BOT_DIRECTOR_EASED
#undef BOT_DIRECTOR_EASE_FOR
#undef BOT_DIRECTOR_SLOP
