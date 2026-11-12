// Talking - the canned lines of bot_chat.dm, said by something more like a person:
//
//  - each bot types its own way (chat_style): some properly, some all in lowercase, some without
//    bothering with apostrophes
//  - spoken to by name, or face to face with nobody else about, it answers what it was asked - what
//    it's doing, who it is, which way somewhere is, how it's holding up - and tags along if asked
//  - two bots with time on their hands make small talk: a line, and an answer
//  - a reply takes as long as it takes to type, and a new arrival says hello on the radio

#define BOT_CHAT_PROPER 1
#define BOT_CHAT_LOWERCASE 2
#define BOT_CHAT_TERSE 3

/// Before the same bot says the same thing again.
#define BOT_SAID_REPEAT (90 SECONDS)
/// Before anybody says on the radio what somebody just said.
#define BOT_RADIO_REPEAT (20 SECONDS)
/// How long something's still worth bringing up.
#define BOT_NEWS_LIFETIME (10 MINUTES)

/// Radio line -> when it's fresh again.
GLOBAL_LIST_EMPTY(bot_radio_lately)

/datum/bot_brain
	var/chat_style = BOT_CHAT_PROPER
	/// Matches this bot's first or full name as whole words - built on first use.
	var/regex/name_regex
	/// Line -> when it's fresh again.
	var/list/said_lately
	/// News it's passed on, or had passed on to it.
	var/list/news_told
	/// When it will next answer someone talking to it (next_reaction_time, bot_brain.dm, paces everything else).
	var/next_answer_time = 0
	/// Lines taken in this second (on_heard_speech()): a person in a flood of chatter follows a few lines a second, not hundreds
	var/heard_this_second = 0
	var/heard_second_ends = 0

/// Lines a second a bot takes in. The busiest seconds of four played rounds had 6-9 lines said or radioed on the whole station
/// (game.log, 2026-11-10/11), of which a bot hears only some; a room of spammers made each of 20 bots read ~2000 a second.
#define BOT_HEARD_LINES_PER_SECOND 10

/// Whether a line it hears gets its attention (Hear(), bot_brain.dm): BOT_HEARD_LINES_PER_SECOND, the rest is lost in the noise
/datum/bot_brain/proc/takes_in_line()
	if(world.time >= heard_second_ends)
		heard_second_ends = world.time + 1 SECONDS
		heard_this_second = 0
	return ++heard_this_second <= BOT_HEARD_LINES_PER_SECOND

/datum/bot_brain/New(mob/living/carbon/human/new_owner)
	. = ..()
	chat_style = pick(45; BOT_CHAT_PROPER, 40; BOT_CHAT_LOWERCASE, 15; BOT_CHAT_TERSE)
	addtimer(CALLBACK(src, PROC_REF(say_hello_on_arrival)), rand(150, 450))

/// A line the way this bot would type it. A radio prefix (";", ":s ") is left alone.
/datum/bot_brain/proc/in_own_words(line)
	if(chat_style == BOT_CHAT_PROPER || gym_scripted)
		return line
	var/prefix = ""
	if(copytext(line, 1, 2) == ";")
		prefix = ";"
		line = copytext(line, 2)
	else if(copytext(line, 1, 2) == ":")
		prefix = copytext(line, 1, 4)
		line = copytext(line, 4)
	line = lowertext(line)
	if(copytext(line, length(line)) == ".")
		line = copytext(line, 1, length(line))
	if(chat_style == BOT_CHAT_TERSE)
		line = replacetext(replacetext(line, "'", ""), ",", "")
	return prefix + line

/// Nobody says the same thing twice in a minute and a half, whatever's going on, and on the radio nobody says what somebody else
/// just did. A round's chat was the same dozen shouts over and over, and "I've got them, Security" forty times.
/datum/bot_brain/proc/worth_saying(line)
	if(gym_run)
		return TRUE
	if((line in GLOB.bot_calm_lines) && bot_shift_gone_bad()) //goals/robust.dm
		return FALSE
	if(said_lately && (world.time < said_lately[line]))
		return FALSE
	if(copytext(line, 1, 2) == ";")
		if(world.time < GLOB.bot_radio_lately[line])
			return FALSE
		if(length(GLOB.bot_radio_lately) > 40)
			GLOB.bot_radio_lately.Cut(1, 21)
		GLOB.bot_radio_lately[line] = world.time + BOT_RADIO_REPEAT
	LAZYINITLIST(said_lately)
	if(length(said_lately) > 16)
		said_lately.Cut(1, 9)
	said_lately[line] = world.time + BOT_SAID_REPEAT
	return TRUE

/// How long a line takes to type, on top of noticing it needs saying.
/proc/bot_typing_time(line)
	return rand(6, 14) + min(length(line) * 1.2, 50)

/// Says a line once it's had time to type it.
/datum/bot_brain/proc/say_after_typing(line)
	addtimer(CALLBACK(src, PROC_REF(speak_reply), line), bot_typing_time(line))

/datum/bot_brain/proc/speak_reply(reply)
	if(QDELETED(owner) || owner.stat != CONSCIOUS)
		return
	bot_say(owner, reply)
	bot_log(src, "said \"[reply]\"")

// ---------------------------------------------------------------------------------------------
// Being spoken to
// ---------------------------------------------------------------------------------------------

/datum/bot_brain/proc/hears_own_name(lower_msg)
	if(!name_regex)
		var/names = REGEX_QUOTE(owner.real_name)
		var/first = owner.first_name()
		if(first && length(first) >= 3)
			names = "[REGEX_QUOTE(first)]|[names]"
		name_regex = regex("\\b([names])\\b", "i")
	return name_regex.Find(lower_msg)

/// Whether talker is plainly speaking to this bot: close, turned this way, and nobody else there to mean.
/datum/bot_brain/proc/is_spoken_to_by(mob/living/talker)
	if(get_dist(owner, talker) > 2 || !(talker in view(3, owner)))
		return FALSE
	if(get_dist(owner, talker) > 1 && !(get_dir(talker, owner) & talker.dir))
		return FALSE
	for(var/mob/living/carbon/human/other in view(3, talker))
		if(other != owner && other != talker && other.stat == CONSCIOUS)
			return FALSE
	return TRUE

/// Words that put a question to whoever hears it.
GLOBAL_LIST_INIT(bot_you_words, list("you", "ya", "u", "your", "you're", "youre", "yall", "y'all"))

/// A question put to whoever's there, nobody named ("what are you up to?" to two of them stood together, or from across the room): the
/// nearest person to whoever asked takes it, if that's this bot. The user asked an engineer and an atmos tech just that from four tiles
/// off, and neither said a word (is_spoken_to_by() wants one person, two tiles away).
/datum/bot_brain/proc/asked_as_nearest(mob/living/talker, lower_msg)
	if(!findtext(lower_msg, "?") || !bot_text_has_any(lower_msg, GLOB.bot_you_words))
		return FALSE
	if(get_dist(owner, talker) > 5)
		return FALSE
	// Every bot that hears it works this out the same way in the same tick, so just the one answers.
	var/mob/living/carbon/human/nearest
	var/nearest_dist
	for(var/mob/living/carbon/human/H in view(5, talker))
		if(H == talker || H.stat != CONSCIOUS)
			continue
		var/dist = get_dist(H, talker)
		if(!nearest || dist < nearest_dist)
			nearest = H
			nearest_dist = dist
	return nearest == owner

