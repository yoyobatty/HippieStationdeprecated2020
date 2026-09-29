// Screentips, after tg: hovering over something shows its name at the top of the screen, and - when it's within reach -
// what clicking it would do with what's in your active hand: "LMB: Pry open", "Alt-LMB: Remove tank".
//
// Things say what happens to them in add_context() (a table, with a wrench in hand: "Deconstruct"). Items that do their
// own thing to whatever they're used on say so in add_item_context() (a health analyzer on a person: "Scan"). The target
// gets the first say, as it does in the attack chain, and a couple of generic cases fill in whatever's left (picking an
// item up, what an empty hand does to a person on each intent). A tip must describe what the click really does: when a
// case isn't certain, leave it out rather than guess. See screentip_contexts.dm for the objects that give tips.
//
// Players can switch them off in the game preferences (SCREENTIPS_DISABLED).

/obj/screen/screentip
	icon = null
	icon_state = null
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	screen_loc = "LEFT,TOP-1"
	maptext_height = 64 // the top two tiles of the view; the text hangs from the top edge
	maptext_y = -4
	maptext_width = 480
	layer = ABOVE_HUD_LAYER
	plane = ABOVE_HUD_PLANE

/// Shows a tip: the name, then the clicks that would do something, or nothing at all for an empty title
/obj/screen/screentip/proc/show(client/C, title, list/context)
	if(!title)
		maptext = ""
		return
	var/list/clicks = list()
	for(var/key in list(SCREENTIP_LMB, SCREENTIP_ALT_LMB, SCREENTIP_CTRL_LMB))
		if(context[key])
			clicks += "<font color='#9fd3ff'>[key]:</font> [context[key]]"
	var/list/view_size = getviewsize(C.view)
	maptext_width = view_size[1] * world.icon_size
	maptext = "<div style=\"text-align: center; font-family: 'Verdana'; font-size: 7pt; color: #ffffff; -dm-text-outline: 1px #000000;\"><b>[title]</b>[length(clicks) ? "<br>[clicks.Join(" &nbsp;|&nbsp; ")]" : ""]</div>"

/datum/hud
	var/obj/screen/screentip/screentip_text

/datum/hud/New(mob/owner)
	. = ..()
	screentip_text = new
	infodisplay += screentip_text // shown with the rest of the HUD, freed with it in Destroy()

/client
	/// What this client's mouse was last over, so the tip can be redrawn when their hands or intent change
	var/datum/weakref/screentip_hover

/atom/MouseEntered(location, control, params)
	. = ..()
	var/client/C = usr?.client
	if(!C)
		return
	C.screentip_hover = WEAKREF(src)
	update_screentip(C)

/// Works out and shows the screentip for this client's mouse being over src
/atom/proc/update_screentip(client/C)
	var/mob/user = C.mob
	var/obj/screen/screentip/tip = user?.hud_used?.screentip_text
	if(!tip)
		return
	if((C.prefs.hippie_toggles & SCREENTIPS_DISABLED) || istype(src, /obj/screen))
		tip.show(C, null)
		return
	var/list/context = list()
	if(isliving(user) && !user.incapacitated() && user.CanReach(src, user.get_active_held_item()))
		gather_screentip_context(context, user)
	tip.show(C, html_encode(format_text(name)), context)

/// Redraws the tip for whatever this mob's mouse is over, after something that changes what a click would do
/mob/proc/refresh_screentip()
	var/atom/hovered = client?.screentip_hover?.resolve()
	if(hovered)
		hovered.update_screentip(client)

/// Fills context with what each click on src would do for user
/atom/proc/gather_screentip_context(list/context, mob/living/user)
	var/obj/item/held_item = user.get_active_held_item()
	add_context(src, context, held_item, user)
	if(held_item)
		var/list/item_context = list()
		held_item.add_item_context(held_item, item_context, src, user)
		for(var/key in item_context)
			if(!context[key])
				context[key] = item_context[key]
	if(!context[SCREENTIP_LMB])
		var/generic = generic_screentip(held_item, user)
		if(generic)
			context[SCREENTIP_LMB] = generic

