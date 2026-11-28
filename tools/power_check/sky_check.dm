// The sky, headless (hippiestation/code/_onclick/hud/parallax.dm, sky.dm, sky_weather.dm): the sky turns with the real sun at
// four speeds and both ways, the sun's hooks line it up, every layer sits in its holder at the right depth, the giant and the
// aurora are placed by transform, and the ash storm, radiation storm and Aurora Caelus start and stop their art. Not part of the
// game: HARNESS=sky_check.dm EXTRA_PARAMS=bot-map=testbench tools/power_check/run.sh <label>
// Ported from the Paradise port's checks (Paradise tools/perf_bench/worktree_archive/sky-v2/sky_sun_check.dm, sky_weather_look.dm).

/datum/controller/master
	sleep_offline_after_initializations = FALSE

GLOBAL_VAR_INIT(skc_passed, 0)
GLOBAL_VAR_INIT(skc_failed, 0)

/proc/uc_log(text)
	text2file(text, "data/update_check.txt")

/proc/skc_check(name, condition, detail)
	if(condition)
		GLOB.skc_passed++
	else
		GLOB.skc_failed++
	uc_log("[condition ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " - [detail]"]")

/world/New()
	. = ..()
	spawn(0)
		sky_check_run()

/proc/sky_check_run()
	UNTIL(SSticker.initialized)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/deadline = world.time + 5 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	sky_check_sun()
	sky_check_layers()
	sky_check_events()
	sky_check_weather()
	sky_check_review_fixes()
	sky_check_2x_art()
	uc_log("[GLOB.skc_passed] passed, [GLOB.skc_failed] failed")
	uc_log("done")
	sleep(10)
	del(world)

/proc/sky_check_sun()
	skc_check("sun line set at startup", islist(SSparallax.turn_line) && abs(closer_angle_difference(sky_sun_bearing(), SSsun.azimuth)) <= 1,
		"line [json_encode(SSparallax.turn_line)], painted sun [round(sky_sun_bearing(), 0.01)], azimuth [SSsun.azimuth]")
	var/old_mod = SSsun.azimuth_mod
	for(var/mod in list(-2, -0.5, 0.5, 2))
		SSsun.azimuth_mod = mod
		SSsun.azimuth = 37
		SSparallax.sun_moved(world.time)
		var/worst = 0
		var/worst_hook = 0
		var/time = world.time
		for(var/fire in 1 to 30)
			SSsun.fire() // its hook lines the sky up at world.time
			worst_hook = max(worst_hook, abs(closer_angle_difference(sky_sun_bearing(world.time), SSsun.azimuth)))
			time += SSsun.wait // as if this fire came a minute after the last
			SSparallax.sun_moved(time)
			worst = max(worst, abs(closer_angle_difference(sky_sun_bearing(time), SSsun.azimuth)))
			var/halfway = SSsun.azimuth + mod * SSsun.base_rotation / 2 // half way to the next fire, the painted sun is between
			worst = max(worst, abs(closer_angle_difference(sky_sun_bearing(time + SSsun.wait / 2), halfway)))
		skc_check("speed [mod]: painted sun on the real sun over 30 fires", worst < 1, "worst [round(worst, 0.01)] degrees")
		skc_check("speed [mod]: complete_movement() hook lines the sky up", worst_hook < 1, "worst [round(worst_hook, 0.01)] degrees")
		var/list/plan = sky_turn_plan()
		skc_check("speed [mod]: turns the sun's way", SIGN(plan[1]) == SIGN(mod), "step [plan[1]] degrees")
		skc_check("speed [mod]: turn animation lasts 12 hours", plan[2] * plan[3] >= 12 HOURS, "[plan[3]] steps of [plan[2]] ds")
	SSsun.vv_edit_var(NAMEOF(SSsun, azimuth), 200)
	skc_check("an admin's azimuth edit moves the painted sun", abs(closer_angle_difference(sky_sun_bearing(), 200)) < 1, "painted sun [round(sky_sun_bearing(), 0.01)]")
	SSsun.azimuth_mod = old_mod
	SSsun.complete_movement()

