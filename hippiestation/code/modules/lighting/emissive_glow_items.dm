// Lit things you carry, and cyborg eyes (see emissive_glow.dm): flashlights, lamps, flares and glowsticks, lighters and smokes,
// energy blades and stun batons. Masks are in tools/icon_merge/glow.txt.

/// Lit, an item doesn't need its emissive blocker: a copy of its own sprite on the blocker plane, which would hide its glow.
/// It gets it back when it goes out.
/atom/movable/set_emissive_glow(icon_state, icon_file = icon, list/extra)
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

/obj/item/flashlight/update_brightness(mob/user)
	. = ..()
	update_state_glow()

// A glowstick keeps its sprite lit or not; its glow is an overlay, in its own colour
/obj/item/flashlight/glowstick/update_icon()
	. = ..()
	set_emissive_glow(null, icon, on && fuel ? emissive_glow(icon, "glowstick-glow") : null)

/obj/item/lighter/update_icon()
	. = ..()
	update_state_glow(lit ? emissive_glow_list(icon, "lighter_overlay_[overlay_state]-on") : null)

/obj/item/lighter/greyscale/update_icon()
	. = ..()
	update_state_glow(lit ? emissive_glow_list(icon, "lighter_overlay_[overlay_state]-on") : null)

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
