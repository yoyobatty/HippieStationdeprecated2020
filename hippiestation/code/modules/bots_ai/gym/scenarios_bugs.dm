// Player-reported bugs (the upstream issue numbers are in the names). None of this has anything to do with the bots: the gym's
// just the quickest way to stand something up in a running round and see what it does.

/datum/bot_scenario/griefed/bug
	layout = list(
		"#########",
		"#.......#",
		"#..BC...#",
		"#.......#",
		"#########")
	time_limit = 10 SECONDS
	/// BOT_GYM_PASS or BOT_GYM_FAIL, from grief().
	var/verdict

/datum/bot_scenario/griefed/bug/check()
	return isnull(verdict) ? BOT_GYM_PENDING : verdict

/datum/bot_scenario/griefed/bug/proc/expect(result, what)
	log_line("[what]: [result ? "yes" : "no"]")
	verdict = result ? BOT_GYM_PASS : BOT_GYM_FAIL

/// Every mask there is, on somebody, and whether what it draws is a state its icon file has. It didn't reproduce: this keeps it that way.
/datum/bot_scenario/griefed/bug/masks
	griefer_job = "Assistant"
	name = "bug 12729: masks show up on the wearer"

/datum/bot_scenario/griefed/bug/masks/grief()
	griefer.dropItemToGround(griefer.wear_mask)
	var/shown = 0
	var/list/missing = list()
	for(var/path in subtypesof(/obj/item/clothing/mask))
		var/obj/item/clothing/mask/M = new path(griefer.loc)
		if(!griefer.equip_to_slot_if_possible(M, ITEM_SLOT_MASK, FALSE, TRUE, TRUE))
			qdel(M)
			continue
		var/mutable_appearance/drawn = griefer.overlays_standing[FACEMASK_LAYER]
		if(!drawn)
			missing += "[path] drew nothing"
		else if(!(drawn.icon_state in icon_states(drawn.icon)))
			missing += "[path] wants [drawn.icon_state] in [drawn.icon]"
		else
			shown++
		griefer.dropItemToGround(M, TRUE)
		qdel(M)
	log_line("[shown] drawn, [length(missing)] not")
	for(var/line in missing)
		log_line(line)
	expect(shown >= 100, "all but the ones that are never worn: abstract parents, a dwarf's, a cyborg's")

/datum/bot_scenario/griefed/bug/bluespace_floor
	name = "bug 12221: walking onto bluespace dust floor doesn't teleport you round and round until the server dies"

/datum/bot_scenario/griefed/bug/bluespace_floor/grief()
	var/turf/middle = get_step(griefer, EAST)
	for(var/turf/open/floor/T in RANGE_TURFS(2, middle))
		var/turf/open/floor/mineral/reagent/R = T.ChangeTurf(/turf/open/floor/mineral/reagent)
		R.reagent_type = new /datum/reagent/bluespace
	griefer.forceMove(middle)
	expect(!QDELETED(griefer), "came through it")

/datum/bot_scenario/griefed/bug/nan
	name = "bug 11324: one reagent gone NaN doesn't take the whole mob's reagents with it"

/datum/bot_scenario/griefed/bug/nan/grief()
	griefer.reagents.add_reagent(/datum/reagent/water, 10)
	griefer.reagents.add_reagent(/datum/reagent/consumable/sugar, 10)
	var/datum/reagent/R = griefer.reagents.reagent_list[1]
	var/huge = 1e30 * 1e30
	R.volume = huge - huge
	griefer.reagents.update_total()
	expect(griefer.reagents.total_volume == 10, "the other one still counts: [griefer.reagents.total_volume], [length(griefer.reagents.reagent_list)] reagents, nan [R.volume]")

/datum/bot_scenario/griefed/bug/chem_master
	name = "bug 11858: both reagents called Translucent mixture come out of the Chem Master"

