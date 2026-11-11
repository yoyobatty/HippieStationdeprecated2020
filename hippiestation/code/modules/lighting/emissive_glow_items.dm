// Lit things you carry, and cyborg eyes (see emissive_glow.dm): flashlights, lamps, flares and glowsticks, lighters and smokes,
// energy blades and stun batons. Masks are in tools/icon_merge/glow.txt.

/// Lit, an item doesn't need its emissive blocker: a copy of its own sprite on the blocker plane, which would hide its glow.
/// It gets it back when it goes out.
/atom/movable/set_emissive_glow(icon_state, icon_file = icon, list/extra, transient = FALSE, alpha)
	. = ..()
	if(blocks_emissive != EMISSIVE_BLOCK_GENERIC)
		return
	var/obj/effect/overlay/vis/blocker
	for(var/obj/effect/overlay/vis/each in managed_vis_overlays)
		if(each.plane == EMISSIVE_BLOCKER_PLANE)
			blocker = each
			break
	if(emissive_glow_shown && blocker)
		SSvis_overlays.remove_vis_overlay(src, list(blocker))
	else if(!emissive_glow_shown && !blocker)
		update_emissive_block()

/// Held or worn, the sprite on the person glows too: its in-hand or worn state's mask ("cigon", "swordred"), when it has one.
/// That's keyed on the state, not on whether the item glows, so it doesn't matter whether the item lit before or after the
/// person's sprite was redrawn.
/obj/item/build_worn_icon(state = "", default_layer = 0, default_icon_file = null, isinhands = FALSE, femaleuniform = NO_FEMALE_UNIFORM)
	. = ..()
	var/mutable_appearance/standing = .
	if(!standing)
		return
	var/file = (!isinhands && alternate_worn_icon) || default_icon_file
	var/glow = emissive_glow_state(file, state)
	if(glow)
		standing.overlays += emissive_glow(file, glow, unblockable = TRUE)

/mob/living/carbon
	/// Glows taken out of worn and held sprites (apply_overlay() below): sprite -> its glow overlays
	var/list/worn_glows
	/// Those glows as they're on the mob now, by overlays_standing index (as text)
	var/list/worn_glows_shown

/// The glow in a worn or held sprite goes on the mob's own overlays beside the sprite, not inside it. Inside the in-hand or worn overlay, on
/// a plane of its own (KEEP_APART), it kept the south-facing frame whichever way the mob turned: the Captain's lit energy sword showed a
/// second blade where it would be facing south (round-13.09.35). Beside it, it turns with the mob. Real-client pictures:
/// data/previews/sword_dir_before_after.png (tools/keybind_check/sword_dir_shots.dm).
/// overlays_standing keeps its entries as they were: callers read them back after applying (human update_inv_wear_mask() offsets the mask
/// and applies it again), so the glow is taken out before the sprite goes on, remembered for it, and put on again with its offset.
/mob/living/carbon/apply_overlay(cache_index)
	var/layer = overlays_standing[cache_index]
	var/list/shown
	if(layer)
		for(var/mutable_appearance/standing in (islist(layer) ? layer : list(layer)))
			var/list/nested
			for(var/each in standing.overlays)
				if(!istext(each) && emissive_glow_plane(each:plane))
					LAZYADD(nested, each)
			if(nested)
				standing.overlays -= nested
				LAZYSET(worn_glows, standing, nested)
			for(var/each in LAZYACCESS(worn_glows, standing))
				if(!standing.pixel_x && !standing.pixel_y)
					LAZYADD(shown, each)
					continue
				// Inside it, it moved with the sprite's offset (a species' hands or mask): beside it, it needs one of its own
				var/mutable_appearance/moved = new(each)
				moved.plane = each:plane //new() puts a mutable appearance on FLOAT_PLANE (mutable_appearance.dm)
				moved.pixel_x += standing.pixel_x
				moved.pixel_y += standing.pixel_y
				LAZYADD(shown, moved)
	. = ..()
	if(shown)
		add_overlay(shown)
		LAZYSET(worn_glows_shown, "[cache_index]", shown)
	if(LAZYLEN(worn_glows) > 12) //sprites since replaced
		for(var/standing in worn_glows.Copy())
			var/still_on = FALSE
			for(var/entry in overlays_standing)
				if(entry == standing || (islist(entry) && (standing in entry)))
					still_on = TRUE
					break
			if(!still_on)
				worn_glows -= standing

/mob/living/carbon/remove_overlay(cache_index)
	var/list/shown = LAZYACCESS(worn_glows_shown, "[cache_index]")
	if(shown)
		cut_overlay(shown)
		worn_glows_shown -= "[cache_index]"
	return ..()

