// Pictures of the new glowing fixtures with a real client, without and with their glow, plus a census of every hooked type.
// Not part of the game: HARNESS=emissive_shots.dm SENDER=shot.ps1 tools/keybind_check/run.sh glow
// Pictures in data/previews/glow_*.png, the census in data/keycheck_glow.txt. "Before" is the same boot with the new glows taken
// off (and luminosity back to 0, as it was), so both pictures have the same lights, the same broken bulbs and the same crew.
// data/glow_which names the group to count and picture: fixtures (default), machines, items or hazards. "Before" takes off only
// that group's glows, so the groups done earlier show in both pictures.

GLOBAL_VAR_INIT(keycheck_running, FALSE)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/proc/kc_log(text)
	text2file(text, "data/keycheck.txt")

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(50)
			glow_shots_run(src)

/proc/glow_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

GLOBAL_VAR_INIT(glow_group, "fixtures")

/// {type: "state" (glows by its state's mask, checked) or "count" (lights of its own, only counted)} for the group
/proc/glow_group_types()
	if(GLOB.glow_group == "hazards")
		return list(/obj/structure/sign/barsign = "count", /obj/structure/holosign = "count",
			/obj/machinery/power/supermatter_crystal = "count", /obj/singularity = "count")
	if(GLOB.glow_group == "items")
		return list(/obj/item/flashlight = "count", /obj/item/lighter = "count", /obj/item/clothing/mask/cigarette = "count",
			/obj/item/melee/transforming = "count", /obj/item/twohanded/dualsaber = "count", /obj/item/melee/baton = "count",
			/mob/living/silicon/robot = "count")
	if(GLOB.glow_group == "machines")
		return list(/obj/machinery/vending = "state", /obj/machinery/smartfridge = "state", /obj/machinery/telecomms = "state",
			/obj/machinery/recharger = "state", /obj/machinery/holopad = "state", /obj/machinery/dna_scannernew = "state",
			/obj/machinery/clonepod = "state", /obj/machinery/chem_dispenser = "state", /obj/machinery/chem_master = "state",
			/obj/machinery/computer/pandemic = "state", /obj/machinery/mineral/ore_redemption = "state",
			/obj/machinery/atmospherics/components/unary/cryo_cell = "count", /obj/machinery/power/smes = "count",
			/obj/machinery/cell_charger = "count", /obj/machinery/disposal/bin = "count", /obj/machinery/suit_storage_unit = "count")
	. = list()
	for(var/kind in glow_fixture_types())
		.[kind] = "state"

/// The group's areas to picture, in order
/proc/glow_group_areas()
	if(GLOB.glow_group == "machines")
		return list(/area/medical, /area/engine, /area/tcommsat, /area/crew_quarters/bar)
	return list(/area/hallway, /area/security)

/proc/glow_in_group(atom/A)
	for(var/kind in glow_group_types())
		if(istype(A, kind))
			return TRUE
	return FALSE

/proc/glow_fixture_types()
	return list(/obj/machinery/door/airlock, /obj/machinery/airalarm, /obj/machinery/button, /obj/machinery/light_switch,
		/obj/machinery/flasher, /obj/machinery/requests_console, /obj/machinery/newscaster, /obj/machinery/turretid,
		/obj/machinery/camera, /obj/machinery/airlock_sensor, /obj/machinery/embedded_controller/radio/airlock_controller,
		/obj/machinery/embedded_controller/radio/simple_vent_controller, /obj/machinery/doorButtons/access_button,
		/obj/machinery/doorButtons/airlock_controller, /obj/machinery/keycard_auth, /obj/item/radio/intercom,
		/obj/machinery/status_display, /obj/machinery/door_timer)

/// Should this one glow? By its own state's mask, or for the odd ones by what they show.
/proc/glow_expected(atom/A)
	if(istype(A, /obj/machinery/door/airlock))
		var/obj/machinery/door/airlock/D = A
		if(D.operating)
			return length(D.emissive_glow_shown) // mid-swing: lights_opening/closing
		return D.hasPower() && (D.lights && D.density && (D.locked || D.emergency) || D.unres_sides)
	if(istype(A, /obj/machinery/status_display) || istype(A, /obj/machinery/door_timer))
		return A.maptext || length(A.overlays)
	var/list/glows = GLOB.emissive_glow_states[A.icon]
	if(!glows)
		glows = list()
		for(var/state in icon_states(A.icon))
			if(length(state) > 5 && copytext(state, -5) == "_glow")
				glows[copytext(state, 1, -5)] = state
		GLOB.emissive_glow_states[A.icon] = glows
	return A.icon_state && glows[A.icon_state]