/datum/bot_scenario/griefed/bug/chem_master/grief()
	var/obj/machinery/chem_master/M = new(get_step(griefer, EAST))
	var/obj/item/reagent_containers/glass/beaker/large/B = new(M)
	M.beaker = B
	B.reagents.add_reagent(/datum/reagent/impvolt, 5)
	B.reagents.add_reagent(/datum/reagent/toxin/sarin_a, 5)
	var/list/shown = M.ui_data(griefer)["beakerContents"]
	var/datum/tgui/dept_gear_test_stub/window = new
	for(var/list/line as anything in shown)
		M.ui_act("transfer", list("id" = line["id"], "amount" = "5", "to" = "buffer"), window)
	expect(M.reagents.total_volume == 10 && !B.reagents.total_volume, "both went across, [M.reagents.total_volume] in the buffer")

/datum/bot_scenario/griefed/bug/abductor
	griefer_job = "Abductor Scientist"
	name = "bug 12034: an abductor scientist can read a gland"

/datum/bot_scenario/griefed/bug/abductor/grief()
	var/obj/item/organ/heart/gland/G = new /obj/item/organ/heart/gland/heals(griefer.loc)
	var/untrained = length(G.examine(griefer))
	griefer.mind.add_antag_datum(/datum/antagonist/abductor/scientist/gym)
	expect(length(G.examine(griefer)) > untrained, "learned something from it")

/// A scientist with none of the setup: no team, no ship to go to.
/datum/antagonist/abductor/scientist/gym/on_gain()
	ADD_TRAIT(owner, TRAIT_ABDUCTOR_SCIENTIST_TRAINING, ABDUCTOR_ANTAGONIST)

/datum/antagonist/abductor/scientist/gym/on_removal()
	REMOVE_TRAIT(owner, TRAIT_ABDUCTOR_SCIENTIST_TRAINING, ABDUCTOR_ANTAGONIST)

/datum/bot_scenario/griefed/bug/contract
	name = "bug 8763: an unused apprentice contract refunds what it cost"

/datum/bot_scenario/griefed/bug/contract/grief()
	var/obj/item/spellbook/book = new(griefer.loc)
	var/obj/item/antag_spawner/contract/C = new(griefer.loc)
	griefer.put_in_active_hand(C)
	book.uses = 0
	var/cost = 0
	for(var/datum/spellbook_entry/item/contract/entry in book.entries)
		cost = entry.cost
	book.attackby(C, griefer)
	expect(cost && book.uses == cost, "got back the [cost] it cost, has [book.uses]")

/datum/bot_scenario/griefed/bug/nanite_defib
	griefer_job = "Assistant"
	name = "bug 12026: nanite defibrillation brings back somebody damage killed"
	time_limit = 20 SECONDS

/datum/bot_scenario/griefed/bug/nanite_defib/grief()
	griefer.AddComponent(/datum/component/nanites, 200)
	var/datum/component/nanites/N = griefer.GetComponent(/datum/component/nanites)
	var/datum/nanite_program/defib/P = new
	N.add_program(null, P)
	griefer.apply_damage(120, BRUTE, BODY_ZONE_CHEST)
	griefer.adjustOxyLoss(100)
	griefer.updatehealth()
	griefer.death()
	log_line("dead at health [griefer.health], stat [griefer.stat]")
	P.on_trigger()

/datum/bot_scenario/griefed/bug/nanite_defib/check()
	if(griefer.stat != DEAD && griefer.timeofdeath)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/griefed/bug/cane_gun
	griefer_job = "Assistant"
	griefer_name = "Pimp"
	name = "bug 12819: the cane gun runs out"
	var/obj/item/gun/ballistic/shotgun/canegun/cane

/datum/bot_scenario/griefed/bug/cane_gun/grief()
	cane = new(griefer.loc)
	griefer.put_in_active_hand(cane)
	QDEL_LIST(cane.magazine.stored_ammo)
	if(cane.chambered)
		QDEL_NULL(cane.chambered)
	var/obj/item/ammo_casing/shotgun/beanbag/shell = new(cane.magazine)
	cane.magazine.stored_ammo += shell
	cane.chamber_round()
	var/turf/wall = locate(griefer.x, griefer.y + 2, griefer.z)
	for(var/i in 1 to 3)
		log_line("shot [i]: chambered [cane.chambered], left in it [cane.magazine.ammo_count()]")
		if(cane.can_shoot())
			cane.process_fire(wall, griefer, FALSE)
	log_line("after: chambered [cane.chambered], live [cane.chambered?.BB], left in it [cane.magazine.ammo_count()], can shoot [cane.can_shoot()]")
	expect(!cane.chambered?.BB, "nothing left to fire")

