// Banter: what somebody says to a bot for the fun of it, answered in kind. The user's ruling (2026-11-12): jokes, insults,
// compliments, flirting and arguing answered in kind instead of stock replies. Insults and compliments were already handled
// (bot_conversation.dm, bot_chatter.dm); this is the rest, by mood and by what it thinks of whoever's talking (bot_social.dm).

/datum/bot_brain
	/// A joke's punchline it's waiting to deliver
	var/joke_punchline_at = 0

/// What to say back to banter, or null if it isn't any.
/datum/bot_brain/proc/banter_answer(mob/living/talker, lower_msg)
	var/r = regard_of(talker)
	// "Tell me a joke"
	if(bot_text_has_any(lower_msg, list("tell me a joke", "know any jokes", "tell a joke", "say something funny", "make me laugh", "got any jokes")))
		if(temper >= 0.7 && r < 2)
			return pick("I'm not a clown.", "Ask the clown.", "No.")
		var/list/J = pick(GLOB.bot_jokes)
		last_joke_at = world.time
		joke_punchline_at = world.time + 4 SECONDS
		// After the setup's out, however long that takes to type (bot_typing_time(): 1.4 s plus 0.12 s a letter at most), and a beat
		addtimer(CALLBACK(src, PROC_REF(say_after_typing), J[2]), 14 + min(length(J[1]) * 1.2, 50) + rand(15, 30))
		return J[1]
	// Laughing at it
	if(length(lower_msg) <= 14 && bot_text_has_any(lower_msg, list("lol", "lmao", "lmfao", "haha", "hahaha", "rofl", "kek", "xd", "hah", "heh")))
		if(world.time < last_joke_at + 1 MINUTES)
			return pick("Thank you, thank you.", "I'm here all shift.", "Right?", "Ha.")
		return prob(50) ? pick("What's funny?", "Ha.", "lol") : null
	// Flirting
	if(bot_text_has_any(lower_msg, list("you're hot", "youre hot", "you're cute", "youre cute", "date me", "marry me", "go out with me", "wanna go out", "want to go out", "kiss me", "i love you", "be my", "you're pretty", "youre pretty", "you're handsome", "youre handsome", "hey cutie", "hey sexy", "sexy")))
		feel(talker, r >= 0 ? 0.3 : -0.3)
		if(r <= -3)
			return pick("Gross.", "No.", "Not in a million years.", "Get away from me.")
		if(r >= 4 && sociability >= 0.5)
			return pick("Ha, buy me a drink first.", "Smooth.", "Maybe after the shift.", "Stop it, you.")
		if(temper >= 0.65)
			return pick("Not interested.", "I'm working.", "Nope.")
		return mood_pick(list("Aw, ha. Thanks?", "Oh! Um. Thanks.", "Ha, you're sweet."), list("Uh. Thanks?", "I'm flattered. I think.", "...Okay."), list("No.", "Not interested."))
	// Arguing
	if(bot_text_has_any(lower_msg, list("you're wrong", "youre wrong", "you are wrong", "that's not true", "thats not true", "liar", "you lie", "you're lying", "youre lying", "prove it", "no u", "nuh uh", "you don't know", "you dont know", "bullshit")))
		if(temper >= 0.6)
			return pick("I know what I saw.", "Believe what you want.", "Whatever.", "Am not.", "Prove I'm wrong, then.")
		return mood_pick(list("Okay, okay, maybe.", "Could be, I guess.", "Hey, I'm just saying."), list("Believe what you want.", "Suit yourself.", "If you say so."), list("Whatever.", "I know what I saw."))
	// Favourites
	if(bot_text_has_any(lower_msg, list("favourite", "favorite", "fav")))
		return favourite_answer(lower_msg)
	// About the job
	if(bot_text_has_any(lower_msg, list("like your job", "enjoy your job", "enjoying your job", "like working here", "like it here", "happy here")))
		if(diligence >= 0.75)
			return pick("Yeah, actually.", "Love it. Mostly.", "Somebody's got to do it, and I'm good at it.")
		if(diligence <= 0.45)
			return pick("It pays.", "Not really.", "Ask me when the shuttle comes.", "It's a job.")
		return pick("It's alright.", "Could be worse.", "Has its moments.")
	if(bot_text_has_any(lower_msg, list("are you happy", "you happy", "how do you feel", "how are you feeling")))
		if(owner.health < owner.maxHealth * 0.7)
			return pick("Not really, I'm hurt.", "Been better.")
		return mood_pick(list("Pretty happy, yeah!", "Can't complain!"), list("I'm alright.", "Fine, I guess."), list("No.", "Ask me after the shift."))
	if(bot_text_has_any(lower_msg, list("where are you from", "where you from", "where'd you come from")))
		return pick("Mars, originally.", "Tau Ceti.", "A mining colony you've never heard of.", "Earth. Long story.", "Lavaland. Kidding.", "Here and there.")
	if(bot_text_has_any(lower_msg, list("how old are you", "your age", "how old r u")))
		return pick("Old enough.", "Older than I look.", "[rand(22, 54)].", "Rude.")
	if(bot_text_has_any(lower_msg, list("nice to meet you", "pleased to meet you", "good to meet you")))
		chatted_with(talker)
		return pick("You too.", "Likewise.", "Same.")
	// Its friends and the people it can't stand
	if(bot_text_has_any(lower_msg, list("got any friends", "who are your friends", "who's your friend", "whos your friend", "who do you like", "who do you hang out with")))
		var/list/names = list()
		for(var/name in regard)
			if(regard[name] >= 4 && name != talker.real_name)
				var/list/parts = splittext(name, " ")
				names += parts[1]
		if(r >= 4)
			names.Insert(1, "you")
		return length(names) ? "[english_list(names)], mostly." : pick("Not really, no.", "Working on it.", "Everyone's alright, I guess.")
	if(bot_text_has_any(lower_msg, list("who do you hate", "who don't you like", "who dont you like", "anyone you don't like", "anyone you dont like", "who annoys you")))
		if(!tells_things())
			return pick("Not saying.", "I keep that to myself.")
		var/worst
		var/worst_r = 0
		for(var/name in regard)
			if(regard[name] < worst_r && name != talker.real_name)
				worst = name
				worst_r = regard[name]
		if(r <= -3)
			return "You, for a start."
		if(!worst || worst_r > -3)
			return pick("Nobody really.", "I get on with most people.")
		var/list/parts = splittext(worst, " ")
		var/why = LAZYACCESS(regard_why, worst)
		return "[parts[1]]. [why ? capitalize(bot_why_line(why)) + "." : ""]"
	return null