/datum/bot_brain/proc/on_heard_speech(atom/movable/speaker, raw_message, radio_freq)
	if(!raw_message || QDELETED(owner) || owner.stat != CONSCIOUS)
		return
	var/mob/living/talker = speaker
	if(istype(speaker, /atom/movable/virtualspeaker))
		var/atom/movable/virtualspeaker/V = speaker
		talker = V.source
	if(!isliving(talker) || talker == owner)
		return
	if(!istype(speaker, /atom/movable/virtualspeaker) || get_dist(owner, talker) <= 7)
		bot_heard_apology(talker, lowertext(raw_message)) //bot_witness.dm: an accident said sorry for
	if(heard_codeword(talker, lowertext(raw_message))) //goals/robust.dm: other traitors' words count, bots or not
		return
	if(gone_loud()) //nobody it's on speaking terms with, short of a deal
		heard_team_offer(talker, lowertext(raw_message), radio_freq)
		return
	heard_of_fire(talker, lowertext(raw_message), radio_freq) //goals/respond_to_fire.dm: from bots as well, who radio the fires they see
	// Bots talk to each other through make_small_talk() below. Answering whatever another bot says as well would
	// have two of them alone in a room trading stock replies for the rest of the shift.
	var/mob/living/carbon/human/crewmate = talker
	if(istype(crewmate) && crewmate.bot_brain)
		return

	var/lower_msg = lowertext(raw_message)
	if(heard_confession(talker, lower_msg, radio_freq)) //goals/robust.dm
		return
	// bot_law.dm: the Captain, a head or Security saying who's to be arrested, let go, spared or killed
	if(istype(crewmate) && heard_command_order(crewmate, lower_msg, radio_freq))
		return
	// bot_asks.dm: somebody it's arresting talking back, and somebody pointing Security at somebody.
	if(istype(crewmate) && bot_heard_plea(crewmate, lower_msg))
		return
	if(bot_heard_accusation(talker, lower_msg, radio_freq))
		return
	// Its job called by its title is it being called; the next line from somebody it's answered is to it as well.
	var/called = hears_own_name(lower_msg) || hears_own_title(lower_msg)
	var/named = called || in_conversation_with(talker)
	if(world.time < access_asked_until && access_asker?.resolve() == talker) //what they want the access for
		access_asked_until = 0
		consider_access_request(talker, lower_msg, radio_freq)
		return
	// A player's "on it" to a call: theirs, and whoever had it stands down (bot_claims.dm).
	if(bot_heard_claim(talker, lower_msg, radio_freq))
		return
	// A call for somebody of this bot's trade, or for this bot by name to come somewhere (bot_requests.dm).
	if(heard_call(talker, lower_msg, radio_freq, named))
		return
	// What they need, told a cargo technician who asked (bot_collabs.dm): "silver"
	if(world.time < materials_ask_until && materials_asker?.resolve() == talker && bot_material_named(lower_msg) && order_materials_for(talker, lower_msg, radio_freq))
		return
	// A job called that nobody's on: said so, to their face or over the radio (bot_asks.dm).
	var/list/title_jobs = bot_title_called(lower_msg)
	// Mining called with nobody mining: Cargo orders it in instead (bot_collabs.dm)
	if(title_jobs && ("Shaft Miner" in title_jobs) && !bot_anyone_in_jobs(title_jobs, owner) && order_materials_for(talker, lower_msg, radio_freq))
		return
	if(title_jobs && !(work_role() in title_jobs) && say_nobody_on(title_jobs, radio_freq))
		return
	// Over the radio it only answers to its name - half the station isn't talking to it.
	var/addressed = named || (!radio_freq && is_spoken_to_by(talker))
	if(!addressed && answer_whereabouts(talker, lower_msg, radio_freq)) //"where's Max?" to everybody, by somebody who can see them
		return
	if(answer_where_to_get(talker, lower_msg, radio_freq)) //"anyone seen a crowbar?" (bot_knowledge.dm)
		return
	if(answer_massacre_question(talker, lower_msg, radio_freq)) //"who's killing everyone?", "who's alive?" (goals/massacre.dm)
		return
	// Somebody dead is news for whoever's in earshot, not just who it's said to: the first one near enough takes it up (bot_talk_more.dm).
	if(!addressed && !radio_freq && get_dist(owner, talker) <= 7 && bot_is_death_news(lower_msg) && world.time >= GLOB.bot_death_news_taken + 5 SECONDS)
		GLOB.bot_death_news_taken = world.time
		addressed = TRUE
	if(!addressed && !radio_freq && asked_as_nearest(talker, lower_msg))
		addressed = TRUE
	if(!addressed && (radio_freq || get_dist(owner, talker) > 3))
		return
	// Someone talking to it gets an answer every time; what it merely overhears, it reacts to now and then.
	if(world.time < (addressed ? next_answer_time : next_reaction_time))
		return
	var/reply
	if(addressed)
		next_answer_time = world.time + 25
		talking_to(talker)
		reply = answer_for(talker, lower_msg, !!radio_freq, called)
	else if(findtext(lower_msg, "?"))
		if(prob(35 * sociability))
			reply = pick(GLOB.bot_question_reply_lines)
	else if(bot_text_has_any(lower_msg, GLOB.bot_greeting_words))
		if(prob(25 + 50 * sociability))
			reply = pick(GLOB.bot_greeting_reply_lines)
	if(!reply)
		return

	next_reaction_time = world.time + rand(80, 200)
	if(!radio_freq && !pursuing_kind)
		owner.face_atom(talker)
	// Back on the channel it came over - ":h" is this bot's own department, which is somebody else's when what it
	// heard was on a channel its headset only listens to.
	say_after_typing(bot_radio_prefix(radio_freq) + reply)

/// Words that are a greeting when they open a line or stand alone.
GLOBAL_LIST_INIT(bot_greeting_words, list("hi", "hello", "hey", "heya", "sup", "yo", "howdy", "morning", "evening", "greetings"))

/// TRUE if any of words is in text as a whole word.
/proc/bot_text_has_any(text, list/words)
	// Each answer is kept for the rest of the tick: every bot that hears a line asks the same questions of it, and a radio line
	// reaches all of them in the same tick. Keyed by the line, then by the word list itself (a list written out at the call is a
	// new list each time and just misses).
	var/static/list/memo = list()
	var/static/memo_time = -1
	if(memo_time != world.time)
		memo = list()
		memo_time = world.time
	var/list/answers = memo[text]
	if(!answers)
		answers = list()
		memo[text] = answers
	else if(!isnull(answers[words]))
		return answers[words]
	. = FALSE
	for(var/word in words)
		if(bot_text_word_at(text, word))
			. = TRUE
			break
	answers[words] = .

/// Where a whole word first comes in the text, or 0
/proc/bot_text_word_at(text, word)
	var/static/list/cache = list()
	var/static/list/plain = list() // words with no regex symbols in them, which findtext() can look for as they are
	var/static/regex/symbols = regex(@"[\\.*+?()\[\]{}|^$]")
	var/regex/R = cache[word]
	if(!R)
		R = regex("\\b[word]\\b", "i")
		cache[word] = R
		plain[word] = !symbols.Find(word)
	// findtext() first (native, case-insensitive like the regex): most words aren't in most lines, and every bot ran every regex
	// on every line it heard. A room of spammers spent 76% of the server's proc time here (2026-11-11, tools/mob_storm speech).
	if(plain[word] && !findtext(text, word))
		return 0
	return R.Find(text)

