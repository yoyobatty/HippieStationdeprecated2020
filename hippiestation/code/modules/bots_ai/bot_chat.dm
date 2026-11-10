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
	if(!GLOB.bot_ai_debug || !B || QDELETED(B.owner))
		return
	message_admins("<span class='notice'>Bot AI: [ADMIN_FLW(B.owner)] [B.owner.real_name]: [msg]</span>")
	// message_admins() alone never touches disk - there was no way to grep a round's
	// bot behavior after the fact, only watch it live. log_admin() writes to game.log
	// the same way every other admin-visible action already does.
	log_admin("BOT AI: [B.owner.real_name]: [msg]")

// The noisy sibling of bot_log() - pathing pass results, per-node stuck diagnostics,
// and other detail that's only useful for grepping game.log after the fact. Written
// straight to disk via log_admin(), never message_admins(), so it can stay on by
// default without flooding anyone watching the live admin feed.
/proc/bot_log_verbose_line(datum/bot_brain/B, msg)
	if(B?.gym_run)
		B.gym_run.log_line("  [msg]") //the transcript, as bot_log()
		return
	if(!GLOB.bot_ai_verbose || !B || QDELETED(B.owner))
		return
	// The line log_admin() writes, without the two copies it keeps for the round (GLOB.admin_log, and Search Logs' round log, which
	// the alerts subsystem then reads through): 450,000 of these a shift filled both, and keeping and reading them was 3% of a
	// test shift's server time. bot_log()'s lines, a tenth as many, still go to Search Logs.
	if(CONFIG_GET(flag/log_admin))
		WRITE_LOG(GLOB.world_game_log, "ADMIN: BOT AI VERBOSE: [B.owner.real_name]: [msg]")

// Same idea as the admin.dm ADMIN_COORDJMP() macro, but as a proc - the macro form
// expands to a full quoted string literal, which breaks if used nested inside another
// interpolated string (the compiler sees mismatched quotes). This is safe to nest.
// Includes the same clickable "(JMP)" link explosion logging already uses
// (message_admins() calls with ADMIN_VERBOSEJMP(), explosions.dm) - same
// adminplayerobservecoodjump href action ADMIN_JMP() itself builds, just inlined here so
// it can nest. Only meaningful in bot_log()'s message_admins() copy (rendered, clickable,
// in the live admin chat panel) - the log_admin() disk copy gets the same literal text
// either way, same as every other ADMIN_VERBOSEJMP()-tagged message_admins() call in the
// codebase already writes raw markup to game.log; the coordinates themselves stay
// grep-able there regardless.
/proc/bot_coord(turf/T)
	if(!T)
		return "nonexistent location"
	return "([T.x],[T.y],[T.z]) (<a href='?_src_=holder;[HrefToken(TRUE)];adminplayerobservecoodjump=1;X=[T.x];Y=[T.y];Z=[T.z]'>JMP</a>)"

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
