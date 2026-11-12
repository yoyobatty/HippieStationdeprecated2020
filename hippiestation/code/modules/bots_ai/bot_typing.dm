// How a bot types. On a real server some players write full sentences, and plenty type the way they'd text a friend: lower case,
// no full stops, "u" and "idk", "sec to medbay", the odd typo put right a second later with "word*". The user's ruling (2026-11-12):
// a mix, by personality. The keen, the competent and the people in charge mostly write properly; greytiders, powergamers and the
// bored type like they text. A bot keeps its own way for the round, and its own handful of shortcuts.
//
// in_own_words() (bot_chatter.dm) runs every line a bot says through here. Not lines said in character (code words: a traitor
// player listening has to recognise them), and not in the gym, whose scenarios read lines back word for word, unless a scenario
// asks for it (typing_in_gym).

/// What a casual typist writes for what a careful one would. Whole words or phrases, matched in lower case. Each bot uses some of
/// them (typing_shortcuts): the sloppy ones most, the casual ones a few.
GLOBAL_LIST_INIT(bot_typing_shortcuts, list(
	"i don't know" = "idk", "i dont know" = "idk",
	"to be honest" = "tbh",
	"right now" = "rn",
	"oh my god" = "omg",
	"on my way" = "omw",
	"be right back" = "brb",
	"going to" = "gonna",
	"want to" = "wanna",
	"got to" = "gotta",
	"okay" = "ok",
	"probably" = "prob",
	"though" = "tho",
	"because" = "cuz",
	"please" = "pls",
	"thanks" = "thx",
	"thank you" = "ty",
	"really" = "rly",
	"seriously" = "srsly",
	"something" = "smth",
	"security" = "sec",
	"engineering" = "engi",
	"maintenance" = "maint",
	"chemistry" = "chem",
	"medbay" = "med",
	"captain" = "cap",
	"head of personnel" = "hop",
	"head of security" = "hos",
	"chief engineer" = "ce",
	"chief medical officer" = "cmo",
	"research director" = "rd",
	"quartermaster" = "qm",
	"atmospherics" = "atmos",
	"hydroponics" = "hydro",
))

/// Only the sloppy typists go this far. Phrases before the words in them: "are you" has to go before "you" can.
GLOBAL_LIST_INIT(bot_typing_sloppy_shortcuts, list(
	"are you" = "r u",
	"see you" = "cya",
	"you're" = "ur",
	"youre" = "ur",
	"your" = "ur",
	"you" = "u",
	"what" = "wat",
	"tonight" = "tonite",
))

/// Laughing, the way it's typed.
GLOBAL_LIST_INIT(bot_typing_laughs, list("ha." = "lol", "ha!" = "lol", "haha." = "lmao", "ha, " = "lol "))

/// The keys next to each key, for a finger that slips.
GLOBAL_LIST_INIT(bot_typing_neighbours, list(
	"a" = "sqz", "b" = "vgn", "c" = "xvd", "d" = "sfe", "e" = "wrd", "f" = "dgr", "g" = "fht", "h" = "gjy", "i" = "uok", "j" = "hku",
	"k" = "jli", "l" = "ko", "m" = "nj", "n" = "bmh", "o" = "ipl", "p" = "o", "q" = "wa", "r" = "etf", "s" = "adw", "t" = "ryg",
	"u" = "yij", "v" = "cbf", "w" = "qes", "x" = "zc", "y" = "tuh", "z" = "xa",
))

/datum/bot_brain
	/// The shortcuts this bot uses (keys of the two lists above), picked when it first speaks.
	var/list/typing_shortcuts
	/// Out of 100, the chance a line it types has a slip in it.
	var/typo_chance = 0
	/// Out of 100, the chance it puts a slip right with "word*".
	var/typo_fix_chance = 0
	/// A gym scenario that tests typing sets this: the gym otherwise gets lines as written.
	var/typing_in_gym = FALSE

/// How it types, from who it is (BOT_CHAT_* in bot_chatter.dm: 1 properly, 2 casually, 3 sloppily).
/datum/bot_brain/proc/pick_chat_style()
	var/role = work_role()
	var/proper = 20 + 40 * diligence + 25 * competence
	var/casual = 45
	var/sloppy = 5 + 30 * (1 - diligence)
	if(role in GLOB.command_positions)
		proper += 30
	if(is_security_job())
		proper += 10
	if(greytider)
		sloppy += 30
		proper -= 20
	if(playstyle == BOT_STYLE_POWERGAMER || playstyle == BOT_STYLE_ROBUST)
		sloppy += 20
	var/list/weights = list("1" = max(1, round(proper)), "2" = max(1, round(casual)), "3" = max(1, round(sloppy)))
	return text2num(pickweight(weights)) || 2