/proc/sky_check_layers()
	var/list/layers = SSparallax.theme.build_layers()
	var/list/bad_holder = list()
	var/list/bad_depth = list()
	var/far = 0
	for(var/obj/screen/parallax_layer/L as anything in layers)
		var/name = replacetext("[L.type]", "/obj/screen/parallax_layer/", "")
		if(!L.holder || L.holder.held != L || !(L in L.holder.vis_contents) || L.holder.layer != L.layer)
			bad_holder += name
		if(istype(L, /obj/screen/parallax_layer/dust) || istype(L, /obj/screen/parallax_layer/random) || istype(L, /obj/screen/parallax_layer/flybys) || istype(L, /obj/screen/parallax_layer/near_weather))
			continue
		if(istype(L, /obj/screen/parallax_layer/body/planet))
			if(L.speed != SKY_DEPTH_PLANET)
				bad_depth += "[name] [L.speed]"
			continue
		far++
		if(L.speed != SKY_DEPTH_FAR)
			bad_depth += "[name] [L.speed]"
	skc_check("every layer sits in its own holder, at its layer", !length(bad_holder), "[length(layers)] layers; wrong: [jointext(bad_holder, ", ")]")
	skc_check("everything beyond the station slides at one depth, Lavaland at its own", far >= 4 && !length(bad_depth), "[far] far layers; wrong: [jointext(bad_depth, ", ")]")
	var/has_weather = FALSE
	for(var/obj/screen/parallax_layer/near_weather/W in layers)
		has_weather = TRUE
	skc_check("the theme builds a near weather layer", has_weather)
	var/obj/screen/parallax_layer/L = layers[1]
	L.slide_to(12, -7)
	var/matrix/M = L.holder.transform
	skc_check("slide_to() moves the holder, not the layer", M.c == 12 && M.f == -7 && !L.pixel_w && !L.pixel_z, "holder [M.c],[M.f], layer [L.pixel_w],[L.pixel_z]")
	var/obj/screen/parallax_home/home = new
	var/list/holders = list()
	for(var/obj/screen/parallax_layer/each as anything in layers)
		holders += each.holder
	home.vis_contents = holders
	skc_check("a home's held_layers() finds every layer", length(home.held_layers()) == length(layers))
	var/obj/screen/parallax_holder/H = L.holder
	home.vis_contents.Cut()
	QDEL_LIST(layers)
	skc_check("a deleted layer takes its holder", QDELETED(H))
	qdel(home)
	var/obj/screen/sky_art/band
	for(var/index in 1 to length(SSparallax.theme.nebula))
		var/list/cloud = SSparallax.theme.nebula[index]
		if(cloud[1] == "band")
			band = SSparallax.nebula_art(index)
	if(band)
		var/matrix/B = band.transform
		// tile_pieces(): its picture's middle on the layer's. The 2x band is 1920 art px in 480 px pieces at half size; the 1x
		// band was 960 in quarters at full size. Either way it covers one repeat, PARALLAX_TILE * SKY_NEBULA_SCALE game px
		var/piece = PARALLAX_TILE
		var/shift = (piece - band.sprite_size) / 2 * B.a
		var/repeat = band.sprite_size * B.a
		skc_check("the band is centred by its transform, not pixel offsets", B.c == shift && B.f == shift && repeat == PARALLAX_TILE * SKY_NEBULA_SCALE && !band.pixel_x && !band.pixel_y, "transform [B.a] scale, [B.c],[B.f] shift (want [shift]), repeat [repeat], pixel [band.pixel_x],[band.pixel_y]")
		// 2x sheet: 16 pieces at half size, one repeat each way round the middle one; 1x sheet: four quarters at full size, two
		// repeats each way as it always had (sky.dm nebula_art())
		var/two_x = sky_sheet_has(band.icon, "band_33")
		var/want_overlays = two_x ? 3 * 3 * 16 - 1 : 5 * 5 * 4 - 1
		skc_check("the band is drawn from its pieces at the sheet's scale", B.a == (two_x ? 0.5 : 1) && length(band.overlays) == want_overlays, "2x sheet [two_x], scale [B.a], [length(band.overlays)] overlays (want [want_overlays])")
	else
		skc_check("the band is centred by its transform, not pixel offsets", TRUE, "this theme ([SSparallax.theme.type]) has no band")

