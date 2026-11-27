// Fishing (hippiestation/code/modules/fishing/), headless: the tables, a cast played out (the wait, a missed bite, a salmon
// played well, a shark that snaps the line), what a rod refuses, lava and deep lava, the exosuit rod on a firefighter Ripley,
// cleaning a fish, a trophy plaque, the tackle box and where the gear comes from. Not part of the game:
// HARNESS=fishing_check.dm EXTRA_PARAMS=bot-map=testbench tools/power_check/run.sh <label>

/datum/controller/master
	sleep_offline_after_initializations = FALSE

GLOBAL_VAR_INIT(fc_passed, 0)
GLOBAL_VAR_INIT(fc_failed, 0)

/proc/uc_log(text)
	text2file(text, "data/update_check.txt")

/proc/fc_check(name, condition, detail)
	if(condition)
		GLOB.fc_passed++
	else
		GLOB.fc_failed++
	uc_log("[condition ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " - [detail]"]")

/world/New()
	. = ..()
	spawn(0)
		fishing_check_run()

/proc/fishing_check_run()
	UNTIL(SSticker.initialized)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/deadline = world.time + 5 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	fishing_check_tables()
	fishing_check_world()
	uc_log("[GLOB.fc_passed] passed, [GLOB.fc_failed] failed")
	uc_log("done")
	sleep(10)
	del(world)

/proc/fishing_check_tables()
	var/list/bait_kinds = list(FISHING_BAIT_MEAT, FISHING_BAIT_CHEESE, FISHING_BAIT_PLANT, FISHING_BAIT_LIVE, FISHING_BAIT_GLOW, FISHING_BAIT_SHINY)
	var/bad = list()
	for(var/datum/fishing_spot/spot as anything in GLOB.fishing_spots)
		for(var/catch_type in spot.catches)
			if(!GLOB.fishing_catches[catch_type] || spot.catches[catch_type] < 1)
				bad += "[spot.type] [catch_type]"
	fc_check("every spot lists only catches that exist, each with a chance", !length(bad), jointext(bad, ", "))
	bad = list()
	for(var/catch_type in GLOB.fishing_catches)
		var/datum/fishing_catch/entry = GLOB.fishing_catches[catch_type]
		if(!ispath(entry.catch_type, /atom/movable) || entry.max_length < entry.min_length)
			bad += "[catch_type]"
		for(var/bait_kind in entry.bait_likes)
			if(!(bait_kind in bait_kinds))
				bad += "[catch_type] likes [bait_kind]"
	fc_check("every catch lands something real, with sane lengths and baits", !length(bad), jointext(bad, ", "))
	fc_check("[length(GLOB.fishing_catches)] catches and [length(GLOB.fishing_spots)] spots", length(GLOB.fishing_catches) > 40 && length(GLOB.fishing_spots) == 8)
	var/list/sprites = icon_states(FISHING_ICON) | icon_states('hippiestation/icons/obj/fish_items.dmi')
	bad = list()
	for(var/path in typesof(/obj/item/fish))
		var/obj/item/fish/F = path
		if(!(initial(F.icon_state) in sprites))
			bad += "[path]"
	fc_check("every fish has a sprite", !length(bad), jointext(bad, ", "))

