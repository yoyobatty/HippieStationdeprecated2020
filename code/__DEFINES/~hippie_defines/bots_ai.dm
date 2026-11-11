// Bot AI crew (hippiestation/code/modules/bots_ai). Kept here rather than in bot_goals.dm so every bot file sees
// them regardless of include order - Dream Maker re-sorts the .dme alphabetically, which put bot_breach.dm first.

// bot_log() and bot_log_verbose() are macros so that a line is only put together when something will keep it: a test run's
// transcript, game.log and bot_trace.log.zst (every round since 2026-11-10 but a bot-quiet one), admin chat with bot AI logging
// turned on. As procs their 940-odd callers built every line first, half a million a shift, even where nothing kept it. So nothing
// in a log line may do anything but read. While an admin has the Bot Crew panel open, each bot keeps its last few lines for it
// (hippiestation/code/modules/admin/bot_crew_panel.dm).
#define bot_log(B, msg) if(GLOB.bot_ai_log || GLOB.bot_ai_debug || GLOB.bot_crew_panel_open || B?.gym_run) bot_log_line(B, msg)
#define bot_log_verbose(B, msg) if(GLOB.bot_ai_verbose || B?.gym_run) bot_log_verbose_line(B, msg)

// What a /datum/bot_step's execute() returns
#define GOAL_STEP_PENDING 0
#define GOAL_STEP_SUCCESS 1
#define GOAL_STEP_FAIL -1

// Give up on the same goal at the same target this many times running, and the bot leaves that alone for a while (note_give_up(), bot_goals.dm)
#define BOT_GIVE_UP_LIMIT 4
#define BOT_GIVE_UP_REST (5 MINUTES)

// Where in handle_wander() a /datum/bot_duty is asked for (bot_duties.dm). Also the index of its list in bot_brain.duties.
#define BOT_DUTY_URGENT 1
#define BOT_DUTY_WORK 2
#define BOT_DUTY_LEISURE 3

// What a bot's after this part of its shift (bot_pursuits.dm)
#define BOT_PURSUIT_JOB "job"
#define BOT_PURSUIT_POWER "power"
#define BOT_PURSUIT_UPKEEP "upkeep"
#define BOT_PURSUIT_EXPLORE "explore"
#define BOT_PURSUIT_SOCIAL "social"
#define BOT_PURSUIT_CAREFUL "careful"

// Pastimes a bot can have (bot_personality.dm)
#define BOT_HABIT_SMOKER "smoker"
#define BOT_HABIT_GAMER "gamer"
#define BOT_HABIT_ANIMAL_LOVER "animal lover"
#define BOT_HABIT_BARFLY "barfly"
#define BOT_HABIT_MUSICIAN "musician"
#define BOT_HABIT_GAMBLER "gambler"
#define BOT_HABIT_FIT "keeps fit"

// How long the accelerator is held back for a coil or rod nobody can get to (goals/setup_tesla_engine.dm)
#define BOT_CAGE_PATIENCE (5 MINUTES)

// How bad a crime is (goals/security_patrol.dm). Murder and the capital crimes go to whoever's in charge (bot_law.dm).
#define BOT_CRIME_MINOR 1
#define BOT_CRIME_MAJOR 2
#define BOT_CRIME_MURDER 3

// Somebody with a tank bomb in their hands (bot_fighting.dm): how close nobody comes, and how far the crew run from them
#define BOT_BOMB_KEEP_AWAY 5
#define BOT_BOMB_RUN_FROM 10

// What whoever's in charge rules for a capital charge (bot_law.dm)
#define BOT_VERDICT_PERMABRIG "permabrig"
#define BOT_VERDICT_INJECTION "lethal injection"

// How a bot plays the round (bot_personality.dm)
#define BOT_STYLE_NORMAL "normal"
#define BOT_STYLE_POWERGAMER "powergamer"
#define BOT_STYLE_HUNTER "antag hunter"
#define BOT_STYLE_PARANOID "paranoid"
#define BOT_STYLE_HOPPER "role-hopper"
#define BOT_STYLE_ROBUST "robust"

/// How a traitor goes about it (goals/robust.dm).
#define BOT_TRAITOR_UNDERCOVER "undercover" //an emag and its objectives, and nobody the wiser until it's caught
#define BOT_TRAITOR_HIT_LIST "hit list" //an emag and a pistol (no suit, since 2026-11-10), its targets, the Captain and Security, and whoever gets in the way
#define BOT_TRAITOR_RAMPAGE "rampage" //the suit, and everybody
/// The chance a rampaging traitor suits up with another traitor already in one, divided by how many are (goals/traitor.dm wants_nanosuit())
#define BOT_EXTRA_SUIT_CHANCE 35
#define BOT_TRAITOR_CORNERED "cornered" //caught: fights whoever comes for it and still goes for its own target, and nobody else
#define BOT_TRAITOR_SABOTEUR "saboteur" //undercover, with sabotage on top of its objectives (goals/sabotage.dm). Only ever asked for: the plan stays undercover

/// What path_engine_astar() (bot_path_engine.dm) returns when AStar() should do the search itself
#define PATH_ENGINE_FALLBACK -1
