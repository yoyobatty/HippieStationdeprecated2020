#define BADTRIP_COOLDOWN 180
/datum/reagent/drug/burpinate
    name = "Burpinate"
    description = "They call me gaseous clay."
    color = "#bfe8a7" // rgb: 191, 232, 167
    metabolization_rate = 0.9 * REAGENTS_METABOLISM
    taste_description = "wet hot dogs"

/datum/reagent/drug/burpinate/on_mob_life(mob/living/M)
    if(ishuman(M))
        var/mob/living/carbon/human/H = M
        if(prob(5+(current_cycle*0.6))) //burping intensifies
            H.emote("burp")
            if(prob(5))
                to_chat(H, "<span class='danger'>You feel your bloated stomach rumble with gas.</span>")

        if(current_cycle>90) //chance to burp = 55% (you can't stop burping)
            if(prob(5))
                to_chat(H, "<span class='danger'>Your throat is sore from all the gas coming out!</span>")
    return ..()

/datum/reagent/drug/fartium
	name = "Fartium"
	description = "A chemical compound that promotes concentrated production of gas in your groin area."
	color = "#8A4B08" // rgb: 138, 75, 8
	overdose_threshold = 30
	addiction_threshold = 50

/datum/reagent/drug/fartium/on_mob_life(mob/living/M)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/butt/B = locate() in H.internal_organs
		if(prob(7))
			if(B)
				H.emote("fart")
			else
				to_chat(H, "<span class='danger'>Your stomach rumbles as pressure builds up inside of you.</span>")
				H.adjustToxLoss(1*REM)
	return ..()

/datum/reagent/drug/fartium/overdose_process(mob/living/M)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/butt/B = locate() in H.internal_organs
		if(prob(9))
			if(B)
				H.emote("fart")
			else
				to_chat(H, "<span class='danger'>Your stomach hurts a bit as pressure builds up inside of you.</span>")
				H.adjustToxLoss(2*REM)
	return ..()

/datum/reagent/drug/fartium/addiction_act_stage1(mob/living/M)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/butt/B = locate() in H.internal_organs
		if(prob(11))
			if(B)
				H.emote("fart")
			else
				to_chat(H, "<span class='danger'>Your stomach hurts as pressure builds up inside of you.</span>")
				H.adjustToxLoss(3*REM)
	return ..()

/datum/reagent/drug/fartium/addiction_act_stage2(mob/living/M)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/butt/B = locate() in H.internal_organs
		if(prob(13))
			if(B)
				H.emote("fart")
			else
				to_chat(H, "<span class='danger'>Your stomach hurts a lot as pressure builds up inside of you.</span>")
				H.adjustToxLoss(4*REM)
	return ..()

/datum/reagent/drug/fartium/addiction_act_stage3(mob/living/M)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/butt/B = locate() in H.internal_organs
		if(prob(15))
			if(B)
				if(prob(2) && !B.loose) H.emote("superfart")
				else H.emote("fart")
			else
				to_chat(H, "<span class='danger'>Your stomach hurts too much as pressure builds up inside of you.</span>")
				H.adjustToxLoss(5*REM)
	return ..()

/datum/reagent/drug/fartium/addiction_act_stage4(mob/living/M)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/butt/B = locate() in H.internal_organs
		if(prob(15))
			if(B)
				if(prob(5) && !B.loose) H.emote("superfart")
				else H.emote("fart")
			else
				to_chat(H, "<span class='danger'>Your stomach hurts too much as pressure builds up inside of you.</span>")
				H.adjustToxLoss(6*REM)
	return ..()

/datum/reagent/drug/nicotine
	description = "Slightly increases stamina regeneration and reduces hunger. If overdosed it will deal toxin and oxygen damage."

/datum/reagent/drug/nicotine/on_mob_life(mob/living/M)
	if(prob(1))
		var/smoke_message = pick("You feel relaxed.", "You feel calmed.","You feel alert.","You feel rugged.")
		to_chat(M, "<span class='notice'>[smoke_message]</span>")
	M.adjustStaminaLoss(-0.5*REM, 0)
	return FINISHONMOBLIFE(M)

/datum/reagent/drug/crank/on_mob_life(mob/living/M)
	var/high_message = pick("You feel jittery.", "You feel like you gotta go fast.", "You feel like you need to step it up.")
	if(prob(5))
		to_chat(M, "<span class='notice'>[high_message]</span>")
	M.AdjustStun(-20, 0)
	M.AdjustParalyzed(-20, 0)
	M.AdjustUnconscious(-20, 0)
	M.adjustToxLoss(2)
	M.adjustBrainLoss(1*REM)
	return FINISHONMOBLIFE(M)

/datum/reagent/drug/methamphetamine
	description = "Reduces stun times by about 300% and allows the user to quickly recover stamina while dealing a small amount of Brain damage. Breaks down slowly into histamine and hits the user with a large amount of histamine if they are stunned. Reacts badly with Ephedrine. If overdosed the subject will move randomly, laugh randomly, drop items and suffer from Toxin and Brain damage. If addicted the subject will constantly jitter and drool, before becoming dizzy and losing motor control and eventually suffer heavy toxin damage."

/datum/reagent/drug/methamphetamine/on_mob_life(mob/living/M)
	var/high_message = pick("You feel hyper.", "You feel like you're unstoppable!", "You feel like you can take on the world.")
	if(prob(5))
		to_chat(M, "<span class='notice'>[high_message]</span>")
	M.reagents.remove_reagent(/datum/reagent/medicine/diphenhydramine,2) //Greatly increases rate of decay
	if(M.IsStun() || M.IsParalyzed() || M.IsUnconscious())
		M.AdjustStun(-40, 0)
		M.AdjustParalyzed(-40, 0)
		M.AdjustUnconscious(-40, 0)
		var/amount2replace = rand(2,6)
		M.reagents.add_reagent(/datum/reagent/toxin/histamine,amount2replace)
		M.reagents.remove_reagent(/datum/reagent/drug/methamphetamine,amount2replace)
	M.adjustStaminaLoss(-2, 0)
	M.Jitter(2)
	M.adjustBrainLoss(0.25)
	if(prob(5))
		M.emote(pick("twitch", "shiver"))
		M.reagents.add_reagent(/datum/reagent/toxin/histamine, rand(1,5))
	return FINISHONMOBLIFE(M)

