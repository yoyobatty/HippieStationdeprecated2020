// Mech facing armour self-test: a mech is hit from each of the eight sides, by an item and by a fired bullet, in the real
// engine, headless, and what it took is checked against the side it was hit from.
//
// Run:      tools/facing_check/run.sh   (builds its own copy, so hippiestation.dmb is left alone)
// Results:  data/facing_check/results.txt, one PASS/FAIL line per hit.
//
// Front (dead ahead or 45 degrees off) takes damage / 1.5, back (dead behind) / 0.5, the sides as it is. Bullets fly for
// real through SSprojectiles: one straight in from each side and two at an angle that isn't a straight line.

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("facing-check" in world.params)
		sleep_offline_after_initializations = FALSE //nobody connects to this, so the world has to keep ticking
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_facing_check))
	return ..()

#define FACING_CHECK_DIR "data/facing_check/"

/proc/run_facing_check()
	sleep(5 SECONDS)
	fdel(FACING_CHECK_DIR)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/round_deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < round_deadline)
		sleep(1 SECONDS)
	var/datum/facing_check/test = new
	test.run_all()
	text2file(jointext(test.lines, "\n"), "[FACING_CHECK_DIR]results.txt")
	log_world("FACING CHECK: done, [test.passed] passed, [test.failed] failed")
	Master.Shutdown()
	qdel(world)

/datum/facing_check
	var/list/lines = list()
	var/passed = 0
	var/failed = 0
	var/turf/centre
	var/obj/mecha/working/ripley/mech
	var/mob/living/carbon/human/attacker
	var/obj/item/weapon

/datum/facing_check/proc/check(name, condition, detail)
	if(condition)
		passed++
	else
		failed++
	lines += "[condition ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " - [detail]"]"

/// What the mech's facing should do to a hit that came from `from` (the way from the mech to whoever hit it)
/datum/facing_check/proc/expected_modifier(facing, from)
	var/relative = abs(dir2angle(facing) - dir2angle(from))
	if(relative > 180)
		relative = 360 - relative
	switch(relative)
		if(0, 45)
			return mech.facing_modifiers[FRONT_ARMOUR]
		if(180)
			return mech.facing_modifiers[BACK_ARMOUR]
	return mech.facing_modifiers[SIDE_ARMOUR]

/datum/facing_check/proc/side_name(modifier)
	if(modifier == mech.facing_modifiers[FRONT_ARMOUR])
		return "front"
	if(modifier == mech.facing_modifiers[BACK_ARMOUR])
		return "back"
	return "side"

/datum/facing_check/proc/run_all()
	var/datum/turf_reservation/reservation = SSmapping.RequestBlockReservation(15, 15)
	centre = locate(reservation.bottom_left_coords[1] + 7, reservation.bottom_left_coords[2] + 7, reservation.bottom_left_coords[3])
	mech = new(centre)
	mech.deflect_chance = 0
	mech.max_integrity = 100000
	mech.obj_integrity = 100000
	attacker = new(centre)
	weapon = new /obj/item/kitchen/knife(attacker)
	weapon.force = 30
	weapon.damtype = BRUTE

	// What a hit does with no side at all, after armour
	var/before = mech.obj_integrity
	mech.take_damage(30, BRUTE, "melee", 0, 0)
	var/melee_base = before - mech.obj_integrity
	before = mech.obj_integrity
	mech.take_damage(30, BRUTE, "bullet", 0, 0)
	var/bullet_base = before - mech.obj_integrity
	lines += "     no side: melee [melee_base], bullet [bullet_base]"

	for(var/facing in list(NORTH, EAST))
		mech.setDir(facing)
		for(var/from in GLOB.alldirs)
			attacker.forceMove(get_step(centre, from))
			before = mech.obj_integrity
			mech.attacked_by(weapon, attacker)
			var/taken = before - mech.obj_integrity
			var/modifier = expected_modifier(facing, from)
			var/want = round(melee_base / modifier, DAMAGE_PRECISION)
			check("melee, facing [dir2text(facing)], hit from [dir2text(from)] ([side_name(modifier)])", abs(taken - want) < 0.2, "took [taken], want [want]")

	attacker.forceMove(locate(1, 1, centre.z)) // out of the bullets' way
	for(var/facing in list(NORTH, EAST))
		mech.setDir(facing)
		for(var/from in GLOB.alldirs)
			var/turf/shooter = get_ranged_target_turf(centre, from, 4)
			fire_at_mech(shooter, facing, from, bullet_base, "from [dir2text(from)]")
		// at an angle: four up and one across, four across and one down
		fire_at_mech(locate(centre.x + 1, centre.y + 4, centre.z), facing, NORTH, bullet_base, "from 1 east, 4 north")
		fire_at_mech(locate(centre.x - 4, centre.y - 1, centre.z), facing, WEST, bullet_base, "from 4 west, 1 south")

/datum/facing_check/proc/fire_at_mech(turf/shooter, facing, from, bullet_base, where)
	mech.setDir(facing)
	var/obj/item/projectile/bullet/P = new(shooter)
	P.damage = 30
	P.damage_type = BRUTE
	P.flag = "bullet"
	P.armour_penetration = 0
	P.preparePixelProjectile(centre, shooter)
	var/before = mech.obj_integrity
	P.fire()
	var/deadline = world.time + 3 SECONDS
	while(!QDELETED(P) && mech.obj_integrity == before && world.time < deadline)
		sleep(1)
	var/taken = before - mech.obj_integrity
	var/modifier = expected_modifier(facing, from)
	var/want = round(bullet_base / modifier, DAMAGE_PRECISION)
	check("bullet, facing [dir2text(facing)], [where] ([side_name(modifier)])", abs(taken - want) < 0.2, "took [taken], want [want]")
	if(!QDELETED(P))
		qdel(P)
	mech.setDir(facing)

#undef FACING_CHECK_DIR
