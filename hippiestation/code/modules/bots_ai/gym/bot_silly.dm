// Silly bots: crew who do whatever comes into their heads, through the same procs a player's clicks go through, to see what breaks. The user
// asked for bots to be silly and break the game so it could be fixed. A Bot Shift booted with bot-silly=<how many> turns that many of the
// crew loose a little way in. Everything that goes wrong lands in runtime.log as usual, and silly.log says what the bot was up to at the time.
// Read a batch with tools/bot_gym/silly_report.py. Not part of the game.
//
// Each of them clicks whatever's next to it, with whatever's in its hand, on any intent, with any modifier. It drags things on to other
// things, works machines' buttons, uses what it's carrying on itself, throws it about, grabs people and walks off with them. Now and then it
// finds something in its hand that it had no business having. Every minute it's put right and moved somewhere else: dead, cuffed or stuck, it
// tests nothing, and walking would keep it in one room.

/// How often a silly bot gets patched up and moved along.
#define BOT_SILLY_RESET (1 MINUTES)

GLOBAL_VAR(bot_silly_log)
GLOBAL_LIST_EMPTY(bot_silly_bots)
/// Everything a player's hand could end up holding, near enough.
GLOBAL_LIST_EMPTY(bot_silly_items)
/// The buttons machines tend to have. Most of them mean nothing to any given machine, which is a test as well.
GLOBAL_LIST_INIT(bot_silly_buttons, list("vend", "eject", "eject_beaker", "ejectBeaker", "toggle", "power", "on", "off", "open", "close", "print", "lock", "unlock", "select", "dispense",
	"purge", "sync", "mode", "reset", "scan", "start", "stop", "set", "change", "remove", "add", "release", "pressure", "valve", "set_pressure", "transfer", "input", "output", "amount",
	"pump", "direction", "refill", "clone", "inject", "door", "lockdown", "send", "request", "buy", "login", "logout", "toggle_filter", "filter", "scrubbing", "panic_siphon", "alarm", "reset_alarm"))
GLOBAL_LIST_INIT(bot_silly_values, list("1", "0", "-1", "100", "99999", "-99999", "max", "min", "input", "on", "off", "true", "", "[0x0]", "nonsense", "1e30", "NaN"))

/proc/bot_silly_start(count)
	GLOB.bot_silly_log = "[GLOB.log_directory]/silly.log"
	for(var/path in typesof(/obj/item))
		var/obj/item/I = path
		if((initial(I.item_flags) & ABSTRACT) || !initial(I.name) || !initial(I.icon_state) || findtext("[path]", "/cyborg")) //a cyborg's stacks need a cyborg
			continue
		if(path == /obj/item/gun/magic || path == /obj/item/slimecross/recurring || path == /obj/item/gangtool/hell_march || ispath(path, /obj/item/paper/contract/infernal))
			continue //parents and things that can't exist on their own
		GLOB.bot_silly_items += path
	var/list/crew = GLOB.bot_crew_members.Copy()
	shuffle_inplace(crew)
	for(var/mob/living/carbon/human/H as anything in crew)
		if(count-- <= 0)
			break
		GLOB.bot_silly_bots += new /datum/bot_silly(H)
	WRITE_LOG(GLOB.bot_silly_log, "[length(GLOB.bot_silly_bots)] silly bots, [length(GLOB.bot_silly_items)] items to find in their hands")

/datum/bot_silly
	var/mob/living/carbon/human/H
	/// What it's up to, for silly.log.
	var/doing
	var/next_reset = 0

/datum/bot_silly/New(mob/living/carbon/human/who)
	. = ..()
	H = who
	next_reset = world.time + BOT_SILLY_RESET
	loop()

/datum/bot_silly/proc/loop()
	set waitfor = FALSE
	while(!QDELETED(H))
		sleep(rand(2, 10))
		try
			if(world.time >= next_reset)
				put_right()
			act()
		catch(var/exception/e)
			WRITE_LOG(GLOB.bot_silly_log, "[e.file]:[e.line] [e.name] | [H?.real_name] [doing] | [e.desc]")
	H = null

/// Whatever happened to it, it's on its feet again somewhere else.
/datum/bot_silly/proc/put_right()
	next_reset = world.time + BOT_SILLY_RESET
	doing = "being put right"
	if(H.stat == DEAD || H.health < 30)
		H.revive(full_heal = TRUE, admin_revive = TRUE)
	if(H.handcuffed)
		QDEL_NULL(H.handcuffed)
		H.update_handcuffed()
	if(H.legcuffed)
		QDEL_NULL(H.legcuffed)
		H.update_inv_legcuffed()
	if(H.buckled)
		H.buckled.unbuckle_mob(H, force = TRUE)
	H.SetAllImmobility(0)
	var/turf/T = H.bot_brain?.pick_poi_destination()
	if(T && !QDELETED(T))
		H.forceMove(T)

