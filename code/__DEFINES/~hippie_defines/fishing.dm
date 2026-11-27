// Fishing (hippiestation/code/modules/fishing/), from Paradise (fishing-standalone, 2026-11-26)

// Things a fishing line can do, checked against what a fishing spot needs
/// The line survives lava and liquid plasma
#define FISHING_LINE_HEATPROOF (1<<0)
/// The line is long enough to reach the bottom of a chasm
#define FISHING_LINE_LONG (1<<1)
/// The line is steel, and reaches what lives in deep lava without burning through
#define FISHING_LINE_MAGMA (1<<2)

// Kinds of bait. Each fish likes some of these more than others
#define FISHING_BAIT_MEAT "meat"
#define FISHING_BAIT_CHEESE "cheese"
#define FISHING_BAIT_PLANT "plant"
#define FISHING_BAIT_LIVE "live bait"
#define FISHING_BAIT_GLOW "glowing bait"
#define FISHING_BAIT_SHINY "shiny bait"

// Stages of one cast, in the order they happen
/// The bobber is out and nothing has bitten yet
#define FISHING_WAITING 1
/// Something is on the hook and the angler has a moment to pull
#define FISHING_BITE 2
/// The fish is hooked and being reeled in
#define FISHING_FIGHT 3
/// The cast is over
#define FISHING_DONE 4

// What a hooked fish is doing during the fight
/// Catching its breath. This is the time to reel
#define FISHING_FISH_RESTING "resting"
/// About to bolt, a short warning before it runs
#define FISHING_FISH_TENSING "tensing"
/// Pulling line out. Reeling now strains the line
#define FISHING_FISH_RUNNING "running"
/// Out of strength, it won't run again
#define FISHING_FISH_WORN_OUT "worn out"

/// Line strain at which the line snaps
#define FISHING_MAX_TENSION 100
/// Strain from reeling in a fish that isn't pulling back
#define FISHING_REEL_TENSION 30
/// Strain added by reeling against a running fish, for each point of its strength
#define FISHING_RUN_STRAIN 2.2
/// How fast strain builds while reeling, per second
#define FISHING_TENSION_RISE 50
/// How fast strain drops with the reel let go, per second
#define FISHING_TENSION_FALL 40
/// How much of the rod's reel speed is left while the fish is running
#define FISHING_RUN_REEL_MULT 0.25
/// How fast any running fish takes line with the reel let go, in tiles a second
#define FISHING_RUN_SPEED 0.3
/// Each point of strength adds this much to that, in tiles a second
#define FISHING_RUN_SPEED_PER_STRENGTH (1 / 60)
/// How much extra line a fish can take before it gets away, in tiles
#define FISHING_SPARE_LINE 5
/// How long the warning before a run lasts, in seconds
#define FISHING_TENSING_TIME 0.6
/// A fish that is being reeled against while it runs tires this many times faster
#define FISHING_TIRING_BONUS 2.5
/// Bites come this much sooner with bait on the hook
#define FISHING_BAIT_WAIT_MULT 0.6
/// The fishing sprites
#define FISHING_ICON 'hippiestation/icons/obj/fishing.dmi'
