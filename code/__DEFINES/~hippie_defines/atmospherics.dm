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
