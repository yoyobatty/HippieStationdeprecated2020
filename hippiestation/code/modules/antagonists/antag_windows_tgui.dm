// hippie -- the antagonists' old HTML windows in tgui (interfaces/AntagWindows.js): the malfunctioning AI's module picker, the arcane
// tome, the gang tool (boss, gangster and vigilante), the wizard's apprentice contract and teleportation scroll, the radioactive
// microlaser, the pirates' cargo hold console, and the role tips that pop up when you become a traitor, wizard, nuke op or abductor.
// Each button goes through what the old page's link did (the object's own Topic()), so costs, checks and bots stay the same.

// ---------------------------------------------------------------------------------------------
// The malfunctioning AI's module picker
// ---------------------------------------------------------------------------------------------

/datum/module_picker/use(mob/user)
	ui_interact(user)

/datum/module_picker/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "malf_modules", "Malf Module Menu", 620, 600, master_ui, state)
		ui.open()

/datum/module_picker/ui_status(mob/user, datum/ui_state/state)
	var/mob/living/silicon/ai/AI = user
	if(!isAI(AI) || AI.malf_picker != src)
		return UI_CLOSE
	return AI.stat == DEAD ? UI_DISABLED : UI_INTERACTIVE

/datum/module_picker/ui_data(mob/user)
	var/mob/living/silicon/ai/AI = user
	. = list()
	.["points"] = processing_time
	.["notice"] = temp ? comm_plain_text(temp) : null
	var/list/modules = list()
	for(var/datum/AI_Module/AM in possible_modules)
		var/uses
		if(isAI(AI) && AM.power_type && !AM.upgrade) // an upgrade's power_type is the base action, which any power matches
			var/datum/action/innate/ai/action = locate(AM.power_type) in AI.actions
			if(action)
				uses = action.uses
		modules += list(list("key" = AM.mod_pick_name, "name" = AM.module_name, "cost" = AM.cost, "desc" = comm_plain_text(AM.description), \
			"large" = istype(AM, /datum/AI_Module/large), "upgrade" = !!AM.upgrade, "owned" = !isnull(uses), "uses" = uses))
	.["modules"] = modules

/datum/module_picker/ui_act(action, list/params)
	if(..())
		return
	if(action == "buy")
		temp = null
		Topic(null, list("[params["key"]]" = "1"))
		return TRUE

// ---------------------------------------------------------------------------------------------
// The arcane tome
// ---------------------------------------------------------------------------------------------

/obj/item/tome/open_tome(mob/user)
	ui_interact(user)

/obj/item/tome/read_tome(mob/user)
	ui_interact(user)

/obj/item/tome/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.hands_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "arcane_tome", "Archives of the Dark One", 640, 620, master_ui, state)
		ui.open()

/obj/item/tome/ui_status(mob/user, datum/ui_state/state)
	if(!iscultist(user))
		return UI_CLOSE
	return ..()

