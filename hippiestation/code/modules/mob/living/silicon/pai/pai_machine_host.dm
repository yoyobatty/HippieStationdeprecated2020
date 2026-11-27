// pAIs can be slotted into everyday machines and run them, from Paradise (pai-machines, 2026-11-25).
// The card sits in a hidden port on the machine's tile, so cooking and fridge code never touch it. The pAI sees and talks
// through the machine, works its controls, and its face floats above it as a hologram in the colour of its mood. Machines
// with a screen big enough show the face on it; small ones project it up out of a lens. Alt-click the floating face to pull
// the card out. Here the screen face is a thing in the machine's vis_contents (tg's machines here have no overlays signal,
// and redraw by cutting their overlays), and the pAI works the machine with interact(), as if standing at it.

/// How high the hologram floats above the machine
#define PAI_HOLOGRAM_Y 20
/// How big the hologram face is next to the card screen
#define PAI_HOLOGRAM_SCALE 1.5
/// How long it takes to pull the card back out
#define PAI_MACHINE_EJECT_TIME (3 SECONDS)
/// How long it takes to slot the card in
#define PAI_MACHINE_LOAD_TIME (2 SECONDS)
/// How far the pAI's glow lights up the room
#define PAI_LIGHT_RANGE 3
/// How bright that glow is
#define PAI_LIGHT_POWER 1
/// The usual blue of a pAI
#define PAI_DEFAULT_MOOD "#66ccff"
/// Faces, screen covers and beams for machine screens
#define PAI_SCREEN_ICON 'hippiestation/icons/obj/pai_screen_faces.dmi'

/obj/machinery
	/// Can a pAI card be slotted in to run this machine?
	var/pai_slot = FALSE

/obj/machinery/vending
	pai_slot = TRUE
/obj/machinery/microwave
	pai_slot = TRUE
/obj/machinery/deepfryer
	pai_slot = TRUE
/obj/machinery/smartfridge
	pai_slot = TRUE
/obj/machinery/biogenerator
	pai_slot = TRUE
/obj/machinery/autolathe
	pai_slot = TRUE
/obj/machinery/rnd/production
	pai_slot = TRUE
/obj/machinery/computer/arcade
	pai_slot = TRUE
/obj/machinery/computer/slot_machine
	pai_slot = TRUE
/obj/machinery/jukebox
	pai_slot = TRUE

// ---- The card

/obj/item/paicard
	/// The face on its screen, 1 to 10 as setEmotion() takes them
	var/current_emotion = 1

/obj/item/paicard/setEmotion(emotion)
	. = ..()
	if(pai)
		current_emotion = emotion
		SEND_SIGNAL(src, COMSIG_PAICARD_EMOTION_CHANGED)

/// The card screen's sprite for the current face
/obj/item/paicard/proc/get_emotion_state()
	var/static/list/emotion_states = list("pai-happy", "pai-cat", "pai-extremely-happy", "pai-face", "pai-laugh", "pai-off", "pai-sad", "pai-angry", "pai-what", "pai-null")
	if(current_emotion < 1 || current_emotion > length(emotion_states))
		return "pai-happy"
	return emotion_states[current_emotion]

// Slotting the card into a machine, before the machine takes it as stock, an ingredient or a hit
/obj/item/paicard/pre_attack(atom/A, mob/living/user, params)
	var/obj/machinery/machine = A
	if(!istype(machine) || !machine.pai_slot || user.a_intent == INTENT_HARM)
		return ..()
	INVOKE_ASYNC(src, PROC_REF(load_into_machine), user, machine)
	return FALSE

