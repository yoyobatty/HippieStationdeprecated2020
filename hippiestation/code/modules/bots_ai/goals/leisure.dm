// Free time. What crew do with a quiet minute, for the bots that go in for it (bot_brain.habits,
// bot_personality.dm) - asked for only when a bot was about to stroll off somewhere anyway:
//
//  - smokers light up: a cigarette out of the pack (pack clicked on yourself), the lighter flicked
//    on and held to it, lighter off and away. No pack or lighter: the cigarette machine, once in a
//    while. Never with a mask on, and never where the air's no good.
//  - animal lovers make a fuss of whatever pet is nearby: a help-intent click or three.
//  - gamers play the arcade's Space Villain: attack, heal when it's going badly, recharge when out
//    of magic - the game's own rules (arcade.dm), a move every second or so, and they take the prize.

/datum/bot_brain
	var/next_smokes_shop_time = 0
	var/cigarettes_smoked = 0
	var/animals_petted = 0
	var/arcade_games_played = 0

// ---------------------------------------------------------------------------------------------
// A smoke
// ---------------------------------------------------------------------------------------------

/datum/bot_brain/proc/carried_cigarette_pack()
	for(var/obj/item/storage/fancy/cigarettes/P in owner.GetAllContents())
		if(locate(/obj/item/clothing/mask/cigarette) in P)
			return P
	return null

/datum/bot_duty/smoke
	name = "having a smoke"
	tier = BOT_DUTY_LEISURE
	interval_min = 3000
	interval_max = 6000

/datum/bot_duty/smoke/applies_to(datum/bot_brain/bot)
	return ..() && bot.has_habit(BOT_HABIT_SMOKER)

/datum/bot_duty/smoke/try_start(datum/bot_brain/bot)
	if(bot.owner.wear_mask || !bot.air_is_breathable())
		return FALSE
	if(bot.carried_cigarette_pack() && bot.find_carried_tool(/obj/item/lighter))
		return bot.assign_goal(new /datum/bot_goal/smoke())
	if(world.time < bot.next_smokes_shop_time)
		return FALSE
	bot.next_smokes_shop_time = world.time + 10 MINUTES
	return bot.assign_goal(new /datum/bot_goal/buy_smokes())

/datum/bot_goal/smoke
	doing = "having a smoke"

/datum/bot_goal/smoke/resolve_target(datum/bot_brain/bot)
	target = bot.owner

/datum/bot_goal/smoke/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/leisure/S = new
	S.steps = list(new /datum/bot_step/light_cigarette())
	return list(S)

/datum/bot_strategy/leisure/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/datum/bot_step/light_cigarette/execute(datum/bot_brain/bot)
	var/obj/item/storage/fancy/cigarettes/pack = bot.carried_cigarette_pack()
	var/obj/item/lighter/lighter = bot.find_carried_tool(/obj/item/lighter)
	if(!pack || !lighter || bot.owner.wear_mask)
		return GOAL_STEP_FAIL
	// The pack clicked on yourself puts one straight in the mouth (fancy/cigarettes/attack()).
	if(!bot.use_item_on(pack, bot.owner))
		return GOAL_STEP_FAIL
	var/obj/item/clothing/mask/cigarette/cig = bot.owner.wear_mask
	if(!istype(cig))
		return GOAL_STEP_FAIL
	bot.put_away(pack, allow_equip = FALSE)
	if(!lighter.lit)
		bot.toggle_in_hand(lighter)
	bot.use_item_on(lighter, bot.owner) //lighter/attack(): held to the cigarette
	if(!QDELETED(lighter) && lighter.lit)
		bot.toggle_in_hand(lighter)
	bot.put_away(lighter, allow_equip = FALSE)
	if(QDELETED(cig) || !cig.lit)
		return GOAL_STEP_FAIL
	bot.cigarettes_smoked++
	bot_log(bot, "lit a cigarette")
	return GOAL_STEP_SUCCESS

/datum/bot_goal/buy_smokes
	lawful = TRUE
	doing = "getting some cigarettes"

/datum/bot_goal/buy_smokes/resolve_target(datum/bot_brain/bot)
	target = bot.find_fare_vendor(list(/obj/machinery/vending/cigarette), /obj/item/storage/fancy/cigarettes, 40) //goals/eat_and_drink.dm