/// The shortcuts and slips that go with its style. Called once, on its first line.
/datum/bot_brain/proc/settle_typing()
	chat_style = pick_chat_style()
	typing_shortcuts = list()
	switch(chat_style)
		if(1) //properly: the odd slip, nearly always put right
			typo_chance = 2
			typo_fix_chance = 70
		if(2) //casually: a few shortcuts
			typo_chance = 5
			typo_fix_chance = 40
			for(var/key in GLOB.bot_typing_shortcuts)
				if(prob(30))
					typing_shortcuts += key
		if(3) //sloppily: most of them, and the u's and ur's
			typo_chance = 12
			typo_fix_chance = 25
			for(var/key in GLOB.bot_typing_shortcuts)
				if(prob(75))
					typing_shortcuts += key
			for(var/key in GLOB.bot_typing_sloppy_shortcuts)
				if(prob(60))
					typing_shortcuts += key

/// Whether this line gets typed its own way: never code words, and in the gym only when the scenario asks.
/datum/bot_brain/proc/types_own_way()
	return !gym_run || typing_in_gym

/// The line with its shortcuts in. `line` is already lower case.
/datum/bot_brain/proc/shorten(line)
	if(!length(typing_shortcuts))
		return line
	// In the lists' order, which puts each phrase before any word in it.
	for(var/key in typing_shortcuts)
		var/short = GLOB.bot_typing_shortcuts[key] || GLOB.bot_typing_sloppy_shortcuts[key]
		if(!short || !findtext(line, key))
			continue
		var/regex/R = bot_typing_regex(key)
		line = R.Replace(line, short)
	for(var/laugh in GLOB.bot_typing_laughs)
		if(findtext(line, laugh) == 1)
			line = GLOB.bot_typing_laughs[laugh] + copytext(line, length(laugh) + 1)
	return line

/// "\bkey\b", case-insensitive, global, kept.
/proc/bot_typing_regex(key)
	var/static/list/cache = list()
	var/regex/R = cache[key]
	if(!R)
		R = regex("\\b[REGEX_QUOTE(key)]\\b", "gi")
		cache[key] = R
	return R

/// Shouting it: a short, urgent line in capitals, the way a sloppy typist calls for help mid-fight. "HELP SEC"
/datum/bot_brain/proc/shouts(line)
	if(chat_style == 1 || length(line) > 40 || !findtext(line, "!"))
		return FALSE
	return state == BOT_STATE_COMBAT || findtext(line, "help") || prob(15)

/// One slip of the finger in one longer word: list(the line with it in, the word as it should be), or null if it typed it fine.
/datum/bot_brain/proc/slip(line)
	if(!prob(typo_chance))
		return null
	var/list/words = splittext(line, " ")
	var/list/candidates = list()
	for(var/i in 1 to length(words))
		var/w = words[i]
		if(length(w) >= 4 && !findtext(w, "*") && bot_typing_all_letters(w))
			candidates += i
	if(!length(candidates))
		return null
	var/i = pick(candidates)
	var/word = words[i]
	for(var/attempt in 1 to 5) //"ll" swapped is still "ll": another go
		var/typed = bot_mistype(word)
		if(typed && typed != word)
			words[i] = typed
			return list(jointext(words, " "), word)
	return null

/// The word with one slip in it, somewhere past its first letter.
/proc/bot_mistype(word)
	var/at = rand(2, length(word) - 1)
	switch(rand(1, 4))
		if(1) //two letters swapped
			return copytext(word, 1, at) + copytext(word, at + 1, at + 2) + copytext(word, at, at + 1) + copytext(word, at + 2)
		if(2) //one left out
			return copytext(word, 1, at) + copytext(word, at + 1)
		if(3) //one twice
			return copytext(word, 1, at + 1) + copytext(word, at)
		if(4) //the key next to it
			var/near = GLOB.bot_typing_neighbours[copytext(word, at, at + 1)]
			if(near)
				var/n = rand(1, length(near))
				return copytext(word, 1, at) + copytext(near, n, n + 1) + copytext(word, at + 1)
	return null

/proc/bot_typing_all_letters(word)
	var/static/regex/letters = regex(@"^[a-z]+$")
	return letters.Find(word)

/// The line as this bot types it. The radio prefix has been taken off; `line` is lower case already for a casual typist, as it was
/// written for a careful one. Returns the line, and may queue a "word*" after it.
/datum/bot_brain/proc/type_out(line, prefix)
	if(chat_style != 1)
		line = shorten(line)
		if(shouts(line))
			line = uppertext(replacetext(line, "!", ""))
	// Slips only out loud: the radio carries calls other bots act on (a fire, a verdict, a call for Security), and a slip there could lose one
	var/list/slipped = prefix ? null : slip(line)
	if(slipped)
		line = slipped[1]
		if(prob(typo_fix_chance))
			addtimer(CALLBACK(src, PROC_REF(fix_slip), prefix + slipped[2] + "*"), rand(15, 35))
	return line

/// "word*": the slip put right, on the same channel.
/datum/bot_brain/proc/fix_slip(line)
	if(QDELETED(owner) || owner.stat != CONSCIOUS)
		return
	owner.say(line)