/proc/sky_check_events()
	SSparallax.flyby_art()
	SSparallax.event_until = 0
	var/kind
	var/rolls = 0
	for(rolls in 1 to 6) // some rolls leave no sky clear enough for a giant (sky.dm start_giant()): roll the sky again, as sky_shots.dm does
		kind = SSparallax.sky_event("giant")
		if(kind == "giant")
			break
		SSparallax.set_theme(new /datum/sky_theme/quiet)
	var/obj/screen/sky_art/piece/giant
	for(var/obj/screen/sky_art/piece/P in SSparallax.flyby.vis_contents)
		if(P.icon_state == "giant")
			giant = P
	skc_check("a giant goes up", kind == "giant" && giant, "sky_event: [kind], roll [rolls]")
	if(giant)
		var/icon/I = icon(giant.icon, giant.icon_state)
		skc_check("the giant's sheet is under the view (448 px) and it's placed by transform", I.Width() == 448 && !giant.pixel_x && !giant.pixel_y, "[I.Width()] px, pixel [giant.pixel_x],[giant.pixel_y]")
	for(var/obj/screen/sky_art/piece/P in SSparallax.flyby.vis_contents)
		qdel(P)
	SSparallax.event_until = 0
	kind = SSparallax.sky_event("aurora")
	skc_check("an ion storm puts its aurora on Lavaland", kind == "aurora" && SSparallax.aurora && (SSparallax.aurora in SSparallax.planet_art), "sky_event: [kind]")
	SSparallax.end_aurora()
	skc_check("its end takes the aurora off", !SSparallax.aurora && !length(SSparallax.planet_art))
	SSparallax.event_until = 0

/proc/sky_check_weather()
	var/z = SSmapping.station_start
	var/datum/weather/ash_storm/stray = new(list(z))
	stray.start() // never telegraphed: starts in its end stage, does nothing
	skc_check("an ash storm that never telegraphed draws nothing", !SSparallax.ash_art && !length(SSparallax.planet_art), "stage [stray.stage]")
	stray.end()
	qdel(stray)
	var/datum/weather/ash_storm/storm = new(list(z))
	storm.telegraph()
	storm.start()
	skc_check("an ash storm puts its veil and cyclone on Lavaland", length(SSparallax.ash_art) == 2 && length(SSparallax.planet_art) == 2, "planet art [length(SSparallax.planet_art)]")
	var/datum/weather/rad_storm/rads = new(list(z))
	rads.telegraph()
	rads.start()
	skc_check("a radiation storm shimmers over the sky", SSparallax.rad_art && (SSparallax.rad_art in SSparallax.near_weather?.vis_contents))
	var/datum/round_event/aurora_caelus/caelus = new(FALSE)
	SSevents.running -= caelus
	caelus.announce()
	skc_check("Aurora Caelus hangs three curtains over the sky", length(SSparallax.caelus_art) == 3 && length(SSparallax.near_weather?.vis_contents) == 4, "near weather pieces [length(SSparallax.near_weather?.vis_contents)]")
	storm.wind_down()
	storm.end()
	rads.wind_down()
	rads.end()
	caelus.end()
	skc_check("their ends start the fades", !SSparallax.ash_art && !SSparallax.rad_art && !SSparallax.caelus_art)
	sleep(SKY_WEATHER_FADE + 2 SECONDS)
	skc_check("after the fade the art is gone", !length(SSparallax.planet_art) && !length(SSparallax.near_weather?.vis_contents), "planet art [length(SSparallax.planet_art)], near weather [length(SSparallax.near_weather?.vis_contents)]")
	qdel(storm)
	qdel(rads)
	qdel(caelus)

