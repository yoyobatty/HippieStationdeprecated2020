// The biggest fish of each kind this shift, a board on the wall that lists them, and plaques to hang a catch on

/// The biggest catch of each kind of fish this shift. Name of the fish = its /datum/fishing_record
GLOBAL_LIST_EMPTY(fishing_records)

/// The biggest one of a kind of fish caught this shift.
/datum/fishing_record
	/// The kind of fish
	var/fish_name
	/// Who caught it
	var/angler
	/// How long it was, in cm
	var/length_cm
	/// The kind of spot it was caught in
	var/spot_name
	/// Station time it was caught at
	var/time

/// Notes down a catch if it's the biggest of its kind so far. Returns TRUE if it beat an older one.
/proc/record_fishing_catch(angler, fish_name, length_cm, spot_name)
	var/datum/fishing_record/old_record = GLOB.fishing_records[fish_name]
	if(old_record && old_record.length_cm >= length_cm)
		return FALSE
	var/datum/fishing_record/record = new
	record.fish_name = fish_name
	record.angler = angler
	record.length_cm = length_cm
	record.spot_name = spot_name
	record.time = station_time_timestamp("hh:mm")
	GLOB.fishing_records[fish_name] = record
	// The first of a kind sets the record without beating anybody
	return !!old_record

// ---- Record board

/obj/item/wallframe/fishing_board
	name = "angler's record board"
	desc = "A board that keeps track of the biggest fish caught this shift. It goes on a wall."
	icon = FISHING_ICON
	icon_state = "board"
	w_class = WEIGHT_CLASS_BULKY
	materials = list()
	result_path = /obj/structure/fishing_board
	pixel_shift = -30

/obj/structure/fishing_board
	name = "angler's record board"
	desc = "The biggest fish caught this shift, and who caught them."
	icon = FISHING_ICON
	icon_state = "board"
	anchored = TRUE
	max_integrity = 100

/obj/structure/fishing_board/examine(mob/user)
	. = ..()
	. += "<span class='notice'>It can be <b>pried</b> off the wall.</span>"

/obj/structure/fishing_board/attack_hand(mob/user)
	. = ..()
	if(.)
		return
	ui_interact(user)

/obj/structure/fishing_board/attack_ghost(mob/user)
	ui_interact(user)

/obj/structure/fishing_board/crowbar_act(mob/living/user, obj/item/I)
	. = TRUE
	if(!I.use_tool(src, user, 2 SECONDS, volume = 50))
		return
	to_chat(user, "<span class='notice'>You pry [src] off the wall.</span>")
	deconstruct(TRUE)

/obj/structure/fishing_board/deconstruct(disassembled = TRUE)
	if(!(flags_1 & NODECONSTRUCT_1))
		if(disassembled)
			new /obj/item/wallframe/fishing_board(drop_location())
		else
			new /obj/item/stack/sheet/mineral/wood(drop_location(), 2)
	qdel(src)

/obj/structure/fishing_board/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "fishing_board", name, 520, 400, master_ui, state)
		ui.open()

/obj/structure/fishing_board/ui_status(mob/user, datum/ui_state/state)
	if(isobserver(user))
		return UI_UPDATE
	return ..()

/obj/structure/fishing_board/ui_data(mob/user)
	var/list/data = list()
	var/list/records = list()
	for(var/fish_name in GLOB.fishing_records)
		var/datum/fishing_record/record = GLOB.fishing_records[fish_name]
		records += list(list(
			"fish" = record.fish_name,
			"angler" = record.angler,
			"length" = record.length_cm,
			"spot" = record.spot_name,
			"time" = record.time,
		))
	data["records"] = records
	return data

// ---- Trophy plaque

/obj/item/wallframe/fish_plaque
	name = "trophy plaque"
	desc = "A polished wooden plaque for showing off a catch. Put a fish you caught on it, then hang it on a wall."
	icon = FISHING_ICON
	icon_state = "plaque"
	materials = list()
	result_path = /obj/structure/fish_trophy
	pixel_shift = -30
	/// The fish on the plaque
	var/obj/item/mounted_fish

/obj/item/wallframe/fish_plaque/Destroy()
	QDEL_NULL(mounted_fish)
	return ..()

