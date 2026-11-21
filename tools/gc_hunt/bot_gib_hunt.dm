// Bot hard-delete hunt: kills bots in every way a round does, mid-errand, and lets gc_hunt.dm name whatever still holds a body once the GC
// gives up on it. A bot human that fails to garbage collect is a 30-50 ms freeze when SSgarbage hard deletes it (qdel.log:
// "Total Hard Deletes", "Time Spent Hard Deleting"), and a round with a traitor and a bomb has several.
//
// Use it as the gc_hunt harness (it includes gc_hunt.dm): a Bot Shift, a crew, and every `gib-every` seconds one of the living bots
// (kept at `gib-keep` or more) is killed: a gib, a small explosion on its tile, a qdel() (what a singularity or a crusher does), or
// death (a body left lying, which is gibbed or deleted at the next pick). Bodies are then left for the GC, and gc_hunt's search runs
// on each hard delete (data/ref_stall.txt: "[path] at Ns: refcount N, M found" and what holds it, e.g. "/datum/bot_brain.attacker").
//
//   AT_END=1 HARNESS=../../gc_hunt/bot_gib_hunt.dm PORT=45933 SECONDS_LIMIT=1500 \
//     PARAMS="bot-shift=30&bot-crew=fill:30&bot-map=hippiestation&bot-quiet=1&timewarp=0&gh-per-type=2&gib-after=180&gib-for=600" \
//     bash tools/byond_reports/ref_stall/hippie_check.sh          (from the repo root; wrap it in the shared slot script when sharing)
//
// World params: gib-after (game seconds before the first kill, default 180), gib-for (how long the kills go on, default 600),
// gib-every (seconds between kills, default 15), gib-keep (bots left alive so they keep fighting, talking and arresting, default 4).
// The shift has to run past gib-after + gib-for + 3 minutes of game time (the GC waits 2 minutes before it gives up on a body).
// A search takes ~45 s of real time and runs per type up to gh-per-type times.
#include "tools/gc_hunt/gc_hunt.dm"

GLOBAL_VAR_INIT(gib_hunt_started, FALSE)
/// Names of the bodies left lying (death only): by name, never by reference, or the hunt is what holds them (its first run found itself)
GLOBAL_LIST_EMPTY(gib_hunt_bodies)

/datum/bot_brain/New(mob/living/carbon/human/new_owner)
	. = ..()
	if(!GLOB.gib_hunt_started)
		GLOB.gib_hunt_started = TRUE
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(gib_hunt_loop))

/proc/gib_hunt_param(name, default)
	var/value = text2num(world.params[name])
	return isnull(value) ? default : value

/proc/gib_hunt_loop()
	sleep(gib_hunt_param("gib-after", 180) SECONDS)
	var/ends = world.time + gib_hunt_param("gib-for", 600) SECONDS
	var/every = gib_hunt_param("gib-every", 15)
	var/keep = gib_hunt_param("gib-keep", 4)
	var/kills = 0
	gh_log("gib hunt: killing bots from [round(world.time / 10)]s to [round(ends / 10)]s")
	while(world.time < ends)
		// in a proc of its own: a local of this one would hold the victim through the sleep, and the GC would fail on the hunt itself
		if(gib_hunt_kill(keep, kills + 1))
			kills++
		sleep(every * (0.5 + rand()) SECONDS)
	gh_log("gib hunt: [kills] killed, no more from [round(world.time / 10)]s")

/// One pick: bodies left lying from before are gibbed or deleted, and one of the living (above `keep`) is killed. TRUE if one was.
/proc/gib_hunt_kill(keep, number)
	var/list/living = list()
	var/list/lying = list()
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(QDELETED(B) || QDELETED(B.owner))
			continue
		if(B.owner.stat == DEAD)
			lying += B.owner
		else
			living += B.owner
	// last picks' bodies that were only killed: now gibbed or deleted, so each one is tested both ways
	for(var/mob/living/carbon/human/body as anything in lying)
		if(body.real_name in GLOB.gib_hunt_bodies)
			GLOB.gib_hunt_bodies -= body.real_name
			gib_hunt_remove(body, "a body left lying")
	if(length(living) <= keep)
		return FALSE
	var/mob/living/carbon/human/victim = pick(living)
	var/where = victim.loc
	var/doing = victim.bot_brain ? "[victim.bot_brain.state][victim.bot_brain.current_goal ? " [victim.bot_brain.current_goal.type]" : ""][victim.bot_brain.pursuing_kind ? " ([victim.bot_brain.pursuing_kind] walk)" : ""]" : "no brain"
	switch(rand(1, 4))
		if(1)
			gh_log("kill [number]: gib [victim.real_name] at [round(world.time / 10)]s, [doing], in [where]")
			victim.gib()
		if(2)
			gh_log("kill [number]: small blast on [victim.real_name] at [round(world.time / 10)]s, [doing], in [where]")
			explosion(get_turf(victim), 0, 0, 2, 3)
		if(3)
			gh_log("kill [number]: qdel [victim.real_name] at [round(world.time / 10)]s, [doing], in [where]")
			qdel(victim)
		if(4)
			gh_log("kill [number]: death [victim.real_name] at [round(world.time / 10)]s, [doing], in [where]")
			GLOB.gib_hunt_bodies += victim.real_name
			victim.death()
	return TRUE

/proc/gib_hunt_remove(mob/living/carbon/human/body, why)
	if(QDELETED(body))
		return
	gh_log("remove: [why], [body.real_name] at [round(world.time / 10)]s")
	if(prob(50))
		body.gib()
	else
		qdel(body)
