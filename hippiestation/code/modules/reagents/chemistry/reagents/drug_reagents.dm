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
	var/bad_trip = FALSE
	var/badtrip_cooldown = 0
	var/burst_cooldown = 0
	var/tripping = FALSE //has the come up kicked in? this is what turns the trip's vision on and off
	var/cresting = FALSE //are we at the top of a wave right now?
	var/heard_intensity = 0 //how hard it's hitting, for what the tripper hears in between life ticks

//Everything the trip does to the eyes is done to the whole view at once (hippiestation/code/modules/trip_vision/trip_vision.dm):
//nothing in the world changes, for the tripper or anyone else
/datum/reagent/drug/grape_blast/proc/vision(mob/living/L)
	if(!L)
		return
	if(!L.trip_vision)
		L.trip_vision = new(L)
	return L.trip_vision

/datum/reagent/drug/grape_blast/on_mob_metabolize(mob/living/L)
	RegisterSignal(L, COMSIG_MOVABLE_MOVED, PROC_REF(on_moved), TRUE)
	RegisterSignal(L, COMSIG_MOVABLE_HEAR, PROC_REF(on_hear), TRUE)
	trip_preload(L) //the trip's art comes down while the drug comes up
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
	var/datum/trip_vision/V = vision(C)
	V.start()

//And settles again as the dose runs dry
/datum/reagent/drug/grape_blast/proc/settle_trip(mob/living/carbon/C)
	tripping = FALSE
	cresting = FALSE
	to_chat(C, "<span class='notice'>You drift back down towards the ground...</span>")
	C.trip_vision?.stop(5 SECONDS)

//How strongly the fractal over everything shows: it comes in with the trip, rolls with its waves, and a bad trip turns it right up
/datum/reagent/drug/grape_blast/proc/fractal_strength(intensity)
	. = clamp((intensity - 0.3) / 0.5, 0, 1) * 0.7
	if(bad_trip)
		. += 0.3

