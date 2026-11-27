// Fishing, from Paradise (fishing-standalone, 2026-11-26), without Paradise's fish tanks: rods, lines, hooks and bait, fishing
// spots from toilets to deep lava, a bite to pull on, a reel fight, a line that hangs and swings, fish and junk, trophies, a
// record board, and an exosuit rod for deep lava.

/obj/item/fishing_rod
	name = "makeshift fishing rod"
	desc = "Two metal rods tied together with a bit of cable. It will catch fish, just not quickly."
	icon = FISHING_ICON
	icon_state = "rod"
	item_state = "fishing_rod"
	lefthand_file = 'hippiestation/icons/mob/inhands/fishing_lefthand.dmi'
	righthand_file = 'hippiestation/icons/mob/inhands/fishing_righthand.dmi'
	force = 5
	throwforce = 5
	attack_verb = list("whipped", "smacked", "hooked")
	/// The line on the rod. A type here is made into the real thing when the rod is
	var/obj/item/fishing_line/line = /obj/item/fishing_line
	/// The hook on the end of the line. A type here is made into the real thing when the rod is
	var/obj/item/fishing_hook/hook = /obj/item/fishing_hook
	/// The bait on the hook, anything get_fishing_bait_kind() knows
	var/obj/item/bait
	/// How fast it winds line in, in tiles a second
	var/reel_speed = 1
	/// How much of a fish's pull ends up as strain on the line. Lower is kinder to the line
	var/strain_mult = 1
	/// The cast in progress, while the line is out
	var/datum/fishing_session/session

/obj/item/fishing_rod/Initialize(mapload)
	. = ..()
	if(ispath(line))
		line = new line(src)
	if(ispath(hook))
		hook = new hook(src)

/obj/item/fishing_rod/Destroy()
	QDEL_NULL(session)
	QDEL_NULL(line)
	QDEL_NULL(hook)
	QDEL_NULL(bait)
	return ..()

/obj/item/fishing_rod/examine(mob/user)
	. = ..()
	. += "<span class='notice'>It has [line ? "\a [line]" : "no line"], [hook ? "\a [hook]" : "no hook"] and [bait ? "\a [bait] for bait" : "no bait"] on it.</span>"
	. += "<span class='notice'>Use a line, a hook or some bait on it to fit it. <b>Alt-Click</b> it to take off the bait, then the hook, then the line.</span>"
	. += "<span class='notice'>Click on water to cast. When something bites, click again to hook it.</span>"

/obj/item/fishing_rod/Exited(atom/movable/AM, atom/newLoc)
	. = ..()
	forget_part(AM)

// A part deleted while on the rod doesn't call Exited()
/obj/item/fishing_rod/handle_atom_del(atom/A)
	. = ..()
	forget_part(A)

/obj/item/fishing_rod/proc/forget_part(atom/movable/part)
	if(part == line)
		line = null
	else if(part == hook)
		hook = null
	else if(part == bait)
		bait = null

/// What the line comes out of when `user` fishes with this. Their own body, for a rod in the hand
/obj/item/fishing_rod/proc/angler_body(mob/living/user)
	return user

/// Can `user` keep fishing with this? They have to be up and holding it
/obj/item/fishing_rod/proc/can_keep_fishing(mob/living/user)
	return !QDELETED(user) && !user.incapacitated() && user.is_holding(src)

/**
  * Where the line leaves the rod's tip, in pixels from the bottom left of the tile `body` is on.
  *
  * Follows the inhand sprites: the tip is out to the side of the hand holding it, a bit above the waist.
  */
/obj/item/fishing_rod/proc/tip_offset(atom/movable/body)
	var/mob/holder = body
	var/left_hand = istype(holder) && (holder.get_held_index_of_item(src) % 2) == 1
	switch(body.dir)
		if(NORTH)
			return left_hand ? list(0.5, 20.5) : list(30.5, 20.5)
		if(EAST)
			return left_hand ? list(28.5, 20.5) : list(22.5, 19.5)
		if(WEST)
			return left_hand ? list(8.5, 19.5) : list(3.5, 20.5)
	return left_hand ? list(29.5, 20.5) : list(1.5, 20.5)