/// What to say back to something said to this bot in particular, or null if it has nothing to say to it.
/datum/bot_brain/proc/answer_for(mob/living/talker, lower_msg, over_radio, named)
	var/adrift_news = adrift_answer(lower_msg)
	if(adrift_news)
		return adrift_news
	if(bot_text_has_any(lower_msg, list("wait", "hold on", "hang on", "stop", "stop running", "wait up")) && !bot_text_has_any(lower_msg, list("stop following", "wait here")))
		var/waiting = wait_for(talker) //bot_asks.dm
		if(waiting)
			return waiting
	if(bot_text_has_any(lower_msg, list("what you in for", "what are you in for", "what're you in for", "why are you in", "what did you do")))
		return what_im_in_for() //bot_asks.dm
	// bot_talk_more.dm: what the user said in played rounds and got nothing back for
	if(bot_text_has_any(lower_msg, list("truce", "don't kill me", "dont kill me", "don't hurt me", "dont hurt me", "don't shoot", "dont shoot", "i'm friendly", "im friendly", "i surrender", "i give up")))
		return peace_offered(talker)
	if(bot_text_has_any(lower_msg, list("you need healing", "let me heal you", "let me patch you", "i'll heal you", "ill heal you", "you're hurt", "youre hurt", "you're bleeding", "youre bleeding", "patch you up", "need patching")))
		return healing_offered(talker)
	if(!over_radio && bot_text_has_any(lower_msg, list("give me back", "give it back", "give back my", "that's mine", "thats mine", "return my")))
		return give_back_theirs(talker, lower_msg)
	if(bot_is_death_news(lower_msg))
		return death_news(talker, over_radio)
	if(!over_radio)
		if(bot_text_has_any(lower_msg, list("follow me", "come with me", "come here")))
			return try_tag_along(talker)
		var/datum/bot_goal/tag_along/following = current_goal
		if(istype(following) && following.target == talker && bot_text_has_any(lower_msg, list("stay here", "stop following", "wait here", "you can go", "that's all", "thats all", "thanks", "thank you")))
			following.dismissed = TRUE
			return pick("Alright.", "Sure thing.", "No problem.")
	if(bot_text_has_any(lower_msg, list("what are you doing", "what're you doing", "what you doing", "whatcha doing", "wyd", "what are you up to", "you busy", "are you busy")))
		var/doing = describe_activity()
		return doing ? pick("Just [doing].", "I'm [doing].", "[capitalize(doing)]. Why?") : pick("Nothing much.", "Just having a wander.", "Taking a breather.")
	if(bot_text_has_any(lower_msg, list("who are you", "your name", "your job", "what do you do", "what's your job", "whats your job", "what can you do")))
		var/role = work_role()
		var/post = ""
		if(role == "Assistant")
			post = " Just an assistant."
		else if(role)
			post = " I'm the [lowertext(role)]."
		return "I'm [owner.first_name()].[post]"
	if(bot_text_has_any(lower_msg, list("shuttle", "evac", "crew transfer", "going home")))
		return shuttle_news()
	if(bot_text_has_any(lower_msg, list("what's going on", "whats going on", "what's happening", "whats happening", "what did i miss", "anything going on", "anything happening", "how's the shift", "hows the shift")))
		return shift_news()
	if(!over_radio)
		var/asked_for = tool_asked_for(lower_msg)
		if(asked_for)
			return lend_tool(talker, asked_for)
	if(bot_text_has_any(lower_msg, list("are you a bot", "are you an ai", "are you a robot", "you a bot", "is this a bot", "you're a bot", "youre a bot")))
		return pick("What? No.", "Rude.", "Do I look like a bot to you?", "That's a weird thing to ask.", "Haven't had my coffee, that's all.")
	// The everyday things the conversation sweep (gym/scenarios_asks.dm) got "Beats me." or nothing at all for.
	if(bot_text_has_any(lower_msg, list("are you a traitor", "are you traitor", "you a traitor", "are you an antag", "are you a ling", "are you a changeling", "are you a cultist", "are you syndie", "are you a syndie", "are you syndicate", "you're a traitor", "youre a traitor", "you're a ling", "youre a ling")))
		return mood_pick(list("Ha, no.", "Me? No way.", "Nope. Just doing my job."), list("No?", "What? No.", "Why would you ask that?"), list("Are YOU?", "No, and that's a weird thing to ask.", "Says the one asking."))
	if(bot_text_has_any(lower_msg, list("you there", "are you there", "you awake", "you alive", "you listening", "anyone home")))
		return pick("Yeah?", "Yep, what's up?", "I'm here.", "Mhm?")
	if(bot_text_has_any(lower_msg, list("what's up", "whats up", "wassup", "what's new", "whats new")) && !bot_text_has_any(lower_msg, list("what's up with", "whats up with")))
		return mood_pick(list("Not much! You?", "All good here. You?"), list("Not much. You?", "Same old.", "Nothing really."), list("Nothing good.", "Don't ask.", "Ugh. This shift."))
	if(bot_text_has_any(lower_msg, list("you're cool", "youre cool", "you're great", "youre great", "you're awesome", "youre awesome", "you rock", "you're the best", "youre the best", "good job", "nice job", "well done", "nice one", "great work", "good work", "love you", "ily", "cute", "adorable")))
		return pick("Thanks!", "Aw, cheers.", "Ha, thanks.", "You're not so bad yourself.")
	if(!over_radio && bot_text_has_any(lower_msg, list("can you help", "could you help", "help me", "i need help", "need a hand", "give me a hand", "lend me a hand", "can i ask you something", "got a minute", "got a sec")))
		if(state == BOT_STATE_GOAL && current_goal && !current_goal.lawful)
			return pick("Bit busy right now.", "Can it wait?", "Not now, sorry.")
		return pick("Sure, what do you need?", "Yeah, what's up?", "What do you need?", "Sure. What is it?")
	// "Help!" and nothing else, said to its face (the user's own words in a played round, three times, unanswered).
	if(!over_radio && length(lower_msg) <= 14 && bot_text_has_any(lower_msg, list("help", "halp")))
		return pick("What's wrong?", "What happened?", "What do you need?", "Whoa, what's up?")
	if(bot_text_has_any(lower_msg, list("plasma here", "plasma in the air", "there's plasma", "theres plasma", "gas leak", "plasma leak", "don't breathe", "dont breathe", "air's bad", "airs bad")))
		return pick("Thanks for the heads up.", "Got it, I'll keep clear.", "Yikes. Thanks.", "Noted, staying away.")
	// Requests, orders and warnings: the second conversation sweep (gym/scenarios_asks.dm) got "Okay." and "Fair enough." for these.
	if(!over_radio && bot_text_has_any(lower_msg, list("open this door", "open the door", "open this", "get the door", "can you open", "could you open")))
		return open_a_door_for(talker)
	// Somebody's found its ID ("I got your ID card", "where are you, I've got your card"). A doctor whose card was left at the HoP's door
	// was told so twice on the radio and answered "no way", taking it for somebody after his card.
	if(bot_text_has_any(lower_msg, list("your id", "your card", "id card", "id cards", "your pda")) && bot_text_has_any(lower_msg, list("got", "have", "found", "picked up", "with me", "holding")))
		return about_my_card(talker, over_radio) //bot_hopping.dm
	if(bot_text_has_any(lower_msg, list("give me your id", "gimme your id", "hand over your id", "your id card", "give me your card")))
		return bot_is_officer(talker) ? pick("What for?", "Am I under arrest?", "...Fine. What's this about?") : pick("No way.", "Why would I do that?", "Get your own.")
	if(!over_radio && bot_text_has_any(lower_msg, list("drop it", "drop that", "drop your weapon", "drop the")))
		if(bot_is_officer(talker) && !gone_loud())
			var/obj/item/held = owner.get_active_held_item()
			if(held && !HAS_TRAIT(held, TRAIT_NODROP))
				owner.dropItemToGround(held)
			return pick("Okay, okay!", "Dropped it! Relax.", "There. Happy?")
		return pick("Make me.", "Why?", "No?")
	if(!over_radio && bot_text_has_any(lower_msg, list("hands up", "put your hands up", "hands in the air")))
		if(bot_is_officer(talker) && !gone_loud())
			owner.emote("surrender")
			return pick("Okay! Don't shoot!", "I'm not doing anything!", "Alright, alright!")
		return pick("What? Why?", "You're not Security.", "Ha. No.")
	if(bot_text_has_any(lower_msg, list("get back to work", "do your job", "stop slacking")))
		return mood_pick(list("On it!", "Yep, going."), list("Yeah, yeah.", "I'm on break.", "Going, going."), list("Make me.", "Mind your own business.", "Who made you boss?"))
	if(bot_text_has_any(lower_msg, list("you're fired", "youre fired", "you are fired", "you're demoted", "youre demoted")))
		var/role = bot_job_of(talker)
		if(role == "Captain" || role == "Head of Personnel")
			return pick("Seriously?", "For what?!", "You can't be serious.")
		return pick("You can't fire me.", "Ha. Sure.", "You're not my boss.")
	// A shout on its own ("run!", "fire!"): the word boundary the phrase list matches on doesn't come after a "!", so those are taken whole.
	var/static/list/alarm_shouts = list("run", "run!", "run!!", "fire", "fire!", "fire!!", "bomb", "bomb!", "breach", "breach!", "help!!")
	if(!over_radio && ((trim(lower_msg) in alarm_shouts) || bot_text_has_any(lower_msg, list("watch out", "look out", "run away", "there's a fire", "theres a fire", "breach", "get down"))))
		return pick("Where?!", "What?!", "Whoa, where?", "What is it?!")
	if(!over_radio && bot_text_has_any(lower_msg, list("got any tools", "have any tools", "any tools", "what tools")))
		var/list/tools = list()
		for(var/word in list("crowbar", "screwdriver", "wrench", "wirecutters", "welder", "multitool"))
			if(find_carried_tool(GLOB.bot_tool_words[word]))
				tools += word
		return length(tools) ? "I've got a [english_list(tools)]." : pick("Nope, nothing on me.", "Not a thing. Tool storage?")
	if(!over_radio && bot_text_has_any(lower_msg, list("fix this", "fix it", "repair this", "can you fix")))
		return (work_role() in list("Station Engineer", "Chief Engineer", "Atmospheric Technician")) ? pick("Sure, what's broken?", "What's wrong with it?", "Let's have a look.") : pick("Not my thing. Call an engineer.", "No idea how. Engineering?", "Wouldn't know where to start.")
	if(bot_text_has_any(lower_msg, list("clone me", "can you clone", "do you know surgery", "can you do surgery", "operate on me")))
		return is_medical_job() ? pick("Yeah, come to Medbay.", "Sure, Medbay's this way.", "Come on then.") : pick("I'm not a doctor. Try Medbay.", "That's Medbay's job.", "Not me, ask a doctor.")
	if(bot_text_has_any(lower_msg, list("seen anything weird", "seen anything strange", "seen anything suspicious", "anything weird", "anything suspicious", "anything strange")))
		return shift_news()
	if(bot_text_has_any(lower_msg, list("leave me alone", "go away", "get lost", "piss off", "buzz off")))
		return mood_pick(list("Sorry! Going.", "Okay, okay."), list("Fine.", "Alright, alright.", "Jeez, okay."), list("What's your problem?", "Make me.", "Rude."))
	if(!over_radio && bot_text_has_any(lower_msg, list("excuse me", "scuse me", "'scuse me", "coming through", "make way", "out of my way", "get out of the way", "move over", "move it")))
		step_aside_for(talker)
		return pick("Oh, sorry.", "Sorry!", "My bad.", "Go ahead.")
	if(!over_radio && bot_text_has_any(lower_msg, list("i need a doctor", "i need a medic", "get me a doctor", "get me a medic", "call a doctor", "call a medic", "i'm hurt", "im hurt", "i'm dying", "im dying", "heal me", "patch me up", "fix me up")))
		return help_find_a_doctor(talker)
	if(!over_radio && bot_text_has_any(lower_msg, list("give me that", "can i have that", "can i have it", "hand it over", "gimme that", "gimme", "can i have one", "give it here", "can i borrow that", "pass me that")))
		return hand_over_what_im_holding(talker)
	// "Where are you?" is about it, not somewhere to be pointed to: directions_for() said "No idea, sorry" to it ten times running.
	var/whereabouts = where_i_am(lower_msg)
	if(whereabouts)
		return whereabouts
	var/about_people = people_answer(lower_msg) //bot_conversation.dm
	if(about_people)
		return about_people
	if(bot_text_has_any(lower_msg, list("where is", "where's", "wheres", "where are", "how do i get to", "which way", "where can i find")))
		return directions_for(lower_msg)
	if(bot_text_has_any(lower_msg, list("how are you", "how's it going", "hows it going", "you ok", "you okay", "you alright", "how you doing")))
		if(owner.health < owner.maxHealth * 0.6)
			return pick("I've been better. Could really use a doctor.", "Not great, honestly.", "Hurting a bit.")
		return mood_pick(list("Great, thanks! You?", "Pretty good! How about you?", "Can't complain, nice shift so far."), list("Not bad. You?", "Can't complain.", "Fine, thanks.", "Surviving."), list("Could be worse.", "Ask me after the shift.", "Same as always.", "Don't ask."))
	if(bot_text_has_any(lower_msg, list("thanks", "thank you", "cheers", "ty")))
		return pick("No problem.", "Anytime.", "Don't mention it.")
	if(bot_text_has_any(lower_msg, GLOB.bot_insult_words))
		return insulted_by(talker) //bot_conversation.dm
	if(bot_text_has_any(lower_msg, list("sorry", "my bad", "apologies")))
		return pick("It's fine.", "Don't worry about it.", "No harm done.")
	if(bot_text_has_any(lower_msg, list("bye", "goodbye", "see you", "see ya", "cya", "take care", "later", "good night", "night night")))
		return pick("See you around.", "Later.", "Take care.")
	if(bot_text_has_any(lower_msg, GLOB.bot_greeting_words))
		var/their_name = talker.name != "Unknown" ? talker.first_name() : null
		return (their_name && prob(40)) ? "Hey, [their_name]." : pick(GLOB.bot_greeting_reply_lines)
	// Just its name ("Sam?"): that's it being called, not a question it can't answer
	if(named && just_my_name(lower_msg))
		return pick("Yeah?", "Yes?", "What's up?", "Here.")
	if(findtext(lower_msg, "?"))
		return pick(GLOB.bot_question_reply_lines)
	// Called by name and nothing else it understood. Someone just talking in its direction gets no stock reply; somebody it's
	// already talking with gets what you say to somebody who's told you something (bot_asks.dm keeps the conversation).
	if(named)
		return pick(GLOB.bot_name_called_lines)
	if(in_conversation_with(talker) && prob(over_radio ? 35 : 60))
		return mood_pick(list("Okay!", "Gotcha.", "Ah, right.", "Nice."), list("Right.", "Okay.", "Mm.", "Fair enough.", "Huh.", "If you say so."), list("Sure.", "Whatever you say.", "Uh huh.", "Okay..."))
	return null