/// What happens to src when user clicks it holding held_item (null for an empty hand). Fill in context
/// (SCREENTIP_LMB and friends -> "What it does") for the clicks you're sure of.
/atom/proc/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	return

/// What this item does to target when user clicks target with it. Only used for clicks the target didn't claim.
/obj/item/proc/add_item_context(obj/item/source, list/context, atom/target, mob/living/user)
	return

/// The LMB tip for the cases every atom shares, when nothing more specific claimed it
/atom/proc/generic_screentip(obj/item/held_item, mob/living/user)
	if(held_item)
		if(SEND_SIGNAL(src, COMSIG_CONTAINS_STORAGE) && SEND_SIGNAL(src, COMSIG_TRY_STORAGE_CAN_INSERT, held_item, user, TRUE))
			return "Put in"
		return
	return empty_hand_screentip(user)

/atom/proc/empty_hand_screentip(mob/living/user)
	return

/obj/item/empty_hand_screentip(mob/living/user)
	if(anchored || user.is_holding(src))
		return
	if(loc == user)
		return "Take off"
	if(!isturf(loc))
		return "Take out"
	return "Pick up"

// What an empty hand does to someone else, on each intent (/datum/species/proc/spec_attack_hand() and friends)
/mob/living/carbon/human/empty_hand_screentip(mob/living/user)
	if(user == src || !ishuman(user))
		return
	var/mob/living/carbon/human/attacker = user
	switch(user.a_intent)
		if(INTENT_HELP)
			var/lying = !(mobility_flags & MOBILITY_STAND)
			if((health < 0 || HAS_TRAIT(src, TRAIT_FAKEDEATH)) && lying) // /datum/species/proc/help()
				return (!HAS_TRAIT(user, TRAIT_NOBREATH) && user.getorganslot(ORGAN_SLOT_LUNGS)) ? "CPR" : null
			if(on_fire) // /mob/living/carbon/proc/help_shake_act()
				return
			if(lying)
				return buckled ? null : "Shake awake"
			return "Hug"
		if(INTENT_DISARM)
			return "Disarm"
		if(INTENT_GRAB)
			return (user.pulling == src) ? "Tighten grip" : "Grab"
		if(INTENT_HARM)
			return capitalize(attacker.dna?.species?.attack_verb || "punch")

// Redrawing the tip when what a click would do changes: swapping hands, changing intent, picking up or dropping things
/mob/living/carbon/swap_hand(held_index)
	. = ..()
	refresh_screentip()

/mob/a_intent_change(input as text)
	..()
	refresh_screentip()

/obj/item/equipped(mob/user, slot, initial = FALSE)
	. = ..()
	if(user.client && slot == ITEM_SLOT_HANDS)
		user.refresh_screentip()

/obj/item/dropped(mob/user)
	. = ..()
	if(user?.client)
		user.refresh_screentip()

// Players can switch them off: in the Hippie OOC settings, or from the Settings menu
TOGGLE_CHECKBOX(/datum/verbs/menu/Settings, toggle_screentips)()
	set name = "Show/Hide Screentips"
	set category = "Preferences"
	set desc = "Show what you're hovering over, and what clicking it would do, at the top of the screen"
	usr.client.prefs.hippie_toggles ^= SCREENTIPS_DISABLED
	usr.client.prefs.save_preferences()
	if(usr.client.prefs.hippie_toggles & SCREENTIPS_DISABLED)
		usr.hud_used?.screentip_text?.show(usr.client, null)
		to_chat(usr, "You will no longer see screentips.")
	else
		to_chat(usr, "You will now see screentips.")

/datum/verbs/menu/Settings/toggle_screentips/Get_checked(client/C)
	return !(C.prefs.hippie_toggles & SCREENTIPS_DISABLED)