/obj/item/paicard/proc/load_into_machine(mob/living/user, obj/machinery/machine)
	if(!pai || pai.stat == DEAD)
		to_chat(user, "<span class='warning'>[src] has no personality to load into [machine].</span>")
		return
	if(machine.GetComponent(/datum/component/pai_host))
		to_chat(user, "<span class='warning'>[machine] already has a pAI running it.</span>")
		return
	if(machine.stat & BROKEN)
		to_chat(user, "<span class='warning'>[machine] is broken.</span>")
		return
	user.visible_message("<span class='notice'>[user] starts slotting [src] into [machine].</span>", "<span class='notice'>You start slotting [src] into [machine]'s service port.</span>")
	if(!do_after(user, PAI_MACHINE_LOAD_TIME, target = machine))
		return
	if(QDELETED(machine) || !pai || pai.stat == DEAD || loc != user || machine.GetComponent(/datum/component/pai_host))
		return
	machine.AddComponent(/datum/component/pai_host, src, user)

// ---- The pAI

/// The machine we're running, if any
/mob/living/silicon/pai/proc/get_host_machine()
	var/obj/effect/abstract/pai_port/port = card?.loc
	if(istype(port))
		return port.host

/mob/living/silicon/pai/reset_perspective(atom/A)
	// Running a machine, we look out from it
	if(!A || A == loc || A == card)
		A = get_host_machine() || A
	return ..(A)

/mob/living/silicon/pai/ClickOn(atom/A, params)
	// Clicking the machine we run, or its face, works its controls
	var/obj/machinery/host = get_host_machine()
	if(host && (A == host || istype(A, /obj/effect/pai_hologram)))
		var/list/modifiers = params2list(params)
		if(!modifiers["shift"] && !modifiers["ctrl"] && !modifiers["alt"] && !modifiers["middle"])
			var/datum/component/pai_host/host_component = host.GetComponent(/datum/component/pai_host)
			host_component?.use_machine(src)
			return
	return ..()

// And its windows answer it as if it stood there
/mob/living/silicon/pai/default_can_use_topic(src_object)
	if(src_object && src_object == get_host_machine() && stat == CONSCIOUS)
		return shared_ui_interaction(src_object)
	return ..()

// ---- The port, the face and the screen

/// Holds the card on the machine's tile. Never seen or touched.
/obj/effect/abstract/pai_port
	name = "pAI port"
	invisibility = INVISIBILITY_ABSTRACT
	anchored = TRUE
	/// The machine this port belongs to
	var/obj/machinery/host
	/// The pAI running the machine
	var/datum/component/pai_host/owner

/obj/effect/abstract/pai_port/Destroy()
	host = null
	owner = null
	return ..()

/obj/effect/abstract/pai_port/HasProximity(atom/movable/AM)
	owner?.greet(AM)

/// The pAI's face, floating above the machine
/obj/effect/pai_hologram
	name = "pAI hologram"
	icon = 'icons/obj/aicards.dmi'
	icon_state = "pai-happy"
	layer = ABOVE_ALL_MOB_LAYER
	appearance_flags = KEEP_APART | PIXEL_SCALE
	vis_flags = VIS_INHERIT_PLANE
	pixel_y = PAI_HOLOGRAM_Y
	alpha = 0
	/// The pAI running the machine
	var/datum/component/pai_host/owner

/obj/effect/pai_hologram/Initialize(mapload)
	. = ..()
	transform = matrix(PAI_HOLOGRAM_SCALE, 0, 0, 0, PAI_HOLOGRAM_SCALE, 0)
	set_mood(PAI_DEFAULT_MOOD)

/obj/effect/pai_hologram/Destroy()
	owner = null
	return ..()

/// Alt-clicking the face pulls the pAI out, any other click goes to the machine
/obj/effect/pai_hologram/Click(location, control, params)
	var/list/modifiers = params2list(params)
	if(modifiers["alt"] || !owner)
		return ..()
	var/atom/host = owner.parent
	return host.Click(location, control, params)

/obj/effect/pai_hologram/DblClick(location, control, params)
	if(!owner)
		return ..()
	var/atom/host = owner.parent
	return host.DblClick(location, control, params)

/obj/effect/pai_hologram/AltClick(mob/user)
	owner?.try_pull_out(user)

