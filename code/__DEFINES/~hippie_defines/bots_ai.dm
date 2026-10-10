// Bot AI crew (hippiestation/code/modules/bots_ai). Kept here rather than in bot_goals.dm so every bot file sees
// them regardless of include order - Dream Maker re-sorts the .dme alphabetically, which put bot_breach.dm first.

// What a /datum/bot_step's execute() returns
#define GOAL_STEP_PENDING 0
#define GOAL_STEP_SUCCESS 1
#define GOAL_STEP_FAIL -1

// Where in handle_wander() a /datum/bot_duty is asked for (bot_duties.dm). Also the index of its list in bot_brain.duties.
#define BOT_DUTY_URGENT 1
#define BOT_DUTY_WORK 2
#define BOT_DUTY_LEISURE 3

// Pastimes a bot can have (bot_personality.dm)
#define BOT_HABIT_SMOKER "smoker"
#define BOT_HABIT_GAMER "gamer"
#define BOT_HABIT_ANIMAL_LOVER "animal lover"
#define BOT_HABIT_BARFLY "barfly"
#define BOT_HABIT_MUSICIAN "musician"
#define BOT_HABIT_GAMBLER "gambler"
