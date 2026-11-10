// Milestone 1 chat: canned-line banter, not real language generation.
/// `in_character` is for what a traitor everybody's after says as itself: anything else it was about to say gives it a threat instead.
/proc/bot_say(mob/living/carbon/human/H, line, in_character = FALSE)
	if(QDELETED(H) || !line || H.stat == DEAD) //a corpse's say() goes to deadchat, radio prefix and all
		return
	if(!in_character && H.bot_brain?.gone_loud()) //goals/robust.dm: "Security! Help!" from somebody in a Syndicate nanosuit
		H.bot_brain.say_something_hostile()
		return
	if(H.mind?.miming && H.bot_brain)
		H.bot_brain.mime_instead(line) //goals/civilians.dm - a mime's say() fails without a word
		return
	if(H.bot_brain && !H.bot_brain.worth_saying(line)) //bot_chatter.dm
		return
	H.say(H.bot_brain ? H.bot_brain.in_own_words(line) : line) //bot_chatter.dm

// Called through the bot_log() macro (~hippie_defines/bots_ai.dm), which only gets this far when the line is wanted.
/proc/bot_log_line(datum/bot_brain/B, msg)
	if(B?.gym_run)
		// Bot Gym transcript (gym/bot_gym.dm), the run's whole record. A copy to admins nobody is and to game.log as well, where
		// nobody reads a gym's lines, was 4% of a full gym's server time (2026-11-09).
		B.gym_run.log_line(msg)
		return
	if(GLOB.bot_crew_panel_open && B)
		B.remember_line(msg) //admin/bot_crew_panel.dm
	if(!B || QDELETED(B.owner))
		return
	// Nobody to read it, no line: message_admins() put together and queued each one for chat whether or not an admin was on, ~45 us
	// a line, 2.3 s of a test shift's server time (2026-11-10).
	if(GLOB.bot_ai_debug && length(GLOB.admins))
		message_admins("<span class='notice'>Bot AI: [ADMIN_FLW(B.owner)] [B.owner.real_name]: [bot_coord_links(msg)]</span>")
	// game.log, the line log_admin() writes. Not its two copies for the round (GLOB.admin_log, and Search Logs' round log, which the
	// alerts subsystem reads through), now that every round has them: a live round's Search Logs would be bot lines from end to end.
	if(GLOB.bot_ai_log && CONFIG_GET(flag/log_admin))
		WRITE_LOG(GLOB.world_game_log, "ADMIN: BOT AI: [B.owner.real_name]: [msg]")

/datum/bot_brain
	/// The last line of the bot's trace (bot_log_verbose_line()), and how many times it's been said again since
	var/trace_last
	var/trace_repeats = 0

/datum/bot_brain/Destroy()
	if(trace_repeats && GLOB.bot_trace_log)
		WRITE_LOG(GLOB.bot_trace_log, "[owner?.real_name]: (and [trace_repeats] more of that)")
		trace_repeats = 0
	return ..()

/// bot_trace.log.zst, the round's bot trace (see bot_log_verbose_line())
GLOBAL_VAR(bot_trace_log)

// The noisy sibling of bot_log() - pathing pass results, per-node stuck diagnostics, and other detail that's only useful for
// reading a round back. It went to game.log until 2026-11-10: 487,000 lines a shift, 92% of a 130 MB game.log. Now it's its own
// file, zstd-compressed by the log writer's thread (hippie_log_compressed(), __HELPERS/log_writer.dm), "[time] Name: line", and
// a line the bot has just written is counted instead of written again (20% of them were): "Name: (and 9 more of that)" before
// the next one. Never admin chat. Read it with tools/bot_gym/logread.py.
/proc/bot_log_verbose_line(datum/bot_brain/B, msg)
	if(B?.gym_run)
		B.gym_run.log_line("  [msg]") //the transcript, as bot_log()
		return
	if(!GLOB.bot_ai_verbose || !B || QDELETED(B.owner))
		return
	if(msg == B.trace_last)
		B.trace_repeats++
		return
	if(!GLOB.bot_trace_log)
		GLOB.bot_trace_log = hippie_log_compressed("[GLOB.log_directory]/bot_trace.log")
	if(B.trace_repeats)
		WRITE_LOG(GLOB.bot_trace_log, "[B.owner.real_name]: (and [B.trace_repeats] more of that)")
		B.trace_repeats = 0
	B.trace_last = msg
	WRITE_LOG(GLOB.bot_trace_log, "[B.owner.real_name]: [msg]")

