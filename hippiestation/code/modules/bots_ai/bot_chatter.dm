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

/datum/bot_brain
	var/chat_style = BOT_CHAT_PROPER
	/// Matches this bot's first or full name as whole words - built on first use.
	var/regex/name_regex
	/// When it will next answer someone talking to it (next_reaction_time, bot_brain.dm, paces everything else).
	var/next_answer_time = 0

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

/datum/bot_brain/proc/on_heard_speech(atom/movable/speaker, raw_message, radio_freq)
	if(!raw_message || QDELETED(owner) || owner.stat != CONSCIOUS)
		return
	var/mob/living/talker = speaker
	if(istype(speaker, /atom/movable/virtualspeaker))
		var/atom/movable/virtualspeaker/V = speaker
		talker = V.source
	if(!isliving(talker) || talker == owner)
		return
	// Bots talk to each other through make_small_talk() below. Answering whatever another bot says as well would
	// have two of them alone in a room trading stock replies for the rest of the shift.
	var/mob/living/carbon/human/crewmate = talker
	if(istype(crewmate) && crewmate.bot_brain)
		return

	var/lower_msg = lowertext(raw_message)
	var/named = hears_own_name(lower_msg)
	// A call for somebody of this bot's trade, or for this bot by name to come somewhere (bot_requests.dm).
	if(heard_call(talker, lower_msg, radio_freq, named))
		return
	// Over the radio it only answers to its name - half the station isn't talking to it.
	var/addressed = named || (!radio_freq && is_spoken_to_by(talker))
	if(!addressed && (radio_freq || get_dist(owner, talker) > 3))
		return
	// Someone talking to it gets an answer every time; what it merely overhears, it reacts to now and then.
	if(world.time < (addressed ? next_answer_time : next_reaction_time))
		return
	var/reply
	if(addressed)
		next_answer_time = world.time + 25
		reply = answer_for(talker, lower_msg, !!radio_freq, named)
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
	var/static/list/cache = list()
	for(var/word in words)
		var/regex/R = cache[word]
		if(!R)
			R = regex("\\b[word]\\b", "i")
			cache[word] = R
		if(R.Find(text))
			return TRUE
	return FALSE

/// What to say back to something said to this bot in particular, or null if it has nothing to say to it.
/datum/bot_brain/proc/answer_for(mob/living/talker, lower_msg, over_radio, named)
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
	if(bot_text_has_any(lower_msg, list("who are you", "your name", "your job", "what do you do", "what's your job", "whats your job")))
		var/role = owner.mind?.assigned_role
		var/post = ""
		if(role == "Assistant")
			post = " Just an assistant."
		else if(role)
			post = " I'm the [lowertext(role)]."
		return "I'm [owner.first_name()].[post]"
	if(bot_text_has_any(lower_msg, list("where is", "where's", "wheres", "where are", "how do i get to", "which way", "where can i find")))
		return directions_for(lower_msg)
	if(bot_text_has_any(lower_msg, list("how are you", "how's it going", "hows it going", "you ok", "you okay", "you alright", "how you doing")))
		if(owner.health < owner.maxHealth * 0.6)
			return pick("I've been better. Could really use a doctor.", "Not great, honestly.", "Hurting a bit.")
		return pick("Not bad. You?", "Can't complain.", "Fine, thanks.", "Surviving.")
	if(bot_text_has_any(lower_msg, list("thanks", "thank you", "cheers", "ty")))
		return pick("No problem.", "Anytime.", "Don't mention it.")
	if(bot_text_has_any(lower_msg, list("idiot", "stupid", "moron", "fuck you", "shut up", "asshole", "dumbass")))
		return pick("Rude.", "What's your problem?", "Yeah, okay.", "Charming.")
	if(bot_text_has_any(lower_msg, list("sorry", "my bad", "apologies")))
		return pick("It's fine.", "Don't worry about it.", "No harm done.")
	if(bot_text_has_any(lower_msg, list("bye", "goodbye", "see you", "see ya", "cya")))
		return pick("See you around.", "Later.", "Take care.")
	if(bot_text_has_any(lower_msg, GLOB.bot_greeting_words))
		var/their_name = talker.name != "Unknown" ? talker.first_name() : null
		return (their_name && prob(40)) ? "Hey, [their_name]." : pick(GLOB.bot_greeting_reply_lines)
	if(findtext(lower_msg, "?"))
		return pick(GLOB.bot_question_reply_lines)
	// Called by name and nothing else it understood. Someone just talking in its direction gets no stock reply.
	return named ? pick(GLOB.bot_name_called_lines) : null

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

/datum/bot_brain/proc/department()
	var/role = owner.mind?.assigned_role
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
		if(prob(40 + sociability * 40))
			make_small_talk(company)
	else if(prob(8))
		bot_say(owner, pick(GLOB.bot_idle_lines)) //muttering to nobody is the exception

/datum/bot_brain/proc/make_small_talk(mob/living/carbon/human/company)
	var/opener
	var/list/replies
	var/dept = department()
	var/list/shop = dept ? GLOB.bot_shop_talk[dept] : null
	if(shop && prob(30))
		opener = pick(shop)
		replies = GLOB.bot_shop_talk_replies
	else
		var/list/exchange = pick(GLOB.bot_small_talk)
		opener = exchange[1]
		replies = exchange[2]
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