/obj/item/wallframe/fish_plaque/examine(mob/user)
	. = ..()
	if(mounted_fish)
		. += "<span class='notice'><b>Alt-Click</b> to take [mounted_fish] off it.</span>"

/obj/item/wallframe/fish_plaque/attackby(obj/item/I, mob/living/user, params)
	var/datum/component/caught_fish/info = I.GetComponent(/datum/component/caught_fish)
	if(!info)
		return ..()
	if(mounted_fish)
		to_chat(user, "<span class='warning'>There's already \a [mounted_fish] on [src].</span>")
		return TRUE
	if(!user.transferItemToLoc(I, src))
		return TRUE
	mounted_fish = I
	name = "mounted [I.name]"
	desc = "\A [I.name], [info.length_cm] cm long. [info.angler] caught it in [info.spot_name]."
	update_icon()
	to_chat(user, "<span class='notice'>You fix [I] to the plaque.</span>")
	return TRUE

/obj/item/wallframe/fish_plaque/AltClick(mob/user)
	if(!isliving(user) || !user.canUseTopic(src, BE_CLOSE, NO_DEXTERY) || !mounted_fish)
		return
	to_chat(user, "<span class='notice'>You take [mounted_fish] off the plaque.</span>")
	user.put_in_hands(mounted_fish)

/obj/item/wallframe/fish_plaque/Exited(atom/movable/AM, atom/newLoc)
	. = ..()
	forget_fish(AM)

// A fish deleted while on the plaque doesn't call Exited()
/obj/item/wallframe/fish_plaque/handle_atom_del(atom/A)
	. = ..()
	forget_fish(A)

/obj/item/wallframe/fish_plaque/proc/forget_fish(atom/movable/gone)
	if(gone != mounted_fish)
		return
	mounted_fish = null
	name = initial(name)
	desc = initial(desc)
	update_icon()

/obj/item/wallframe/fish_plaque/update_icon()
	cut_overlays()
	if(mounted_fish)
		add_overlay(mutable_appearance(mounted_fish.icon, mounted_fish.icon_state))

/obj/item/wallframe/fish_plaque/try_build(turf/on_wall, mob/user)
	if(!mounted_fish)
		to_chat(user, "<span class='warning'>Put a fish on [src] before hanging it.</span>")
		return FALSE
	return ..()

// The plaque goes up whole, fish and all, so the trophy holds it
/obj/item/wallframe/fish_plaque/after_attach(obj/O)
	. = ..()
	var/obj/structure/fish_trophy/trophy = O
	if(!istype(trophy))
		return
	var/obj/item/wallframe/fish_plaque/hung = new type(trophy)
	hung.mounted_fish = mounted_fish
	mounted_fish.forceMove(hung)
	mounted_fish = null
	hung.name = name
	hung.desc = desc
	hung.update_icon()
	trophy.hang(hung)

/// A trophy plaque hanging on a wall. It holds the plaque item and looks like it.
/obj/structure/fish_trophy
	name = "mounted fish"
	icon = FISHING_ICON
	icon_state = "plaque"
	anchored = TRUE
	max_integrity = 50
	/// The plaque that was hung up, with its fish on it
	var/obj/item/wallframe/fish_plaque/plaque

/obj/structure/fish_trophy/proc/hang(obj/item/wallframe/fish_plaque/hung)
	plaque = hung
	name = plaque.name
	desc = plaque.desc
	update_icon()

/obj/structure/fish_trophy/Destroy()
	QDEL_NULL(plaque)
	return ..()

/obj/structure/fish_trophy/examine(mob/user)
	. = ..()
	. += "<span class='notice'>It can be <b>pried</b> off the wall.</span>"

/obj/structure/fish_trophy/update_icon()
	cut_overlays()
	if(plaque?.mounted_fish)
		add_overlay(mutable_appearance(plaque.mounted_fish.icon, plaque.mounted_fish.icon_state))

/obj/structure/fish_trophy/crowbar_act(mob/living/user, obj/item/I)
	. = TRUE
	if(!I.use_tool(src, user, 2 SECONDS, volume = 50))
		return
	to_chat(user, "<span class='notice'>You pry [src] off the wall.</span>")
	deconstruct(TRUE)

// The plaque comes down in one piece either way
/obj/structure/fish_trophy/deconstruct(disassembled = TRUE)
	if(plaque)
		plaque.forceMove(drop_location())
		plaque = null
	qdel(src)