/obj/effect/pai_hologram/examine(mob/user)
	if(owner)
		var/atom/host = owner.parent
		return host.examine(user)
	return ..()

/// Tints the face and its glow to the pAI's mood
/obj/effect/pai_hologram/proc/set_mood(mood)
	filters = list(
		filter(type = "drop_shadow", x = 0, y = 0, size = 1, color = "[mood]dd"),
		filter(type = "drop_shadow", x = 0, y = 0, size = 4, color = "[mood]66"),
	)
	if(mood == PAI_DEFAULT_MOOD)
		color = null
		return
	// Keep the face's light and dark, swap its blue for the mood
	var/list/rgb = rgb2num(mood)
	var/r = rgb[1] / 255 * 1.3
	var/g = rgb[2] / 255 * 1.3
	var/b = rgb[3] / 255 * 1.3
	color = list(0.3 * r, 0.3 * g, 0.3 * b, 0.59 * r, 0.59 * g, 0.59 * b, 0.11 * r, 0.11 * g, 0.11 * b)

/// Lets the face glow in the dark
/obj/effect/pai_hologram/proc/update_glow(glowing = TRUE)
	cut_overlays()
	if(glowing)
		add_overlay(emissive_glow(icon, icon_state))

/// The pAI on the machine's own screen, or a lens lit up on a small one. In the machine's vis_contents.
/obj/effect/pai_screen
	name = "pAI screen"
	icon = PAI_SCREEN_ICON
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	appearance_flags = KEEP_APART | PIXEL_SCALE
	vis_flags = VIS_INHERIT_PLANE | VIS_INHERIT_LAYER

/// Light from a small screen up to the hologram, for machines whose screen is too small for a face
/obj/effect/pai_beam
	name = "pAI projection"
	icon = PAI_SCREEN_ICON
	layer = ABOVE_ALL_MOB_LAYER - 0.01
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	appearance_flags = KEEP_APART | PIXEL_SCALE
	vis_flags = VIS_INHERIT_PLANE
	alpha = 0

/obj/effect/pai_beam/proc/update_glow(glowing = TRUE)
	cut_overlays()
	if(glowing)
		add_overlay(emissive_glow(icon, icon_state))

// ---- Running the machine

/datum/component/pai_host
	dupe_mode = COMPONENT_DUPE_UNIQUE
	/// The card running this machine
	var/obj/item/paicard/card
	/// Where the card sits
	var/obj/effect/abstract/pai_port/port
	/// The face above the machine
	var/obj/effect/pai_hologram/hologram
	/// The face on the machine's screen, or its lit lens
	var/obj/effect/pai_screen/screen_face
	/// The light from a small screen up to the face, if the machine has one
	var/obj/effect/pai_beam/beam
	/// The machine's name before the pAI moved in
	var/old_name
	/// The name we gave it, so we don't undo a rename someone did since
	var/hosted_name
	/// Was the vendor already quiet before we took over its speaker
	var/vendor_was_quiet
	/// The vendor's own "thanks for shopping" line, muted while we run it
	var/vendor_reply
	/// Is the machine powered, last we checked
	var/powered = TRUE
	/// What the pAI says when someone walks up
	var/greeting
	/// Watches for people walking up
	var/datum/proximity_monitor/greeter
	/// Who we greeted, by ref, and when we can greet them again
	var/list/greeted = list()
	COOLDOWN_DECLARE(greet_cooldown)
	/// The pAI's buttons for this machine
	var/list/datum/action/innate/pai_machine/actions = list()

