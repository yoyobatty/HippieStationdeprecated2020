// Station looks self-test (hippiestation/code/modules/station_looks/): the roll, weights, bans and forcing in the lobby, then
// on the real station each look put on and taken off again, headless.
//
// Run:      tools/looks_check/run_looks_check.sh   (builds its own copy, so hippiestation.dmb is left alone)
// Results:  data/looks_check/results.txt, one PASS/FAIL line per check, and snapshot_<look>.txt: the station's lighting with
//           each look on, for tools/looks_check/looks_sheet.py to draw over the map.
// Boots with station-looks=plain, so the round starts on a day shift with nothing else on.

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("looks-check" in world.params)
		sleep_offline_after_initializations = FALSE //nobody connects to this, so the world has to keep ticking
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_looks_check))
	return ..()

#define LOOKS_CHECK_DIR "data/looks_check/"

/proc/run_looks_check()
	UNTIL(SSticker.current_state >= GAME_STATE_PREGAME)
	sleep(2 SECONDS)
	fdel(LOOKS_CHECK_DIR)
	var/datum/looks_check/test = new
	test.in_lobby()
	GLOB.master_mode = "extended"
	CONFIG_SET(number/bot_crew_target, 0)
	SSticker.start_immediately = TRUE
	var/round_deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < round_deadline)
		sleep(1 SECONDS)
	test.in_round()
	text2file(jointext(test.lines, "\n"), "[LOOKS_CHECK_DIR]results.txt")
	log_world("LOOKS CHECK: done, [test.passed] passed, [test.failed] failed")
	Master.Shutdown()
	qdel(world)

/datum/looks_check
	var/list/lines = list()
	var/passed = 0
	var/failed = 0
	var/z

/datum/looks_check/proc/check(name, condition, detail)
	if(condition)
		passed++
	else
		failed++
	lines += "[condition ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " - [detail]"]"

/datum/looks_check/proc/note(text)
	lines += "     [text]"

/datum/looks_check/proc/picked(slot)
	return SSstation_looks.picked[slot]

/// How often each id comes up in `times` rolls of a slot
/datum/looks_check/proc/roll_counts(slot, times)
	var/list/counts = list()
	for(var/i in 1 to times)
		SSstation_looks.roll_slot(slot)
		for(var/id in picked(slot))
			counts[id]++
	return counts

/datum/looks_check/proc/set_weight(id, weight)
	var/datum/config_entry/keyed_list/station_look_weight/E = config.entries_by_type[/datum/config_entry/keyed_list/station_look_weight]
	if(isnull(weight))
		E.config_entry_value -= id
	else
		E.config_entry_value[id] = weight