/proc/emissive_glow_plane(plane)
	return plane == EMISSIVE_UNBLOCKABLE_PLANE || plane == EMISSIVE_BLOOM_PLANE || plane == EMISSIVE_PLANE

/obj/item/flashlight/update_brightness(mob/user)
	. = ..()
	update_state_glow()

// A glowstick keeps its sprite lit or not; its glow is an overlay, in its own colour
/obj/item/flashlight/glowstick/update_icon()
	. = ..()
	set_emissive_glow(null, icon, on && fuel ? emissive_glow(icon, "glowstick-glow") : null)

// The flame; the lighter's decorated body (its overlay) doesn't glow
/obj/item/lighter/update_icon()
	. = ..()
	update_state_glow()

/obj/item/lighter/greyscale/update_icon()
	. = ..()
	update_state_glow()

/obj/item/clothing/mask/cigarette/light(flavor_text)
	. = ..()
	update_state_glow()

/obj/item/clothing/mask/cigarette/extinguish()
	. = ..()
	update_state_glow()

/obj/item/clothing/mask/cigarette/pipe/process()
	var/was = icon_state
	. = ..()
	if(icon_state != was && !QDELETED(src))
		update_state_glow()

/obj/item/clothing/mask/cigarette/pipe/attack_self(mob/user)
	var/was = icon_state
	. = ..()
	if(icon_state != was)
		update_state_glow()

// Energy weapons set their lit sprite after the base proc, so each level looks again
/obj/item/melee/transforming/transform_weapon(mob/living/user, supress_message_text)
	. = ..()
	update_state_glow()

/obj/item/melee/transforming/energy/transform_weapon(mob/living/user, supress_message_text)
	. = ..()
	update_state_glow()

/obj/item/melee/transforming/energy/sword/transform_weapon(mob/living/user, supress_message_text)
	. = ..()
	update_state_glow()

/obj/item/twohanded/dualsaber/update_icon()
	. = ..()
	update_state_glow()

/obj/item/melee/baton/update_icon()
	. = ..()
	update_state_glow()

// Cyborg eyes, while it's awake
/mob/living/silicon/robot/update_icons()
	. = ..()
	if(module && eye_lights && stat != DEAD && !(IsUnconscious() || IsStun() || IsParalyzed() || low_power_mode))
		set_emissive_glow(eye_lights.icon_state, eye_lights.icon)
	else
		set_emissive_glow(null)

/// A colour at full strength, same hue: brown eyes glow amber rather than a dark brown nobody would see
/proc/glow_brighten(colour)
	if(length(colour) == 4) // "#542"
		colour = "#[copytext(colour, 2, 3)][copytext(colour, 2, 3)][copytext(colour, 3, 4)][copytext(colour, 3, 4)][copytext(colour, 4, 5)][copytext(colour, 4, 5)]"
	var/list/rgb = rgb2num(colour)
	if(length(rgb) < 3)
		return colour
	var/top = max(rgb[1], rgb[2], rgb[3])
	if(!top)
		return "#FFFFFF"
	return rgb(rgb[1] * 255 / top, rgb[2] * 255 / top, rgb[3] * 255 / top)

// Cybernetic eyes glow, in the eyes' colour, unless something covers them. Not night-vision eyes: a nightmare hides in the dark.
/mob/living/carbon/human/proc/update_eye_glow()
	var/obj/item/organ/eyes/robotic/eyes = getorganslot(ORGAN_SLOT_EYES)
	var/datum/species/species = dna?.species
	if(!istype(eyes) || stat == DEAD || !species || (NOEYESPRITES in species.species_traits) || HAS_TRAIT(src, TRAIT_HUSK) || !get_bodypart(BODY_ZONE_HEAD) || is_eyes_covered())
		set_emissive_glow(null)
		return
	var/x = 0
	var/y = 0
	if(OFFSET_FACE in species.offset_features)
		x = species.offset_features[OFFSET_FACE][1]
		y = species.offset_features[OFFSET_FACE][2]
	var/colour = (EYECOLOR in species.species_traits) ? glow_brighten("#[eye_color]") : null
	set_emissive_glow(null, null, emissive_glow('icons/mob/human_face.dmi', eyes.eye_icon_state, SOUTH, 255, x, y, unblockable = TRUE, color = colour))

/datum/species/handle_body(mob/living/carbon/human/H)
	. = ..()
	H.update_eye_glow()

/mob/living/carbon/human/update_inv_head()
	. = ..()
	update_eye_glow()

/mob/living/carbon/human/update_inv_wear_mask()
	. = ..()
	update_eye_glow()

/mob/living/carbon/human/update_inv_glasses()
	. = ..()
	update_eye_glow()

/mob/living/carbon/human/death(gibbed)
	. = ..()
	update_eye_glow()
