#define INIT_ORDER_DEMO				-99 // To avoid a bunch of changes related to initialization being written, do this last
#define INIT_ORDER_STATION_LOOKS	54 // rolls the round's looks once config is in, before the lobby opens (station_looks.dm)

/// SSdemo's mark_*() procs, called only while it records: with demos off (the config's default) each call was two procs for nothing,
/// on every step, setDir(), new atom and qdel(). disabled is set by its first recording_off() check, so the first calls still go in.
#define DEMO_ON (!SSdemo.disabled)