/datum/looks_check/proc/in_lobby()
	var/datum/controller/subsystem/station_looks/S = SSstation_looks
	check("subsystem initialized", S.initialized)
	var/list/per_slot = list()
	for(var/id in S.looks)
		var/datum/station_look/L = S.looks[id]
		per_slot[L.slot]++
	check("a sky look for every sky", per_slot[LOOK_SLOT_SKY] == length(subtypesof(/datum/sky_theme)), "[per_slot[LOOK_SLOT_SKY]] of [length(subtypesof(/datum/sky_theme))]")
	check("four shift times", per_slot[LOOK_SLOT_SHIFT] == 4, "[per_slot[LOOK_SLOT_SHIFT]]")
	check("extras to roll", per_slot[LOOK_SLOT_EXTRA] >= 1, "[per_slot[LOOK_SLOT_EXTRA]]")
	note("rolled at boot: [S.summary()]")

	// station-looks=plain: the sky rolled, a day shift, nothing else
	var/list/skies = picked(LOOK_SLOT_SKY)
	check("plain: one sky", length(skies) == 1)
	var/datum/station_look/sky/sky = length(skies) ? S.looks[skies[1]] : null
	check("plain: the sky rolled is the sky up", sky && SSparallax.theme?.type == sky.theme_type, "[sky?.theme_type] / [SSparallax.theme?.type]")
	check("plain: a day shift", picked(LOOK_SLOT_SHIFT) ~= list("day"), "[english_list(picked(LOOK_SLOT_SHIFT))]")
	check("plain: no extras or history", !length(picked(LOOK_SLOT_EXTRA)) && !length(picked(LOOK_SLOT_HISTORY)))
	var/list/on_early = list()
	for(var/id in S.looks)
		var/datum/station_look/L = S.looks[id]
		if(L.active && L.slot != LOOK_SLOT_SKY)
			on_early += id
	check("lobby: only the sky is on", !S.applied && !length(on_early), "[english_list(on_early)]")

	// Weights: config's win over the code's, 0 never rolls
	var/list/counts = roll_counts(LOOK_SLOT_SHIFT, 300)
	note("300 shift rolls: [list2params(counts)]")
	check("shift: every time comes up", counts["day"] && counts["morning"] && counts["night"] && counts["power_saving"])
	check("shift: day likeliest, power-saving rarest", counts["day"] > counts["power_saving"] && counts["night"] > counts["power_saving"])
	set_weight("night", 0)
	counts = roll_counts(LOOK_SLOT_SHIFT, 200)
	check("config weight 0: night never rolls", !counts["night"], list2params(counts))
	set_weight("night", null)
	set_weight("none_extra", 0)
	counts = roll_counts(LOOK_SLOT_EXTRA, 50)
	check("config none_extra 0: an extra every time", counts["tired_wiring"] == 50, list2params(counts))
	set_weight("none_extra", null)
	counts = roll_counts(LOOK_SLOT_EXTRA, 300)
	check("extras: some rounds get none", counts["tired_wiring"] > 60 && counts["tired_wiring"] < 240, "[counts["tired_wiring"]] of 300")

	// Bans keep a look out of re-rolls
	S.banned["day"] = TRUE
	counts = roll_counts(LOOK_SLOT_SHIFT, 100)
	check("banned day never rolls", !counts["day"], list2params(counts))
	S.banned -= "day"
	for(var/id in S.looks)
		var/datum/station_look/L = S.looks[id]
		if(L.slot == LOOK_SLOT_SKY && L.id != "sky_quiet")
			S.banned[id] = TRUE
	S.roll_slot(LOOK_SLOT_SKY)
	check("every sky banned but one: that one", picked(LOOK_SLOT_SKY) ~= list("sky_quiet") && SSparallax.theme?.type == /datum/sky_theme/quiet, "[english_list(picked(LOOK_SLOT_SKY))]")
	S.banned = list()

	// Forcing in the lobby picks without putting on
	S.picked[LOOK_SLOT_EXTRA] = list() //the rolls above may have left one in
	S.force("night")
	var/datum/station_look/night = S.looks["night"]
	check("lobby force: picked, not on yet", picked(LOOK_SLOT_SHIFT) ~= list("night") && !night.active)
	S.force("tired_wiring")
	check("lobby force: an extra goes in", "tired_wiring" in picked(LOOK_SLOT_EXTRA))
	S.force("tired_wiring")
	check("lobby force: and out again", !("tired_wiring" in picked(LOOK_SLOT_EXTRA)))
	S.force("day")
	S.picked[LOOK_SLOT_EXTRA] = list()
	S.picked[LOOK_SLOT_HISTORY] = list()

	var/datum/station_looks_window/W = new
	var/list/data = W.ui_data(null)
	var/list/slots = data["slots"]
	check("window: a section for each slot with looks", length(slots) == 3, "[length(slots)]")
	qdel(W)

/// Every station lamp, settled: waits for the looks' relighting, then the lighting engine
/datum/looks_check/proc/settle(seconds = 5)
	sleep(seconds SECONDS)
	lighting_bench_flush()

/datum/looks_check/proc/snapshot(name)
	lighting_bench_snapshot(z, "[LOOKS_CHECK_DIR]snapshot_[name].txt")

/datum/looks_check/proc/lamp_detail(obj/machinery/light/L)
	return "[L] at [L.x],[L.y] in [get_area(L)]: colour [L.bulb_colour] power [L.bulb_power] night [L.nightshift_light_color] [L.nightshift_light_power], base [jointext(L.look_base, " ")], status [L.status] on [L.on] flickering [L.flickering] worn [L.worn] color [L.color]"