/// From a played round: a dead officer kept taking Security's calls and saying so into deadchat, for 17 minutes. Alive it has to take the call, or this proves nothing.
/datum/bot_scenario/griefed/bug/dead_officer
	name = "bug: a dead officer takes no calls and starts no goals"
	job = "Security Officer"
	griefer_job = "Assistant"

/datum/bot_scenario/griefed/bug/dead_officer/grief()
	brain.on_heard_security_call(griefer, "Security! Help!", FREQ_COMMON)
	if(!istype(brain.current_goal, /datum/bot_goal/respond_to_call))
		expect(FALSE, "alive, it took the call")
		return
	log_line("alive, it took the call: yes")
	brain.drop_goals("gym")
	brain.state = BOT_STATE_WANDER
	brain.next_security_call_time = 0
	bot.death()
	brain.on_heard_security_call(griefer, "Security! Help!", FREQ_COMMON)
	var/took_call = !!brain.current_goal
	log_line("dead, it took the call: [took_call ? "yes" : "no"]")
	expect(!took_call && !brain.assign_goal(new /datum/bot_goal/clean_contamination()), "dead, nothing gets assigned")

/// round-10.32.13: a doctor radioed "Science, could you upgrade the machines in Medbay Treatment Center? Better parts would help." and all
/// five officers said they were responding to it. Each line is heard on Common by an idle officer; which it answers is what's checked.
/datum/bot_scenario/griefed/bug/not_for_security
	name = "security: calls to another trade and everyday \"help\" aren't Security's"
	job = "Security Officer"
	griefer_job = "Assistant"
	griefer_name = "Ca Ller"

/datum/bot_scenario/griefed/bug/not_for_security/grief()
	var/list/lines = list(
		"Science, could you upgrade the machines in Medbay Treatment Center? Better parts would help." = FALSE,
		"Mining, R&D is out of silver. Anything you can bring up would help." = FALSE,
		"Fresh pizza on the kitchen counter, help yourselves." = FALSE,
		"I'll come help." = FALSE,
		"Can I help you?" = FALSE,
		"doctor, I need help" = FALSE,
		"Help! Security!" = TRUE,
		"Somebody help me, I'm being attacked!" = TRUE,
		"Help! Ash is trying to kill me!" = TRUE,
		"HELP SEC" = TRUE,
		"help maint" = TRUE,
		"pls help in the bar" = TRUE,
		"medic, help! someone's attacking me in the bar" = TRUE,
		"sec to medbay" = TRUE,
		// round-20.48.49: the Captain asking the AI for the Brig's doors brought three officers
		"AI unbolt all security" = FALSE,
		"Unbolt security" = FALSE,
		"AI open the security door" = FALSE,
		"security help" = TRUE,
		"AI, call security, they're shooting at me" = TRUE)
	var/wrong = 0
	for(var/line in lines)
		brain.drop_goals("gym")
		brain.state = BOT_STATE_WANDER
		brain.next_security_call_time = 0
		brain.on_heard_security_call(griefer, line, FREQ_COMMON)
		var/took = istype(brain.current_goal, /datum/bot_goal/respond_to_call)
		if(took != lines[line])
			wrong++
		log_line("\"[line]\": [took ? "answered" : "let be"][took != lines[line] ? " (WRONG)" : ""]")
	brain.drop_goals("gym")
	brain.state = BOT_STATE_WANDER
	expect(!wrong, "every line answered or let be as it should be")

