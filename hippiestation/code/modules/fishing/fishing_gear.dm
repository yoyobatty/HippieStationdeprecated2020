// MARK: Lines

/obj/item/fishing_line
	name = "fishing line"
	desc = "A reel of plain fishing line. Good for water, toilets and the void of space."
	icon = FISHING_ICON
	icon_state = "line"
	w_class = WEIGHT_CLASS_TINY
	/// What this line can be used for, FISHING_LINE_ flags
	var/line_flags = NONE
	/// How far it can be cast, in tiles
	var/cast_range = 5
	/// How much pull it takes before it snaps. A line of 1.15 takes 15% more than a plain one
	var/strength = 1
	/// Colour of the line drawn from the angler to the bobber
	var/line_color = "#dddddd"

/obj/item/fishing_line/examine(mob/user)
	. = ..()
	. += "<span class='notice'>It can be cast up to [cast_range] tiles.</span>"
	if(line_flags & FISHING_LINE_HEATPROOF)
		. += "<span class='notice'>It won't burn in lava or liquid plasma.</span>"
	if(line_flags & FISHING_LINE_LONG)
		. += "<span class='notice'>It's long enough to reach the bottom of a chasm.</span>"

/obj/item/fishing_line/sinew
	name = "sinew fishing line"
	desc = "Fishing line braided from watcher sinew. It doesn't burn and it's hard to snap."
	icon_state = "line_sinew"
	line_flags = FISHING_LINE_HEATPROOF
	strength = 1.15
	line_color = "#c98a5a"

/obj/item/fishing_line/long
	name = "deep fishing line"
	desc = "A fat reel of very thin line. There's a lot of it, but it snaps easier."
	icon_state = "line_long"
	line_flags = FISHING_LINE_LONG
	cast_range = 7
	strength = 0.85
	line_color = "#8fc1e6"

// MARK: Hooks

/obj/item/fishing_hook
	name = "fishing hook"
	desc = "A bent bit of metal with a point on the end."
	icon = FISHING_ICON
	icon_state = "hook"
	w_class = WEIGHT_CLASS_TINY
	/// How long the angler has to pull once something bites
	var/bite_window = 2 SECONDS
	/// A fish has to take this many times more line than usual to get off the hook
	var/spare_line_mult = 1
	/// The kind of bait this hook counts as while there's no bait on it
	var/lure_kind

/obj/item/fishing_hook/barbed
	name = "barbed fishing hook"
	desc = "A hook with barbs. Whatever bites it stays on for longer."
	icon_state = "hook_barbed"
	bite_window = 3 SECONDS
	spare_line_mult = 1.4

/obj/item/fishing_hook/lure
	name = "shiny lure"
	desc = "A hook with a polished spinner on it. Some fish can't resist a bit of glitter, and it never runs out."
	icon_state = "hook_lure"
	lure_kind = FISHING_BAIT_SHINY

// MARK: Bait

/// Gives the kind of bait `bait` is, or null if nothing would bite on it
/proc/get_fishing_bait_kind(obj/item/bait)
	var/static/list/bait_kinds = list(
		/obj/item/fish/feederfish = FISHING_BAIT_LIVE,
		/obj/item/fish/shrimp = FISHING_BAIT_LIVE,
		/obj/item/reagent_containers/food/snacks/cheesewedge = FISHING_BAIT_CHEESE,
		/obj/item/reagent_containers/food/snacks/meat = FISHING_BAIT_MEAT,
		/obj/item/reagent_containers/food/snacks/carpmeat = FISHING_BAIT_MEAT,
		/obj/item/reagent_containers/food/snacks/fish_fillet = FISHING_BAIT_MEAT,
		/obj/item/reagent_containers/food/snacks/grown = FISHING_BAIT_PLANT,
		/obj/item/flashlight/glowstick = FISHING_BAIT_GLOW,
		/obj/item/coin = FISHING_BAIT_SHINY,
	)
	for(var/bait_type in bait_kinds)
		if(istype(bait, bait_type))
			return bait_kinds[bait_type]

// MARK: Tackle box

/obj/item/storage/fishing_tackle
	name = "tackle box"
	desc = "A box with little trays for fishing lines, hooks and bait."
	icon = FISHING_ICON
	icon_state = "tackle_box"
	w_class = WEIGHT_CLASS_NORMAL

/obj/item/storage/fishing_tackle/ComponentInitialize()
	. = ..()
	var/datum/component/storage/STR = GetComponent(/datum/component/storage)
	STR.max_items = 14
	STR.max_combined_w_class = 28
	STR.max_w_class = WEIGHT_CLASS_SMALL
	STR.set_holdable(list(
		/obj/item/fishing_line,
		/obj/item/fishing_hook,
		/obj/item/reagent_containers/food/snacks,
		/obj/item/fish/feederfish,
		/obj/item/fish/shrimp,
		/obj/item/coin,
		/obj/item/flashlight/glowstick,
	))

/// The tackle box from the cargo crate, with a line and a hook of every kind
/obj/item/storage/fishing_tackle/full

/obj/item/storage/fishing_tackle/full/PopulateContents()
	new /obj/item/fishing_line(src)
	new /obj/item/fishing_line/sinew(src)
	new /obj/item/fishing_line/long(src)
	new /obj/item/fishing_hook(src)
	new /obj/item/fishing_hook(src)
	new /obj/item/fishing_hook/barbed(src)
	new /obj/item/fishing_hook/lure(src)
