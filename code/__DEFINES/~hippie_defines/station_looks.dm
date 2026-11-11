// Station looks: what each round rolls for how the station looks and feels (hippiestation/code/modules/station_looks/)

/// The slots a round's looks are rolled into: one sky and one shift time every round, then up to two extras and at most one history
#define LOOK_SLOT_SKY "sky"
#define LOOK_SLOT_SHIFT "shift"
#define LOOK_SLOT_EXTRA "extra"
#define LOOK_SLOT_HISTORY "history"

/// World param that picks the looks instead of rolling them: "plain" (a day shift and nothing else), or look ids joined by commas
#define STATION_LOOKS_PARAMETER "station-looks"

/// An old yellowed tube (Tired wiring): this colour multiplied into its own, and this much of its power
#define LOOK_YELLOWED_TINT "#FFE6A6"
#define LOOK_YELLOWED_POWER 0.85
/// Chance in a hundred that a tired tube burns out when it sputters (sputter() in light_glow.dm)
#define LOOK_TIRED_BURNOUT 8

/// How long the lamp buzz sound runs, and so how often a buzzing lamp plays it again
#define LAMP_BUZZ_LOOP (2 SECONDS)
/// How far off a buzzing lamp can be heard, in tiles
#define LAMP_BUZZ_RANGE 4