/datum/reagent/drug/bath_salts/on_mob_life(mob/living/M)
	var/high_message = pick("You feel amped up.", "You feel ready.", "You feel like you can push it to the limit.")
	if(prob(5))
		to_chat(M, "<span class='notice'>[high_message]</span>")
	M.add_movespeed_modifier(type, update=TRUE, priority=100, multiplicative_slowdown=-2, blacklisted_movetypes=(FLYING|FLOATING))
	M.AdjustUnconscious(-100, 0)
	M.AdjustStun(-100, 0)
	M.AdjustParalyzed(-100, 0)
	M.adjustStaminaLoss(-100, 0)
	M.adjustBrainLoss(5)
	M.adjustToxLoss(4)
	M.hallucination += 20
	if((M.mobility_flags & MOBILITY_MOVE) && !istype(M.loc, /atom/movable))
		step(M, pick(GLOB.cardinals))
		step(M, pick(GLOB.cardinals))
	if(prob(40))
		var/obj/item/I = M.get_active_held_item()
		if(I)
			M.dropItemToGround(M.get_active_held_item())
	return FINISHONMOBLIFE(M)

/datum/reagent/drug/bath_salts/on_mob_end_metabolize(mob/living/M)
	if (istype(M))
		M.remove_movespeed_modifier(type)
	..()

/datum/reagent/drug/flipout
	name = "Flipout"
	description = "A chemical compound that causes uncontrolled and extremely violent flipping."
	color = "#ff33cc" // rgb: 255, 51, 204
	overdose_threshold = 40
	addiction_threshold = 30


/datum/reagent/drug/flipout/on_mob_life(mob/living/M)
	var/high_message = pick("You have the uncontrollable, all consuming urge to FLIP!.", "You feel as if you are flipping to a higher plane of existence.", "You just can't stop FLIPPING.")
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(prob(80))
			H.SpinAnimation(10,1)
		if(prob(10))
			M << "<span class='notice'>[high_message].</span>"

	..()
	return

/datum/reagent/drug/flipout/overdose_process(mob/living/M)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		H.SpinAnimation(16,100)
		if(prob(70))
			H.Dizzy(20)
			if((M.mobility_flags & MOBILITY_MOVE) && !istype(M.loc, /atom/movable))
				for(var/i = 0, i < 4, i++)
				step(M, pick(GLOB.cardinals))
		if(prob(15))
			M << "<span class='danger'>The flipping is so intense you begin to tire </span>"
			H.confused +=4
			M.adjustStaminaLoss(10)
			H.transform *= -1
	..()
	return

/datum/reagent/drug/flipout/addiction_act_stage1(mob/living/M)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(prob(85))
			H.SpinAnimation(12,1)
		else
			H.Dizzy(16)
	..()

/datum/reagent/drug/flipout/addiction_act_stage2(mob/living/M)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(prob(90))
			H.SpinAnimation(10,3)
		else
			H.Dizzy(20)
			M.adjustStaminaLoss(25)
	..()

/datum/reagent/drug/flipout/addiction_act_stage3(mob/living/M)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(prob(95))
			H.SpinAnimation(7,20)
		else
			H.Dizzy(30)
			M.adjustStaminaLoss(40)
	..()

/datum/reagent/drug/flipout/addiction_act_stage4(mob/living/M)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		H.SpinAnimation(2,100)
		if(prob(10))
			M << "<span class='danger'>Your flipping has become so intense you've become an improvised generator </span>"
			H.Dizzy(25)
			M.electrocute_act(rand(1,5), 1, 1)
			playsound(M, "sparks", 50, 1)
			H.emote("scream")
			H.Jitter(-100)

		else
			H.Dizzy(60)
	..()

/datum/reagent/drug/flipout/reaction_obj(obj/O, reac_volume)
	if(istype(O,/obj))
		O.SpinAnimation(16,40)

/datum/reagent/drug/yespowder
	name = "Yes Powder"
	description = "Powder that makes you say yes."
	color = "#fffae0"

/datum/reagent/drug/yespowder/on_mob_life(mob/living/M)
	var/high_message = pick("Agreement fills your mind.", "'No' is so last year. 'Yes' is in.", "Yes.")
	if(prob(5))
		to_chat(M, "<span class='notice'>[high_message]</span>")
	if(prob(20))
		M.say("Yes.", forced = "yes powder")
	..()

/datum/reagent/drug/pupupipi
	name = "Sweet Brown"
	description = "A fetid concoction often huffed or drank by vagrants and bums. High dosages have... interesting effects."
	color = "#602101" // rgb: 96, 33, 1
	overdose_threshold = 100
	addiction_threshold = 50 // doesn't do shit though

/datum/reagent/drug/pupupipi/on_mob_life(mob/living/M)
	if(prob(5))
		var/high_message = pick("You need mo' o' dat sweet brown juice...", "Your guts tingle...", "You feel lightheaded...")
		to_chat(M, "<span class='notice'>[high_message]</span>")
	M.Jitter(30)
	if(prob(15)) //once every six-ish ticks. is that ok?
		M.emote("burp")
	..()

/datum/reagent/drug/pupupipi/overdose_process(mob/living/carbon/human/H)
	CHECK_DNA_AND_SPECIES(H)
	H.setBrainLoss(30)
	if(ishuman(H))
		to_chat(H, "<span class= 'userdanger'>Oh shit!</span>")
		H.set_species(/datum/species/krokodil_addict)
	..()