// ---------------------------------------------------------------------------------------------
// What it knows
// ---------------------------------------------------------------------------------------------

/// What's the shuttle doing, the way anyone would put it. The same state the crew reads off the status displays.
/datum/bot_brain/proc/shuttle_news()
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	if(!E)
		return "No idea, sorry."
	var/minutes = round(E.timeLeft() / 600)
	switch(E.mode)
		if(SHUTTLE_CALL)
			return minutes >= 1 ? pick("It's on its way. About [minutes] minute\s out.", "Called already, [minutes] minute\s or so.") : pick("Any second now.", "It's nearly here.")
		if(SHUTTLE_RECALL)
			return pick("It got recalled.", "They called it back.")
		if(SHUTTLE_DOCKED)
			return pick("It's here! Get to departures.", "Docked. Get moving.")
		if(SHUTTLE_IGNITING)
			return pick("It's leaving now, run!", "Engines are going, hurry!")
		if(SHUTTLE_ESCAPE, SHUTTLE_ENDGAME)
			return pick("We're on our way home.", "Nearly there.")
	return pick("Not called yet, as far as I know.", "Nobody's called it.", "Not yet.")

/// How the shift's going, from what anyone could know: the shuttle, the alert level, the friends who've stopped answering.
/datum/bot_brain/proc/shift_news()
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	if(E && E.mode != SHUTTLE_IDLE && E.mode != SHUTTLE_RECALL)
		return shuttle_news()
	var/level = seclevel2num(get_security_level())
	if(level >= SEC_LEVEL_RED)
		return pick("Red alert, that's what. Keep your head down.", "We're on red. Stay away from the bad bits.")
	var/lost = 0
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.stat == DEAD && H.mind?.assigned_role)
			lost++
	var/latest = latest_news()
	if(latest)
		return prob(50) ? capitalize(latest) + "." : pick("Did you hear? ", "You missed it, ", "Well, ") + latest + "."
	if(lost)
		return pick("We've lost [lost] so far.", "[lost] dead that I know of. Watch yourself.")
	return level >= SEC_LEVEL_BLUE ? pick("Blue alert. Nothing's gone bang yet.", "Something's up, but it's quiet here.") : pick("Quiet shift so far.", "Not much. Same old.", "Nothing I've heard about.")

/// What people ask each other to borrow -> the item.
GLOBAL_LIST_INIT(bot_tool_words, list(
	"crowbar" = /obj/item/crowbar, "screwdriver" = /obj/item/screwdriver, "wrench" = /obj/item/wrench,
	"wirecutters" = /obj/item/wirecutters, "cutters" = /obj/item/wirecutters, "welder" = /obj/item/weldingtool,
	"welding tool" = /obj/item/weldingtool, "multitool" = /obj/item/multitool, "flashlight" = /obj/item/flashlight,
	"extinguisher" = /obj/item/extinguisher, "gloves" = /obj/item/clothing/gloves/color/yellow, "cable" = /obj/item/stack/cable_coil,
	"cigarette" = /obj/item/clothing/mask/cigarette, "lighter" = /obj/item/lighter, "insuls" = /obj/item/clothing/gloves/color/yellow,
	"insulated gloves" = /obj/item/clothing/gloves/color/yellow,
))

/// "Can you open this door?": the nearest door by them that this bot's ID opens and theirs doesn't, opened, or a word why not.
/datum/bot_brain/proc/open_a_door_for(mob/living/talker)
	var/obj/machinery/door/airlock/best
	for(var/obj/machinery/door/airlock/D in range(2, talker))
		if(!D.density || D.locked || D.welded || !D.hasPower() || D.allowed(talker))
			continue
		if(!best || get_dist(talker, D) < get_dist(talker, best))
			best = D
	if(!best)
		return pick("Which door?", "What door?", "It's open, isn't it?")
	if(!best.allowed(owner))
		return pick("Can't, I don't have access there.", "My ID won't open that one, sorry.", "No access, sorry. Ask the AI?")
	if(state == BOT_STATE_GOAL && current_goal && !current_goal.lawful)
		return pick("Bit busy right now.", "In a minute.")
	if(!owner.Adjacent(best))
		pursue(best, "follow", force = TRUE)
		addtimer(CALLBACK(src, PROC_REF(open_door_on_arrival), best), 3 SECONDS)
		return pick("Sure, hang on.", "One sec.", "Yeah, coming.")
	use_atom(best)
	return pick("There you go.", "There.", "Go on through.")

/datum/bot_brain/proc/open_door_on_arrival(obj/machinery/door/airlock/D)
	if(!QDELETED(D) && D.density && owner.Adjacent(D) && D.allowed(owner))
		use_atom(D)

/datum/bot_brain
	/// When it last stepped aside for somebody who walked into it (walked_into_by())
	var/last_made_way = 0

/// A player walked into it and couldn't get past (living/MobBump()): out of their way, as anybody would. In round-13.09.35 the Captain,
/// pulling a cuffed chemist out of the CE's office, pushed at an officer stood in the doorway for three seconds, and the officer never moved.
/// Not for somebody it's fighting or arresting, nor while it's dragging something itself.
/datum/bot_brain/proc/walked_into_by(mob/living/who)
	if(QDELETED(owner) || owner.stat != CONSCIOUS || owner.incapacitated() || owner.buckled || owner.pulling || world.time < last_made_way + 1 SECONDS)
		return
	if((state == BOT_STATE_COMBAT && attacker == who) || (state == BOT_STATE_ARREST && arrest_suspect == who))
		return
	if(gone_loud() && !on_my_side(who)) //a traitor in the open isn't polite to the crew
		return
	last_made_way = world.time
	if(step_aside_for(who) && prob(25))
		bot_say(owner, pick("Sorry.", "Oh, sorry.", "Go ahead.", "My bad."))