/// read_tome()'s pages, by part: the runes, the talismans, the equipment and the constructs
/obj/item/tome/ui_static_data(mob/user)
	var/static/list/pages = list(
		list("part" = "Runes", "name" = "Create Talisman", "text" = "One of the most important runes the cult has, the only way to create new talismans. A blank sheet of paper must be on top of the rune. After invoking it and choosing which talisman you desire, the paper will be converted, after some delay, into a talisman."),
		list("part" = "Runes", "name" = "Teleport", "text" = "Needs a keyword before the scribing can begin. When invoked, it finds any other Teleport runes; the user chooses which to send to, and everything above this rune goes to the chosen one, if it isn't blocked."),
		list("part" = "Runes", "name" = "Offer", "need" = TRUE, "text" = "Placing a noncultist above it converts them if it can and sacrifices them otherwise. Two invokers to convert, three to sacrifice a living target or the sacrifice target. A conversion makes a tome for the new cultist and heals them. A sacrifice pleases the Geometer, can complete your objective if it was the sacrifice target, and tries to put the target into a soulstone."),
		list("part" = "Runes", "name" = "Raise Dead", "text" = "Needs the corpse of a cultist on the rune, and one person sacrificed for each revival. While revivals remain, invoking it revives the cultist on it."),
		list("part" = "Runes", "name" = "Electromagnetic Disruption", "text" = "A large electromagnetic pulse from the rune, growing a lot with each extra adjacent cultist when it is invoked. Robotic lifeforms have been the downfall of many a fledgling cult."),
		list("part" = "Runes", "name" = "Astral Communion", "text" = "Rips the user's spirit from their body to wander the station as a ghost and commune with the dead. The body stays locked to the rune, takes constant damage while you're out, and may die."),
		list("part" = "Runes", "name" = "Form Barrier", "text" = "Draws a little of the user's blood and makes the space above the rune impassable for about a minute and a half, spreading to nearby Barrier runes. Invoke it again to undo it."),
		list("part" = "Runes", "name" = "Summon Cultist", "text" = "Summons a single cultist to the rune from anywhere. Two invokers, each damaged slightly."),
		list("part" = "Runes", "name" = "Blood Boil", "text" = "Rapidly does a massive amount of damage to every non-cultist who can see it, then bursts into flame. Three invokers."),
		list("part" = "Runes", "name" = "Drain Life", "text" = "Drains the life of every living creature above the rune, healing the invoker for each one."),
		list("part" = "Runes", "name" = "Manifest Spirit", "text" = "Brings a spirit above the rune to life as a naked human fighter that serves you. Stay on the rune or the spirits dissipate, dropping their items; you take damage slowly, and quickly for each extra spirit."),
		list("part" = "Runes", "name" = "Summon Nar-Sie", "need" = TRUE, "text" = "Scribing it raises shields around you and warns the whole station; it takes a very long time and does massive damage to the scribe. Invoking it needs nine invokers and the sacrifice of a specific crewmember, and summons the Geometer herself. This completes your objectives."),
		list("part" = "Talismans", "name" = "Talisman of Teleportation", "text" = "Sends the invoker to a chosen Teleport rune, once."),
		list("part" = "Talismans", "name" = "Talisman of Construction", "text" = "Strike 25 sheets of metal with it to twist them into a construct shell. Used on plasteel, it makes runed metal."),
		list("part" = "Talismans", "name" = "Talisman of Tome Summoning", "text" = "Produces a single tome at your feet."),
		list("part" = "Talismans", "name" = "Talisman of Veiling/Revealing", "text" = "Hides runes on its first use and reveals them on the second."),
		list("part" = "Talismans", "name" = "Talisman of Disguising", "text" = "Permanently disguises all nearby runes as crayon runes."),
		list("part" = "Talismans", "name" = "Talisman of Electromagnetic Pulse", "text" = "EMPs anything else nearby. One use."),
		list("part" = "Talismans", "name" = "Talisman of Stunning", "text" = "Knocks a target down for a long time and stops their speech. Robots get a heavy EMP instead."),
		list("part" = "Talismans", "name" = "Talisman of Armaments", "text" = "Equips the user with armored robes, a backpack, an eldritch longsword, an empowered bola and boots. On a fellow cultist, equips them instead."),
		list("part" = "Talismans", "name" = "Talisman of Horrors", "text" = "Works at range without the victim noticing, and gives them severe hallucinations after a while."),
		list("part" = "Talismans", "name" = "Talisman of Shackling", "text" = "Applied to the victim directly: four uses, each cuffing them in magic shackles that vanish when removed."),
		list("part" = "Equipment", "name" = "Cult Blade", "text" = "A sharp weapon noncultists can't use. From the Talisman of Arming."),
		list("part" = "Equipment", "name" = "Cult Bola", "text" = "A strong bola for snaring targets. From the Talisman of Arming."),
		list("part" = "Equipment", "name" = "Cult Robes", "text" = "Heavily armored robes. From the Talisman of Arming."),
		list("part" = "Equipment", "name" = "Soulstone", "text" = "Made by the starter talisman or by sacrificing humans. Use it on an unconscious or dead human, or a Shade, to trap their soul for a construct shell; use it in hand to release the soul as a Shade."),
		list("part" = "Equipment", "name" = "Construct Shell", "text" = "Put a filled soulstone in it to make a Wraith, a Juggernaut or an Artificer. From the starter talisman or the Rite of Fabrication."),
		list("part" = "Constructs", "name" = "Shade", "text" = "Released from a soulstone. Fragile with weak attacks, but fully healed when recaptured."),
		list("part" = "Constructs", "name" = "Wraith", "text" = "A fast, lethal melee attacker that can jaunt through walls, only slightly tougher than a shade."),
		list("part" = "Constructs", "name" = "Juggernaut", "text" = "Slow but durable, makes temporary forcewalls and reflects most lethal energy weapons."),
		list("part" = "Constructs", "name" = "Artificer", "text" = "Weak and fragile. Heals constructs and shades, makes soulstones and construct shells, builds cult walls and floors, and fires a few stunning missiles."),
		list("part" = "Constructs", "name" = "Harvester", "text" = "If you see one, know that you have done all you can and your life is void."),
	)
	return list("pages" = pages)

