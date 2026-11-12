//Endgame Results
#define GANG_LOSS 6
#define GANG_TAKEOVER 7

#define INFILTRATION_ALLCOMPLETE 25
#define INFILTRATION_MOSTCOMPLETE 26
#define INFILTRATION_SOMECOMPLETE 27
#define INFILTRATION_NONECOMPLETE 28

#define BLUESPACE_STONE "bluespace stone"
#define SUPERMATTER_STONE "supermatter stone"
#define CLOWN_STONE "clown stone"
#define LAG_STONE "lag stone"
#define GHOST_STONE "ghost stone"
#define SYNDIE_STONE "syndie stone"

#define GANGMAGEDDON	(1 << 0)
#define GANGS			(1 << 1)
#define VIGILANTE		(1 << 2)

#define DOM_BLOCKED_SPAM_CAP 6
#define DOM_REQUIRED_TURFS 30
#define DOM_HULK_HITS_REQUIRED 10

/// Examining the same thing again within this long takes a closer look (examine_more)
#define EXAMINE_MORE_WINDOW (1 SECONDS)

// Screentips (hippiestation/code/modules/screentips): the clicks a screentip can describe
#define SCREENTIP_LMB "LMB"
#define SCREENTIP_ALT_LMB "Alt-LMB"
#define SCREENTIP_CTRL_LMB "Ctrl-LMB"

/// The most of one supply pack a cargo or express console orders in one go
#define CARGO_MAX_ORDER_AMOUNT 10

/// What to loop over for `for(x in A)`: A itself, or a copy of its contents when it holds more than 64 things. BYOND walks a
/// contents list from its start for every step of a loop over it, so a loop over a pile is quadratic (489 ns a thing at 4096
/// against 50 with a copy first, 2026-11-11); under ~64 things the copy costs more than it saves. A is evaluated more than once.
/// A null A (doMove() out of nullspace) loops over nothing, as `for(x in null)` does.
#define LOOP_CONTENTS(A) (A && length(A.contents) > 64 ? A.contents.Copy() : A)
