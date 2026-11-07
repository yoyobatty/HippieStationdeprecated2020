// Does an object still look on fire after it's put out? Uses only calls the old overlay queue also had, so the same file
// runs on a build from before the change. Not part of the game. Writes data/smooth_check/fire_summary.txt.

/datum/controller/master
	sleep_offline_after_initializations = FALSE

/world/New()
	. = ..()
	spawn(0)
		fire_pile_run()

/proc/fp_fires(atom/A)
	var/n = 0
	for(var/mutable_appearance/M as anything in A.overlays)
		if(M.icon_state == GLOB.fire_overlay.icon_state && "[M.icon]" == "[GLOB.fire_overlay.icon]")
			n++
	return n

/proc/fp_list(atom/A)
	var/list/l = list()
	for(var/mutable_appearance/M as anything in A.overlays)
		l += "[M.icon]:[M.icon_state]"
	return l.Join(",")

/proc/fire_pile_run()
	UNTIL(SSticker.initialized)
	sleep(2 SECONDS)
	var/list/out = list()
	var/turf/T = locate(10, 10, SSmapping.levels_by_trait(ZTRAIT_CENTCOM)[1])
	var/obj/item/paper/P = new(T)
	P.fire_act(400)
	sleep(2)
	COMPILE_OVERLAYS(P)
	out += "on fire: [fp_fires(P)] fire sprites; overlays [fp_list(P)]; priority [length(P.priority_overlays)]; ON_FIRE [(P.resistance_flags & ON_FIRE) ? "yes" : "no"]; fire_overlay [GLOB.fire_overlay.icon]:[GLOB.fire_overlay.icon_state]"
	P.add_overlay("paper_words") // anything else changing its look while it burns
	sleep(2)
	COMPILE_OVERLAYS(P)
	out += "after another overlay: [fp_fires(P)] fire sprites; overlays [fp_list(P)]"
	P.extinguish()
	sleep(2)
	COMPILE_OVERLAYS(P)
	out += "put out: [fp_fires(P)] fire sprites; overlays [fp_list(P)]; ON_FIRE [(P.resistance_flags & ON_FIRE) ? "yes" : "no"]"
	text2file("[out.Join("\n")]\ndone", "data/smooth_check/fire_summary.txt")
	sleep(5)
	del(world)