/proc/glow_census()
	var/total_all = 0
	var/glowing_all = 0
	var/wrong_all = 0
	var/list/kinds = glow_group_types()
	for(var/kind in kinds)
		var/total = 0
		var/glowing = 0
		var/list/wrong = list()
		var/list/states = list()
		for(var/atom/A as anything in typesof_instances(kind))
			if(!is_station_level(A.z))
				continue
			total++
			var/is_glowing = length(A.emissive_glow_shown) > 0
			if(is_glowing)
				glowing++
				states["[A.icon_state]"]++
			if(kinds[kind] == "count")
				if(is_glowing && A.luminosity != 1)
					wrong += "[A.type] [A.icon_state] ([A.x],[A.y]) glowing with luminosity [A.luminosity]"
				var/atom/movable/AM = A
				if(is_glowing && istype(AM) && AM.blocks_emissive == EMISSIVE_BLOCK_GENERIC && glow_has_blocker(AM))
					wrong += "[A.type] [A.icon_state] ([A.x],[A.y]) glowing behind its own emissive blocker"
				continue
			if(!is_glowing != !glow_expected(A))
				wrong += "[A.type] [A.icon_state] ([A.x],[A.y]) glowing [is_glowing] expected [!!glow_expected(A)] lum [A.luminosity]"
			else if(is_glowing && A.luminosity != 1)
				wrong += "[A.type] [A.icon_state] ([A.x],[A.y]) glowing with luminosity [A.luminosity]"
		var/list/state_text = list()
		for(var/state in states)
			state_text += "[state] [states[state]]"
		kc_log("census [kind]: [glowing] of [total] glowing ([state_text.Join(", ")]), [length(wrong)] wrong")
		for(var/i in 1 to min(5, length(wrong)))
			kc_log("   WRONG [wrong[i]]")
		total_all += total
		glowing_all += glowing
		wrong_all += length(wrong)
	kc_log("census: [glowing_all] of [total_all] glowing, [wrong_all] wrong")

/proc/typesof_instances(kind)
	. = list()
	if(ispath(kind, /obj/machinery))
		for(var/obj/machinery/M as anything in GLOB.machines)
			if(istype(M, kind))
				. += M
	else
		for(var/atom/A in world)
			if(istype(A, kind))
				. += A

/proc/glow_lights(turf/T, on)
	var/list/areas = list()
	for(var/turf/near in range(9, T))
		areas |= get_area(near)
	for(var/area/A as anything in areas)
		A.lightswitch = on
		A.power_change()
		for(var/obj/machinery/light_switch/L in A)
			L.update_icon()

/// Takes the new glows off everything near (and luminosity back to 0, as before), or puts them back
/proc/glow_strip(turf/T, list/stripped)
	if(stripped)
		for(var/atom/A as anything in stripped)
			var/list/kept = stripped[A]
			A.add_overlay(kept[1])
			A.luminosity = 1
			if(kept[2])
				A.set_light(kept[2], kept[3], kept[4])
		return
	. = list()
	for(var/atom/A in range(10, T))
		if(length(A.emissive_glow_shown) && glow_in_group(A))
			var/obj/O = A
			var/glow_lit = istype(O) && O.emissive_glow_lit // the faint light the glow casts goes too
			.[A] = list(A.emissive_glow_shown, glow_lit ? A.light_range : 0, A.light_power, A.light_color)
			A.cut_overlay(A.emissive_glow_shown)
			A.luminosity = 0
			if(glow_lit)
				A.set_light(0)

/// The floor with the most kinds of new glowing fixtures round it, in a hallway or the brig
/proc/glow_pick_spot(area_type, avoid)
	var/turf/best
	var/best_score = -1
	for(var/obj/machinery/M as anything in GLOB.machines)
		if(!is_station_level(M.z) || !length(M.emissive_glow_shown) || !istype(get_area(M), area_type) || !glow_in_group(M))
			continue
		var/turf/T = get_turf(M)
		if(avoid && get_dist(T, avoid) < 12)
			continue
		var/list/kinds = list()
		for(var/obj/near in range(5, T))
			if(length(near.emissive_glow_shown) && glow_in_group(near))
				kinds |= near.type
		var/score = length(kinds)
		if(score > best_score)
			best_score = score
			best = T
	kc_log("spot ([best?.x],[best?.y]) in [get_area(best)]: [best_score] kinds glowing within 5")
	return best

/// Bolts one closed airlock near, sets emergency access on another, so their lights show
/proc/glow_dress_airlocks(turf/T)
	var/bolted = 0
	for(var/obj/machinery/door/airlock/D in range(6, T))
		if(!D.density || !D.hasPower())
			continue
		if(!bolted)
			D.bolt()
			bolted = 1
			kc_log("bolted [D] ([D.x],[D.y]): glow [length(D.emissive_glow_shown)]")
		else
			D.emergency = TRUE
			D.update_icon()
			kc_log("emergency on [D] ([D.x],[D.y]): glow [length(D.emissive_glow_shown)]")
			return

