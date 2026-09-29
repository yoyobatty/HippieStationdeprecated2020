// Bot AI crew (hippiestation/code/modules/bots_ai). Kept here rather than in bot_goals.dm so every bot file sees
// them regardless of include order - Dream Maker re-sorts the .dme alphabetically, which put bot_breach.dm first.

// What a /datum/bot_step's execute() returns
#define GOAL_STEP_PENDING 0
#define GOAL_STEP_SUCCESS 1
#define GOAL_STEP_FAIL -1
