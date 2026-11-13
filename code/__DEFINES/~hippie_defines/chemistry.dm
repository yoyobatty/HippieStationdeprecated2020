#define LIQUID_PARTICLE_EFFECT_EFFICIENCY 0.03
#define SOLID_PARTICLE_EFFECT_EFFICIENCY 0.08
#define GAS_PARTICLE_EFFECT_EFFICIENCY 0.1
/// Reagent vapour on the station at once (masters and the tiles they've spread to): past this no more starts or spreads
#define VAPOUR_MAX 2000

// Heat in reagent containers (hippiestation/code/modules/reagents/chemistry/reagent_heat.dm)
/// expose_temperature() (a hot tool, a fire, a microwave) heats this many units at the rate it always did; twice as much takes twice as long
#define REAGENT_HEAT_REFERENCE_VOLUME 50
/// The most of the way to the heat source one expose_temperature() goes, however little is in it
#define REAGENT_HEAT_MAX_STEP 0.5
/// REAGENT_HEAT_REFERENCE_VOLUME units at the default specific heat in still room air: its gap to the air's temperature shrinks to 37% in this long
#define REAGENT_DRIFT_TIME (10 MINUTES)
/// Reagents this far from room temperature (T20C) start drifting towards the air around them
#define REAGENT_DRIFT_START 10
/// ... and stop this close to it
#define REAGENT_DRIFT_STOP 0.5
/// How often drifting reagents move towards the air's temperature (a pile of 500 hot beakers: 5 ms each time)
#define REAGENT_DRIFT_STEP (2 SECONDS)
/// How often reagents kept from the air (in a machine, a grenade) look again
#define REAGENT_DRIFT_INSULATED_RECHECK (10 SECONDS)