/proc/glow_spot_shots(mob/living/carbon/human/H, turf/spot, name)
	H.forceMove(spot)
	if(GLOB.glow_group == "fixtures")
		glow_dress_airlocks(spot)
	sleep(3 SECONDS)
	var/list/stripped = glow_strip(spot)
	kc_log("[name]: [length(stripped)] glowing things in range")
	sleep(1 SECONDS)
	glow_shot("glow_[name]_1_lit_before")
	glow_strip(spot, stripped)
	sleep(1 SECONDS)
	glow_shot("glow_[name]_2_lit_after")
	glow_lights(spot, FALSE)
	sleep(3 SECONDS)
	stripped = glow_strip(spot)
	sleep(1 SECONDS)
	glow_shot("glow_[name]_3_dark_before")
	glow_strip(spot, stripped)
	sleep(1 SECONDS)
	glow_shot("glow_[name]_4_dark_after")
	glow_lights(spot, TRUE)
	sleep(2 SECONDS)

/// A clear 5x3 strip of hallway floor, the first one found at least 15 tiles from avoid
/proc/glow_clear_strip(turf/avoid)
	for(var/turf/open/floor/F in world)
		if(!is_station_level(F.z) || !istype(get_area(F), /area/hallway/primary))
			continue
		var/clear = TRUE
		for(var/turf/T in block(locate(F.x - 2, F.y - 1, F.z), locate(F.x + 2, F.y + 1, F.z)))
			if(!istype(T, /turf/open/floor) || T.density || (locate(/obj/structure) in T) || (locate(/obj/machinery) in T))
				clear = FALSE
				break
		if(clear && (!avoid || get_dist(F, avoid) >= 15))
			return F

/// Holosigns, a bar sign, lava, a supermatter shard, a tesla miniball and a singularity, the last two stopped so they don't zap or eat
/proc/glow_hazards_scene()
	var/turf/spot = glow_clear_strip(glow_clear_strip())
	if(!spot)
		kc_log("hazards: no clear floor found")
		return
	kc_log("hazards scene at ([spot.x],[spot.y]) in [get_area(spot)]")
	new /obj/structure/holosign/barrier/engineering(locate(spot.x - 2, spot.y - 1, spot.z))
	new /obj/structure/holosign/barrier/atmos(locate(spot.x - 1, spot.y - 1, spot.z))
	new /obj/structure/holosign/barrier/medical(locate(spot.x, spot.y - 1, spot.z))
	var/obj/machinery/power/supermatter_crystal/shard/SM = new(locate(spot.x + 2, spot.y - 1, spot.z))
	for(var/dx in -2 to -1)
		var/turf/T = locate(spot.x + dx, spot.y + 1, spot.z)
		T.ChangeTurf(/turf/open/lava)
	var/obj/singularity/energy_ball/ball = new(locate(spot.x + 1, spot.y + 1, spot.z), 50, TRUE)
	STOP_PROCESSING(SSobj, ball)
	var/obj/singularity/sing = new(locate(spot.x + 6, spot.y, spot.z))
	STOP_PROCESSING(SSobj, sing)
	sing.expand(STAGE_TWO)
	var/obj/structure/sign/barsign/B = new(locate(spot.x, spot.y + 2, spot.z))
	B.set_sign(new /datum/barsign/thebark)
	var/turf/open/lava/L = locate(spot.x - 2, spot.y + 1, spot.z)
	kc_log("  shard [SM.icon_state] glow [length(SM.emissive_glow_shown)]; ball [ball.icon_state] glow [length(ball.emissive_glow_shown)]; singularity [sing.icon_state] glow [length(sing.emissive_glow_shown)]; sign [B.icon_state] glow [length(B.emissive_glow_shown)]; lava [L?.type] overlays [length(L?.overlays)]")
	return spot

