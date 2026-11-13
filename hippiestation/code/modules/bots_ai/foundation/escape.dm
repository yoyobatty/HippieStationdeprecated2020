// Escape anything (the plan's foundation/escape.dm, M1).
//
// Breaking out. Smashing a window or a grille in its way was only ever allowed when the bot itself was in danger (urgency, bot_breach.dm):
// on fire, bad air, badly hurt. That's right for the crew about their day. It left an apex bot (every antagonist, by default) shut in a room
// on its own business and calm, waiting for somebody to let it out, the same as an assistant. Now an apex bot that isn't about its
// everyday work breaks through when there's no other way: when it's shut in, fighting, making an arrest for a major crime, or when it has
// already dropped its cover (gone_loud(), goals/robust.dm). A traitor keeping its cover doesn't smash its way round the station; one shut
// in somewhere gets out. Below apex nothing changes.

/datum/bot_brain
	/// breaks_out(), for the tick it was worked out in: route searches ask it for every window they look at
	var/breaks_out_known = FALSE
	var/breaks_out_at = -1

/// Breaks what's in its way when there's no other way, calm or not (above).
/datum/bot_brain/proc/breaks_out()
	if(breaks_out_at == world.time)
		return breaks_out_known
	breaks_out_at = world.time
	breaks_out_known = FALSE
	if(!pursuing_kind || pursuing_kind == "wander" || measuring_shut_in || !is_apex() || pursuit_is_lawful())
		return FALSE
	// An arrest only for a major crime: the user's ruling (2026-11-04), breaking in to chase is for serious crimes only
	// (minor_arrest_at_door(), goals/security_patrol.dm). An apex officer broke the Head of Security's office window with a baton over
	// low-threat trespassing (Bot Shift found_after run3).
	breaks_out_known = state == BOT_STATE_COMBAT || (state == BOT_STATE_ARREST && arrest_severity >= BOT_CRIME_MAJOR) || gone_loud() || is_shut_in()
	return breaks_out_known

/// The urgency breaking things goes by (bot_breach.dm): what it feels, or an emergency for an apex bot breaking out.
/datum/bot_brain/proc/breach_urgency()
	. = get_urgency()
	if(. < BOT_URGENCY_EMERGENCY && breaks_out())
		. = BOT_URGENCY_EMERGENCY