/// "What's your favourite drink?": from its habits and job where it has one.
/datum/bot_brain/proc/favourite_answer(lower_msg)
	if(bot_text_has_any(lower_msg, list("drink", "cocktail", "booze")))
		return has_habit(BOT_HABIT_BARFLY) ? pick("Whiskey cola. Make it a double.", "Anything the bartender's pouring.", "Gin and tonic.") : pick("Coffee.", "Space Cola.", "Water, honestly.", "Orange juice.")
	if(bot_text_has_any(lower_msg, list("food", "meal", "dish", "snack")))
		return pick("Burgers.", "Whatever the cook's made, if it isn't meat from who knows where.", "Donk pockets. Don't judge.", "Chips.", "Pizza.")
	if(bot_text_has_any(lower_msg, list("job", "department", "role")))
		var/role = work_role()
		return role ? pick("Mine, obviously. [role].", "[role]. Wouldn't do anything else.") : "Haven't got one."
	if(bot_text_has_any(lower_msg, list("color", "colour")))
		return pick("Blue.", "Green.", "Red. Like the alert.", "Black.", "Orange, like the prison jumpsuits. Kidding.")
	if(bot_text_has_any(lower_msg, list("animal", "pet")))
		return has_habit(BOT_HABIT_ANIMAL_LOVER) ? pick("Ian, obviously.", "Runtime. Don't tell Ian.", "Any of them.") : pick("Ian, I guess.", "Don't really like animals.")
	if(bot_text_has_any(lower_msg, list("game", "arcade")))
		return has_habit(BOT_HABIT_GAMER) ? pick("Space Villain. I'm on a streak.", "Orion Trail.") : pick("Don't really play.", "Cards, maybe.")
	return pick("Hard to pick.", "Don't really have one.", "Ooh. Tough one.")