/obj/item/tome/ui_act(action, list/params)
	if(..())
		return
	if(action == "scribe" && iscultist(usr))
		INVOKE_ASYNC(src, PROC_REF(scribe_rune), usr)
		return TRUE

// ---------------------------------------------------------------------------------------------
// The gang tool: the boss's (and a spare or a lieutenant's), a gangster's (Gangmageddon) and the vigilante's
// ---------------------------------------------------------------------------------------------

// The two subtypes have their own old pages in gangtool.dm, so ..() from here would reach those: each opens the window itself
/obj/item/gangtool/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	gangtool_open(user, ui_key, ui, force_open, master_ui, state)

/obj/item/gangtool/hell_march/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	gangtool_open(user, ui_key, ui, force_open, master_ui, state)

/obj/item/gangtool/hell_march/vigilante/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	gangtool_open(user, ui_key, ui, force_open, master_ui, state)

/obj/item/gangtool/proc/gangtool_open(mob/user, ui_key, datum/tgui/ui, force_open, datum/tgui/master_ui, datum/ui_state/state)
	if(!gangtool_mode(user))
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "gang_tool", gangtool_mode(user) == "vigilante" ? "Vigilante's Companion" : "GangTool", 420, 640, master_ui, state)
		ui.open()

/// Who's looking, as the old pages split them: "boss", "gangster", "vigilante", or null when the old page showed nothing
/obj/item/gangtool/proc/gangtool_mode(mob/user)
	if(!user?.mind)
		return null
	if(istype(src, /obj/item/gangtool/hell_march/vigilante))
		return user.mind.has_antag_datum(/datum/antagonist/gang) ? null : "vigilante"
	if(istype(src, /obj/item/gangtool/hell_march) && !user.mind.has_antag_datum(/datum/antagonist/gang/boss))
		return user.mind.has_antag_datum(/datum/antagonist/gang) ? "gangster" : null
	return "boss"

/obj/item/gangtool/ui_status(mob/user, datum/ui_state/state)
	if(!(src in user.contents) || user.incapacitated())
		return UI_CLOSE
	return UI_INTERACTIVE

/obj/item/gangtool/ui_data(mob/user)
	. = list()
	var/mode = gangtool_mode(user)
	.["mode"] = mode
	var/obj/item/gangtool/hell_march/HM = src
	var/marching = istype(HM)
	if(mode == "vigilante")
		.["influence"] = HM.points
	else if(!gang)
		.["registered"] = FALSE
		var/datum/antagonist/gang/boss/L = user.mind.has_antag_datum(/datum/antagonist/gang/boss)
		var/datum/antagonist/gang/G = user.mind.has_antag_datum(/datum/antagonist/gang)
		.["is_boss"] = !!L
		.["promotable"] = promotable
		.["promotion_open"] = G && G.gang && G.gang.leaders.len < G.gang.max_leaders
		return
	else
		.["registered"] = TRUE
		.["gang"] = gang.name
		.["color"] = gang.color
		.["members"] = gang.members.len
		.["territories"] = gang.territories.len
		.["influence"] = marching ? HM.points : gang.influence
		if(!marching)
			.["next_influence"] = time2text(gang.next_point_time - world.time, "mm:ss")
			.["can_recall"] = TRUE
			.["recalling"] = recalling
		if(gang.domination_time != NOT_DOMINATING)
			.["takeover"] = DisplayTimeText(gang.domination_time_remaining() * 10)
	var/list/cats = list()
	for(var/cat in buyable_items)
		var/list/items = list()
		for(var/id in buyable_items[cat])
			var/datum/gang_item/G = buyable_items[cat][id]
			if(!G.can_see(user, gang, src))
				continue
			items += list(list("id" = id, "name" = comm_plain_text(G.get_name_display(user, gang, src)), "cost" = comm_plain_text(G.get_cost_display(user, gang, src)), \
				"extra" = comm_plain_text(G.get_extra_info(user, gang, src)), "can_buy" = !!G.can_buy(user, gang, src)))
		if(length(items))
			cats += list(list("name" = cat, "items" = items))
	.["categories"] = cats