/// Hands something just reeled in to `user`
/obj/item/fishing_rod/proc/receive_catch(atom/movable/landed, mob/living/user)
	if(isitem(landed))
		user.put_in_hands(landed)

/// The kind of bait on the hook right now, or null for a bare hook
/obj/item/fishing_rod/proc/get_bait_kind()
	if(bait)
		return get_fishing_bait_kind(bait)
	return hook?.lure_kind

// ---- Fitting parts

/obj/item/fishing_rod/attackby(obj/item/I, mob/living/user, params)
	if(istype(I, /obj/item/fishing_line))
		line = swap_part(user, I, line)
		return TRUE
	if(istype(I, /obj/item/fishing_hook))
		hook = swap_part(user, I, hook)
		return TRUE
	if(get_fishing_bait_kind(I))
		if(!hook)
			to_chat(user, "<span class='warning'>There's no hook on [src] to put [I] on.</span>")
			return TRUE
		bait = swap_part(user, I, bait)
		return TRUE
	return ..()

/**
  * Fits `new_part` in place of `old_part` and hands the old one back to `user`.
  *
  * Returns the part that is on the rod afterwards, which is `old_part` if the swap didn't happen.
  */
/obj/item/fishing_rod/proc/swap_part(mob/living/user, obj/item/new_part, obj/item/old_part)
	if(session)
		to_chat(user, "<span class='warning'>Reel [src] in first.</span>")
		return old_part
	if(!user.transferItemToLoc(new_part, src))
		return old_part
	if(old_part)
		user.put_in_hands(old_part)
		to_chat(user, "<span class='notice'>You swap [old_part] on [src] for [new_part].</span>")
	else
		to_chat(user, "<span class='notice'>You fit [new_part] to [src].</span>")
	playsound(src, 'sound/items/zip.ogg', 30, TRUE)
	return new_part

/obj/item/fishing_rod/AltClick(mob/user)
	if(!isliving(user) || !user.canUseTopic(src, BE_CLOSE, NO_DEXTERY))
		return
	if(session)
		to_chat(user, "<span class='warning'>Reel [src] in first.</span>")
		return
	// The line can't come off with the hook still tied to it, and the hook can't with bait on it
	var/obj/item/part = bait || hook || line
	if(!part)
		to_chat(user, "<span class='warning'>There's nothing on [src] to take off.</span>")
		return
	user.put_in_hands(part)
	to_chat(user, "<span class='notice'>You take [part] off [src].</span>")

// ---- Casting

// Next to the water: before the thing clicked takes the rod as a hit or an item
/obj/item/fishing_rod/pre_attack(atom/A, mob/living/user, params)
	if(use_on(A, user))
		return FALSE
	return ..()

// Further out
/obj/item/fishing_rod/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	. = ..()
	if(!proximity_flag)
		use_on(target, user)

/obj/item/fishing_rod/attack_self(mob/user)
	if(session)
		session.pull(user)
		return TRUE
	return ..()

/// Casts at `target`, or pulls on the line if it's already out. Returns TRUE if the click was used for fishing.
/obj/item/fishing_rod/proc/use_on(atom/target, mob/living/user)
	if(session)
		// The rod still works for hitting people with
		if(user.a_intent == INTENT_HARM && isliving(target))
			return FALSE
		session.pull(user)
		return TRUE
	var/datum/fishing_spot/spot = get_fishing_spot(target)
	// Clicking something that is in the water is as good as clicking the water
	if(!spot && isturf(target.loc))
		target = target.loc
		spot = get_fishing_spot(target)
	if(!spot)
		return FALSE
	cast(target, spot, user)
	return TRUE

/// Is the rod ready to be cast? Tells `user` why not.
/obj/item/fishing_rod/proc/can_cast(mob/living/user)
	if(!line)
		to_chat(user, "<span class='warning'>There's no line on [src].</span>")
		return FALSE
	if(!hook)
		to_chat(user, "<span class='warning'>There's no hook on [src].</span>")
		return FALSE
	return TRUE