/// "Excuse me": a step to one side, out of their way.
/datum/bot_brain/proc/step_aside_for(mob/living/talker)
	var/turf/here = get_turf(owner)
	var/towards = get_dir(talker, owner)
	for(var/d in list(turn(towards, 90), turn(towards, -90), towards))
		var/turf/T = get_step(here, d)
		if(T && !T.density && !is_blocked_turf(T, TRUE) && !bot_turf_is_deadly(T) && !(locate(/mob/living) in T))
			step_to(owner, T)
			return TRUE
	return FALSE

/// "I need a doctor", said to its face: a doctor has a look, anybody else calls one for them on the radio if they're hurt.
/datum/bot_brain/proc/help_find_a_doctor(mob/living/carbon/human/talker)
	if(!istype(talker))
		return null
	var/hurt = talker.health < talker.maxHealth * 0.9 || talker.getToxLoss() > 10
	if(!hurt)
		return pick("You look fine to me?", "Where does it hurt?", "Medbay's the place for that.")
	if(is_medical_job())
		if(state != BOT_STATE_GOAL || !current_goal)
			called_patient = WEAKREF(talker)
			called_patient_until = world.time + 2 MINUTES
			assign_goal(new /datum/bot_goal/treat_patient())
		return pick("Let me have a look.", "Hold still, I've got you.", "Okay, let's see.")
	if(world.time >= next_call_time)
		var/where = get_area_name(owner, TRUE)
		call_for(/datum/bot_request_kind/medical, pick("Medic to [where], [talker.first_name()]'s hurt.", "Need a doctor in [where] for [talker.first_name()]."))
	return pick("Hang on, I'll call one.", "I'll get you a medic.", "Calling one now.")

/// "Give me that": what's in its hand, set down by them as anything's passed over in this game (lend_tool()), unless it needs it.
/datum/bot_brain/proc/hand_over_what_im_holding(mob/living/talker)
	var/obj/item/I = owner.get_active_held_item() || owner.get_inactive_held_item()
	if(!I)
		return pick("I'm not holding anything.", "Give you what?", "Got nothing in my hands.")
	if(HAS_TRAIT(I, TRAIT_NODROP) || istype(I, /obj/item/card/id) || istype(I, /obj/item/pda) || istype(I, /obj/item/gun) || (I == current_goal?.target))
		return pick("I need this, sorry.", "No, this one's mine.", "Get your own.")
	if(state == BOT_STATE_GOAL || !owner.Adjacent(talker) || trusts_not(talker))
		return pick("Not right now.", "I'm using it.", "Maybe later.")
	owner.dropItemToGround(I)
	return pick("Here.", "Sure, take it.", "All yours.")

/// Somebody it has a grudge against, or who's wanted: it doesn't hand them things.
/datum/bot_brain/proc/trusts_not(mob/living/talker)
	return bot_is_wanted(talker) || LAZYFIND(grudges, WEAKREF(talker))

/// The tool somebody's asking for, as an item type, or null if this isn't that. "got a crowbar?", "can I borrow your wrench"
/datum/bot_brain/proc/tool_asked_for(lower_msg)
	if(!bot_text_has_any(lower_msg, list("got a", "got any", "have a", "have any", "you got", "you have", "borrow", "lend me", "give me", "spare", "i need", "need some", "need a")))
		return null
	for(var/word in GLOB.bot_tool_words)
		if(bot_text_has_any(lower_msg, list(word)))
			return GLOB.bot_tool_words[word]
	return null

/// Asked for a tool: hands it over if it has one and isn't using it, set down where they can reach it. Hands are the
/// only way this game has of passing something over, so a person does the same.
/datum/bot_brain/proc/lend_tool(mob/living/asker, item_type)
	var/obj/item/I = find_carried_tool(item_type)
	if(!I || HAS_TRAIT(I, TRAIT_NODROP) || (I in owner.get_equipped_items()))
		return pick("Sorry, haven't got one.", "Nope, sorry.", "Try the tool storage.")
	if(state == BOT_STATE_GOAL || !owner.Adjacent(asker))
		return pick("I need mine, sorry.", "Using it right now.", "Come back in a bit.")
	if(!ready_in_hand(I))
		return "Can't get at it, sorry."
	owner.dropItemToGround(I)
	return pick("Here, take it.", "There you go.", "All yours.")

// ---------------------------------------------------------------------------------------------
// What it's doing, and which way things are
// ---------------------------------------------------------------------------------------------

/// What a bot says it's doing on each kind of goal, to finish "I'm ...". Newer goals carry their own (bot_goal.doing).
GLOBAL_LIST_INIT(bot_goal_descriptions, list(
	/datum/bot_goal/repair_cable = "fixing a broken cable",
	/datum/bot_goal/tend_tray = "looking after the plants",
	/datum/bot_goal/botany_supply = "fetching something for the plants",
	/datum/bot_goal/fill_bucket = "filling a bucket",
	/datum/bot_goal/get_seeds = "getting some seeds",
	/datum/bot_goal/stock_produce = "taking produce to the kitchen fridge",
	/datum/bot_goal/botany_project_errand = "working on a plant experiment",
	/datum/bot_goal/synthesize_medicine = "mixing up some medicine",
	/datum/bot_goal/treat_patient = "treating a patient",
	/datum/bot_goal/revive_patient = "trying to revive someone",
	/datum/bot_goal/escort_to_sleeper = "getting someone to a sleeper",
	/datum/bot_goal/connect_cryo_canister = "setting up the cryo tubes",
	/datum/bot_goal/activate_cryo_freezer = "setting up the cryo tubes",
	/datum/bot_goal/load_cryo_beaker = "setting up the cryo tubes",
	/datum/bot_goal/fight_fire = "putting out a fire",
	/datum/bot_goal/clean_contamination = "dealing with a gas leak",
	/datum/bot_goal/check_alert_console = "checking the alarms",
	/datum/bot_goal/activate_atmos_pump = "setting up the air supply",
	/datum/bot_goal/assemble_pa_part = "putting the particle accelerator together",
	/datum/bot_goal/activate_particle_accelerator = "starting the engine",
	/datum/bot_goal/activate_tesla_emitter = "setting up the engine",
	/datum/bot_goal/activate_field_generator = "setting up the engine",
	/datum/bot_goal/wrench_tesla_coil = "setting up the engine",
	/datum/bot_goal/wrench_grounding_rod = "setting up the engine",
	/datum/bot_goal/remove_singularity_generator = "setting up the engine",
	/datum/bot_goal/close_engine_shutters = "closing the engine shutters",
	/datum/bot_goal/engineer_gear = "getting my gear on",
	/datum/bot_goal/gear_up_for_eva = "suiting up",
	/datum/bot_goal/raid_suit_storage_unit = "suiting up",
	/datum/bot_goal/refill_internals = "refilling my air tank",
	/datum/bot_goal/seek_air = "trying to get somewhere I can breathe",
	/datum/bot_goal/self_heal = "patching myself up",
	/datum/bot_goal/seek_medbay_healing = "heading to medbay",
	/datum/bot_goal/respond_to_call = "answering a call for help",
	/datum/bot_goal/brig_prisoner = "taking someone to the brig",
	/datum/bot_goal/acquire_tool = "looking for a tool",
	/datum/bot_goal/acquire_item_type = "looking for something",
))

/// What the bot would say it's doing, to finish "I'm ..." - or null for nothing in particular.
/datum/bot_brain/proc/describe_activity()
	if(state == BOT_STATE_ARREST)
		return "making an arrest"
	if(state == BOT_STATE_COMBAT)
		return "a bit busy right now"
	var/datum/bot_goal/G = suspended_goal || current_goal
	if(G)
		if(G.doing)
			return G.doing
		for(var/path in GLOB.bot_goal_descriptions)
			if(istype(G, path))
				return GLOB.bot_goal_descriptions[path]
		return "working"
	if(owner.buckled)
		return "taking a break"
	return null

