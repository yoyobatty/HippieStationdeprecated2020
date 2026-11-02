// How many times each person hears one radio message, on the real station with real telecomms. Not part of the game:
// HARNESS=say_check.dm tools/power_check/run.sh <label>

/datum/controller/master
	sleep_offline_after_initializations = FALSE

GLOBAL_LIST_EMPTY(sc_radio_heard)
GLOBAL_LIST_EMPTY(sc_local_heard)

/proc/uc_log(text)
	text2file(text, "data/update_check.txt")

/world/New()
	. = ..()
	spawn(0)
		say_check_run()

/mob/living/carbon/human/Hear(message, atom/movable/speaker, message_language, raw_message, radio_freq, list/spans, message_mode)
	if(radio_freq)
		GLOB.sc_radio_heard[src] += 1
	else
		GLOB.sc_local_heard[src] += 1
	return ..()

/proc/sc_person(turf/where, name)
	var/mob/living/carbon/human/H = new(where)
	H.real_name = name
	H.name = name
	H.status_flags |= GODMODE
	var/obj/item/radio/headset/headset = new(H)
	H.equip_to_slot_or_del(headset, ITEM_SLOT_EARS)
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), ITEM_SLOT_ICLOTHING)
	return H

/proc/sc_hallway_turfs()
	. = list()
	for(var/turf/open/floor/T in GLOB.the_station_areas ? get_area_turfs(/area/hallway/primary/central) : list())
		if(!is_blocked_turf(T, TRUE))
			. += T

/proc/sc_report(label, list/people, say_what, mob/living/carbon/human/speaker)
	GLOB.sc_radio_heard.Cut()
	GLOB.sc_local_heard.Cut()
	speaker.say(say_what)
	sleep(4 SECONDS)
	var/list/parts = list()
	for(var/mob/living/carbon/human/H in people)
		parts += "[H.name] radio [GLOB.sc_radio_heard[H] + 0], nearby [GLOB.sc_local_heard[H] + 0]"
	uc_log("[label]: [jointext(parts, " | ")]")

/proc/say_check_run()
	UNTIL(SSticker.initialized) // it reads data/mode.txt when it starts up
	GLOB.master_mode = "extended" // data/mode.txt is whatever the last real round left there, and most modes won't start with nobody playing
	SSticker.start_immediately = TRUE
	var/deadline = world.time + 5 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
		sleep(1 SECONDS)
	sleep(10 SECONDS)
	var/list/spots = sc_hallway_turfs()
	if(length(spots) < 30)
		uc_log("only [length(spots)] hallway tiles")
		uc_log("done")
		del(world)
		return
	var/turf/first = spots[1]
	var/turf/far = spots[length(spots)]
	uc_log("round state [SSticker.current_state], speaker at [first.x],[first.y], listener at [far.x],[far.y], [get_dist(first, far)] tiles apart")
	var/mob/living/carbon/human/speaker = sc_person(first, "Speaker")
	var/mob/living/carbon/human/listener = sc_person(far, "Listener")
	var/list/people = list(speaker, listener)
	sleep(2 SECONDS)

	// A plain list of the same thing twice, for the rule itself
	var/list/combined = list(1)
	combined |= list(2, 2)
	uc_log("rule: list(1) |= list(2, 2) gives [length(combined)] items")
	var/list/one_headset = get_hearers_in_view(0, listener.ears)
	var/times = 0
	for(var/thing in one_headset)
		if(thing == listener)
			times++
	uc_log("get_hearers_in_view(0, headset): listener is in the list [times] times, list is [length(one_headset)] long")
	var/list/from_radio = get_mobs_in_radio_ranges(list(listener.ears))
	times = 0
	for(var/thing in from_radio)
		if(thing == listener)
			times++
	uc_log("get_mobs_in_radio_ranges(that headset): listener is in the list [times] times")

	sc_report("headset to headset", people, ";radio check one", speaker)

	var/obj/item/radio/intercom/com = new(get_step(far, NORTH))
	com.listening = TRUE
	com.on = TRUE
	sc_report("listener beside an intercom too", people, ";radio check two", speaker)
	qdel(com)

	var/obj/item/radio/off/held = new(listener)
	listener.put_in_hands(held)
	held.on = TRUE
	held.listening = TRUE
	sc_report("listener holding a radio too", people, ";radio check three", speaker)
	qdel(held)

	sc_report("just talking, for comparison", people, "nothing on the radio", speaker)

	var/mob/living/carbon/human/nearby = sc_person(get_step(first, EAST), "Neighbour")
	people += nearby
	sleep(1 SECONDS)
	sc_report("someone standing next to the speaker", people, ";radio check four", speaker)

	// Things that aren't directly on a tile
	var/obj/structure/closet/locker = new(get_step(first, WEST))
	var/mob/living/carbon/human/hidden = sc_person(get_step(first, NORTH), "In a locker")
	hidden.forceMove(locker)
	people += hidden
	var/obj/item/taperecorder/held_recorder = new(speaker)
	speaker.put_in_hands(held_recorder)
	held_recorder.recording = TRUE
	if(!held_recorder.mytape)
		held_recorder.mytape = new /obj/item/tape(held_recorder)
	var/lines_before = length(held_recorder.mytape.storedinfo)
	sleep(1 SECONDS)
	sc_report("someone in a locker next to the speaker", people, "can you hear me in there", speaker)
	uc_log("recorder held by the speaker: [length(held_recorder.mytape.storedinfo) - lines_before] lines recorded")
	uc_log("done")
	sleep(5)
	del(world)
