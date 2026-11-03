// Personality - twenty bots that loaf, chat and panic to exactly the same degree read as twenty
// copies of one bot. Each rolls a few traits as it joins, leaning the way its job does, and picks up
// a pastime or two. Duties and reactions read them (bot_duties.dm); nothing here does anything itself.
//
// A real server's players are mostly ordinary: they do their job and pitch in when somebody needs stopping. Past that, a few
// play the round their own way, and that's a bot's playstyle: the powergamer after the best kit going, the antag hunter who's
// only here for that, the paranoid one ready for the worst, the one who turns up wherever it's short-handed, the robust one modelled on
// a real player's rounds (goals/robust.dm). Being attacked or
// seeing somebody dead hardens anybody into the paranoid kind, for the rest of the round (bot_playstyles.dm).

/// Out of a hundred, how many just play the game.
#define BOT_NORMAL_SHARE 60

/datum/bot_brain
	/// 0-1. How readily it gets on with the job rather than loafing - work duties come round sooner for a keen one.
	var/diligence = 0.7
	/// 0-1. How much it talks, and how much it seeks out company.
	var/sociability = 0.5
	/// 0-1. Low runs from trouble, high wades in.
	var/nerve = 0.5
	/// 0-1. How little it takes before it stops telling somebody off and starts hitting them (bot_reflexes.dm).
	var/temper = 0.5
	/// Out for trouble when it gets the chance (goals/greytide.dm). Most assistants are, and the odd anybody else.
	var/greytider = FALSE
	/// Its pastimes (BOT_HABIT_*).
	var/list/habits
	/// How it plays the round (BOT_STYLE_*).
	var/playstyle = BOT_STYLE_NORMAL
	/// 0-1. How well it knows the station's machinery. Only a very competent bot takes on what isn't its job and could go badly wrong.
	var/competence = 0.5
	/// 0-1. How much it minds who's in its department: low props the doors open, high puts them back and throws people out.
	var/strictness = 0.5
	/// Been attacked, or seen somebody dead: it plays it paranoid from here on, whatever it started as.
	var/hardened = FALSE

/datum/bot_brain/New(mob/living/carbon/human/new_owner)
	. = ..()
	roll_personality()

/datum/bot_brain/proc/roll_personality()
	var/role = owner?.mind?.assigned_role
	diligence = rand(40, 100) / 100
	sociability = rand(15, 95) / 100
	nerve = rand(15, 85) / 100
	temper = rand(10, 90) / 100
	if(role in GLOB.command_positions)
		diligence = max(diligence, 0.75) //nobody made head of department by loafing
		nerve = max(nerve, 0.5)
	if(role in GLOB.security_positions)
		nerve = rand(75, 100) / 100
	if(role in list("Assistant", "Clown", "Mime"))
		diligence = rand(20, 70) / 100
	if(role in list("Bartender", "Clown", "Chaplain", "Head of Personnel", "Curator", "DJ"))
		sociability = max(sociability, 0.6)
	// A third of the assistants are decent people. Everybody else mostly has a job to lose.
	greytider = prob(role == "Assistant" ? 65 : (role == "Clown" ? 25 : ((role in GLOB.security_positions) || (role in GLOB.command_positions) ? 0 : 4)))
	if(greytider)
		temper = max(temper, 0.6)
		nerve = max(nerve, 0.5)
	habits = list()
	var/list/pool = list(BOT_HABIT_SMOKER, BOT_HABIT_GAMER, BOT_HABIT_ANIMAL_LOVER, BOT_HABIT_BARFLY, BOT_HABIT_MUSICIAN, BOT_HABIT_GAMBLER)
	for(var/i in 1 to rand(1, 3))
		habits |= pick(pool)
	roll_playstyle(role)
	bot_log_verbose(src, "personality: [playstyle], diligence [diligence], sociability [sociability], nerve [nerve], temper [temper], competence [competence], strictness [strictness], habits [english_list(habits)]")

/datum/bot_brain/proc/roll_playstyle(role)
	competence = rand(20, 100) / 100
	strictness = rand(10, 90) / 100
	if(role in GLOB.command_positions)
		competence = max(competence, 0.6)
	if(role in GLOB.security_positions)
		strictness = rand(75, 100) / 100 //nobody gets in or out of the brig without a reason
	if(prob(BOT_NORMAL_SHARE))
		playstyle = BOT_STYLE_NORMAL
		return
	var/list/styles = list(BOT_STYLE_POWERGAMER, BOT_STYLE_HUNTER, BOT_STYLE_PARANOID, BOT_STYLE_HOPPER, BOT_STYLE_ROBUST)
	if(greytider)
		styles -= BOT_STYLE_HUNTER //after anybody's trouble but its own
	set_playstyle(pick(styles))

/// Sets a playstyle, with what goes along with playing that way. Bot Gym scenarios call this too.
/datum/bot_brain/proc/set_playstyle(style)
	playstyle = style
	duties = null //a role-hopper has one more
	switch(style)
		if(BOT_STYLE_POWERGAMER)
			diligence = max(diligence, 0.8)
			competence = max(competence, 0.7)
		if(BOT_STYLE_HUNTER)
			nerve = max(nerve, 0.7)
		if(BOT_STYLE_HOPPER)
			diligence = max(diligence, 0.7)
			sociability = max(sociability, 0.5)
		if(BOT_STYLE_ROBUST)
			nerve = max(nerve, 0.75)
			competence = max(competence, 0.7)

/// Ready for the worst, by nature or because it's seen it.
/datum/bot_brain/proc/is_paranoid()
	return hardened || playstyle == BOT_STYLE_PARANOID

/// For the rest of the round, whatever it was before.
/datum/bot_brain/proc/harden(why)
	if(is_paranoid())
		return
	hardened = TRUE
	bot_log(src, "hardened: [why]")
	bot_tally("hardened")

/// Whether this bot goes in for a pastime. A Bot Gym bot goes in for whichever one its scenario is about.
/datum/bot_brain/proc/has_habit(habit)
	return gym_run ? TRUE : (habit in habits)

#undef BOT_NORMAL_SHARE