/// What people call a place -> a word its area's name has.
GLOBAL_LIST_INIT(bot_place_words, list(
	"medbay" = "Medbay", "medical" = "Medbay", "doctor" = "Medbay", "bar" = "Bar", "kitchen" = "Kitchen", "brig" = "Brig",
	"security" = "Security", "sec" = "Security", "cargo" = "Cargo", "bridge" = "Bridge", "engineering" = "Engineering",
	"engi" = "Engineering", "atmos" = "Atmospherics", "atmospherics" = "Atmospherics", "chemistry" = "Chemistry",
	"chem" = "Chemistry", "botany" = "Hydroponics", "hydroponics" = "Hydroponics", "science" = "Research",
	"research" = "Research", "rnd" = "Research", "robotics" = "Robotics", "hop" = "Head of Personnel",
	"arrivals" = "Arrival", "departures" = "Departure", "escape" = "Departure", "dorms" = "Dormitories",
	"dormitories" = "Dormitories", "chapel" = "Chapel", "library" = "Library", "janitor" = "Custodial",
	"custodial" = "Custodial", "eva" = "EVA", "tool storage" = "Tool Storage", "tools" = "Tool Storage", "morgue" = "Morgue",
	"genetics" = "Genetics", "virology" = "Virology", "cafeteria" = "Cafeteria", "mining" = "Mining", "theatre" = "Theatre",
	"armory" = "Armory", "courtroom" = "Courtroom", "teleporter" = "Teleporter", "gateway" = "Gateway", "vault" = "Vault",
	"toilet" = "Toilet", "bathroom" = "Toilet", "restroom" = "Toilet", "locker room" = "Locker", "garden" = "Garden",
	"detective" = "Detective", "captain" = "Captain", "xenobiology" = "Xenobiology", "toxins" = "Toxins",
	"hallway" = "Hallway", "maintenance" = "Maintenance", "maint" = "Maintenance", "hydro" = "Hydroponics",
	"disposals" = "Disposal", "lounge" = "Lounge", "holodeck" = "Holodeck", "quartermaster" = "Quartermaster",
))

/// "Where are you?", "where you at", "tell me your location", "are you in maintenance?": where it is by the area's name, and yes or no
/// when they've a place in mind. Null for anything else.
/datum/bot_brain/proc/where_i_am(lower_msg)
	var/asked_mine = bot_text_has_any(lower_msg, list("where are you", "where r u", "where are u", "where you at", "where ya at", "where u at", "wru", "your location", "your position", "whereabouts are you", "where you be", "coords", "coordinates", "co-ords", "your gps"))
	// Out in space it's where it is by the numbers: what it gave calling for help, and all anybody coming out can steer by
	var/turf/out_there = get_turf(owner)
	if(asked_mine && isspaceturf(out_there))
		return pick("Out in space at [out_there.x], [out_there.y].", "[out_there.x], [out_there.y], out in space.", "In space, [out_there.x], [out_there.y].")
	var/asked_if_in = bot_text_has_any(lower_msg, list("are you in", "you in the", "r u in", "are you at", "you at the", "you still in"))
	if(!asked_mine && !asked_if_in)
		return null
	var/place = get_area_name(owner, TRUE)
	if(asked_if_in)
		for(var/word in GLOB.bot_place_words)
			if(!bot_text_has_any(lower_msg, list(word)))
				continue
			if(findtext(place, GLOB.bot_place_words[word]))
				return pick("Yeah, [place].", "Yep, I'm in [place].", "That's right, [place].")
			return pick("No, I'm in [place].", "Nope, [place].", "No, [place]. Why?")
		if(!asked_mine)
			return null
	return mood_pick(list("I'm in [place]! What's up?", "[place]. Need me?"), list("[place].", "I'm in [place].", "[place], why?"), list("[place]. Why?", "[place]. What do you want?"))

/// Asked about being out in space after it called for help ("you stuck?", "trying to help", "coming to get you"): where it still is,
/// or that it's back. Sam called from space, was back in EVA a minute later, and to "coords?", "you're adrift though?" and "trying
/// to help" said "Couldn't tell you", "Beats me" and "Yeah, that's me" while the CE searched space for him.
/datum/bot_brain/proc/adrift_answer(lower_msg)
	if(!drift_called_for_help && world.time > drift_back_at + 5 MINUTES)
		return null
	if(!bot_text_has_any(lower_msg, list("adrift", "stuck", "in space", "drifting", "still out", "you ok", "you okay", "you alright", "help you", "trying to help", "get you", "on my way", "omw", "i'm coming", "im coming", "coming for you", "jetpack", "rescue")))
		return null
	var/turf/here = get_turf(owner)
	if(drift_called_for_help)
		return pick("Still out here at [here.x], [here.y]!", "Yeah, still drifting. [here.x], [here.y].", "Please hurry, I'm at [here.x], [here.y].")
	return pick("I'm back inside now, all good. Thanks though!", "Made it back in on my own. Thanks!", "All good now, I got back in.")

/// Nothing in it but its name and a hello: "Sam?", "yo Sam"
/datum/bot_brain/proc/just_my_name(lower_msg)
	var/static/regex/not_letters = regex("\[^a-z ]", "g")
	var/rest = " [not_letters.Replace(lower_msg, "")] "
	for(var/word in list(lowertext(owner.real_name), lowertext(owner.first_name()), "hey", "yo", "oi", "hello", "hi"))
		rest = replacetext(rest, " [word] ", " ")
	return !length(trim(rest))

/// "Medbay? East of here." - the way anyone points a newcomer, by compass rather than by map.
/datum/bot_brain/proc/directions_for(lower_msg)
	var/asked
	var/keyword
	for(var/word in GLOB.bot_place_words)
		if(bot_text_has_any(lower_msg, list(word)) && (!asked || length(word) > length(asked)))
			asked = word
			keyword = GLOB.bot_place_words[word]
	if(!keyword)
		return pick("No idea, sorry.", "Couldn't tell you.", "Not sure where that is.")
	var/turf/here = get_turf(owner)
	var/turf/nearest
	for(var/area_name in GLOB.teleportlocs)
		if(!findtext(area_name, keyword))
			continue
		var/area/AR = GLOB.teleportlocs[area_name]
		if(AR == get_area(owner))
			return pick("You're standing in it.", "This is it.", "Right here.")
		var/turf/spot = locate(/turf/open) in AR
		if(spot && spot.z == here.z && (!nearest || get_dist(here, spot) < get_dist(here, nearest)))
			nearest = spot
	if(!nearest)
		return pick("No idea, sorry.", "Couldn't tell you.", "Not sure where that is.")
	var/way = dir2text(get_dir(here, nearest))
	var/far = get_dist(here, nearest)
	var/place = capitalize(asked)
	if(far < 12)
		return pick("[place]? Just [way] of here.", "It's right there, [way].")
	if(far < 45)
		return pick("[place]? [capitalize(way)] of here.", "Head [way], you'll see it.")
	return pick("[place]? A fair way [way] of here.", "Other side of the station - keep going [way].")

// ---------------------------------------------------------------------------------------------
// Tagging along
// ---------------------------------------------------------------------------------------------

/// Asked to come along: says yes and follows for a minute or so, unless it has something better to do.
/datum/bot_brain/proc/try_tag_along(mob/living/leader)
	if(state != BOT_STATE_WANDER || goal_chain_pending)
		var/doing = describe_activity()
		return doing ? "Can't right now, I'm [doing]." : "Can't right now, sorry."
	if(!assign_goal(new /datum/bot_goal/tag_along(leader)))
		return "Can't right now, sorry."
	if(owner.buckled)
		owner.buckled.unbuckle_mob(owner, force = TRUE)
	return pick("Sure, lead the way.", "Right behind you.", "Okay, where to?")

/datum/bot_goal/tag_along
	lawful = TRUE
	/// Told it can go.
	var/dismissed = FALSE

/datum/bot_goal/tag_along/New(mob/living/leader)
	. = ..()
	target = leader
	doing = "following [leader] about"

/datum/bot_goal/tag_along/resolve_target(datum/bot_brain/bot)
	return //set in New()

/datum/bot_goal/tag_along/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/tag_along/S = new
	S.steps = list(new /datum/bot_step/paced/tag_along())
	return list(S)

/datum/bot_strategy/tag_along/is_feasible(datum/bot_brain/bot)
	return TRUE

/// Keeps a couple of steps behind the leader, re-routing as they move, until dismissed or it's been long enough.
/datum/bot_step/paced/tag_along
	var/until = 0
	var/turf/heading_for

/datum/bot_step/paced/tag_along/start(datum/bot_brain/bot)
	until = world.time + rand(600, 900)
	heading_for = null
	return TRUE

/datum/bot_step/paced/tag_along/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/tag_along/G = bot.current_goal
	var/mob/living/leader = G?.target
	if(!istype(G) || G.dismissed || QDELETED(leader) || leader.stat == DEAD || world.time >= until)
		return FALSE
	var/turf/their_turf = get_turf(leader)
	if(!their_turf || their_turf.z != bot.owner.z || get_dist(bot.owner, their_turf) > 25)
		return FALSE //lost them
	wait_for = 10
	if(get_dist(bot.owner, their_turf) <= 2)
		if(!bot.pursuing_kind)
			bot.owner.face_atom(leader)
		return TRUE
	// Only a new route once they've moved on from where the last one led.
	if(bot.pursuing_kind != "follow" || !heading_for || get_dist(heading_for, their_turf) > 2)
		heading_for = their_turf
		bot.pursue(leader, "follow", force = TRUE)
	return TRUE

