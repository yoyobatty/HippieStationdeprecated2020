// Subsystems with nothing to do aren't queued (hippie, 2026-11-08, the user's "MC overhead").
//
// The MC's census (tools/mc_check, STEPS=census) counted ~315 fires a game second on a crewed station, ~240 of them tickers and
// processors walking an empty list: Throwing, Projectiles, Explosions, Chat and Input forty times a second each, Networks,
// Fields, Parallax and the rest. Each one cost the MC a queue insert, its RunQueue bookkeeping, ignite() and fire() for nothing.
// With idle_check, CheckQueue asks has_work() first and, when there's nothing, just moves next_fire on (master.dm).
//
// has_work() is asked whenever the subsystem is due and isn't running or paused, so a paused run with work left in currentrun
// is never asked. Keep each one a length() or two: it's on the MC's own path.

/datum/controller/subsystem/processing
	idle_check = TRUE

/datum/controller/subsystem/processing/has_work()
	return length(processing)

/datum/controller/subsystem/throwing
	idle_check = TRUE

/datum/controller/subsystem/throwing/has_work()
	return length(processing)

/datum/controller/subsystem/spacedrift
	idle_check = TRUE

/datum/controller/subsystem/spacedrift/has_work()
	return length(processing)

/datum/controller/subsystem/fire_burning
	idle_check = TRUE

/datum/controller/subsystem/fire_burning/has_work()
	return length(processing)

/datum/controller/subsystem/acid
	idle_check = TRUE

/datum/controller/subsystem/acid/has_work()
	return length(processing)

/datum/controller/subsystem/explosions
	idle_check = TRUE

/datum/controller/subsystem/explosions/has_work()
	return is_exploding()

/datum/controller/subsystem/chat
	idle_check = TRUE

/datum/controller/subsystem/chat/has_work()
	return length(payload)

/datum/controller/subsystem/tgui
	idle_check = TRUE

/datum/controller/subsystem/tgui/has_work()
	return length(processing_uis)

// The next two only matter with nobody on (bot rounds, benches): keyLoop() and parallax are for clients

/datum/controller/subsystem/input
	idle_check = TRUE

/datum/controller/subsystem/input/has_work()
	return length(GLOB.clients)

/datum/controller/subsystem/parallax
	idle_check = TRUE

/datum/controller/subsystem/parallax/has_work()
	return length(GLOB.clients)