/// round-13.09.35: the Warden confiscated an energy sword, set it down two seconds later to take a crowbar it passed, and went off on a
/// call. The Captain picked it up off the floor.
/datum/bot_scenario/griefed/bug/sword_kept
	name = "items: a weapon in hand isn't put on the floor to free a hand"
	desc = "Both hands full, an energy sword in the other one, and nowhere to put it away. Making room for something it passes, the bot keeps the sword in hand. It used to set it down and walk off."

/datum/bot_scenario/griefed/bug/sword_kept/grief()
	for(var/obj/item/storage/S in list(bot.get_item_by_slot(ITEM_SLOT_BACK), bot.get_item_by_slot(ITEM_SLOT_BELT)))
		bot.dropItemToGround(S, TRUE)
		qdel(S)
	// Belt and pockets taken by things that aren't bags, as an officer's are: nowhere to wear it either
	bot.equip_to_slot_or_del(new /obj/item/wrench(bot), ITEM_SLOT_BELT)
	bot.equip_to_slot_or_del(new /obj/item/pen(bot), ITEM_SLOT_LPOCKET)
	bot.equip_to_slot_or_del(new /obj/item/pen(bot), ITEM_SLOT_RPOCKET)
	var/obj/item/sword = new /obj/item/melee/transforming/energy/sword/saber(bot.loc)
	var/obj/item/pen = new /obj/item/pen(bot.loc)
	bot.put_in_active_hand(pen)
	bot.put_in_inactive_hand(sword)
	log_line("holding [english_list(bot.held_items)]: active [bot.get_active_held_item()], inactive [bot.get_inactive_held_item()]; back [bot.get_item_by_slot(ITEM_SLOT_BACK)], belt [bot.get_item_by_slot(ITEM_SLOT_BELT)], dex [bot.get_item_by_slot(ITEM_SLOT_DEX_STORAGE)]")
	brain.make_room_for_item(FALSE)
	log_line("the sword's in [sword.loc] ([sword.loc?.type]), held: [(sword in bot.held_items) ? "yes" : "no"]")
	expect(!isturf(sword.loc), "the sword's not on the floor")

/// round-13.09.35: the Captain stammered in a cell for minutes after one baton hit. The baton's stutter was its stunforce in Life ticks
/// (100, over three minutes); tg main gives 40 s.
/datum/bot_scenario/griefed/bug/baton_stutter
	name = "bug: a stun baton leaves 40 s of stutter, not minutes"
	desc = "Somebody's hit with a loaded stun baton. They stutter for at most 20 Life ticks (40 s, tg main's), not the baton's stunforce of 100."

/datum/bot_scenario/griefed/bug/baton_stutter/grief()
	var/obj/item/melee/baton/loaded/B = griefer_holds(/obj/item/melee/baton/loaded)
	B.status = TRUE
	B.baton_stun(bot, griefer)
	log_line("stuttering [bot.stuttering]")
	expect(bot.stuttering > 0 && bot.stuttering <= 20, "stutters, 20 ticks at most")

/// round-13.09.35: a scientist bot said "[capitalize(M.name)] should run better now" about the DNA scanner, "\improper DNA scanner", and
/// it came out as a broken symbol and "NA scanner".
/datum/bot_scenario/griefed/bug/capitalize_improper
	name = "bug: capitalize() on a name starting \\improper gives the name"
	desc = "capitalize(\"\\improper DNA scanner\") is \"DNA scanner\", and \"\\proper Poly\" is \"Poly\"."

/datum/bot_scenario/griefed/bug/capitalize_improper/grief()
	var/a = capitalize("\improper DNA scanner")
	var/b = capitalize("\proper poly")
	log_line("got \"[url_encode(a)]\" and \"[url_encode(b)]\"")
	expect(a == "DNA scanner" && b == "Poly", "both read right")

/// The AI's own procs, with no AI: the gym can't have one (it would answer every arena's door requests), so this is the AI's datum with
/// no body and no think loop. A scenario calls what heard() would, and reads back what it would have said.
/datum/bot_silicon/ai/gym_probe
	var/list/replies = list()

/datum/bot_silicon/ai/gym_probe/New()
	return //no body to drive, no loop, nothing heard