/datum/bot_step/paced/tag_along/finish(datum/bot_brain/bot)
	bot.stop_pursuit()
	var/datum/bot_goal/tag_along/G = bot.current_goal
	if(istype(G) && !G.dismissed && !QDELETED(G.target) && get_dist(bot.owner, G.target) <= 4)
		bot.say_after_typing(pick("I should get back to it.", "Right, I'd better be off.", "Anyway, things to do."))
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// Small talk
// ---------------------------------------------------------------------------------------------

/// An opening line and what it might get back. Said to whoever is standing about nearby.
GLOBAL_LIST_INIT(bot_small_talk, list(
	list("Quiet shift so far.", list("Don't jinx it.", "Give it time.", "Suits me.")),
	list("How's your shift going?", list("Can't complain.", "Slow. Yours?", "Same as always.")),
	list("Has anyone seen the captain today?", list("Not once.", "Probably hiding on the bridge.", "Do we even have one?")),
	list("I could go for a coffee.", list("There's a machine round the corner.", "Same.", "Get me one too.")),
	list("Did the lights just flicker?", list("Didn't notice.", "Engineering's problem.", "Probably nothing.")),
	list("Anything good in the kitchen today?", list("Haven't looked.", "The usual.", "Wouldn't risk it.")),
	list("I swear the vents smell weird today.", list("That's atmos for you.", "I thought it was just me.", "Don't breathe so deep.")),
	list("You hear the clown's been at it again?", list("When isn't he.", "No, what happened?", "Typical.")),
	list("How long until the shuttle, you reckon?", list("Hours yet.", "Not soon enough.", "Depends who blows what up.")),
	list("I heard cargo ordered something weird again.", list("They always do.", "Not my department.", "As long as it isn't another goose.")),
	list("Long shift.", list("Tell me about it.", "It's only just started.", "Yep.")),
	list("Seen anything strange today?", list("Define strange.", "Nothing yet.", "On this station? Constantly.")),
	list("My feet are killing me.", list("Sit down then.", "Mine too.", "Should've worn better shoes.")),
	list("You on break?", list("Something like that.", "Don't tell my boss.", "Just for a minute.")),
	list("Is it me or is it cold in here?", list("It's you.", "Bit chilly, yeah.", "Complain to atmos.")),
	list("Anyone know what's for lunch?", list("Whatever the cook feels like.", "Vending machine, probably.", "No idea.")),
	list("I keep losing my pen.", list("Check your PDA.", "Classic.", "Someone's got a drawer full of them.")),
	list("You ever actually read the space law book?", list("Skimmed it.", "Does anyone?", "I know the important bits.")),
	list("I think Ian likes me.", list("Ian likes everyone.", "He likes whoever has food.", "Good for you.")),
	list("Hope nothing explodes today.", list("Bold thing to hope for.", "There's always tomorrow.", "Same.")),
))

/// What a playstyle goes on about (bot_personality.dm).
GLOBAL_LIST_INIT(bot_playstyle_talk, list(
	BOT_STYLE_PARANOID = list(
		list("Keep your eyes open. Something's off today.", list("You always say that.", "Like what?", "You're making me nervous.")),
		list("You've got a weapon on you, right?", list("Should I?", "Why, what have you heard?", "Of course.")),
		list("I don't trust half this crew.", list("Which half?", "Only half?", "Should I be worried?")),
		list("Where were you ten minutes ago?", list("Why do you ask?", "Working. Why?", "Relax.")),
		list("I've got heals if it comes to it.", list("Good to know.", "Hope it doesn't.", "Got any spare?")),
	),
	BOT_STYLE_POWERGAMER = list(
		list("Everything I need's in the bag already.", list("Course it is.", "Save some for the rest of us.", "Show off.")),
		list("Whoever stocked that locker's an idiot.", list("That was probably you.", "Could be worse.", "Fix it then.")),
		list("If you're not ready by now you're already dead.", list("Cheery.", "It's a space station, not a war.", "Noted.")),
		list("I've been through the whole lab already.", list("Find anything good?", "Is that allowed?", "Of course you have.")),
	),
	BOT_STYLE_HUNTER = list(
		list("Seen anyone acting shifty?", list("Only you.", "Not yet.", "Define shifty.")),
		list("Somebody's a traitor. Somebody always is.", list("Probably.", "Got a name?", "Bit dark.")),
		list("Tell me if you see anything. Anything.", list("Will do.", "Sure, officer.", "Are you even Security?")),
		list("I've got my eye on someone.", list("Who?", "Don't do anything stupid.", "Is it me?")),
	),
	BOT_STYLE_HOPPER = list(
		list("Need a hand with anything?", list("Always.", "We're fine, thanks.", "Aren't you busy?")),
		list("I'll do anything, honestly. Just tell me what's short.", list("Medbay's always short.", "Ask the HoP.", "Good attitude.")),
		list("This is my third job today.", list("Doing any of them well?", "Do they pay you for all three?", "Busy shift.")),
	),
))

/// What's said back to a bit of news.
GLOBAL_LIST_INIT(bot_news_replies, list("No way.", "Figures.", "Who's next?", "That's this place all over.", "I heard.", "Yeah, I heard that too.",
	"Wow.", "Not surprised.", "Can't say I'm sorry.", "Keep your head down.", "Great, that's all we need.", "Really?"))

/// Shop talk, by department: said by someone who works there, answered by anyone.
GLOBAL_LIST_INIT(bot_shop_talk, list(
	"engineering" = list("Engine's holding steady.", "Something's been chewing the power cables again.", "If the lights go out, it wasn't me."),
	"medical" = list("Medbay's quiet for once.", "Come by if you need patching up.", "Somebody's been at the medicine cabinet."),
	"security" = list("Keep out of trouble, yeah?", "Quiet in the brig today.", "Seen anything I should know about?"),
	"science" = list("Research is coming along.", "Don't go in toxins without asking.", "We should have upgrades soon."),
	"supply" = list("If you need something ordered, put a request in.", "Shuttle's due soon.", "Cargo bay's a mess again."),
	"service" = list("Fresh food in the kitchen if you're hungry.", "Bar's open, by the way.", "Mind the wet floor."),
))
GLOBAL_LIST_INIT(bot_shop_talk_replies, list("Good to know.", "Nice.", "Noted.", "Alright.", "Glad to hear it.", "I'll bear it in mind."))
GLOBAL_LIST_INIT(bot_shop_talk_good_replies, list("Nice.", "Glad to hear it.", "Good.", "Nice one.", "Keep it up."))
GLOBAL_LIST_INIT(bot_shop_talk_bad_replies, list("That's not good.", "Yikes.", "Hope it holds.", "Shout if you need a hand.", "Great, that's all we need."))
GLOBAL_LIST_INIT(bot_shop_talk_plain_replies, list("Good to know.", "Noted.", "Alright.", "Huh.", "I'll bear it in mind."))

