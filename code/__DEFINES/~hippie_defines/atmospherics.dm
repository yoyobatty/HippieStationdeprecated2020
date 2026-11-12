//Plasma fusion properties
#define PLASMA_BINDING_ENERGY_HIPPIE 2e9//this has to be a big number
#define PLASMA_FUSION_ENERGY_HIPPIE 4e7
#define MAX_CARBON_EFFICENCY_HIPPIE 9
#define PLASMA_FUSED_COEFFICENT_HIPPIE 20
#define CARBON_CATALYST_COEFFICENT_HIPPIE 0.2
#define FUSION_PURITY_THRESHOLD_HIPPIE 0.9
#define FUSION_POWER_GENERATION_COEFFICIENT_HIPPIE 0.0000001

/// A turf's seal_dir while a shut door on it has no side to share air with yet: it looks again the next time its
/// neighbours are worked out (hippiestation/code/modules/atmospherics/door_seals.dm)
#define SEAL_PENDING -1

// The tile atmos engine running LINDA's awake turfs and excited groups itself (atmos-engine-own, hippiestation/code/modules/
// atmospherics/tile_engine.dm): what DM did to them, told to the engine in order. The numbers are the engine's
// (tools/atmos_engine/src/world.rs).
/// add_to_active(T)
#define TILE_EVENT_WAKE 1
/// add_to_active(T, blockchanges = TRUE)
#define TILE_EVENT_WAKE_BLOCK 2
/// remove_from_active(T)
#define TILE_EVENT_REMOVE 3
/// sleep_active_turf(T)
#define TILE_EVENT_SLEEP 4
/// T.active_hotspot set
#define TILE_EVENT_HOTSPOT_ON 5
/// T.active_hotspot cleared
#define TILE_EVENT_HOTSPOT_OFF 6
/// A hotspot keeping its turf's excited group going (reset_cooldowns())
#define TILE_EVENT_RESET_GROUP 7
/// A reaction redrew the turf's gas overlays
#define TILE_EVENT_UNDRAWN 8
/// A new turf in its place (ChangeTurf)
#define TILE_EVENT_NEW_TURF 9

/// Something in DM has a turf's air and may change it: the tile engine has to be sent it again. Once per turf between
/// SSair's calls to the engine; with the engine keeping LINDA's state (atmos-engine-own) the turf is queued for it too.
#define TILE_ENGINE_TOUCH(T) if(T.air_touched != SSair.tile_engine_air_clock) { T.air_touched = SSair.tile_engine_air_clock; if(SSair.tile_engine_tracking) { SSair.tile_engine_touched += T } }
/// A turf's atmos_adjacent_turfs changed: the tile engine has to be sent its kind and neighbours again
#define TILE_ENGINE_DIRTY(T) T.tile_engine_sent = 0; if(SSair.tile_engine_tracking) { SSair.tile_engine_dirty += T }
/// How long a vent or scrubber the tile engine watches waits idle before it runs anyway, in atmos ticks (20 seconds); the
/// rest wait ATMOS_IDLE_RECHECK (hippiestation/code/modules/atmospherics/idle_machines.dm). It's for air changed without
/// add_to_active() (heat through walls, breathing), which wakes nothing in DM either but used to be caught sooner.
#define ATMOS_IDLE_RECHECK_WATCHED 40

/// Something in DM changed a pipe network's gas mixture: the tile engine is sent it again the next time the network is evened
/// out (hippiestation/code/modules/atmospherics/pipe_engine.dm)
#define PIPE_AIR_TOUCH(G) G.pipe_engine_dirty = TRUE