/datum/bot_silly/proc/something_nearby()
	var/list/things = list()
	for(var/atom/A in range(1, H))
		if(!QDELETED(A) && A != H && !isarea(A) && !istype(A, /atom/movable/lighting_object))
			things += A
	for(var/obj/item/I in H.get_equipped_items(TRUE))
		things += I
	return length(things) ? pick(things) : null

/datum/bot_silly/proc/ready()
	H.next_click = 0
	H.next_move = 0
	H.a_intent = pick(INTENT_HELP, INTENT_DISARM, INTENT_GRAB, INTENT_HARM)
	H.zone_selected = pick(BODY_ZONE_HEAD, BODY_ZONE_CHEST, BODY_ZONE_L_ARM, BODY_ZONE_R_ARM, BODY_ZONE_L_LEG, BODY_ZONE_R_LEG, BODY_ZONE_PRECISE_EYES, BODY_ZONE_PRECISE_MOUTH, BODY_ZONE_PRECISE_GROIN)

/datum/bot_silly/proc/act()
	if(H.stat == DEAD)
		return
	ready()
	usr = H //a click's usr, for everything it calls. It doesn't come back up out of a helper
	switch(pickweight(list("click" = 40, "modifier" = 12, "drag" = 10, "button" = 16, "self" = 10, "grab" = 4, "throw" = 5, "drop" = 3, "swap" = 4, "walk" = 8, "find" = 3, "resist" = 2)))
		if("click")
			var/atom/A = something_nearby()
			if(A)
				doing = "clicking [A] ([A.type]) with [H.get_active_held_item()] on [H.a_intent]"
				H.ClickOn(A, "icon-x=[rand(1, 32)];icon-y=[rand(1, 32)]")
		if("modifier")
			var/atom/A = something_nearby()
			if(A)
				// Shift and Alt on their own read the client, and a bot hasn't got one: what they lead to is called straight
				var/mods = pick("ctrl=1", "middle=1", "shift=1;ctrl=1", "right=1", "alt", "altclick")
				doing = "[mods] on [A] ([A.type]) with [H.get_active_held_item()]"
				if(mods == "alt" || mods == "altclick")
					if(!isturf(A)) //a turf's opens the statpanel
						A.AltClick(H)
				else
					H.ClickOn(A, mods)
		if("drag")
			var/atom/from = something_nearby()
			var/atom/over = pick(something_nearby(), H, get_turf(H))
			if(from && over)
				doing = "dragging [from] ([from.type]) on to [over] ([over.type])"
				over.MouseDrop_T(from, H) //the half of a drag that isn't about the client
		if("button")
			press_a_button()
		if("self")
			var/obj/item/I = H.get_active_held_item()
			if(I)
				doing = "using [I] ([I.type]) on itself"
				I.attack_self(H)
		if("grab")
			var/mob/living/L = locate() in range(1, H)
			if(L && L != H)
				doing = "grabbing [L] ([L.type])"
				H.grab_state = pick(GRAB_PASSIVE, GRAB_AGGRESSIVE)
				H.start_pulling(L, H.grab_state)
		if("throw")
			var/obj/item/I = H.get_active_held_item()
			var/atom/A = pick(view(5, H))
			if(I && A)
				doing = "throwing [I] ([I.type]) at [A] ([A.type])"
				H.throw_mode_on()
				H.throw_item(A)
		if("drop")
			doing = "dropping what it's holding"
			H.dropItemToGround(H.get_active_held_item())
		if("swap")
			doing = "swapping hands"
			H.swap_hand()
		if("walk")
			doing = "walking"
			step(H, pick(GLOB.alldirs))
		if("find")
			var/path = pick(GLOB.bot_silly_items)
			doing = "finding a [path] in its hand"
			var/obj/item/I = new path(H.loc)
			if(!QDELETED(I))
				H.put_in_hands(I)
		if("resist")
			doing = "resisting"
			H.resist()

/// The way a click on a tgui window gets there: Topic() on the window, with whatever the button might have said.
/datum/bot_silly/proc/press_a_button()
	var/obj/machinery/M = locate() in range(1, H)
	if(!M)
		return
	var/action = pick(GLOB.bot_silly_buttons)
	var/list/href = list("action" = action)
	for(var/key in list("ref", "amount", "id", "name", "item", "target", "value", "type", "tag", "pressure", "rate", "to"))
		if(prob(25))
			href[key] = pick(GLOB.bot_silly_values)
	doing = "pressing [action] on [M] ([M.type]) with [json_encode(href)]"
	var/datum/tgui/ui = new(H, M, "main", "generic", "silly", 100, 100, null, GLOB.always_state)
	ui.Topic("", href)
	if(!QDELETED(ui))
		qdel(ui)

#undef BOT_SILLY_RESET