/// How its department really is right now, the way somebody working there would say it: list(line, "good", "bad" or "plain"), or null
/// when there's nothing to say. The fixed lines had "Engine's holding steady." with the crystal at half, and "Medbay's quiet for
/// once." with the beds full.
/datum/bot_brain/proc/shop_talk_now()
	switch(department())
		if("engineering")
			var/obj/machinery/power/supermatter_crystal/S = GLOB.main_supermatter_engine
			if(S && !QDELETED(S) && S.z == owner.z && S.power > 0)
				var/integrity = round(S.get_integrity())
				if(integrity < 95)
					return list(pick("The crystal's down to [integrity]%. Nobody touch anything.", "Supermatter's at [integrity]%, I'm keeping an eye on it."), "bad")
				return list(pick("Crystal's holding at full integrity.", "Supermatter's running nice and stable."), "good")
			var/smes = bot_smes_percent(owner.z)
			if(!isnull(smes))
				if(smes < 15)
					return list(pick("The SMES are nearly flat, [smes]%.", "Power's running out. SMES are at [smes]%."), "bad")
				return list(pick("SMES are at [smes]%.", "Power's fine. SMES at [smes]%."), smes >= 50 ? "good" : "plain")
		if("medical")
			var/patients = bot_medbay_patients(owner.z)
			if(patients >= 3)
				return list(pick("[patients] in Medbay right now. It's mad.", "We've got [patients] patients in. Busy one."), "bad")
			if(patients)
				return list(pick("Just the [patients == 1 ? "one patient" : "two patients"] in Medbay.", "Medbay's alright, [patients] in."), "plain")
			return list(pick("Medbay's quiet for once.", "Nobody in Medbay right now."), "good")
		if("security")
			var/held = bot_brig_cells_in_use(owner.z)
			if(held >= 3)
				return list(pick("[held] in the cells. Busy shift.", "Brig's filling up, [held] cells in use."), "bad")
			if(held)
				return list(pick("[held == 1 ? "Somebody's" : "[held] of them are"] in the cells right now.", "Got [held] in the brig."), "plain")
			return list(pick("Brig's empty.", "Nobody in the cells yet."), "good")
		if("science")
			var/nodes = length(SSresearch.science_tech.researched_nodes)
			return list(pick("We're [nodes] nodes in.", "[nodes] nodes researched so far."), nodes >= 20 ? "good" : "plain")
		if("supply")
			var/datum/bank_account/D = SSeconomy.get_dep_account(ACCOUNT_CAR)
			if(D)
				var/credits = round(D.account_balance)
				return list(pick("Cargo's got [credits] credits, if you need anything ordered.", "Budget's at [credits]. Put a request in if you need something."), credits >= 2000 ? "good" : "plain")
	return null

/// How full the station's SMES are, out of 100; null with none on this level.
/proc/bot_smes_percent(z)
	var/charge = 0
	var/capacity = 0
	for(var/obj/machinery/power/smes/S in GLOB.machines)
		if(S.z == z && istype(get_area(S), /area/engine))
			charge += S.charge
			capacity += S.capacity
	return capacity ? round(100 * charge / capacity) : null

/// Hurt people in Medbay who aren't its own staff.
/proc/bot_medbay_patients(z)
	. = 0
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.z != z || H.stat == DEAD || !istype(get_area(H), /area/medical) || (H.mind?.assigned_role in GLOB.medical_positions))
			continue
		if(H.health < H.maxHealth * 0.9 || H.buckled)
			.++

/// Brig cells with a sentence running.
/proc/bot_brig_cells_in_use(z)
	. = 0
	for(var/obj/machinery/door_timer/T in GLOB.machines)
		if(T.z == z && T.timing)
			.++

/datum/bot_brain/proc/department()
	var/role = work_role()
	if(role in GLOB.engineering_positions)
		return "engineering"
	if(role in GLOB.medical_positions)
		return "medical"
	if(role in GLOB.security_positions)
		return "security"
	if(role in GLOB.science_positions)
		return "science"
	if(role in list("Quartermaster", "Cargo Technician", "Shaft Miner"))
		return "supply"
	if(role in list("Bartender", "Botanist", "Cook", "Janitor"))
		return "service"
	return null

/// Someone awake and close enough to chat to, the nearest first.
/datum/bot_brain/proc/someone_to_talk_to()
	var/mob/living/carbon/human/nearest
	for(var/mob/living/carbon/human/H in view(3, owner))
		if(H == owner || H.stat != CONSCIOUS)
			continue
		if(!nearest || get_dist(owner, H) < get_dist(owner, nearest))
			nearest = H
	return nearest

/datum/bot_brain/proc/handle_idle_chat()
	if(world.time < next_chat_time)
		return
	next_chat_time = world.time + rand(600, 1800) / (0.5 + sociability)
	if(gym_scripted || state == BOT_STATE_COMBAT || state == BOT_STATE_ARREST || owner.stat != CONSCIOUS)
		return
	var/mob/living/carbon/human/company = someone_to_talk_to()
	if(maybe_report_mess()) //bot_requests.dm
		return
	if(company)
		if(company.bot_brain && temper >= 0.65 && prob(15) && start_argument(company)) //bot_conversation.dm
			return
		if(prob(40 + sociability * 40))
			make_small_talk(company)
	else if(prob(8))
		bot_say(owner, idle_mutter()) //muttering to nobody is the exception

/// Something to say to nobody in particular: how it's doing first, when there's anything to say about that. Six stock lines were all
/// there was, and "Has anyone seen my ID around here?" came round 29 times in three shifts, from people wearing theirs.
/datum/bot_brain/proc/idle_mutter()
	var/list/options = list()
	if(owner.nutrition < NUTRITION_LEVEL_HUNGRY)
		options += list("I need to eat something.", "Starving.", "Could murder a sandwich right now.")
	if(owner.health < owner.maxHealth * 0.7)
		options += list("Ow. I should get this looked at.", "That really hurts.")
	if(istype(get_area(owner), /area/maintenance))
		options += list("It's creepy down here.", "Who keeps leaving trash in maintenance?", "Should've brought a flashlight.")
	var/shift_minutes = (world.time - SSticker.round_start_time) / (1 MINUTES)
	if(shift_minutes > 45)
		options += list("This shift is dragging on.", "Long shift.", "Feels like I've been here all day.")
	else if(shift_minutes < 10)
		options += list("Right, let's get started.", "New shift, same station.")
	if(length(options) && prob(70))
		return pick(options)
	var/list/stock = GLOB.bot_idle_lines.Copy()
	if(!owner.wear_id)
		stock += "Has anyone seen my ID around here?" // only somebody without one
	return pick(stock)

/datum/bot_brain/proc/make_small_talk(mob/living/carbon/human/company)
	if(gone_loud())
		return
	var/opener
	var/list/replies
	var/dept = department()
	var/list/shop = dept ? GLOB.bot_shop_talk[dept] : null
	var/news = prob(50) ? latest_news(company, TRUE) : null
	var/list/style = GLOB.bot_playstyle_talk[is_paranoid() ? BOT_STYLE_PARANOID : playstyle]
	if(news)
		opener = pick("Did you hear? ", "You hear about it? ", "So, ", "Word is ") + news + "."
		replies = GLOB.bot_news_replies
		LAZYOR(news_told, news)
		if(company.bot_brain)
			LAZYOR(company.bot_brain.news_told, news) //it's heard it now, and won't be telling this one back
	else if(style && prob(25))
		var/list/exchange = pick(style)
		opener = exchange[1]
		replies = exchange[2]
	else if(shop && prob(30))
		var/list/fact = shop_talk_now()
		if(fact)
			opener = fact[1]
			replies = fact[2] == "good" ? GLOB.bot_shop_talk_good_replies : (fact[2] == "bad" ? GLOB.bot_shop_talk_bad_replies : GLOB.bot_shop_talk_plain_replies)
		else
			opener = pick(shop)
			replies = GLOB.bot_shop_talk_replies
	else
		var/list/exchange = pick(GLOB.bot_small_talk)
		opener = exchange[1]
		replies = exchange[2]
	if((opener in GLOB.bot_calm_lines) && bot_shift_gone_bad())
		return
	var/datum/bot_brain/other = company.bot_brain
	var/they_answer = other && other.state != BOT_STATE_COMBAT && other.state != BOT_STATE_ARREST && company.can_hear()
	if(they_answer)
		other.next_reaction_time = world.time + 100 //it has its answer already - not a stock one as well
	if(!pursuing_kind)
		owner.face_atom(company)
	bot_say(owner, opener)
	bot_log(src, "said \"[opener]\" to [company]")
	if(they_answer)
		if(!other.pursuing_kind)
			company.face_atom(owner)
		other.say_after_typing(pick(replies))

// ---------------------------------------------------------------------------------------------
// News
// ---------------------------------------------------------------------------------------------

/// What's happened this round that people would talk about: list(what, when, who it was). The newest last.
GLOBAL_LIST_EMPTY(bot_news)

/// Something for the crew to talk about, in the words they'd use, with no capital or full stop: it goes in the middle of a sentence.
/proc/bot_news(what, mob/living/about)
	for(var/list/old as anything in GLOB.bot_news)
		if(old[1] == what)
			return
	GLOB.bot_news += list(list(what, world.time, about ? WEAKREF(about) : null))
	if(length(GLOB.bot_news) > 30)
		GLOB.bot_news.Cut(1, 2)

/// Something from the last ten minutes, that isn't about the bot it's being said to. Asked for gossip, something it hasn't been over already.
/datum/bot_brain/proc/latest_news(mob/living/company, fresh_only = FALSE)
	for(var/i in length(GLOB.bot_news) to 1 step -1)
		var/list/item = GLOB.bot_news[i]
		if(world.time > item[2] + BOT_NEWS_LIFETIME)
			return null
		if(fresh_only && LAZYFIND(news_told, item[1]))
			continue
		var/datum/weakref/about = item[3]
		var/mob/living/who = about?.resolve()
		if(who == owner || (company && who == company))
			continue
		return item[1]
	return null

// ---------------------------------------------------------------------------------------------
// Arriving
// ---------------------------------------------------------------------------------------------

/// A new arrival says hello on its department's channel, the way latejoiners do.
/datum/bot_brain/proc/say_hello_on_arrival()
	if(QDELETED(owner) || owner.stat != CONSCIOUS || gym_scripted)
		return
	var/dept = department()
	if(!dept || !prob(30 + sociability * 50))
		return
	bot_say(owner, ":h [pick("Hey all.", "Morning, [dept].", "Hi, just got in.", "Hello hello.", "Reporting in.", "Hey, anything need doing?")]")

#undef BOT_CHAT_PROPER
#undef BOT_CHAT_LOWERCASE
#undef BOT_CHAT_TERSE