/datum/bot_goal/buy_smokes/get_strategies(datum/bot_brain/bot)
	var/list/wanted = list()
	if(!bot.carried_cigarette_pack())
		wanted += /obj/item/storage/fancy/cigarettes
	if(!bot.find_carried_tool(/obj/item/lighter))
		wanted += /obj/item/lighter/greyscale
	var/datum/bot_strategy/leisure/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/vend_products(wanted))
	return list(S)

/// And straight into the first one out of the pack.
/datum/bot_goal/buy_smokes/on_success(datum/bot_brain/bot)
	if(!bot.owner.wear_mask)
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, assign_goal), new /datum/bot_goal/smoke()))

// ---------------------------------------------------------------------------------------------
// The station's animals
// ---------------------------------------------------------------------------------------------

/// A living, friendly animal near enough to wander over to.
/datum/bot_brain/proc/find_pet_to_fuss()
	var/mob/living/simple_animal/nearest
	for(var/mob/living/simple_animal/A in view(9, owner))
		if(A.stat == DEAD || !isturf(A.loc))
			continue
		if(!istype(A, /mob/living/simple_animal/pet) && !istype(A, /mob/living/simple_animal/parrot) && !istype(A, /mob/living/simple_animal/cow) && !istype(A, /mob/living/simple_animal/chicken))
			continue
		if(!nearest || get_dist(owner, A) < get_dist(owner, nearest))
			nearest = A
	return nearest

/datum/bot_duty/pet_animal
	name = "petting an animal"
	tier = BOT_DUTY_LEISURE
	interval_min = 900
	interval_max = 2400

/datum/bot_duty/pet_animal/applies_to(datum/bot_brain/bot)
	return ..() && bot.has_habit(BOT_HABIT_ANIMAL_LOVER)

/datum/bot_duty/pet_animal/try_start(datum/bot_brain/bot)
	var/mob/living/simple_animal/pet = bot.find_pet_to_fuss()
	return pet ? bot.assign_goal(new /datum/bot_goal/pet_animal(pet)) : FALSE

/datum/bot_goal/pet_animal
	lawful = TRUE

/datum/bot_goal/pet_animal/New(mob/living/simple_animal/pet)
	. = ..()
	target = pet
	doing = "saying hello to [pet]"

/datum/bot_goal/pet_animal/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/pet_animal/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/leisure/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/pet_animal())
	return list(S)

/datum/bot_step/paced/pet_animal
	var/pets = 0
	var/pets_wanted = 2

/datum/bot_step/paced/pet_animal/start(datum/bot_brain/bot)
	pets = 0
	pets_wanted = rand(2, 4)
	return TRUE

/datum/bot_step/paced/pet_animal/do_click(datum/bot_brain/bot)
	var/mob/living/simple_animal/pet = bot.current_goal?.target
	if(pets >= pets_wanted || QDELETED(pet) || pet.stat == DEAD || !bot.owner.Adjacent(pet))
		return FALSE
	bot.owner.a_intent = INTENT_HELP
	if(!bot.use_atom(pet))
		return FALSE
	pets++
	wait_for = rand(8, 20)
	return TRUE

/datum/bot_step/paced/pet_animal/finish(datum/bot_brain/bot)
	if(pets)
		bot.animals_petted++
	return pets ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// The arcade
// ---------------------------------------------------------------------------------------------

/datum/bot_brain/proc/find_arcade_machine()
	var/obj/machinery/computer/arcade/battle/best
	var/best_dist
	for(var/obj/machinery/computer/arcade/battle/A as anything in bot_instances_of(/obj/machinery/computer/arcade/battle))
		if(QDELETED(A) || A.z != owner.z || (A.stat & (BROKEN|NOPOWER)) || (A.obj_flags & EMAGGED) || taken_by_another(A))
			continue //a rigged machine kills whoever loses on it
		var/dist = get_dist(owner, A)
		if(dist > 25 || (best && dist >= best_dist))
			continue
		if(gym_run && get_area(A) != get_area(owner))
			continue
		best = A
		best_dist = dist
	return best

/datum/bot_duty/play_arcade
	name = "playing the arcade"
	tier = BOT_DUTY_LEISURE
	interval_min = 3000
	interval_max = 6000

/datum/bot_duty/play_arcade/applies_to(datum/bot_brain/bot)
	return ..() && bot.has_habit(BOT_HABIT_GAMER)

/datum/bot_duty/play_arcade/try_start(datum/bot_brain/bot)
	return bot.find_arcade_machine() ? bot.assign_goal(new /datum/bot_goal/play_arcade()) : FALSE