/// A lit corner of a hallway: lights on the floor, someone holding a lit sword and smoking, a cyborg looking east
/proc/glow_items_scene()
	var/turf/spot = glow_clear_strip()
	if(!spot)
		kc_log("items: no clear floor found")
		return
	kc_log("items scene at ([spot.x],[spot.y]) in [get_area(spot)]")
	var/list/lit = list()
	var/x = spot.x - 2
	var/y = spot.y - 1
	var/obj/item/flashlight/F = new(locate(x++, y, spot.z))
	F.on = TRUE
	F.update_brightness()
	lit += F
	var/obj/item/flashlight/lamp/L = new(locate(x++, y, spot.z))
	L.on = TRUE
	L.update_brightness()
	lit += L
	var/obj/item/flashlight/flare/FL = new(locate(x++, y, spot.z))
	FL.on = TRUE
	FL.update_brightness()
	lit += FL
	var/obj/item/flashlight/glowstick/cyan/G = new(locate(x++, y, spot.z))
	G.on = TRUE
	G.update_icon()
	lit += G
	var/obj/item/lighter/Z = new(locate(x++, y, spot.z))
	Z.set_lit(TRUE)
	lit += Z
	x = spot.x - 1
	y = spot.y + 1
	var/obj/item/clothing/mask/cigarette/CG = new(locate(x++, y, spot.z))
	CG.light()
	lit += CG
	var/obj/item/melee/transforming/energy/sword/saber/blue/S = new(locate(x++, y, spot.z))
	S.transform_weapon(null, TRUE)
	lit += S
	var/obj/item/melee/baton/loaded/B = new(locate(x++, y, spot.z))
	B.status = TRUE
	B.update_icon()
	lit += B
	for(var/obj/item/I in lit)
		kc_log("  [I.type] icon [I.icon_state]: glow [length(I.emissive_glow_shown)], blocker [glow_has_blocker(I) ? "kept" : "gone"]")
	// Someone with a lit sword in hand and a lit cigarette
	var/mob/living/carbon/human/M = new(locate(spot.x + 2, spot.y, spot.z))
	M.equipOutfit(/datum/outfit/job/assistant)
	var/obj/item/melee/transforming/energy/sword/saber/red/RS = new(M.loc)
	M.put_in_hands(RS)
	RS.transform_weapon(M, TRUE)
	var/obj/item/clothing/mask/cigarette/smoke = new(M.loc)
	M.equip_to_slot_or_del(smoke, ITEM_SLOT_MASK)
	smoke.light()
	M.regenerate_icons()
	kc_log("  smoker: sword [RS.icon_state] held [RS.loc == M], cig [smoke.icon_state] worn [M.wear_mask == smoke]")
	// Someone with cybernetic eyes, in a shade the bloom shows up well in
	var/mob/living/carbon/human/E = new(locate(spot.x - 1, spot.y, spot.z))
	E.equipOutfit(/datum/outfit/job/assistant)
	E.eye_color = "33ccff"
	var/obj/item/organ/eyes/robotic/cyber = new
	cyber.Insert(E)
	kc_log("  cyber eyes [cyber.eye_icon_state] colour [E.eye_color]: glow [length(E.emissive_glow_shown)] lum [E.luminosity]")
	// A cyborg turned east
	var/mob/living/silicon/robot/modules/engineering/R = new(locate(spot.x - 2, spot.y, spot.z))
	R.setDir(EAST)
	R.update_icons()
	kc_log("  cyborg [R.icon_state] dir [R.dir]: eyes glow [length(R.emissive_glow_shown)] lum [R.luminosity]")
	return spot

/proc/glow_has_blocker(atom/movable/A)
	for(var/obj/effect/overlay/vis/each in A.managed_vis_overlays)
		if(each.plane == EMISSIVE_BLOCKER_PLANE)
			return TRUE
	return FALSE

/proc/glow_shots_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	var/list/groups = list("fixtures")
	if(fexists("data/glow_which"))
		groups = splittext(trim(file2text("data/glow_which")), ",")
	kc_log("groups [groups.Join(", ")]")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	var/mob/living/carbon/human/H
	for(var/group in groups)
		GLOB.glow_group = group
		var/list/spots = list()
		if(group == "items" || group == "hazards")
			var/turf/scene = group == "items" ? glow_items_scene() : glow_hazards_scene()
			if(scene)
				spots[scene] = "scene"
		else
			glow_census()
			var/turf/last
			for(var/area_type in glow_group_areas())
				var/turf/T = glow_pick_spot(area_type, last)
				if(T)
					spots[T] = copytext("[area_type]", findlasttext("[area_type]", "/") + 1)
					last = T
		if(!H)
			H = new(spots.len ? spots[1] : get_turf(C.mob))
			H.mind_initialize()
			H.equipOutfit(/datum/outfit/job/assistant)
			H.ckey = C.ckey
			sleep(3 SECONDS)
		for(var/turf/T as anything in spots)
			glow_spot_shots(H, T, "[group]_[spots[T]]")
		if(group == "fixtures")
			// A denied press on the nearest button: the glow follows the flick, then goes back
			var/obj/machinery/button/B = locate() in range(12, H)
			if(B)
				B.flick_emissive_glow("[B.skin]-denied_glow", 2 SECONDS)
				kc_log("button ([B.x],[B.y]) denied: glow [B.emissive_glow_shown ? "on" : "off"]")
				sleep(3 SECONDS)
				kc_log("button after the flick: icon [B.icon_state], glow [length(B.emissive_glow_shown)]")
		glow_census()

	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