/datum/looks_check/proc/clock_minutes()
	return round(station_time() / (1 MINUTES)) % 1440

/datum/looks_check/proc/in_round()
	var/datum/controller/subsystem/station_looks/S = SSstation_looks
	check("round started", SSticker.current_state >= GAME_STATE_PLAYING, "state [SSticker.current_state]")
	z = SSmapping.levels_by_trait(ZTRAIT_STATION)[1]
	settle(3)
	check("looks on at round start", S.applied && S.looks["day"]:active)
	var/minutes = clock_minutes()
	check("day: clock 10:00-15:00 (plus the wait)", minutes >= 600 && minutes <= 1020, "[minutes]")
	var/list/lamps = station_lamps()
	note("[length(lamps)] lamps on the station level")

	// Reference lamps: a plain one in a hall, one in medbay, and a plain one with a mood colour
	var/obj/machinery/light/hall
	var/obj/machinery/light/medbay
	for(var/obj/machinery/light/L as anything in lamps)
		if(L.status != LIGHT_OK || L.color)
			continue
		var/area/A = get_area(L)
		if(!hall && istype(A, /area/hallway/primary) && L.bulb_colour == "#FFFFFF")
			hall = L
		if(!medbay && istype(A, /area/medical/medbay))
			medbay = L
	check("reference lamps found", hall && medbay)
	if(!hall || !medbay)
		return
	var/hall_colour = hall.bulb_colour
	var/hall_power = hall.bulb_power
	snapshot("plain")

	// Morning: the clock, every plain lamp warmer, a lamp built now as well
	S.force("morning")
	settle()
	var/datum/station_look/shift/morning = S.looks["morning"]
	minutes = clock_minutes()
	check("morning: clock 07:40-09:30", minutes >= 460 && minutes <= 575, "[minutes]")
	var/tinted = 0
	var/plain = 0
	var/custom_kept = 0
	var/custom = 0
	for(var/obj/machinery/light/L as anything in lamps)
		if(!L.look_base || QDELETED(L))
			continue
		if(L.plain_lamp())
			plain++
			if(L.bulb_colour == look_tint(L.look_base[1], morning.lamp_tint))
				tinted++
			else
				note("untinted: [lamp_detail(L)]")
		else
			custom++
			if(L.bulb_colour == L.look_base[1])
				custom_kept++
	check("morning: every plain lamp tinted", plain > 100 && tinted == plain, "[tinted] of [plain]")
	check("morning: lamps with their own colour keep it", custom_kept == custom, "[custom_kept] of [custom]")
	check("morning: shift notes say so", findtext(S.shift_notes(), "Morning shift"), S.shift_notes())
	var/obj/machinery/light/built = new(get_turf(hall))
	sleep(1)
	check("morning: a lamp built now is tinted too", built.bulb_colour == look_tint("#FFFFFF", morning.lamp_tint), built.bulb_colour)
	qdel(built)
	snapshot("morning")

	// Night: morning off again, the halls and public rooms on night lighting and nowhere else
	S.force("night")
	settle()
	var/datum/station_look/shift/night/night = S.looks["night"]
	check("night: morning's tint off", hall.bulb_colour == hall_colour && !morning.active, hall.bulb_colour)
	minutes = clock_minutes()
	check("night: clock 21:00-02:00", minutes >= 1260 || minutes <= 125, "[minutes]")
	check("night: hall lamp on night lighting", hall.nightshift_enabled)
	check("night: in the night tint", hall.nightshift_light_color == look_tint(hall.look_base[1], night.night_tint), hall.nightshift_light_color)
	check("night: medbay lamp not", !medbay.nightshift_enabled)
	var/public_on = 0
	var/public = 0
	var/other_on = 0
	for(var/obj/machinery/power/apc/APC as anything in GLOB.apcs_list)
		if(!APC.area || !(APC.area.type in GLOB.the_station_areas))
			continue
		if(is_type_in_typecache(APC.area, GLOB.night_lit_areas))
			public++
			public_on += APC.nightshift_lights
		else
			other_on += APC.nightshift_lights
	check("night: every public APC on night lighting, no other", public && public_on == public && !other_on, "[public_on] of [public], [other_on] others")
	check("night: SSnightshift holds it all round", SSnightshift.can_fire && SSnightshift.nightshift_active && SSnightshift.nightshift_end_time == 24 HOURS)
	check("night: shift notes say so", findtext(S.shift_notes(), "Night shift"), S.shift_notes())
	settle(1)
	snapshot("night")
	set_security_level(SEC_LEVEL_RED)
	SSnightshift.check_nightshift()
	sleep(3 SECONDS)
	check("night: red alert brings the lights up", !hall.nightshift_enabled)
	set_security_level(SEC_LEVEL_GREEN)
	SSnightshift.check_nightshift()
	sleep(3 SECONDS)
	check("night: and back to night after", hall.nightshift_enabled)

	// Power-saving: night off again, every plain lamp amber and dimmer
	S.force("power_saving")
	settle()
	var/datum/station_look/shift/saving = S.looks["power_saving"]
	check("power-saving: night lighting off", !hall.nightshift_enabled && !SSnightshift.nightshift_active)
	check("power-saving: SSnightshift as it was", SSnightshift.nightshift_end_time == initial(SSnightshift.nightshift_end_time) && SSnightshift.can_fire == night.nightshift_fired)
	check("power-saving: hall lamp amber and dimmer", hall.bulb_colour == look_tint(hall_colour, saving.lamp_tint) && hall.bulb_power == hall_power * saving.lamp_power, "[hall.bulb_colour] [hall.bulb_power]")
	snapshot("power_saving")

	// Day again: every lamp as it was
	S.force("day")
	settle()
	var/changed = 0
	for(var/obj/machinery/light/L as anything in lamps)
		if(QDELETED(L))
			continue
		if(L.look_base && (L.bulb_colour != L.look_base[1] || L.bulb_power != L.look_base[2] || L.nightshift_light_color != L.look_base[3] || L.nightshift_light_power != L.look_base[4]))
			changed++
			note("still changed: [lamp_detail(L)]")
	check("day: every lamp back as it was", !changed, "[changed] still changed")

	// Tired wiring
	var/worn_before = length(GLOB.worn_lights)
	S.force("tired_wiring")
	settle(8)
	var/datum/station_look/tired_wiring/wiring = S.looks["tired_wiring"]
	var/eligible = 0
	var/yellowed = 0
	var/yellow_right = 0
	var/tired = 0
	var/tired_worn = 0
	var/list/buzzers = list()
	for(var/obj/machinery/light/L as anything in lamps)
		var/area/A = get_area(L)
		if(A && (A.type in GLOB.the_station_areas) && !istype(A, /area/maintenance))
			eligible++
		if(L.yellowed)
			yellowed++
			if(L.bulb_colour == look_tint(L.look_base[1], LOOK_YELLOWED_TINT) && L.bulb_power == L.look_base[2] * LOOK_YELLOWED_POWER)
				yellow_right++
		if(L.tired)
			tired++
			if(L.worn && (L in GLOB.worn_lights))
				tired_worn++
		if(L.buzzing)
			buzzers += L
	check("tired: about one tube in ten yellowed", yellowed >= eligible * 0.04 && yellowed <= eligible * 0.18, "[yellowed] of [eligible]")
	check("tired: yellowed ones tinted and dimmer", yellowed && yellow_right == yellowed, "[yellow_right] of [yellowed]")
	check("tired: about half of those sputter", tired >= yellowed * 0.25 && tired <= yellowed * 0.75 && tired_worn == tired, "[tired] tired, [tired_worn] worn")
	var/list/halls = list()
	for(var/obj/machinery/light/L as anything in buzzers)
		halls |= get_area(L)
	check("tired: one lamp humming in each hall", length(buzzers) && length(buzzers) == length(halls) && length(GLOB.buzzing_lights) == length(buzzers), "[length(buzzers)] lamps, [length(halls)] halls")
	var/list/obj/machinery/power/apc/tripped = list()
	for(var/obj/machinery/power/apc/APC as anything in GLOB.apcs_list)
		if(!isnull(APC.look_tripped_from))
			tripped += APC
	var/tripped_off = 0
	var/emergency = 0
	var/dept_lamps = 0
	for(var/obj/machinery/power/apc/APC as anything in tripped)
		tripped_off += (APC.lighting == 0)
		for(var/obj/machinery/light/L in APC.area)
			if(L.status == LIGHT_OK && L.cell)
				dept_lamps++
				emergency += L.emergency_mode
	check("tired: [wiring.department]'s lighting tripped", length(tripped) && tripped_off == length(tripped), "[tripped_off] of [length(tripped)] APCs")
	check("tired: its lamps on emergency light", dept_lamps && emergency >= dept_lamps * 0.9, "[emergency] of [dept_lamps]")
	check("tired: shift notes name the department", findtext(S.shift_notes(), wiring.department), S.shift_notes())
	settle(1)
	snapshot("tired_wiring")

	// A new tube is a sound one
	var/obj/machinery/light/old
	for(var/obj/machinery/light/L as anything in buzzers)
		if(L.yellowed && L.tired)
			old = L
			break
	if(!old)
		for(var/obj/machinery/light/L as anything in lamps)
			if(L.tired && L.status == LIGHT_OK)
				old = L
				L.start_buzz()
				break
	if(old)
		var/obj/item/light/taken = old.drop_light_tube()
		check("tube out: wear gone with it", !old.yellowed && !old.tired && !old.worn && !old.buzzing && !(old in GLOB.worn_lights) && !(old in GLOB.buzzing_lights))
		qdel(taken)
		old.status = LIGHT_OK
		old.on = old.has_power()
		old.update()
		check("tube in: lit as it was", old.bulb_colour == old.look_base[1] && old.bulb_power == old.look_base[2], "[old.bulb_colour] [old.bulb_power]")
	else
		check("tube swap: a tired lamp to try", FALSE)

	// Tired tubes burn out in the end: 30 of them sputtered six times over is ~180 tries at LOOK_TIRED_BURNOUT in 100
	var/list/obj/machinery/light/sputterers = list()
	for(var/obj/machinery/light/L as anything in lamps)
		if(L.tired && L.on && L.status == LIGHT_OK)
			sputterers += L
			if(length(sputterers) >= 30)
				break
	for(var/i in 1 to 6)
		for(var/obj/machinery/light/L as anything in sputterers)
			L.sputter()
		sleep(7 SECONDS)
	var/burned = 0
	for(var/obj/machinery/light/L as anything in sputterers)
		burned += (L.status == LIGHT_BURNED)
	check("tired: some burn out after sputtering", burned > 0, "[burned] of [length(sputterers)]")

	// Taken off again
	S.force("tired_wiring")
	settle(6)
	var/still_yellow = 0
	var/still_tired = 0
	var/still_buzzing = 0
	for(var/obj/machinery/light/L as anything in lamps)
		still_yellow += L.yellowed
		still_tired += L.tired
		still_buzzing += L.buzzing
	check("tired off: no yellowed, tired or humming lamps left", !still_yellow && !still_tired && !still_buzzing && !length(GLOB.buzzing_lights), "[still_yellow] [still_tired] [still_buzzing]")
	check("tired off: worn list back to maintenance's", length(GLOB.worn_lights) == worn_before, "[length(GLOB.worn_lights)] of [worn_before]")
	var/still_off = 0
	for(var/obj/machinery/power/apc/APC as anything in tripped)
		still_off += (APC.lighting == 0 || !isnull(APC.look_tripped_from))
	check("tired off: the breakers set back", !still_off, "[still_off] still off")
	settle(4)
	snapshot("after")
	note("lighting after everything against before: [lighting_bench_compare_snapshots("[LOOKS_CHECK_DIR]snapshot_plain.txt", "[LOOKS_CHECK_DIR]snapshot_after.txt")] ([burned] tubes burned out, 1 swapped)")
	note("looks on now: [S.summary()]")

#undef LOOKS_CHECK_DIR