//The top of a wave, everything hits at the same moment
/datum/reagent/drug/grape_blast/proc/crest(mob/living/carbon/C, intensity)
	to_chat(C, "<span class='userdanger'>[pick("A wave of euphoria crashes over you!", "Everything surges at once!", "The colors PEAK!", "It's all coming up at you!")]</span>")
	var/power = 1 + round(intensity * 3)
	var/datum/trip_vision/V = vision(C)
	V.ripple(power)
	V.split(power)
	V.fisheye(power)
	if(intensity >= 0.9 || bad_trip) //the top of the biggest waves breaks through: the world goes, and only geometry is left
		to_chat(C, "<span class='userdanger'>[pick("Everything folds in on itself!", "The world comes apart into shapes!", "There's no room any more, only the pattern!")]</span>")
		V.breakthrough()
	else
		V.flare(1)
		V.flash(TRUE)
		if(power >= 3)
			V.spin()
		else
			V.tilt(power)
	V.wobble(power)
	burst_cooldown = world.time + 30

/datum/reagent/drug/grape_blast/on_mob_life(mob/living/carbon/H)
	if(!H)
		return
	if(!H.hud_used)
		return ..()
	var/intensity = get_intensity()
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

	heard_intensity = tripping ? intensity : 0
	if(tripping)
		var/datum/trip_vision/V = vision(H)
		V.update(intensity, bad_trip, fractal_strength(intensity)) //before a crest, which flares the fractal from here
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
		if(prob(round(10 + 35 * intensity)))
			V.melt(1 + round(intensity * 3))
			if(prob(15))
				to_chat(H, "<span class='notice'>You feel reality melt away...</span>")
		if(prob(round(5 + 30 * intensity)))
			V.breathe(1 + round(intensity * 2))
		if(prob(round(10 + 50 * intensity)))
			V.flash(intensity >= 0.8)
		if(prob(round(6 + 30 * intensity)))
			V.split(1 + round(intensity * 3))
		if(prob(round(5 + 25 * intensity)))
			V.fisheye(1 + round(intensity * 2))
		if(burst_cooldown < world.time && prob(round(15 + 60 * intensity)))
			psychedelic_burst(H, 1 + round(intensity * 3) + bad_trip)
		if(intensity >= 0.6)
			if(prob(5))
				V.mirror(rand(40, 100))
				to_chat(H, "<span class='warning'>Left is right. It always was.</span>")
			if(prob(6))
				V.tunnel(rand(40, 80))
		if(intensity >= 0.7)
			if(prob(8))
				V.spin()
			if(prob(6))
				V.rush(2)
			if(prob(4))
				V.turn_view(rand(30, 80))
		if(intensity >= 0.85 && prob(5))
			V.breakthrough()
		if(intensity >= 0.9 && prob(6))
			ego_death(H)
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
			high_message = pick("I can feel my thoughts racing!", "WHO THE FUCK SAID THAT??!!", "I feel like I'm going to die!")
			if(prob(35))
				V.melt(3)
			if(prob(25))
				V.split(3, 30) //everything doubled and shaking apart
			if(prob(8))
				V.rush(3)
			if(prob(4))
				V.turn_view(rand(20, 50))
			if(prob(35))
				V.flash(TRUE)
			if(prob(25))
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
				V.breathe(3) //the world thumps with it
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
	UnregisterSignal(L, list(COMSIG_MOVABLE_MOVED, COMSIG_MOVABLE_HEAR))
	heard_intensity = 0
	tripping = FALSE
	cresting = FALSE
	L.trip_vision?.stop(5 SECONDS)
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
	if(C.client)
		PlaySpook(C, 'hippiestation/sound/misc/honk_echo_distant.ogg', 0, FALSE)

//Moving smears the whole view the way you went
/datum/reagent/drug/grape_blast/proc/on_moved(atom/movable/source, atom/oldloc, dir)
	SIGNAL_HANDLER
	var/mob/living/L = source
	if(tripping && istype(L))
		L.trip_vision?.streak(dir)

//A random screen-wide effect, the higher the power the bigger it gets
/datum/reagent/drug/grape_blast/proc/psychedelic_burst(mob/living/carbon/C, power = 1)
	burst_cooldown = world.time + rand(15, 40)
	var/datum/trip_vision/V = vision(C)
	switch(rand(1, 7))
		if(1)
			V.ripple(power)
		if(2)
			V.radial(power)
		if(3)
			V.rays(power)
		if(4)
			V.bloom(power)
		if(5)
			V.wobble(power)
		if(6)
			V.fisheye(power)
		if(7)
			V.tunnel(20 + power * 10)
	if(power >= 3 && prob(50)) //at the deep end everything lands at once
		V.ripple(power)
		V.wobble(power)

//The deepest part of the trip
/datum/reagent/drug/grape_blast/proc/ego_death(mob/living/carbon/C)
	to_chat(C, "<span class='userdanger'>[pick("You are the colors. The colors are you.", "There is no one left to be scared.", "You dissolve into the grape.")]</span>")
	C.jitteriness += 10
	C.blur_eyes(5)
	C.playsound_local(C, 'sound/effects/singlebeat.ogg', 100, 0)
	var/datum/trip_vision/V = vision(C)
	V.white_out()
	addtimer(CALLBACK(V, TYPE_PROC_REF(/datum/trip_vision, breakthrough), 12 SECONDS), 5 SECONDS) //out of the white, nothing but the pattern

//What you hear comes out wrong: words stretch out, echo, or turn into something else. Not what you say yourself
/datum/reagent/drug/grape_blast/proc/on_hear(datum/source, list/hearing_args)
	SIGNAL_HANDLER
	if(!tripping || hearing_args[HEARING_SPEAKER] == source || !prob(15 + 45 * heard_intensity))
		return
	var/message = hearing_args[HEARING_MESSAGE]
	//the words said sit in the last pair of quotes, often in a span of their own: "<span class=' '>words</span>"
	var/close = findlasttext(message, "\"")
	if(close <= 1)
		return
	var/open = findlasttext(message, "\"", close - 1)
	if(!open)
		return
	var/said_from = open + 1
	var/said_to = close
	if(copytext(message, said_from, said_from + 6) == "<span ")
		said_from = findtext(message, ">", said_from, close) + 1
		if(said_from <= 1)
			return
		if(copytext(message, close - 7, close) == "</span>")
			said_to = close - 7
	var/said = copytext(message, said_from, said_to)
	if(!length(said) || findtext(said, "<"))
		return
	hearing_args[HEARING_MESSAGE] = copytext(message, 1, said_from) + trip_words(said) + copytext(message, said_to)

/datum/reagent/drug/grape_blast/proc/trip_words(said)
	var/list/words = splittext(said, " ")
	for(var/i in 1 to length(words))
		var/word = words[i]
		if(!length(word))
			continue
		var/roll = rand(1, 100) //most words come through as they were
		if(roll <= 12)
			words[i] = stretch_word(word)
		else if(roll <= 20)
			words[i] = "[word]... [lowertext(word)]... [lowertext(word)]..."
		else if(roll <= 28)
			words[i] = pick("grape", "colours", "forever", "melting", "you", "us", "always", "inside", "purple", "breathing", "nothing", "everything")
	return jointext(words, " ")

//Every vowel drawn out: "hello" heard as "heeeelloooo"
/datum/reagent/drug/grape_blast/proc/stretch_word(word)
	. = ""
	for(var/i in 1 to length(word))
		var/letter = copytext(word, i, i + 1)
		. += (findtext("aeiou", letter) ? "[letter][letter][letter][letter]" : letter)

//Replays short sounds you just heard, sometimes backwards and sometimes slowed down
/datum/reagent/drug/grape_blast/proc/echo_sounds(mob/living/carbon/C)
	for(var/sound/S in C.client.SoundQuery())
		if(S.len <= 3)
			PlaySpook(C, S.file, 23, TRUE, prob(50), prob(40))
			return

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