/datum/component/pai_host/Initialize(obj/item/paicard/new_card, mob/user)
	if(!istype(parent, /obj/machinery) || !istype(new_card) || !new_card.pai)
		return COMPONENT_INCOMPATIBLE
	var/obj/machinery/host = parent
	var/mob/living/silicon/pai/pai = new_card.pai
	card = new_card

	port = new(get_turf(host))
	port.host = host
	port.owner = src
	if(ismob(card.loc))
		var/mob/holder = card.loc
		holder.dropItemToGround(card)
	card.forceMove(port)

	hologram = new
	hologram.owner = src
	host.vis_contents += hologram
	var/list/screen = get_screen()
	if(screen)
		screen_face = new
		host.vis_contents += screen_face
		// Small screens project the face up out of them
		if(screen[8])
			hologram.pixel_x = screen[9]
			beam = new
			beam.icon_state = screen[8]
			host.vis_contents += beam
	old_name = host.name
	hosted_name = "[host.name] ([pai.name])"
	host.name = hosted_name
	// The pAI is the voice now, so the vendor stops its ads and its thank yous
	if(istype(host, /obj/machinery/vending))
		var/obj/machinery/vending/vendor = host
		vendor_was_quiet = vendor.shut_up
		vendor.shut_up = TRUE
		vendor_reply = vendor.vend_reply
		vendor.vend_reply = null

	RegisterSignal(host, COMSIG_PARENT_EXAMINE, PROC_REF(on_examine))
	RegisterSignal(host, COMSIG_ATOM_EMP_ACT, PROC_REF(on_emp))
	RegisterSignal(host, COMSIG_MOVABLE_MOVED, PROC_REF(on_host_moved))
	RegisterSignal(card, COMSIG_MOVABLE_MOVED, PROC_REF(on_card_moved))
	RegisterSignal(card, COMSIG_PAICARD_EMOTION_CHANGED, PROC_REF(on_emotion_changed))
	RegisterSignal(pai, COMSIG_MOB_DEATH, PROC_REF(on_pai_death))
	RegisterSignal(pai, COMSIG_MOB_SAY, PROC_REF(on_pai_say))
	// Not every machine redraws when its power goes, so we check now and then
	START_PROCESSING(SSprocessing, src)

	for(var/action_type in subtypesof(/datum/action/innate/pai_machine))
		var/datum/action/innate/pai_machine/action = new action_type(card)
		action.host_component = src
		action.Grant(pai)
		actions += action
	var/datum/action/innate/pai_machine/use/use_button = locate() in actions
	use_button?.show_machine(host)

	pai.reset_perspective()
	log_combat(user, pai, "loaded into [host]")
	update_hologram()
	boot()

/datum/component/pai_host/Destroy(force, silent)
	var/obj/machinery/host = parent
	STOP_PROCESSING(SSprocessing, src)
	if(host.name == hosted_name)
		host.name = old_name
	if(istype(host, /obj/machinery/vending))
		var/obj/machinery/vending/vendor = host
		vendor.shut_up = vendor_was_quiet
		vendor.vend_reply = vendor_reply
	host.vis_contents -= hologram
	QDEL_NULL(hologram)
	if(screen_face)
		host.vis_contents -= screen_face
		QDEL_NULL(screen_face)
	if(beam)
		host.vis_contents -= beam
		QDEL_NULL(beam)
	QDEL_NULL(greeter)
	QDEL_LIST(actions)

	if(card)
		UnregisterSignal(card, list(COMSIG_MOVABLE_MOVED, COMSIG_PAICARD_EMOTION_CHANGED))
		var/mob/living/silicon/pai/pai = card.pai
		if(card.loc == port)
			card.forceMove(get_turf(port) || get_turf(host))
		if(pai)
			UnregisterSignal(pai, list(COMSIG_MOB_DEATH, COMSIG_MOB_SAY))
			pai.reset_perspective()
		card = null
	QDEL_NULL(port)
	return ..()