/// The review fixes of 2026-11-27: a fast sun's capped turn, a False Alarm's and a killed aurora, two storms, a camera picture's sky
/proc/sky_check_review_fixes()
	// A fast sun (an admin's): the turn queues at most SKY_TURN_MAX_STEPS steps, and sun_moved() starts it again before they run out
	var/old_mod = SSsun.azimuth_mod
	SSsun.azimuth_mod = 200
	SSsun.complete_movement()
	var/list/plan = sky_turn_plan()
	skc_check("a fast sun's turn is capped", plan[3] == SKY_TURN_MAX_STEPS, "[plan[3]] steps of [plan[2]] ds")
	SSparallax.turn_armed_until = world.time + 1 // as if the steps were about to run out
	SSsun.complete_movement() // on the line still: only the re-arm can start it again
	skc_check("a fast sun's turn is started again before it runs out", SSparallax.turn_armed_until > world.time + SSsun.wait, "armed until [SSparallax.turn_armed_until], now [world.time]")
	SSsun.azimuth_mod = old_mod
	SSsun.complete_movement()

	// A False Alarm announces an aurora and kills it first: nothing would ever take the curtains down
	var/datum/round_event/aurora_caelus/fake = new(FALSE)
	SSevents.running -= fake
	fake.kill()
	fake.announce(TRUE)
	skc_check("a False Alarm's aurora puts nothing in the sky", !SSparallax.caelus_art)
	qdel(fake)
	var/datum/round_event/aurora_caelus/killed = new(FALSE)
	SSevents.running -= killed
	killed.announce()
	var/had = length(SSparallax.caelus_art)
	killed.kill()
	skc_check("an aurora killed early takes its curtains down", had == 3 && !SSparallax.caelus_art, "had [had]")
	qdel(killed)

	// Two ash storms: one that never began can't end the other's sky; deleting the one blowing ends it
	var/z = SSmapping.station_start
	var/datum/weather/ash_storm/first = new(list(z))
	first.telegraph()
	first.start()
	var/datum/weather/ash_storm/second = new(list(z))
	second.end()
	skc_check("a storm that never began leaves another's sky alone", length(SSparallax.ash_art) == 2, "ash art [length(SSparallax.ash_art)]")
	qdel(first)
	skc_check("deleting a storm mid-blow takes its sky off", !SSparallax.ash_art && !length(SSparallax.ash_storms))
	qdel(second)

	// A camera picture's sky: its Lavaland gets the storm art and loses it, keeps its turn to the sun, and the station's weather
	// hides off the station
	var/list/layers = SSparallax.theme.build_layers()
	var/obj/screen/parallax_layer/body/planet/P = locate() in layers
	var/obj/screen/parallax_layer/near_weather/W = locate() in layers
	var/obj/screen/sky_art/probe = new
	SSparallax.add_planet_art(probe)
	var/added = P && (probe in P.vis_contents)
	SSparallax.remove_planet_art(probe)
	skc_check("Lavaland art reaches a camera picture's Lavaland and leaves it", added && !(probe in P?.vis_contents))
	qdel(probe)
	var/obj/screen/parallax_home/home = new
	var/list/holders = list()
	for(var/obj/screen/parallax_layer/each as anything in layers)
		holders += each.holder
	home.vis_contents = holders
	SSparallax.view_homes += home
	var/turf/spot = locate(round(world.maxx / 2), round(world.maxy / 2), z)
	map_view_place_sky(home, spot, spot.x - 7, spot.y - 7)
	var/matrix/M = P.transform
	var/matrix/R = P.rest_transform()
	skc_check("a camera picture keeps Lavaland turned to the sun", P.angle && M.a == R.a && M.b == R.b && M.d == R.d && M.e == R.e, "angle [P.angle], transform [M.a],[M.b],[M.d],[M.e]")
	W.update_status(spot)
	var/shown = !W.invisibility
	var/turf/off
	for(var/other_z in 1 to world.maxz)
		if(!is_station_level(other_z))
			off = locate(1, 1, other_z)
			break
	if(off)
		W.update_status(off)
	skc_check("the station's weather shows on the station and not off it", shown && (!off || W.invisibility), "off the station: z [off?.z]")
	qdel(home)
	skc_check("a camera picture's sky goes with its home", !(home in SSparallax.view_homes) && QDELETED(P) && !(P in SSparallax.planet_layers))
	var/list/sun = SSparallax.body_places["sun"]
	SSparallax.body_places -= "sun"
	var/bearing = sky_sun_bearing()
	SSparallax.body_places["sun"] = sun
	skc_check("no sun painted: no bearing, and no runtime", isnull(bearing))