/obj/item/gangtool/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("register")
			Topic(null, list("register" = "1"))
		if("buy")
			Topic(null, list("purchase" = "1", "id" = params["id"], "cat" = params["cat"]))
		if("recall")
			Topic(null, list("recall" = "1"))
		if("destroy")
			Topic(null, list("destroy" = "1"))
		if("message")
			gangtool_ping(usr, "[params["text"]]")
	return TRUE

/// ping_gang() with the text from the window, not a prompt
/obj/item/gangtool/proc/gangtool_ping(mob/user, text)
	var/message = stripped_input_text(text)
	if(!message || !gang || !can_use(user))
		return
	if(!is_station_level(user.z))
		to_chat(user, "<span class='info'>[icon2html(src, user)]Error: Station out of range.</span>")
		return
	var/datum/antagonist/gang/G = user.mind.has_antag_datum(/datum/antagonist/gang)
	if(!G || !gang.members.len)
		return
	var/ping = "<span class='danger'><B><i>[gang.name] [G.message_name] [user.real_name]</i>: [message]</B></span>"
	for(var/datum/mind/ganger in gang.members)
		if(ganger.current && is_station_level(ganger.current.z) && (ganger.current.stat == CONSCIOUS))
			to_chat(ganger.current, ping)
	for(var/mob/M in GLOB.dead_mob_list)
		var/link = FOLLOW_LINK(M, user)
		to_chat(M, "[link] [ping]")
	user.log_talk(message, LOG_SAY, tag="[gang.name] gangster")

// ---------------------------------------------------------------------------------------------
// The wizard's apprentice contract
// ---------------------------------------------------------------------------------------------

/obj/item/antag_spawner/contract/attack_self(mob/user)
	user.set_machine(src)
	ui_interact(user)

/obj/item/antag_spawner/contract/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.hands_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "apprentice_contract", "Contract of Apprenticeship", 460, 470, master_ui, state)
		ui.open()

/obj/item/antag_spawner/contract/ui_data(mob/user)
	return list("used" = used, "waiting" = is_spawning, "schools" = list(
		list("id" = APPRENTICE_DESTRUCTION, "name" = "Destruction", "desc" = "Offensive magic: Magic Missile and Fireball."),
		list("id" = APPRENTICE_BLUESPACE, "name" = "Bluespace Manipulation", "desc" = "Defies physics, melting through solid objects and crossing great distances in a blink: Teleport and Ethereal Jaunt."),
		list("id" = APPRENTICE_HEALING, "name" = "Healing", "desc" = "Spells to keep you alive: Forcewall and Charge, and a Staff of Healing."),
		list("id" = APPRENTICE_ROBELESS, "name" = "Robeless", "desc" = "Casts without robes: Knock and Mindswap."),
	))

/obj/item/antag_spawner/contract/ui_act(action, list/params)
	if(..())
		return
	if(action == "school" && (params["id"] in list(APPRENTICE_DESTRUCTION, APPRENTICE_BLUESPACE, APPRENTICE_HEALING, APPRENTICE_ROBELESS)))
		// The poll waits for ghosts (15 s): not in the window's click
		INVOKE_ASYNC(src, PROC_REF(contract_pick), params["id"])
		return TRUE

/obj/item/antag_spawner/contract/proc/contract_pick(school)
	Topic(null, list("school" = school))
	SStgui.update_uis(src)

// ---------------------------------------------------------------------------------------------
// The scroll of teleportation
// ---------------------------------------------------------------------------------------------

/obj/item/teleportation_scroll/attack_self(mob/user)
	user.set_machine(src)
	ui_interact(user)

/obj/item/teleportation_scroll/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.hands_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "teleport_scroll", "Scroll of Teleportation", 420, 560, master_ui, state)
		ui.open()

/obj/item/teleportation_scroll/ui_static_data(mob/user)
	var/list/areas = list()
	for(var/name in GLOB.teleportlocs)
		areas += name
	return list("areas" = sortList(areas))

/obj/item/teleportation_scroll/ui_data(mob/user)
	return list("uses" = uses)

/obj/item/teleportation_scroll/ui_act(action, list/params)
	if(..())
		return
	var/mob/living/carbon/human/H = usr
	if(action == "teleport" && ishuman(H) && H.is_holding(src) && !H.restrained())
		scroll_teleport(H, "[params["area"]]")
		return TRUE