/datum/reagent/drug/grape_blast
	name = "Grape Blast"
	description = "A juice of a very special fruit, concentrated and sold at your local A1 vendor."
	color = "#ffffe6"
	reagent_state = LIQUID
	taste_description = "artificial grape"
	var/obj/effect/hallucination/simple/druggy/brain
	var/bad_trip = FALSE
	var/badtrip_cooldown = 0
	var/chaser_cooldown = 0
	var/burst_cooldown = 0
	var/trail_cooldown = 0
	var/transform_cooldown = 0 //only one world-wide transform at a time, a new animate() would restart the one still playing
	var/rainbow_body = FALSE //is the tripper cycling through the colour wheel for everyone to see?
	var/structure_cooldown = 0
	var/alive_cooldown = 0
	var/list/warp_images = list() //every image we've put over the world for the tripper, so they can all be taken back
	var/list/warped = list() //the real atoms those images are covering right now
	var/list/alive_things = list() //objects that have woken up and are wandering around
	var/tripping = FALSE //has the come up kicked in? this is what turns the world effects on and off
	var/cresting = FALSE //are we at the top of a wave right now?
	var/floating = FALSE //are we levitating because of the trip?
	var/view_rotated = FALSE //is the client's map turned sideways?

/datum/reagent/drug/grape_blast/proc/get_screens(mob/living/carbon/C, color_only = FALSE)
	var/list/screens = list()
	if(!C || !C.hud_used)
		return screens
	var/list/planes = list(FLOOR_PLANE, GAME_PLANE)
	if(!color_only) //colour matrices would mess with the multiply-blended planes, so those only get warped
		planes += list(LIGHTING_PLANE, CAMERA_STATIC_PLANE, PLANE_SPACE_PARALLAX, PLANE_SPACE)
	for(var/plane in planes)
		var/obj/screen/plane_master/PM = C.hud_used.plane_masters["[plane]"]
		if(PM)
			screens += PM
	return screens

/datum/reagent/drug/grape_blast/proc/create_brain(mob/living/carbon/C)
	var/turf/T = locate(C.x + pick(-1, 1), C.y + pick(-1, 1), C.z)
	if(!T)
		return
	brain = new(T, C)
	INVOKE_ASYNC(brain, TYPE_PROC_REF(/obj/effect/hallucination/simple/druggy, spook), C)

/datum/reagent/drug/grape_blast/on_mob_metabolize(mob/living/L)
	RegisterSignal(L, COMSIG_MOB_SAY, PROC_REF(on_say), TRUE)
	RegisterSignal(L, COMSIG_MOVABLE_MOVED, PROC_REF(on_moved), TRUE)
	..()

//How hard the drug is hitting right now, from 0 to 1. It comes up fast, rolls in waves that crest and recede, and the
//last stretch of the dose is the comedown, so a bigger dose means a longer and stronger peak
/datum/reagent/drug/grape_blast/proc/get_intensity()
	var/rise = clamp(current_cycle / 8, 0, 1) //the come up hits within about 15 seconds
	var/fall = clamp(volume / (metabolization_rate * 10), 0, 1) //the last 10 cycles of the dose are the comedown
	var/wave = 0.65 + 0.35 * sin(current_cycle * 30 - 60) //one wave every 12 cycles, never quite dropping to nothing
	return min(rise, fall) * wave

//The world starts to move
/datum/reagent/drug/grape_blast/proc/begin_trip(mob/living/carbon/C)
	tripping = TRUE
	to_chat(C, "<span class='notice'>The world begins to shimmer and hum...</span>")
	start_floating(C)
	start_rainbow(C)

//And settles again as the dose runs dry
/datum/reagent/drug/grape_blast/proc/settle_trip(mob/living/carbon/C)
	tripping = FALSE
	cresting = FALSE
	to_chat(C, "<span class='notice'>You drift back down towards the ground...</span>")
	stop_floating(C)
	stop_rainbow(C)

