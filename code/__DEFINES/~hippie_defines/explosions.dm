// Realistic explosions (hippiestation/code/modules/explosion_realism/)

/// The ring past the damage that only the pressure reaches: glass breaks and ears ring. Never passed to ex_act(): SSexplosions
/// hands these tiles to blast_far() with how hard they're hit.
#define EXPLODE_FAR 4

/// Below this many kilopascals the products expand into nothing and no blast wave forms
#define BLAST_AIR_NONE 2
/// From this many kilopascals down to BLAST_AIR_NONE the wave fades out
#define BLAST_AIR_FADE 20
/// The most dense air can strengthen a blast: the cube root of about 2.2 atmospheres
#define BLAST_AIR_MAX 1.3