/obj/item/fishing_rod/proc/cast(atom/target, datum/fishing_spot/spot, mob/living/user)
	if(!can_cast(user))
		return
	var/turf/user_turf = get_turf(angler_body(user))
	var/turf/landing = get_turf(target)
	if(landing == user_turf)
		to_chat(user, "<span class='warning'>You can't cast at your own feet.</span>")
		return
	if(get_dist(user_turf, landing) > line.cast_range)
		to_chat(user, "<span class='warning'>[line] can't reach that far.</span>")
		return
	if(cast_blocked(user_turf, landing))
		to_chat(user, "<span class='warning'>Something is in the way.</span>")
		return
	var/problem = spot.why_not(target, src)
	if(problem)
		to_chat(user, "<span class='warning'>[problem]</span>")
		return
	user.changeNext_move(CLICK_CD_MELEE)
	session = new(src, user, target, spot)

/// Is there a wall, a window or a closed door between the angler and where the bobber should land?
/obj/item/fishing_rod/proc/cast_blocked(turf/from, turf/landing)
	for(var/turf/crossed as anything in getline(from, landing))
		if(crossed == from)
			continue
		// Chasms are open, and there's nothing in them to stop a hook
		if(crossed.density)
			return TRUE
		// What stands on the landing tile is what's being fished in
		if(crossed == landing)
			continue
		for(var/obj/thing in crossed)
			// Tables and the like can be cast over, railings and thin windows can be cast past
			if(thing.density && !(thing.pass_flags & LETPASSTHROW) && !(thing.flags_1 & ON_BORDER_1))
				return TRUE
	return FALSE

/obj/item/fishing_rod/dropped(mob/user, silent)
	. = ..()
	if(session)
		session.give_up(user)

// ---- Reel window

/obj/item/fishing_rod/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state)
	if(!state)
		state = fishing_ui_state()
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "fishing_reel", name, 340, 320, master_ui, state)
		// The fight sends its own updates, five times a second
		ui.set_autoupdate(FALSE)
		ui.open()

/// Hands, for a rod in the hand
/obj/item/fishing_rod/proc/fishing_ui_state()
	return GLOB.hands_state

/obj/item/fishing_rod/ui_data(mob/user)
	var/list/data = list()
	data["fighting"] = session?.state == FISHING_FIGHT
	if(!data["fighting"])
		return data
	data["tension"] = round(session.tension)
	data["max_tension"] = FISHING_MAX_TENSION
	data["distance"] = round(session.distance, 0.1)
	data["max_distance"] = round(session.max_distance, 0.1)
	data["fish_state"] = session.fish_state
	data["hint"] = session.hooked.pull_hint(session.fight_strength)
	data["reeling"] = session.reeling
	return data

/obj/item/fishing_rod/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return
	if(action != "reel")
		return
	if(session?.state != FISHING_FIGHT || ui.user != session.user)
		return
	session.reeling = !!text2num("[params["held"]]")
	return TRUE

// Closing the window lets go of the reel
/obj/item/fishing_rod/ui_close(mob/user)
	. = ..()
	if(session)
		session.reeling = FALSE

// ---- Telescopic rod

/obj/item/fishing_rod/telescopic
	name = "telescopic fishing rod"
	desc = "A proper carbon fibre rod with a smooth reel. It winds in faster, goes easier on the line and folds down to fit in a bag."
	icon_state = "rod_telescopic_folded"
	item_state = "fishing_rod_folded"
	w_class = WEIGHT_CLASS_SMALL
	reel_speed = 1.3
	strain_mult = 0.9
	/// Is it pulled out to full length? It can't be cast while folded
	var/extended = FALSE

/obj/item/fishing_rod/telescopic/attack_self(mob/user)
	if(session)
		return ..()
	extended = !extended
	if(extended)
		to_chat(user, "<span class='notice'>You pull [src] out to its full length.</span>")
		icon_state = "rod_telescopic"
		item_state = "fishing_rod_telescopic"
		w_class = WEIGHT_CLASS_BULKY
	else
		to_chat(user, "<span class='notice'>You fold [src] down.</span>")
		icon_state = "rod_telescopic_folded"
		item_state = "fishing_rod_folded"
		w_class = WEIGHT_CLASS_SMALL
	user.update_inv_hands()
	playsound(src, 'sound/weapons/batonextend.ogg', 50, TRUE)
	return TRUE

/obj/item/fishing_rod/telescopic/can_cast(mob/living/user)
	if(!extended)
		to_chat(user, "<span class='warning'>Pull [src] out to its full length first.</span>")
		return FALSE
	return ..()