/// The sci-fi bit: the screen flickers, text races past and the face blinks on
/datum/component/pai_host/proc/boot()
	var/obj/machinery/host = parent
	var/mob/living/silicon/pai/pai = card.pai
	playsound(host, 'sound/machines/terminal_on.ogg', 40, TRUE)
	host.visible_message("<span class='notice'>[host]'s screen flickers. Lines of text race past, then a little face blinks into the air above it.</span>")
	to_chat(pai, "<span class='notice'><tt>&gt; handshake with [old_name]... ok<br>&gt; mapping control bus... ok<br>&gt; personality matrix loaded.</tt></span>")
	to_chat(pai, "<span class='notice'>[boot_flavour()] Use <b>Use Machine</b> or click it to work its controls, <b>Greeting</b> to welcome people and <b>Leave Machine</b> to pop back out.</span>")

	// Flicker on, like an old projector warming up
	animate(hologram, alpha = 170, time = 1)
	animate(alpha = 0, time = 1)
	animate(alpha = 220, time = 2)
	animate(alpha = 40, time = 1)
	animate(alpha = 210, time = 3)
	// Gentle bob while it's on
	animate(hologram, pixel_y = PAI_HOLOGRAM_Y + 2, time = 1.5 SECONDS, loop = -1, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
	animate(pixel_y = PAI_HOLOGRAM_Y, time = 1.5 SECONDS, easing = SINE_EASING)
	if(beam)
		animate(beam, alpha = 255, time = 1)
		animate(alpha = 0, time = 1)
		animate(alpha = 200, time = 3)
		// Projector shimmer
		animate(beam, alpha = 180, time = 0.8 SECONDS, loop = -1, delay = 1 SECONDS, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
		animate(alpha = 245, time = 0.8 SECONDS, easing = SINE_EASING)
	// The room light stutters on with it
	port.set_light(0)
	addtimer(CALLBACK(src, PROC_REF(update_light), 0.6), 1)
	addtimer(CALLBACK(src, PROC_REF(update_light), 0), 2)
	addtimer(CALLBACK(src, PROC_REF(update_light), 1.4), 4)
	addtimer(CALLBACK(src, PROC_REF(update_light)), 8)
	addtimer(CALLBACK(src, PROC_REF(boot_chime)), 1 SECONDS)
	update_power()

/datum/component/pai_host/proc/boot_chime()
	if(!QDELETED(parent))
		playsound(parent, 'sound/machines/chime.ogg', 30, TRUE)

/// A line about the machine the pAI just moved into
/datum/component/pai_host/proc/boot_flavour()
	var/obj/machinery/host = parent
	if(istype(host, /obj/machinery/vending))
		return "You settle in between the coils and the price list. The ad speaker is yours now."
	if(istype(host, /obj/machinery/microwave) || istype(host, /obj/machinery/deepfryer))
		return "Heating coils, a timer and a little bell. You feel oddly hungry."
	if(istype(host, /obj/machinery/smartfridge))
		return "Cold shelves hum around you. Everything here is labelled. You like that."
	if(istype(host, /obj/machinery/autolathe) || istype(host, /obj/machinery/rnd) || istype(host, /obj/machinery/biogenerator))
		return "Arms, nozzles and a hopper. You could make almost anything, given enough material."
	if(istype(host, /obj/machinery/computer/arcade) || istype(host, /obj/machinery/computer/slot_machine))
		return "Blinking lights and a high score table. You already want to beat it."
	if(istype(host, /obj/machinery/jukebox))
		return "Speakers, strobes and a bass line waiting to drop."
	return "You spread out through [old_name]'s circuits."

/datum/component/pai_host/proc/on_examine(datum/source, mob/user, list/examine_list)
	SIGNAL_HANDLER
	var/mob/living/silicon/pai/pai = card?.pai
	if(!pai)
		return
	examine_list += "<span class='notice'>[pai] is running it. [pai.p_their(TRUE)] face floats above the screen.</span>"
	examine_list += "<span class='notice'>Alt-click [pai.p_their()] face to take the pAI card out.</span>"

/datum/component/pai_host/proc/on_emotion_changed(obj/item/paicard/source)
	SIGNAL_HANDLER
	update_hologram()

/// The colour of the pAI's mood, from the face on its card
/datum/component/pai_host/proc/get_mood()
	// Same order as the card faces: happy, cat, very happy, plain, laugh, off, sad, angry, what, blank
	var/static/list/moods = list(PAI_DEFAULT_MOOD, "#ff8ad8", "#6dffd2", PAI_DEFAULT_MOOD, "#ffd84a", "#4f6fb0", "#5a78ff", "#ff4a3d", "#c7a0ff", PAI_DEFAULT_MOOD)
	var/emotion = card?.current_emotion
	if(!emotion || emotion < 1 || emotion > length(moods))
		return PAI_DEFAULT_MOOD
	return moods[emotion]

/// Face, screen, glow and room light to match the mood and the power
/datum/component/pai_host/proc/update_hologram()
	if(!hologram || !card)
		return
	var/mood = powered ? get_mood() : PAI_DEFAULT_MOOD
	hologram.icon_state = powered ? card.get_emotion_state() : "pai-off"
	hologram.set_mood(mood)
	hologram.update_glow(powered)
	hologram.alpha = powered ? 210 : 60
	if(beam)
		beam.color = mood
		beam.update_glow(powered)
		beam.invisibility = powered ? 0 : INVISIBILITY_ABSTRACT
	update_screen()
	update_light()

/// Lights the room around the machine in the pAI's mood. Boost makes it brighter for a moment.
/datum/component/pai_host/proc/update_light(boost = 1)
	if(!port)
		return
	if(!powered || !boost)
		port.set_light(0)
		return
	var/sleepy = card?.current_emotion == 6
	port.set_light(PAI_LIGHT_RANGE, (sleepy ? 0.4 : PAI_LIGHT_POWER) * boost, get_mood())

/// Little pulse when the pAI talks, so you can tell who's speaking
/datum/component/pai_host/proc/on_pai_say(datum/source, list/speech_args)
	SIGNAL_HANDLER
	if(!hologram || !powered)
		return
	animate(hologram, transform = matrix(PAI_HOLOGRAM_SCALE * 1.12, 0, 0, 0, PAI_HOLOGRAM_SCALE * 1.12, 0), time = 1, flags = ANIMATION_PARALLEL)
	animate(transform = matrix(PAI_HOLOGRAM_SCALE, 0, 0, 0, PAI_HOLOGRAM_SCALE, 0), time = 2)
	// And the light brightens with each word
	update_light(1.6)
	addtimer(CALLBACK(src, PROC_REF(update_light)), 4, TIMER_UNIQUE | TIMER_OVERRIDE)

/// Puts the pAI on the machine's own screen, where it has one
/datum/component/pai_host/proc/update_screen()
	if(!screen_face)
		return
	screen_face.cut_overlays()
	var/list/screen = get_screen()
	if(!powered || !card || !screen)
		screen_face.invisibility = INVISIBILITY_ABSTRACT
		return
	screen_face.invisibility = 0
	var/obj/machinery/host = parent
	// Small screens light up like a projector lens instead
	if(screen[8])
		var/lens_state = "lens_[screen[8]]"
		screen_face.icon_state = lens_state
		screen_face.color = get_mood()
		screen_face.add_overlay(emissive_glow(PAI_SCREEN_ICON, lens_state))
		return
	screen_face.icon_state = null
	screen_face.color = null
	if(screen[6])
		screen_face.add_overlay(mutable_appearance(PAI_SCREEN_ICON, screen[6], host.layer + 0.01))
	var/face_state = "face_[screen[3]]_[clamp(card.current_emotion, 1, 9)]"
	var/mutable_appearance/face = mutable_appearance(PAI_SCREEN_ICON, face_state, host.layer + 0.02)
	face.color = screen[7]
	face.pixel_x = screen[4]
	face.pixel_y = screen[5]
	screen_face.add_overlay(face)
	screen_face.add_overlay(emissive_glow(PAI_SCREEN_ICON, face_state, pixel_x = screen[4], pixel_y = screen[5]))

/// Where the pAI shows on this machine's screen, found by its sprite. Each entry: icon, sprite name start, face size, face x
/// and y offset, screen cover, face colour, and for screens too small for a face: the beam, and how far across the hologram
/// moves to sit over it.
/datum/component/pai_host/proc/get_screen()
	var/static/list/screens = list(
		list('icons/obj/computer.dmi', "arcade", "large", 1, 1, "bg_arcade", "#6dff5f", null, 0),
		list('icons/obj/machines/biogenerator.dmi', "biogen", "large", -5, 1, "bg_biogenerator", "#8ff0ff", null, 0),
		list('icons/obj/kitchen.dmi', "mw", "large", -5, -3, null, "#a8ecff", null, 0),
		list('icons/obj/vending.dmi', "smartfridge", null, 0, 0, null, null, "smartfridge", 7),
		list('icons/obj/stationobjs.dmi', "autolathe", null, 0, 0, null, null, "autolathe", -1),
		list('icons/obj/machines/research.dmi', "protolathe", null, 0, 0, null, null, "protolathe", 7),
	)
	var/obj/machinery/host = parent
	for(var/list/screen as anything in screens)
		if(host.icon == screen[1] && findtext(host.icon_state, screen[2]) == 1)
			return screen

/datum/component/pai_host/process()
	update_power()

/datum/component/pai_host/proc/update_power()
	var/obj/machinery/host = parent
	var/now_powered = host.is_operational()
	if(now_powered == powered || !hologram)
		return
	powered = now_powered
	update_hologram()
	var/mob/living/silicon/pai/pai = card?.pai
	if(pai)
		to_chat(pai, powered ? "<span class='notice'>Power flows back into [host]. You blink back on.</span>" : "<span class='warning'>[host] loses power. You can still talk, but its controls are dead.</span>")

/datum/component/pai_host/proc/on_host_moved(datum/source)
	SIGNAL_HANDLER
	port.forceMove(get_turf(parent))

/datum/component/pai_host/proc/on_card_moved(datum/source)
	SIGNAL_HANDLER
	// The card left some other way, like the pAI unfolding
	if(card.loc != port)
		qdel(src)

/datum/component/pai_host/proc/on_pai_death(datum/source)
	SIGNAL_HANDLER
	eject()

/datum/component/pai_host/proc/on_emp(datum/source, severity)
	SIGNAL_HANDLER
	var/obj/machinery/host = parent
	var/obj/item/paicard/old_card = card
	host.visible_message("<span class='warning'>[old_card] shoots out of [host] in a shower of sparks!</span>")
	eject(quiet = TRUE)
	old_card.emp_act(severity)

/datum/component/pai_host/proc/try_pull_out(mob/living/user)
	var/obj/machinery/host = parent
	if(!isliving(user) || user == card?.pai || user.incapacitated() || !user.Adjacent(host))
		return
	to_chat(user, "<span class='notice'>You start pulling [card] out of [host]...</span>")
	if(!do_after(user, PAI_MACHINE_EJECT_TIME, target = host) || QDELETED(src) || !card)
		return
	user.visible_message("<span class='notice'>[user] pulls [card] out of [host].</span>", "<span class='notice'>You pull [card] out of [host].</span>")
	log_combat(user, card.pai, "pulled out of [host]")
	eject(quiet = TRUE)

/// Pops the card back out onto the floor
/datum/component/pai_host/proc/eject(quiet = FALSE)
	var/obj/machinery/host = parent
	if(!quiet)
		host.visible_message("<span class='notice'>The face above [host] blinks out and [card] slides out of its port.</span>")
	playsound(host, 'sound/machines/terminal_off.ogg', 40, TRUE)
	if(card?.pai)
		to_chat(card.pai, "<span class='notice'>You fold yourself back into your card.</span>")
	qdel(src)

/// The pAI pressing the machine's buttons, like someone standing at it
/datum/component/pai_host/proc/use_machine(mob/living/silicon/pai/pai)
	var/obj/machinery/host = parent
	if(pai.stat != CONSCIOUS)
		return
	if(!host.is_operational())
		to_chat(pai, "<span class='warning'>[host] has no power. Its controls won't answer.</span>")
		return
	host.interact(pai)

/datum/component/pai_host/proc/set_greeting(mob/living/silicon/pai/pai)
	var/new_greeting = tgui_input_text(pai, "What do you say when someone walks up? $name becomes their name. Leave it empty to stay quiet.", "Greeting", greeting, 100)
	if(QDELETED(src) || isnull(new_greeting))
		return
	greeting = new_greeting
	if(!length(greeting))
		greeting = null
		QDEL_NULL(greeter)
		to_chat(pai, "<span class='notice'>You won't greet anyone.</span>")
		return
	if(!greeter)
		greeter = new(port, 1)
	to_chat(pai, "<span class='notice'>You'll greet people with: \"[greeting]\"</span>")

/// Someone walked up, say hi if we haven't lately
/datum/component/pai_host/proc/greet(atom/movable/AM)
	if(!greeting || !ishuman(AM))
		return
	var/mob/living/carbon/human/visitor = AM
	if(!visitor.client || visitor.stat != CONSCIOUS)
		return
	var/mob/living/silicon/pai/pai = card?.pai
	if(!pai?.client || pai.stat != CONSCIOUS || pai.silent || !powered)
		return
	if(!COOLDOWN_FINISHED(src, greet_cooldown))
		return
	var/visitor_id = REF(visitor)
	if(greeted[visitor_id] > world.time)
		return
	greeted[visitor_id] = world.time + 3 MINUTES
	COOLDOWN_START(src, greet_cooldown, 10 SECONDS)
	INVOKE_ASYNC(pai, TYPE_PROC_REF(/atom/movable, say), replacetext(greeting, "$name", visitor.name))

// The pAI's buttons while it runs a machine
/datum/action/innate/pai_machine
	background_icon_state = "bg_tech_blue"
	icon_icon = 'icons/obj/aicards.dmi'
	/// The machine we're in
	var/datum/component/pai_host/host_component

/datum/action/innate/pai_machine/Destroy()
	host_component = null
	return ..()

/datum/action/innate/pai_machine/use
	name = "Use Machine"
	desc = "Work the controls of the machine you're running."

/// Shows the machine itself on the button
/datum/action/innate/pai_machine/use/proc/show_machine(obj/machinery/host)
	icon_icon = host.icon
	button_icon_state = host.icon_state
	UpdateButtonIcon()

/datum/action/innate/pai_machine/use/Activate()
	host_component?.use_machine(owner)

/datum/action/innate/pai_machine/greeting
	name = "Greeting"
	desc = "Set what you say when someone walks up to your machine."
	button_icon_state = "pai-laugh"

/datum/action/innate/pai_machine/greeting/Activate()
	INVOKE_ASYNC(host_component, TYPE_PROC_REF(/datum/component/pai_host, set_greeting), owner)

/datum/action/innate/pai_machine/leave
	name = "Leave Machine"
	desc = "Fold back into your card and pop out of the machine."
	icon_icon = 'icons/mob/actions/actions_spells.dmi'
	button_icon_state = "exit_possession"

/datum/action/innate/pai_machine/leave/Activate()
	host_component?.eject()

#undef PAI_HOLOGRAM_Y
#undef PAI_HOLOGRAM_SCALE
#undef PAI_MACHINE_EJECT_TIME
#undef PAI_MACHINE_LOAD_TIME
#undef PAI_LIGHT_RANGE
#undef PAI_LIGHT_POWER
#undef PAI_DEFAULT_MOOD
#undef PAI_SCREEN_ICON