/proc/fishing_check_world()
	var/datum/turf_reservation/res = SSmapping.RequestBlockReservation(20, 14)
	var/x0 = res.bottom_left_coords[1] + 2
	var/y0 = res.bottom_left_coords[2] + 2
	var/z = res.bottom_left_coords[3]
	var/area/bot_gym/A = new
	for(var/turf/T in block(locate(x0 - 1, y0 - 1, z), locate(x0 + 16, y0 + 10, z)))
		var/area/old_area = T.loc
		old_area.contents -= T
		A.contents += T
		T.change_area(old_area, A)
		T.ChangeTurf(/turf/open/floor/plasteel)
	var/mob/living/carbon/human/H = new(locate(x0 + 2, y0 + 2, z))
	H.real_name = "Test Angler"
	H.name = H.real_name
	H.status_flags |= GODMODE
	var/turf/water = locate(x0 + 4, y0 + 2, z)
	water.ChangeTurf(/turf/open/water)
	var/obj/item/fishing_rod/rod = new(H)
	H.put_in_hands(rod)

	// Casting and reeling in before anything bites
	rod.use_on(water, H)
	fc_check("a rod cast at water starts a cast", !!rod.session, "spot [get_fishing_spot(water)?.type]")
	rod.use_on(water, H)
	fc_check("clicking again with nothing on the hook reels in", !rod.session)

	// Missing the bite goes back to waiting
	rod.use_on(water, H)
	var/datum/fishing_session/session = rod.session
	session.bite()
	fc_check("a bite takes the hook", session.state == FISHING_BITE)
	session.miss_bite()
	fc_check("a missed bite goes back to waiting", session.state == FISHING_WAITING)

	// A salmon played well: wind while it rests, let go while it runs
	session.bite()
	session.hooked = GLOB.fishing_catches[/datum/fishing_catch/salmon]
	session.length_cm = 70
	session.start_fight()
	for(var/i in 1 to 2000)
		if(QDELETED(session))
			break
		session.reeling = (session.fish_state == FISHING_FISH_RESTING || session.fish_state == FISHING_FISH_WORN_OUT)
		session.process(2)
	fc_check("a well played salmon comes in", QDELETED(session))
	var/obj/item/fish/salmon/salmon = locate() in H.held_items
	fc_check("and ends up in the angler's free hand", istype(salmon))
	var/datum/component/caught_fish/info = salmon?.GetComponent(/datum/component/caught_fish)
	fc_check("keeping its length and who caught it", info?.length_cm == 70 && info?.angler == "Test Angler", "[info?.length_cm] cm, [info?.angler]")
	var/datum/fishing_record/record = GLOB.fishing_records["salmon"]
	fc_check("and it makes the record board", record?.length_cm == 70 && record?.angler == "Test Angler")

	// Winding against a shark the whole way snaps the line and loses the hook
	H.dropItemToGround(salmon)
	rod.use_on(water, H)
	session = rod.session
	session.bite()
	session.hooked = GLOB.fishing_catches[/datum/fishing_catch/shark]
	session.length_cm = 300
	session.start_fight()
	for(var/i in 1 to 2000)
		if(QDELETED(session))
			break
		session.reeling = TRUE
		session.process(2)
	fc_check("winding against a shark the whole way snaps the line", QDELETED(session) && !rod.hook)

	// No hook, no cast
	rod.use_on(water, H)
	fc_check("a rod without a hook isn't cast", !rod.session)
	var/obj/item/fishing_hook/new_hook = new(H.loc)
	rod.attackby(new_hook, H)
	fc_check("a hook fits back on", rod.hook == new_hook && new_hook.loc == rod)
	var/obj/item/reagent_containers/food/snacks/meat/slab/bait = new(H.loc)
	rod.attackby(bait, H)
	fc_check("meat goes on as bait", rod.bait == bait && rod.get_bait_kind() == FISHING_BAIT_MEAT)

	// A plain line can't go in lava, a sinew one can
	water.ChangeTurf(/turf/open/lava)
	rod.use_on(water, H)
	fc_check("a plain line isn't cast into lava", !rod.session)
	var/obj/item/fishing_line/sinew/sinew = new(H.loc)
	rod.attackby(sinew, H)
	rod.use_on(water, H)
	fc_check("a sinew line is", !!rod.session)
	H.dropItemToGround(rod)
	fc_check("dropping the rod ends the cast", !rod.session)

	// Deep lava: lava two tiles all round, for an exosuit's steel line only
	var/turf/corner = locate(x0 + 8, y0 + 2, z)
	for(var/turf/T in block(corner, locate(x0 + 12, y0 + 6, z)))
		T.ChangeTurf(/turf/open/lava)
	var/turf/deep = locate(x0 + 10, y0 + 4, z)
	fc_check("lava with lava two tiles all round is deep lava", get_fishing_spot(deep)?.type == /datum/fishing_spot/deep_lava)
	fc_check("the corner of a lava lake isn't", get_fishing_spot(corner)?.type == /datum/fishing_spot/lava)
	var/datum/fishing_spot/deep_spot = get_fishing_spot(deep)
	fc_check("a sinew line can't fish deep lava", !!deep_spot.why_not(deep, rod))
	var/obj/item/mecha_parts/mecha_equipment/fishing_rod/mount = new(locate(x0 + 6, y0 + 4, z))
	fc_check("an exosuit's steel line can", !deep_spot.why_not(deep, mount.rod))
	var/obj/mecha/working/ripley/firefighter/ripley = new(locate(x0 + 7, y0 + 4, z))
	fc_check("the exosuit rod fits a firefighter Ripley", mount.can_attach(ripley))
	mount.attach(ripley)
	fc_check("and its line comes out of the exosuit", mount.rod.angler_body(null) == ripley)
	var/datum/fishing_catch/leviathan = GLOB.fishing_catches[/datum/fishing_catch/lava_leviathan]
	fc_check("deep lava has the leviathan in it", deep_spot.catches[/datum/fishing_catch/lava_leviathan] && leviathan)

	// The lurker that comes up after anglers
	var/mob/living/simple_animal/hostile/asteroid/magma_lurker/lurker = new(locate(x0 + 14, y0 + 8, z))
	fc_check("a magma lurker climbs out", !QDELETED(lurker) && lurker.health == 110)
	qdel(lurker)

	// Cleaning a fish
	var/obj/item/fish/wild/magma_eel/eel = new(H.loc)
	var/obj/item/kitchen/knife/knife = new(H.loc)
	H.put_in_hands(knife)
	var/turf/eel_turf = get_turf(eel)
	eel.attackby(knife, H)
	var/fillets = 0
	for(var/obj/item/reagent_containers/food/snacks/fish_fillet/magma/F in eel_turf)
		fillets++
	fc_check("a knife cleans a magma eel into two fillets", QDELETED(eel) && fillets == 2, "[fillets] fillets")

	// A trophy plaque
	var/obj/item/wallframe/fish_plaque/plaque = new(H.loc)
	plaque.attackby(salmon, H)
	fc_check("a caught fish goes on a trophy plaque", plaque.mounted_fish == salmon && findtext(plaque.desc, "70 cm"), plaque.desc)

	// Where fishing won't work
	var/turf/open/pool/pool = locate(x0 + 4, y0 + 6, z)
	pool.ChangeTurf(/turf/open/pool)
	pool = locate(x0 + 4, y0 + 6, z)
	fc_check("the pool is a fishing spot", get_fishing_spot(pool)?.type == /datum/fishing_spot/pool)
	pool.filled = FALSE
	fc_check("a drained pool can't be fished", !!get_fishing_spot(pool).why_not(pool, rod))
	var/obj/structure/toilet/toilet = new(locate(x0 + 2, y0 + 6, z))
	toilet.open = FALSE
	fc_check("a toilet with its lid down can't be fished", !!get_fishing_spot(toilet)?.why_not(toilet, rod))
	var/obj/item/fishing_rod/telescopic/telescopic = new(H.loc)
	fc_check("a folded telescopic rod won't cast", !telescopic.can_cast(H))
	telescopic.attack_self(H)
	fc_check("pulled out, it will", telescopic.extended && telescopic.can_cast(H) && telescopic.w_class == WEIGHT_CLASS_BULKY)

	// The gear
	var/obj/item/storage/fishing_tackle/full/box = new(H.loc)
	fc_check("the full tackle box has its 7 pieces", length(box.contents) == 7, "[length(box.contents)]")
	var/datum/techweb_node/mech_tools = SSresearch.techweb_node_by_id("mech_tools")
	fc_check("the exosuit rod is in Basic Exosuit Equipment", mech_tools?.design_ids["mech_fishing_rod"])
	var/datum/supply_pack/pack = SSshuttle.supply_packs[/datum/supply_pack/misc/fishing]
	fc_check("cargo sells the fishing crate", !!pack, pack?.name)