/datum/bot_goal/play_arcade
	lawful = TRUE
	exclusive = TRUE //one player to a machine
	doing = "playing the arcade"

/datum/bot_goal/play_arcade/resolve_target(datum/bot_brain/bot)
	target = bot.find_arcade_machine()

/datum/bot_goal/play_arcade/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/leisure/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/play_arcade())
	return list(S)

/// One game of Space Villain, a move at a time, by the buttons on its screen (arcade/battle/Topic()).
/datum/bot_step/paced/play_arcade
	var/obj/machinery/computer/arcade/battle/machine
	var/moves = 0

/datum/bot_step/paced/play_arcade/start(datum/bot_brain/bot)
	machine = bot.current_goal?.target
	moves = 0
	if(!istype(machine) || !bot.owner.Adjacent(machine))
		return FALSE
	bot.owner.face_atom(machine)
	if(machine.gameover) //"New Game"
		bot.human_pause(machine)
		bot.telemetry_ui_action(machine, "new game")
		machine.temp = "New Round"
		machine.player_hp = 30
		machine.player_mp = 10
		machine.enemy_hp = 45
		machine.enemy_mp = 20
		machine.gameover = FALSE
		machine.turtle = 0
	bot_log(bot, "playing [machine]")
	return TRUE

/datum/bot_step/paced/play_arcade/do_click(datum/bot_brain/bot)
	// A game usually runs 20-40 moves, but one where both sides keep healing can go past a hundred - and a player
	// that far in sees it out.
	if(QDELETED(machine) || machine.gameover || moves >= 150 || !bot.owner.Adjacent(machine) || (machine.stat & (BROKEN|NOPOWER)))
		return FALSE
	if(machine.blocked)
		wait_for = 5
		return TRUE
	bot.human_pause(machine)
	if(QDELETED(machine) || machine.gameover || machine.blocked || !bot.owner.Adjacent(machine))
		return FALSE
	bot.owner.face_atom(machine)
	machine.blocked = TRUE
	if(machine.player_hp <= 10 && machine.player_mp >= 4)
		bot.telemetry_ui_action(machine, "heal")
		var/cost = rand(1, 3)
		var/healed = rand(6, 8)
		machine.temp = "You use [cost] magic to heal for [healed] damage!"
		playsound(machine.loc, 'sound/arcade/heal.ogg', 50, 1, extrarange = -3, falloff = 10)
		machine.turtle++
		sleep(10)
		machine.player_mp -= cost
		machine.player_hp += healed
	else if(machine.player_mp <= 3)
		bot.telemetry_ui_action(machine, "recharge")
		var/charged = rand(4, 7)
		machine.temp = "You regain [charged] points"
		playsound(machine.loc, 'sound/arcade/mana.ogg', 50, 1, extrarange = -3, falloff = 10)
		machine.player_mp += charged
		if(machine.turtle > 0)
			machine.turtle--
		sleep(10)
	else
		bot.telemetry_ui_action(machine, "attack")
		var/hit = rand(2, 6)
		machine.temp = "You attack for [hit] damage!"
		playsound(machine.loc, 'sound/arcade/hit.ogg', 50, 1, extrarange = -3, falloff = 10)
		if(machine.turtle > 0)
			machine.turtle--
		sleep(10)
		machine.enemy_hp -= hit
	if(QDELETED(machine))
		return FALSE
	machine.arcade_action(bot.owner)
	moves++
	wait_for = rand(3, 10)
	return TRUE

/datum/bot_step/paced/play_arcade/finish(datum/bot_brain/bot)
	if(!moves || QDELETED(machine))
		machine = null
		return GOAL_STEP_FAIL
	bot.arcade_games_played++
	var/won = machine.gameover && (machine.enemy_hp <= 0 || machine.enemy_mp <= 0)
	if(won)
		// The prize drops out at the machine's feet.
		for(var/obj/item/prize in get_turf(machine))
			if(bot.take_in_hand(prize))
				bot.put_away(prize)
			break
		if(prob(50))
			bot.say_after_typing(pick("Yes!", "Ha, got him.", "Too easy."))
	else if(machine.gameover && prob(50))
		bot.say_after_typing(pick("Damn.", "Rigged.", "One more go and I'd have had him."))
	machine = null
	return GOAL_STEP_SUCCESS