/// "(x,y,z)" for a log line. The JMP link that used to follow (adminplayerobservecoodjump, as ADMIN_JMP()) was 45 MB of a shift's
/// 130 MB game.log and a token per line; admin chat's copy of a line gets it back from bot_coord_links().
/proc/bot_coord(turf/T)
	if(!T)
		return "nonexistent location"
	return "([T.x],[T.y],[T.z])"

/// A log line for admin chat: each "(x,y,z)" from bot_coord() with its clickable JMP link
/proc/bot_coord_links(msg)
	var/static/regex/coords = regex(@"\((\d+),(\d+),(\d+)\)", "g")
	var/token = HrefToken(TRUE)
	return coords.Replace(msg, "($1,$2,$3) (<a href='?_src_=holder;[token];adminplayerobservecoodjump=1;X=$1;Y=$2;Z=$3'>JMP</a>)")

// Shared by every async entry point (timer callbacks, signal handlers) that isn't
// covered by process()'s own try/catch - those run in their own call stack, so an
// exception there needs its own net or it silently kills that callback chain forever
// (e.g. a crashed stuck-timeout never reschedules itself - the bot just stops).
/proc/bot_log_exception(datum/bot_brain/B, where, exception/e)
	var/msg = "BOT AI EXCEPTION (owner=[B?.owner], in [where]): [e] at [e.file]:[e.line]"
	message_admins("<span class='danger'>[msg]</span>[B?.owner ? " [ADMIN_FLW(B.owner)]" : ""]")
	log_runtime(msg)
	GLOB.bot_shift?.note_bot_exception(msg) //gym/bot_shift.dm

/// Nobody says these with bodies in the hallways.
GLOBAL_LIST_INIT(bot_calm_lines, list("Quiet shift so far.", "Not much. Same old.", "Nothing I've heard about.", "Medbay's quiet for once.", "Quiet in the brig today."))

GLOBAL_LIST_INIT(bot_idle_lines, list(
	"Anyone else think the vents smell weird today?",
	"I should really get back to work.",
	"Quiet shift so far.",
	"Does anyone have a spare cup of coffee?",
	"Man, I could go for a snack right about now.",
	"Who even designed this station?",
	"I swear the lights flickered.",
	"Somebody needs to fix that noise.",
	"What was I doing again?",
	"Hm.",
	"This place could use a clean.",
	"I should've stayed in bed.",
	"Is it just me or is it cold in here?",
	"Wonder what's for dinner.",
	"Right. Where was I.",
))

GLOBAL_LIST_INIT(bot_combat_lines, list(
	"Hey, knock it off!",
	"What the hell?!",
	"Back off!",
	"I'll call security!",
	"Stop that!",
))

GLOBAL_LIST_INIT(bot_name_called_lines, list(
	"Yeah, that's me.",
	"What's up?",
	"You called?",
	"Huh? Oh, hey.",
	"That's my name, don't wear it out.",
))

GLOBAL_LIST_INIT(bot_greeting_reply_lines, list(
	"Hey there.",
	"Oh, hi!",
	"Hey, how's it going?",
	"Sup.",
	"Afternoon.",
))

GLOBAL_LIST_INIT(bot_question_reply_lines, list(
	"Hm, not sure, honestly.",
	"Beats me.",
	"No idea, sorry.",
	"Couldn't tell you.",
	"Wish I knew.",
))

// Passed straight to /mob/proc/emote() - keep this list to emotes every human can
// safely perform with no target/item required.
GLOBAL_LIST_INIT(bot_idle_emotes, list(
	"yawn",
	"stretch",
	"sigh",
	"shrug",
	"nod",
	"look",
))