/// Stars, bodies and clouds drawn by shared art the layers carry (2026-11-27): from 2x pieces at their scale, or whole as before
/proc/sky_check_2x_art()
	var/list/layers = SSparallax.theme.build_layers()
	var/list/bad = list()
	var/checked = 0
	for(var/obj/screen/parallax_layer/L as anything in layers)
		L.set_quality(GRAPHICS_QUALITY_HIGH)
		// Each is drawn from 2x pieces ("<state>_00" and on) when its sheet has them, or whole as before: stars and bodies at
		// 1x, clouds at twice size (sky_has_pieces(); build_v2.py --scale)
		var/obj/screen/sky_art/art
		var/state
		var/pieces_scale
		var/whole_scale
		if(istype(L, /obj/screen/parallax_layer/stars))
			var/obj/screen/parallax_layer/stars/S = L
			state = S.art_state
			art = SSparallax.star_art(state, S.layer)
			pieces_scale = 0.5
			whole_scale = 1
		else if(istype(L, /obj/screen/parallax_layer/body) && !istype(L, /obj/screen/parallax_layer/body/deep))
			var/obj/screen/parallax_layer/body/B = L
			if(!B.art_state)
				continue
			state = B.art_state
			art = SSparallax.body_art(state, B.layer)
			pieces_scale = 0.5
			whole_scale = 1
		else if(istype(L, /obj/screen/parallax_layer/nebula))
			var/obj/screen/parallax_layer/nebula/N = L
			var/list/cloud = SSparallax.theme.nebula[N.index]
			if(cloud[1] == "band")
				continue
			state = cloud[1]
			art = SSparallax.nebula_art(N.index)
			pieces_scale = 1
			whole_scale = SKY_NEBULA_SCALE
		else
			continue
		var/from_pieces = sky_has_pieces(art.icon, state)
		var/want_scale = from_pieces ? pieces_scale : whole_scale
		checked++
		var/matrix/M = art.transform
		var/name = replacetext("[L.type]", "/obj/screen/parallax_layer/", "")
		if(!(art in L.vis_contents))
			bad += "[name]: art not carried"
		if(L.icon_state)
			bad += "[name]: the layer still draws its own [L.icon_state]"
		if(art.icon_state != (from_pieces ? "[state]_00" : state))
			bad += "[name]: draws [art.icon_state] (pieces [from_pieces])"
		if(abs(M.a - want_scale) > 0.001)
			bad += "[name]: scale [M.a], want [want_scale]"
		if(art.appearance_flags & (PIXEL_SCALE | RESET_TRANSFORM))
			bad += "[name]: art flags [art.appearance_flags]"
	skc_check("stars, bodies and clouds are drawn by shared art at their sheet's scale", checked >= 6 && !length(bad), "[checked] layers; [jointext(bad, "; ")]")
	var/obj/screen/parallax_layer/body/sun/sun = locate() in layers
	if(sun)
		var/obj/screen/sky_art/sun_art = SSparallax.body_art(sun.art_state, sun.layer)
		skc_check("the sun's art takes its layer's tint", sun.color && !(sun_art.appearance_flags & RESET_COLOR) && sun_art.blend_mode == BLEND_DEFAULT, "layer colour [sun.color], art flags [sun_art.appearance_flags], blend [sun_art.blend_mode]")
	QDEL_LIST(layers)
