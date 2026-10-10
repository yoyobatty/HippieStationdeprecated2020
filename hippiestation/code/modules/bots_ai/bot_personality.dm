// Personality - twenty bots that loaf, chat and panic to exactly the same degree read as twenty
// copies of one bot. Each rolls a few traits as it joins, leaning the way its job does, and picks up
// a pastime or two. Duties and reactions read them (bot_duties.dm); nothing here does anything itself.

/datum/bot_brain
	/// 0-1. How readily it gets on with the job rather than loafing - work duties come round sooner for a keen one.
	var/diligence = 0.7
	/// 0-1. How much it talks, and how much it seeks out company.
	var/sociability = 0.5
	/// 0-1. Low runs from trouble, high wades in.
	var/nerve = 0.5
	/// Its pastimes (BOT_HABIT_*).
	var/list/habits

/datum/bot_brain/New(mob/living/carbon/human/new_owner)
	. = ..()
	roll_personality()

/datum/bot_brain/proc/roll_personality()
	var/role = owner?.mind?.assigned_role
	diligence = rand(40, 100) / 100
	sociability = rand(15, 95) / 100
	nerve = rand(15, 85) / 100
	if(role in GLOB.command_positions)
		diligence = max(diligence, 0.75) //nobody made head of department by loafing
		nerve = max(nerve, 0.5)
	if(role in GLOB.security_positions)
		nerve = rand(75, 100) / 100
	if(role in list("Assistant", "Clown", "Mime"))
		diligence = rand(20, 70) / 100
	if(role in list("Bartender", "Clown", "Chaplain", "Head of Personnel", "Curator", "DJ"))
		sociability = max(sociability, 0.6)
	habits = list()
	var/list/pool = list(BOT_HABIT_SMOKER, BOT_HABIT_GAMER, BOT_HABIT_ANIMAL_LOVER, BOT_HABIT_BARFLY, BOT_HABIT_MUSICIAN, BOT_HABIT_GAMBLER)
	for(var/i in 1 to rand(1, 3))
		habits |= pick(pool)
	bot_log_verbose(src, "personality: diligence [diligence], sociability [sociability], nerve [nerve], habits [english_list(habits)]")

/// Whether this bot goes in for a pastime. A Bot Gym bot goes in for whichever one its scenario is about.
/datum/bot_brain/proc/has_habit(habit)
	return gym_run ? TRUE : (habit in habits)