/// teleportscroll() (and hippie scrolls.dm's wait) with the area picked in the window, not a list prompt
/obj/item/teleportation_scroll/proc/scroll_teleport(mob/user, area_name)
	var/area/thearea = GLOB.teleportlocs[area_name]
	if(!thearea || !uses || user.incapacitated())
		return
	if(world.time < GLOB.telescroll_time) // hippie scrolls.dm's teleportscroll() gate: not before the round's wizards may go
		to_chat(user, "<span class='notice bold'>It's too soon to go. You need to wait [DisplayTimeText(GLOB.telescroll_time - world.time)] to go!</span>")
		return
	var/datum/effect_system/smoke_spread/smoke = new
	smoke.set_up(2, user.loc)
	smoke.attach(user)
	smoke.start()
	var/list/L = list()
	for(var/turf/T in get_area_turfs(thearea.type))
		if(!is_blocked_turf(T))
			L += T
	if(!L.len)
		to_chat(user, "The spell matrix was unable to locate a suitable teleport destination for an unknown reason. Sorry.")
		return
	if(do_teleport(user, pick(L), forceMove = TRUE, channel = TELEPORT_CHANNEL_MAGIC, forced = TRUE))
		smoke.start()
		uses--
	else
		to_chat(user, "The spell matrix was disrupted by something near the destination.")

// ---------------------------------------------------------------------------------------------
// The radioactive microlaser
// ---------------------------------------------------------------------------------------------

/obj/item/healthanalyzer/rad_laser/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.hands_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "rad_laser", "Radioactive Microlaser", 400, 300, master_ui, state)
		ui.open()

/obj/item/healthanalyzer/rad_laser/ui_data(mob/user)
	return list("irradiate" = !!irradiate, "stealth" = !!stealth, "scanmode" = scanmode, "intensity" = intensity, \
		"wavelength" = wavelength + intensity * 4, "cooldown" = DisplayTimeText(GetCooldown()), "cooling" = !!used)

/obj/item/healthanalyzer/rad_laser/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("irradiate")
			Topic(null, list("rad" = "1"))
		if("stealth")
			Topic(null, list("stealthy" = "1"))
		if("mode")
			Topic(null, list("mode" = "1"))
		if("intensity")
			Topic(null, list("radint" = "[text2num(params["by"])]"))
		if("wavelength")
			Topic(null, list("radwav" = "[text2num(params["by"])]"))
	return TRUE

// ---------------------------------------------------------------------------------------------
// The pirates' cargo hold console
// ---------------------------------------------------------------------------------------------

/obj/machinery/computer/piratepad_control/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "pirate_pad", name, 420, 440, master_ui, state)
		ui.open()

/obj/machinery/computer/piratepad_control/ui_data(mob/user)
	var/list/lines = list()
	for(var/line in splittext(comm_plain_text(status_report), "\n"))
		if(length(trim(line)))
			lines += trim(line)
	return list("points" = points, "pad" = !!pad, "sending" = sending, "report" = lines)

/obj/machinery/computer/piratepad_control/ui_act(action, list/params)
	if(..())
		return
	if(action in list("recalc", "send", "stop"))
		Topic(null, list("[action]" = "1"))
		return TRUE

// ---------------------------------------------------------------------------------------------
// The role tips (show_tips(), antag_datum.dm)
// ---------------------------------------------------------------------------------------------

/datum/antagonist/show_tips(file)
	if(!owner || !owner.current || !owner.current.client)
		return
	var/datum/asset/stuff = get_asset_datum(/datum/asset/simple/hippie_antags)
	stuff.send(owner.current.client)
	var/datum/antag_tips_window/W = new(owner.current, file2text(file), name)
	// Opening a window can sleep, and this runs in the middle of becoming an antagonist (Initialize() chains, the lint says)
	INVOKE_ASYNC(W, TYPE_PROC_REF(/datum/antag_tips_window, open_for), owner.current)

/datum/antag_tips_window
	var/datum/weakref/owner_ref
	var/html
	var/role

/datum/antag_tips_window/New(mob/owner, text, role_name)
	owner_ref = WEAKREF(owner)
	html = text
	role = role_name

/datum/antag_tips_window/proc/open_for(mob/user)
	ui_interact(user)

/datum/antag_tips_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "antag_tips", role || "Tips", 600, 520, master_ui, state)
		ui.open()

/datum/antag_tips_window/ui_status(mob/user, datum/ui_state/state)
	return user == owner_ref?.resolve() ? UI_INTERACTIVE : UI_CLOSE

/datum/antag_tips_window/ui_close(mob/user)
	qdel(src)

/datum/antag_tips_window/ui_static_data(mob/user)
	return list("html" = html, "role" = role)
