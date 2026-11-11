// Self-test of overlays applied at once (code/controllers/subsystem/overlays.dm). Not part of the game.
//   tools/smooth_check/run.sh build ovcheck tools/smooth_check/overlay_check.dm && tools/smooth_check/run.sh run ovcheck
// Writes data/smooth_check/overlay_summary.txt.

/datum/controller/master
	sleep_offline_after_initializations = FALSE

/world/New()
	. = ..()
	spawn(0)
		overlay_check_run()

GLOBAL_LIST_EMPTY(oc_lines)
GLOBAL_VAR_INIT(oc_failed, 0)

/proc/oc_check(name, ok, detail = "")
	GLOB.oc_lines += "[ok ? "PASS" : "FAIL"] [name][detail ? " ([detail])" : ""]"
	if(!ok)
		GLOB.oc_failed++

/proc/oc_states(atom/A)
	var/list/out = list()
	for(var/mutable_appearance/M as anything in A.overlays)
		out += M.icon_state
	return out.Join(",")

/proc/overlay_check_run()
	UNTIL(SSticker.initialized)
	sleep(2 SECONDS)
	var/turf/T = locate(10, 10, SSmapping.levels_by_trait(ZTRAIT_CENTCOM)[1])
	var/obj/item/O = new(T)
	var/mutable_appearance/P = mutable_appearance('icons/effects/effects.dmi', "P")
	var/mutable_appearance/N1 = mutable_appearance('icons/effects/effects.dmi', "N1")
	var/mutable_appearance/N2 = mutable_appearance('icons/effects/effects.dmi', "N2")

	O.add_overlay(P, TRUE)
	O.add_overlay(N1)
	oc_check("an overlay shows at once, without waiting a tick", length(O.overlays) == 2, oc_states(O))
	oc_check("a priority overlay stays drawn above a later normal one", oc_states(O) == "N1,P", oc_states(O))
	O.cut_overlays()
	oc_check("cut_overlays() keeps the priority overlay", oc_states(O) == "P", oc_states(O))
	O.add_overlay(N2)
	oc_check("and the next normal one goes under it", oc_states(O) == "N2,P", oc_states(O))
	O.cut_overlay(P)
	oc_check("cut_overlay() without priority leaves a priority overlay", findtext(oc_states(O), "P"), oc_states(O))
	O.add_overlay(P, TRUE)
	oc_check("adding a priority overlay twice keeps one copy", length(O.priority_overlays) == 1 && length(O.overlays) == 2, "[length(O.priority_overlays)] kept, [oc_states(O)]")
	O.cut_overlay(P, TRUE)
	oc_check("cut_overlay(x, TRUE) removes it for good", oc_states(O) == "N2" && !length(O.priority_overlays), oc_states(O))
	O.cut_overlays()
	oc_check("then cut_overlays() empties it", !length(O.overlays), oc_states(O))

	var/obj/item/other = new(T)
	other.add_overlay(list(N1, N2))
	O.add_overlay(P, TRUE)
	O.add_overlay(N2)
	O.copy_overlays(other, TRUE)
	oc_check("copy_overlays(cut_old) takes the other's and keeps priority on top", oc_states(O) == "N1,N2,P", oc_states(O))
	O.cut_overlays(TRUE)
	oc_check("cut_overlays(TRUE) removes everything", !length(O.overlays) && !length(O.priority_overlays), oc_states(O))
	O.add_overlay("N1")
	O.add_overlay("N1")
	oc_check("an icon_state string overlay, added twice, is there once", length(O.overlays) == 1, oc_states(O))

	// the old queue's trap: a body dressed this tick had no overlays yet, so getFlatIcon() drew it bare
	var/mob/living/carbon/human/H = new(T)
	H.equipOutfit(/datum/outfit/job/engineer)
	oc_check("a person dressed this tick has their clothes on at once", length(H.overlays) >= 5, "[length(H.overlays)] overlays")
	var/icon/flat = getFlatIcon(H, defdir = SOUTH, no_anim = TRUE)
	oc_check("and getFlatIcon() draws them", flat && flat.Width() == 32, flat ? "[flat.Width()]x[flat.Height()]" : "null")

	// gun light: the off and removed paths used cut_overlays(light, TRUE), which wiped every overlay on the gun
	var/obj/item/gun/energy/e_gun/G = new(T)
	G.gun_light = new /obj/item/flashlight/seclite(G)
	var/mutable_appearance/mark = mutable_appearance('icons/effects/effects.dmi', "bloodmark")
	G.add_overlay(mark, TRUE)
	G.gun_light.on = TRUE
	G.update_gunlight()
	G.gun_light.on = FALSE
	G.update_gunlight()
	oc_check("turning a gun light off leaves the gun's other priority overlays", findtext(oc_states(G), "bloodmark"), oc_states(G))
	var/lights = 0
	for(var/mutable_appearance/M as anything in G.overlays)
		if("[M.icon]" == "icons/obj/guns/flashlights.dmi")
			lights++
	oc_check("and leaves one light sprite, not a pile", lights == 1, "[lights] light sprites")

	// floor decals: a south-facing turf carries decals facing every way (dir 0 overlays turned them all south)
	var/turf/F = locate(12, 10, T.z)
	var/list/decal_dirs = list()
	for(var/d in GLOB.cardinals)
		F.AddComponent(/datum/component/decal, 'icons/turf/decals.dmi', "warningline", d, CLEAN_NEVER, null, TURF_DECAL_LAYER, null, 255)
	for(var/mutable_appearance/M as anything in F.overlays)
		if(M.icon_state == "warningline" && M.layer == TURF_DECAL_LAYER)
			decal_dirs += "[M.dir]"
	sortTim(decal_dirs, GLOBAL_PROC_REF(cmp_text_asc))
	oc_check("floor decals keep their own dir", decal_dirs.Join(",") == "1,2,4,8", decal_dirs.Join(","))

	// image() overlays, the way a pipe manifold draws its arms: an /image's .appearance doesn't carry its dir, so they came out with
	// one dir between them (whatever the shared builder image had last) and merged into one arm
	var/obj/item/manifold = new(T)
	manifold.dir = SOUTH
	for(var/d in list(NORTH, EAST, WEST))
		manifold.add_overlay(image('icons/obj/atmospherics/pipes/manifold.dmi', "pipe-2", dir = d))
	var/list/arm_dirs = list()
	for(var/mutable_appearance/M as anything in manifold.overlays)
		arm_dirs += "[M.dir]"
	sortTim(arm_dirs, GLOBAL_PROC_REF(cmp_text_asc))
	oc_check("image() overlays keep their own dir (a manifold's three arms)", arm_dirs.Join(",") == "1,4,8", arm_dirs.Join(","))
	manifold.cut_overlay(image('icons/obj/atmospherics/pipes/manifold.dmi', "pipe-2", dir = EAST))
	oc_check("and one comes off by itself", length(manifold.overlays) == 2, "[length(manifold.overlays)] left")
	var/obj/item/burning = new(T)
	var/mutable_appearance/flames = mutable_appearance('icons/effects/effects.dmi', "fire")
	var/mutable_appearance/turned = new(image('icons/effects/effects.dmi', null, "shield", ABOVE_OBJ_LAYER, EAST))
	burning.add_overlay(list(flames, turned), TRUE)
	burning.add_overlay(N1)
	burning.add_overlay(P)
	oc_check("priority overlays, with or without a dir, are there once after more changes", length(burning.overlays) == 4, oc_states(burning))
	burning.cut_overlay(list(flames, turned), TRUE)
	oc_check("and come off for good", oc_states(burning) == "N1,P", oc_states(burning))

	text2file("[GLOB.oc_lines.Join("\n")]\nfailed [GLOB.oc_failed]\ndone", "data/smooth_check/overlay_summary.txt")
	sleep(5)
	del(world)