//The top of a wave, everything hits at the same moment
/datum/reagent/drug/grape_blast/proc/crest(mob/living/carbon/C, intensity)
	to_chat(C, "<span class='userdanger'>[pick("A wave of euphoria crashes over you!", "Everything surges at once!", "The colors PEAK!", "It's all coming up at you!")]</span>")
	var/power = 1 + round(intensity * 3)
	burst_ripple(C, power)
	drift_colors(C, TRUE)
	shake_camera(C, rand(6, 12), 0.08 * power)
	warp_world(get_screens(C))
	warp_structures(C, power)
	if(power >= 3)
		wake_object(C)
	burst_cooldown = world.time + 30

/datum/reagent/drug/grape_blast/on_mob_life(mob/living/carbon/H)
	if(!H)
		return
	if(!H.hud_used)
		return ..()
	var/intensity = get_intensity()
	var/list/screens = get_screens(H)
	var/high_message
	if(prob(5))
		H.emote(pick("twitch","drool","moan"))

	//the come up starts almost immediately, and the trip loosens its grip again as the dose runs out
	if(!tripping && intensity >= 0.3)
		begin_trip(H)
	else if(tripping && intensity < 0.15)
		settle_trip(H)

	if(intensity < 0.5 && prob(30)) //blurry eyes and talk like an idiot on the way up and the way down
		H.blur_eyes(2)
		H.derpspeech++
	if(intensity < 0.3)
		high_message = pick("Holy shit, I feel so fucking happy...", "What the fuck is going on?", "Where am I?", "Everything is so... colorful...", "My skin is tingling.", "Is the floor breathing?")
	else if(intensity < 0.75)
		high_message = pick("I feel like I'm flying!", "I feel something swimming inside my lungs....", "I can see the words I'm saying...", "Reality doesn't exist man.", "...", "No one flies around the sun.")
	else
		high_message = pick("The walls are made of grapes.", "Something is behind the colors.", "I've been here before. I'm always here.", "Time is a purple smear.")

	if(tripping)
		//every wave has a crest, where everything lands together, and a trough where it eases off
		if(intensity >= 0.6 && !cresting)
			cresting = TRUE
			crest(H, intensity)
		else if(intensity < 0.45 && cresting)
			cresting = FALSE
			to_chat(H, "<span class='notice'>The wave recedes, leaving everything soft and glowing...</span>")
		if(prob(round(25 * intensity)) && (H.mobility_flags & MOBILITY_MOVE) && !ismovable(H.loc))
			step(H, pick(GLOB.cardinals))
		if(H.client)
			echo_sounds(H)
		if(prob(round(5 + 25 * intensity)))
			warp_world(screens)
			for(var/obj/screen/plane_master/whole_screen in screens)
				if(prob(15))
					whole_screen.filters += filter(type="wave", x=20*rand() - 20, y=20*rand() - 20, size=rand()*0.1, offset=rand()*0.5, flags = WAVE_BOUNDED)
					animate(whole_screen.filters[whole_screen.filters.len], size = rand(1,3), time = 30, easing = QUAD_EASING, loop = -1)
					to_chat(H, "<span class='notice'>You feel reality melt away...</span>")
					addtimer(VARSET_CALLBACK(whole_screen, filters, list()), 1200)
		else if(prob(5))
			create_brain(H)
		if(prob(round(5 + 30 * intensity)))
			breathe(screens)
		if(prob(round(8 + 45 * intensity)))
			drift_colors(H, intensity >= 0.8)
		if(burst_cooldown < world.time && prob(round(10 + 55 * intensity)))
			psychedelic_burst(H, 1 + round(intensity * 3) + bad_trip)
		if(intensity >= 0.7)
			if(prob(6))
				spin_world(screens)
			if(prob(4))
				spawn_chaser(H)
			if(prob(3))
				spin_view(H)
		if(intensity >= 0.9 && prob(6))
			ego_death(H)
		if(structure_cooldown < world.time && prob(round(6 + 40 * intensity)))
			warp_structures(H, 1 + round(intensity * 3))
		if(intensity >= 0.6 && prob(3))
			wake_object(H)
		if(!bad_trip)
			if(prob(4))
				H.emote("laugh")
				H.say(pick("GRERRKRKRK",";HAHAH I AM SO FUCKING HIGH!!","I AM A BUTTERFLY!!"))
				H.visible_message("<span class='notice'>[H] looks high as fuck!</span>")
			else if(prob(3))
				H.Knockdown(20)
				H.emote("laugh")
				H.say(pick("TURN IT ON!!!","I CAN HEAR VOICES AHAHAHAH","YOU'RE GOKU!!"))
				H.visible_message("<span class='notice'>[H] appears to be on some good drugs!</span>")
			if(intensity >= 0.75 && prob(3) && badtrip_cooldown < world.time)
				bad_trip = TRUE
				to_chat(H, "<span class='userdanger'>The colors turn against you...</span>")
		if(bad_trip)
			for(var/obj/screen/plane_master/whole_screen in screens)
				if(prob(35))
					whole_screen.filters += filter(type="wave", x=30*rand() - 20, y=30*rand() - 20, size=rand()*0.5, offset=rand()*0.5)
					animate(whole_screen.filters[whole_screen.filters.len], size = rand(2,5), time = 60, easing = QUAD_EASING)
			var/list/t_ray_images = list()
			for(var/mob/living/L in orange(8, H) )
				if(!L.invisibility)
					var/image/I = new(loc = L)
					var/mutable_appearance/MA = new(L)
					MA.alpha = 128
					MA.dir = L.dir
					I.appearance = MA
					step(I, pick(GLOB.cardinals))
					t_ray_images += I
			if(t_ray_images.len)
				flick_overlay(t_ray_images, list(H.client), rand(10,30))
			high_message = pick("I can feel my thoughts racing!", "WHO THE FUCK SAID THAT??!!", "I feel like I'm going to die!")
			if(prob(8))
				spawn_chaser(H)
			if(prob(4))
				spin_view(H)
			if(prob(35))
				drift_colors(H, TRUE)
			if(prob(25))
				H.hallucination += 2
				H.jitteriness += 3
				H.emote("me", 1, pick("hyperventilates.", "gasps."))
				H.confused += 2
			else if(prob(5))
				H.emote("cry")
				H.say(pick("MAKE IT STOP!! I'M SORRY!!", ";I'LL DO ANYTHING, MAKE IT STOP!!", "YOU DIDN'T EVEN BOTHER, YOU DIDN'T SEE THEM GO!!", "YOU WANNA SEE WHAT REALITY REALLY IS?!!"))
				H.visible_message("<span class='warning'>[H] appears to be freaking out!</span>")
			else if(prob(3))
				H.stop_sound_channel(CHANNEL_HEARTBEAT)
				H.playsound_local(H, 'sound/effects/singlebeat.ogg', 100, 0)
				if(prob(40))
					H.visible_message("<span class='warning'>[H] clutches at [H.p_their()] chest as if [H.p_their()] heart is stopping!</span>")
				H.adjustStaminaLoss(80)
			if(intensity < 0.4) //a bad trip eases off with the wave
				end_bad_trip(H)
			else if(prob(3))
				addtimer(CALLBACK(src, PROC_REF(end_bad_trip), H), 30)

	if(high_message && prob(5))
		to_chat(H, "<i>You hear your own thoughts... <b>[high_message]</b></i>")
	..()

/datum/reagent/drug/grape_blast/on_mob_end_metabolize(mob/living/L)
	UnregisterSignal(L, list(COMSIG_MOB_SAY, COMSIG_MOVABLE_MOVED))
	tripping = FALSE
	cresting = FALSE
	clear_warps(L)
	stop_floating(L)
	stop_rainbow(L)
	unspin_view(L)
	end_trip(L)
	..()

/datum/reagent/drug/grape_blast/proc/end_bad_trip(mob/living/carbon/human/H)
	bad_trip = FALSE
	badtrip_cooldown = world.time + BADTRIP_COOLDOWN
	H.visible_message("<span class='notice'>[H] appears to have calmed down.</span>")
	H.emote("me", 1, pick("takes a deep breath.", "relaxes."))

/datum/reagent/drug/grape_blast/proc/end_trip(mob/living/carbon/C)
	to_chat(C, "<span class='notice'>As the drugs wear off, you feel yourself slowly coming back to reality...</span>")
	C.drowsyness++ //We feel sleepy after going through that trip.
	if(!HAS_TRAIT(C, TRAIT_DUMB))
		C.derpspeech = 0
	if(C && C.hud_used)
		for(var/obj/screen/plane_master/whole_screen in get_screens(C))
			animate(whole_screen, transform = matrix(), time = 60, easing = SINE_EASING)
			addtimer(VARSET_CALLBACK(whole_screen, filters, list()), 200) //reset filters
			addtimer(VARSET_CALLBACK(whole_screen, color, null), 201) //reset any colour drift
			addtimer(CALLBACK(whole_screen, /obj/screen/plane_master/.proc/backdrop, C), 201) //reset backdrop filters so they reappear
		PlaySpook(C, 'hippiestation/sound/misc/honk_echo_distant.ogg', 0, FALSE)

//Your feet leave the ground for as long as the trip lasts
/datum/reagent/drug/grape_blast/proc/start_floating(mob/living/carbon/C)
	floating = TRUE
	to_chat(C, "<span class='notice'>Your feet leave the ground...</span>")
	INVOKE_ASYNC(C, TYPE_PROC_REF(/atom/movable, float), TRUE)

/datum/reagent/drug/grape_blast/proc/stop_floating(mob/living/L)
	if(!floating)
		return
	floating = FALSE
	INVOKE_ASYNC(L, TYPE_PROC_REF(/atom/movable, float), FALSE)

//Pulses the colours of the world around the color wheel, or into a photo negative for the nastier moments
/datum/reagent/drug/grape_blast/proc/drift_colors(mob/living/carbon/C, strong = FALSE)
	var/list/tint
	if(strong && prob(25))
		tint = list(-1,0,0,0, 0,-1,0,0, 0,0,-1,0, 0,0,0,1, 1,1,1,0)
	else
		tint = color_matrix_rotate_hue(rand(60, 300))
	var/pulse_time = strong ? rand(10, 25) : rand(25, 50)
	for(var/obj/screen/plane_master/whole_screen in get_screens(C, TRUE))
		animate(whole_screen, color = tint, time = pulse_time, easing = SINE_EASING)
		animate(color = color_matrix_rotate_hue(0), time = pulse_time, easing = SINE_EASING)

//The whole world tilts and swells together, then settles back. Every plane gets the same roll so nothing drifts apart
/datum/reagent/drug/grape_blast/proc/warp_world(list/screens)
	if(transform_cooldown > world.time)
		return
	transform_cooldown = world.time + 75
	var/max_tilt = clamp(round(current_cycle / 4), 20, 60)
	var/tilt = rand(-max_tilt, max_tilt)
	var/scale = 1 + (rand(5, 20) / 100)
	for(var/obj/screen/plane_master/whole_screen in screens)
		animate(whole_screen, transform = turn(matrix() * scale, tilt), time = 30, easing = SINE_EASING)
		animate(transform = turn(matrix() * scale, -tilt), time = 20, easing = SINE_EASING)
		animate(transform = matrix(), time = 20, easing = SINE_EASING)

//The world inhales and exhales
/datum/reagent/drug/grape_blast/proc/breathe(list/screens)
	if(transform_cooldown > world.time)
		return
	transform_cooldown = world.time + 32
	var/scale = 1 + (rand(4, 9) / 100)
	for(var/obj/screen/plane_master/whole_screen in screens)
		animate(whole_screen, transform = matrix() * scale, time = 15, easing = SINE_EASING)
		animate(transform = matrix(), time = 15, easing = SINE_EASING)

//Everyone else sees the tripper cycle through the colour wheel
/datum/reagent/drug/grape_blast/proc/start_rainbow(mob/living/carbon/C)
	rainbow_body = TRUE
	animate(C, color = color_matrix_rotate_hue(120), time = 15, loop = -1, easing = SINE_EASING)
	animate(color = color_matrix_rotate_hue(240), time = 15, easing = SINE_EASING)
	animate(color = color_matrix_rotate_hue(0), time = 15, easing = SINE_EASING)

/datum/reagent/drug/grape_blast/proc/stop_rainbow(mob/living/L)
	if(!rainbow_body)
		return
	rainbow_body = FALSE
	animate(L, color = color_matrix_rotate_hue(0), time = 10)
	addtimer(CALLBACK(L, TYPE_PROC_REF(/atom, update_atom_colour)), 11)

//Leave a trail of coloured afterimages behind you
/datum/reagent/drug/grape_blast/proc/on_moved(atom/movable/source, atom/oldloc, dir)
	if(!tripping || trail_cooldown > world.time || !isturf(oldloc))
		return
	trail_cooldown = world.time + 2
	var/obj/effect/temp_visual/decoy/fading/D = new(oldloc, source)
	D.color = pick("#ff66ff", "#66ffff", "#ffff66", "#66ff66", "#ff6666")

//A random screen-wide effect, the higher the power the bigger it gets
/datum/reagent/drug/grape_blast/proc/psychedelic_burst(mob/living/carbon/C, power = 1)
	burst_cooldown = world.time + rand(15, 40)
	switch(rand(1, 5))
		if(1)
			burst_ripple(C, power)
		if(2)
			burst_radial_blur(C, power)
		if(3)
			burst_rays(C, power)
		if(4)
			burst_bloom(C, power)
		if(5)
			shake_camera(C, rand(4, 10), 0.1 * power)
	if(power >= 3 && prob(50)) //at the deep end everything lands at once
		burst_ripple(C, power)
		shake_camera(C, rand(4, 10), 0.1 * power)

/datum/reagent/drug/grape_blast/proc/clear_filter(obj/screen/plane_master/PM, F)
	if(PM)
		PM.filters -= F

//A shockwave rolls across the world
/datum/reagent/drug/grape_blast/proc/burst_ripple(mob/living/carbon/C, power)
	var/duration = rand(25, 40)
	var/center_x = rand(-96, 96)
	var/center_y = rand(-96, 96)
	for(var/obj/screen/plane_master/PM in get_screens(C, TRUE))
		PM.filters += filter(type="ripple", x = center_x, y = center_y, size = 2 + power * 2, repeat = rand(10, 25), radius = 0, falloff = 1)
		var/F = PM.filters[PM.filters.len]
		animate(F, radius = rand(200, 400), size = 0, time = duration, easing = SINE_EASING)
		addtimer(CALLBACK(src, PROC_REF(clear_filter), PM, F), duration + 2)

//The world smears outward from the middle of your vision
/datum/reagent/drug/grape_blast/proc/burst_radial_blur(mob/living/carbon/C, power)
	for(var/obj/screen/plane_master/PM in get_screens(C, TRUE))
		PM.filters += filter(type="radial_blur", x = 0, y = 0, size = 0)
		var/F = PM.filters[PM.filters.len]
		animate(F, size = 0.03 * power, time = 8, easing = SINE_EASING)
		animate(size = 0, time = 12, easing = SINE_EASING)
		addtimer(CALLBACK(src, PROC_REF(clear_filter), PM, F), 22)

//Coloured light rays sweep out of the middle of the screen
/datum/reagent/drug/grape_blast/proc/burst_rays(mob/living/carbon/C, power)
	var/obj/screen/plane_master/PM = C.hud_used.plane_masters["[GAME_PLANE]"]
	if(!PM)
		return
	PM.filters += filter(type="rays", x = 0, y = 0, size = 60 + power * 40, color = rgb(rand(100, 255), rand(100, 255), rand(100, 255), 120), offset = 0, density = rand(6, 14), threshold = 0.4, factor = 1)
	var/F = PM.filters[PM.filters.len]
	animate(F, offset = rand(2, 4), time = 25, easing = LINEAR_EASING)
	animate(size = 0, time = 5)
	addtimer(CALLBACK(src, PROC_REF(clear_filter), PM, F), 32)

//Everything bright swells up and glows
/datum/reagent/drug/grape_blast/proc/burst_bloom(mob/living/carbon/C, power)
	var/obj/screen/plane_master/PM = C.hud_used.plane_masters["[GAME_PLANE]"]
	if(!PM)
		return
	PM.filters += filter(type="bloom", threshold = "#404040", size = 1, offset = 1, alpha = 0)
	var/F = PM.filters[PM.filters.len]
	animate(F, size = 4 + power * 2, offset = 3, alpha = 200, time = 15, easing = SINE_EASING)
	animate(size = 1, offset = 1, alpha = 0, time = 15, easing = SINE_EASING)
	addtimer(CALLBACK(src, PROC_REF(clear_filter), PM, F), 32)

//The whole world does a full turn
/datum/reagent/drug/grape_blast/proc/spin_world(list/screens)
	if(transform_cooldown > world.time)
		return
	transform_cooldown = world.time + 55
	for(var/obj/screen/plane_master/whole_screen in screens)
		animate(whole_screen, transform = turn(matrix(), 180), time = 25, easing = SINE_EASING)
		animate(transform = turn(matrix(), 359), time = 25, easing = SINE_EASING)
		animate(transform = matrix(), time = 1)

/datum/reagent/drug/grape_blast/proc/is_warpable(atom/A)
	if(A in warped)
		return FALSE
	if(A.invisibility)
		return FALSE
	if(iswallturf(A))
		return TRUE
	return isobj(A) && !istype(A, /obj/effect) && !istype(A, /obj/screen) && isturf(A.loc)

//Nearby walls, structures and machines start to dance, melt, breathe or dissolve, all in time with each other.
//These are only images laid over the real thing for the tripper, nothing actually changes in the world
/datum/reagent/drug/grape_blast/proc/warp_structures(mob/living/carbon/C, power = 1)
	if(!C.client || warp_images.len >= 30)
		return
	structure_cooldown = world.time + rand(30, 60)
	var/list/candidates = list()
	for(var/atom/A in view(7, C))
		if(is_warpable(A))
			candidates += A
	if(!candidates.len)
		return
	var/mode = bad_trip ? pick("melt", "melt", "dissolve", "dissolve", "dance") : pick("dance", "dance", "breathe", "melt", "dissolve")
	switch(mode)
		if("dance")
			to_chat(C, "<span class='notice'>The walls begin to sway to a beat only you can hear.</span>")
		if("breathe")
			to_chat(C, "<span class='notice'>The walls are breathing. In, and out.</span>")
		if("melt")
			to_chat(C, "<span class='warning'>Everything around you begins to melt...</span>")
		if("dissolve")
			to_chat(C, "<span class='warning'>The world starts to dissolve at the edges.</span>")
	var/beat = rand(4, 8)
	var/duration = rand(80, 200)
	for(var/i in 1 to min(candidates.len, 2 + power * 2))
		var/atom/A = pick(candidates)
		candidates -= A
		warp_atom(C, A, mode, duration, beat)

/datum/reagent/drug/grape_blast/proc/warp_atom(mob/living/carbon/C, atom/A, mode, duration, beat)
	var/image/I = new(loc = A)
	I.appearance = A.appearance
	I.override = TRUE
	C.client.images += I
	warp_images += I
	warped += A
	var/base_y = I.pixel_y //animate() changes the var straight away, so remember where we started
	switch(mode)
		if("dance")
			var/sway = rand(4, 10)
			var/bounce = rand(2, 5)
			animate(I, pixel_y = base_y + bounce, transform = turn(matrix(), sway), time = beat, loop = -1, easing = SINE_EASING)
			animate(pixel_y = base_y - bounce, transform = turn(matrix(), -sway), time = beat, easing = SINE_EASING)
		if("breathe")
			animate(I, transform = matrix() * 1.1, time = beat * 2, loop = -1, easing = SINE_EASING)
			animate(transform = matrix() * 0.95, time = beat * 2, easing = SINE_EASING)
		if("melt")
			//sag down and spread out, keeping the bottom edge where it was, then slump a little further, over and over
			animate(I, transform = matrix(1.1, 0, 0, 0, 0.55, 0), pixel_y = base_y - 7, color = pick("#b34dff", "#4dffb3", "#ff4db3"), time = 40, loop = -1, easing = SINE_EASING)
			animate(transform = matrix(1.25, 0, 0, 0, 0.3, 0), pixel_y = base_y - 11, time = 40, easing = SINE_EASING)
			animate(transform = matrix(1.1, 0, 0, 0, 0.55, 0), pixel_y = base_y - 7, time = 40, easing = SINE_EASING)
		if("dissolve")
			animate(I, alpha = 0, transform = turn(matrix() * 0.2, rand(-180, 180)), time = 30, easing = SINE_EASING)
	addtimer(CALLBACK(src, PROC_REF(settle_atom), C, I, A), duration)

//Things pull themselves back together before the illusion is taken away
/datum/reagent/drug/grape_blast/proc/settle_atom(mob/living/carbon/C, image/I, atom/A)
	if(QDELETED(A))
		restore_atom(C, I, A)
		return
	animate(I, transform = matrix(), alpha = A.alpha, pixel_y = A.pixel_y, color = A.color, time = 15, easing = SINE_EASING)
	addtimer(CALLBACK(src, PROC_REF(restore_atom), C, I, A), 16)

/datum/reagent/drug/grape_blast/proc/restore_atom(mob/living/carbon/C, image/I, atom/A)
	warp_images -= I
	warped -= A
	if(C && C.client)
		C.client.images -= I

//An ordinary object wakes up, pulls itself off the floor and goes for a wander
/datum/reagent/drug/grape_blast/proc/wake_object(mob/living/carbon/C)
	if(!C.client || alive_cooldown > world.time || alive_things.len >= 2)
		return
	var/list/candidates = list()
	for(var/obj/O in view(6, C))
		if(is_warpable(O))
			candidates += O
	if(!candidates.len)
		return
	var/obj/O = pick(candidates)
	alive_cooldown = world.time + 100
	to_chat(C, "<span class='warning'>\The [O] twitches, then slowly turns to look at you.</span>")
	var/image/hide = new(loc = O) //an image with no icon covering the real object, so it's gone from where it was
	hide.override = TRUE
	C.client.images += hide
	warp_images += hide
	warped += O
	var/obj/effect/hallucination/simple/druggy/alive/A = new(get_turf(O), C, O)
	alive_things += A
	addtimer(CALLBACK(src, PROC_REF(put_back), C, hide, O, A), 110)

/datum/reagent/drug/grape_blast/proc/put_back(mob/living/carbon/C, image/hide, obj/O, obj/effect/hallucination/simple/druggy/alive/A)
	alive_things -= A
	if(!QDELETED(A))
		qdel(A)
	restore_atom(C, hide, O)

//Take back every image we put over the world
/datum/reagent/drug/grape_blast/proc/clear_warps(mob/living/L)
	if(L && L.client)
		for(var/image/I in warp_images)
			L.client.images -= I
	warp_images.Cut()
	warped.Cut()
	for(var/obj/effect/hallucination/simple/druggy/alive/A in alive_things)
		qdel(A)
	alive_things.Cut()

//Tilts the whole map sideways for a few seconds
/datum/reagent/drug/grape_blast/proc/spin_view(mob/living/carbon/C)
	if(view_rotated || !C.client)
		return
	view_rotated = TRUE
	C.client.dir = pick(EAST, SOUTH, WEST)
	to_chat(C, "<span class='warning'>The world tilts sideways...</span>")
	addtimer(CALLBACK(src, PROC_REF(unspin_view), C), rand(30, 80))

/datum/reagent/drug/grape_blast/proc/unspin_view(mob/living/L)
	view_rotated = FALSE
	if(L && L.client)
		L.client.dir = NORTH

//Something that isn't there comes running at you
/datum/reagent/drug/grape_blast/proc/spawn_chaser(mob/living/carbon/C)
	if(chaser_cooldown > world.time)
		return
	var/turf/T = locate(C.x + pick(-6, -5, 5, 6), C.y + pick(-6, -5, 5, 6), C.z)
	if(!T)
		return
	chaser_cooldown = world.time + 50
	new /obj/effect/hallucination/simple/druggy/chaser(T, C)

//The deepest part of the trip
/datum/reagent/drug/grape_blast/proc/ego_death(mob/living/carbon/C)
	to_chat(C, "<span class='userdanger'>[pick("You are the colors. The colors are you.", "There is no one left to be scared.", "You dissolve into the grape.")]</span>")
	C.hallucination += 10
	C.jitteriness += 10
	C.blur_eyes(5)
	C.playsound_local(C, 'sound/effects/singlebeat.ogg', 100, 0)
	spawn_chaser(C)
	spin_view(C)
	drift_colors(C, TRUE)

//You can see the words you're saying, they float up and away
/datum/reagent/drug/grape_blast/proc/on_say(datum/source, list/speech_args)
	var/mob/living/carbon/C = source
	if(!tripping || !istype(C) || !C.client)
		return
	var/message = speech_args[SPEECH_MESSAGE]
	if(!message)
		return
	INVOKE_ASYNC(src, PROC_REF(float_words), C, message)

/datum/reagent/drug/grape_blast/proc/float_words(mob/living/carbon/C, message)
	var/image/I = new(loc = C)
	I.appearance_flags = APPEARANCE_UI_IGNORE_ALPHA
	I.layer = FLY_LAYER
	I.maptext_x = -32
	I.maptext_width = 96
	I.maptext_height = 32
	I.pixel_y = 32
	I.maptext = "<span style='color: [pick("#ff66ff", "#66ffff", "#ffff66", "#66ff66")]; font-family: Comic Sans MS; -dm-text-outline: 1px black'>[html_encode(copytext(message, 1, 41))]</span>"
	flick_overlay(I, list(C.client), 40)
	animate(I, pixel_y = 72, alpha = 0, transform = turn(matrix(), pick(-25, 25)), time = 40, easing = SINE_EASING)

//Replays short sounds you just heard, sometimes backwards and sometimes slowed down
/datum/reagent/drug/grape_blast/proc/echo_sounds(mob/living/carbon/C)
	for(var/sound/S in C.client.SoundQuery())
		if(S.len <= 3)
			PlaySpook(C, S.file, 23, TRUE, prob(50), prob(40))
			return

/obj/effect/hallucination/simple/druggy
	name = "Your brain"
	desc = "Don't do drugs kids."
	image_icon = 'icons/obj/surgery.dmi'
	image_state = "brain"

/obj/effect/hallucination/simple/druggy/proc/spook(mob/living/L)
	sleep(20)
	var/image/I = image('icons/mob/talk.dmi', src, "default2", FLY_LAYER)
	var/message = "This is your brain on drugs."
	I.appearance_flags = APPEARANCE_UI_IGNORE_ALPHA
	if(L)
		L.Hear(message, src, L.get_default_language(), message)
		INVOKE_ASYNC(GLOBAL_PROC, /.proc/flick_overlay, I, list(L.client), 30)
	sleep(10)
	animate(src, transform = matrix()*0.75, time = 5)
	QDEL_IN(src, 30)

//A copy of a real object that has come to life. It looks exactly like the thing it was, and hops around
/obj/effect/hallucination/simple/druggy/alive
	name = "something"
	desc = "It's alive. It shouldn't be."
	var/mutable_appearance/source_appearance
	var/wander_steps = 14

/obj/effect/hallucination/simple/druggy/alive/Initialize(mapload, mob/living/carbon/T, atom/source)
	source_appearance = new /mutable_appearance(source)
	name = source.name
	. = ..()
	INVOKE_ASYNC(src, PROC_REF(wander))

/obj/effect/hallucination/simple/druggy/alive/GetImage()
	var/image/I = new(loc = src)
	I.appearance = source_appearance
	return I

/obj/effect/hallucination/simple/druggy/alive/proc/hop()
	if(!current_image)
		return
	var/base_y = current_image.pixel_y //animate() changes the var straight away, so remember where we started
	animate(current_image, pixel_y = base_y + 6, time = 2)
	animate(pixel_y = base_y, time = 2)

/obj/effect/hallucination/simple/druggy/alive/proc/wander()
	var/approach = prob(60) //some of them creep up on you and the rest scatter
	while(wander_steps-- > 0 && !QDELETED(src) && !QDELETED(target))
		var/turf/next = approach ? get_step_towards(src, target) : get_step(src, pick(GLOB.alldirs))
		if(next && !next.density)
			forceMove(next)
		hop()
		if(approach && get_dist(src, target) <= 1)
			to_chat(target, "<span class='warning'>\The [src] leans in close, trembling with delight.</span>")
			approach = FALSE
		sleep(rand(3, 6))

/obj/effect/hallucination/simple/druggy/chaser
	name = "It"
	desc = "It isn't real. Probably."
	image_icon = 'icons/mob/alien.dmi'
	image_state = "alienh_pounce"
	var/chase_steps = 10

/obj/effect/hallucination/simple/druggy/chaser/Initialize(mapload, mob/living/carbon/T)
	col_mod = pick("#ff66ff", "#66ffff", "#ffff66", "#66ff66")
	. = ..()
	INVOKE_ASYNC(src, PROC_REF(chase))

/obj/effect/hallucination/simple/druggy/chaser/proc/chase()
	while(chase_steps-- > 0 && !QDELETED(src) && !QDELETED(target))
		var/turf/next = get_step_towards(src, target)
		if(!next)
			break
		forceMove(next)
		if(get_dist(src, target) <= 1)
			to_chat(target, "<span class='userdanger'>It reaches you, and comes apart into color.</span>")
			target.jitteriness += 5
			break
		sleep(rand(2, 4))
	QDEL_IN(src, 5)

/datum/reagent/drug/grape_blast/proc/PlaySpook(mob/living/carbon/C, soundfile, environment = 0, vary = TRUE, reverse = FALSE, slow = FALSE)
	var/sound/sound = sound(soundfile)
	sound.environment = environment //druggy
	sound.volume = rand(25,100)
	var/freq = 0
	if(slow)
		freq = rand(8000, 20000)
	else if(vary)
		freq = rand(10000,70000)
	if(reverse)
		freq = -(freq || 44100)
	if(freq)
		sound.frequency = freq
	SEND_SOUND(C.client, sound)