/datum/bot_silicon/ai/gym_probe/reply(line)
	replies += line

/// round-20.48.49: the Captain, kill on sight for murder with twenty dead, asked "AI where is emery" and the AI told him Emery was in the
/// Brig. Asked by somebody clean it says where; asked by the killer it doesn't.
/datum/bot_scenario/griefed/bug/ai_whereabouts_killer
	name = "AI: won't tell somebody wanted for murder where people are"
	griefer_job = "Captain"
	griefer_name = "Mika Killcap"

/datum/bot_scenario/griefed/bug/ai_whereabouts_killer/grief()
	bot.real_name = "Emery Whereabouts" //nobody in any other arena answers to it
	bot.name = bot.real_name
	var/obj/item/clothing/under/U = bot.w_uniform
	if(!istype(U))
		U = new /obj/item/clothing/under/color/grey(bot)
		bot.equip_to_slot_or_del(U, ITEM_SLOT_ICLOTHING)
	U.sensor_mode = SENSOR_COORDS
	var/datum/bot_silicon/ai/gym_probe/P = new
	var/ask = "ai where is emery whereabouts"
	var/clean = P.whereabouts(griefer, ask)
	log_line("asked clean: \"[clean]\"")
	var/datum/bot_wanted/W = new
	W.crime = "Murder"
	W.severity = BOT_CRIME_MURDER
	W.time_reported = world.time
	var/datum/weakref/ref = WEAKREF(griefer)
	GLOB.bot_security_wanted[ref] = W
	var/wanted = P.whereabouts(griefer, ask)
	GLOB.bot_security_wanted -= ref //shared with every arena: off the list before anybody else looks
	log_line("asked wanted for murder: \"[wanted]\"")
	var/told_clean = findtext(clean, "Emery Whereabouts") //the arena isn't a station level: "isn't on the station" is its answer here
	var/told_killer = findtext(wanted, "Emery Whereabouts")
	expect(told_clean && wanted && !told_killer, "where they are to somebody clean, nothing to the killer")

/// round-20.48.49: the Captain bolted the Brig with a door remote and asked the AI to unbolt it. It asked him "What for?" twice, then
/// opened the Brig Desk beside him. Two shut doors in reach: the bolted one farther off. Asked to unbolt, it's the bolted one, and no
/// questions for the Captain. Then both bolted and "unbolt all": both.
/datum/bot_scenario/griefed/bug/ai_unbolt_for_captain
	name = "AI: unbolts the bolted door the Captain asks for, without asking why"
	griefer_job = "Captain"
	griefer_name = "Mika Boltcap"
	layout = list(
		"#########",
		"#...B...#",
		"###D#D###",
		"#....C..#",
		"#########")

/datum/bot_scenario/griefed/bug/ai_unbolt_for_captain/grief()
	var/list/doors = placed["D"]
	var/obj/machinery/door/airlock/far = doors[1]
	var/obj/machinery/door/airlock/near = doors[2]
	if(get_dist(griefer, far) <= get_dist(griefer, near))
		var/obj/machinery/door/airlock/swap = far
		far = near
		near = swap
	far.bolt()
	var/datum/bot_silicon/ai/gym_probe/P = new
	P.strictness = 0.9 //the strict sort, which asks what a door's for
	P.consider_door_for(griefer, "ai unbolt this door", FALSE)
	log_line("one door: far (bolted) locked=[far.locked], near locked=[near.locked] dense=[near.density]; said [english_list(P.replies)]")
	var/one_ok = !far.locked && !near.locked && near.density
	for(var/line in P.replies)
		if(findtext(line, "What for") || findtext(line, "Reason") || findtext(line, "State your reason"))
			one_ok = FALSE
	far.bolt() //open or shut, it's the bolts that count
	near.bolt()
	P.replies.Cut()
	P.consider_door_for(griefer, "ai unbolt all the doors", FALSE)
	log_line("all: far locked=[far.locked], near locked=[near.locked]; said [english_list(P.replies)]")
	expect(one_ok && !far.locked && !near.locked, "the bolted door unbolted with no questions, then both")
