/obj/item/robot_module
    var/hippie_cyborg_base_icon

/// The skin menu. A cyborg nobody's playing (bots_ai/goals/silicon.dm) picks for itself: input() would wait on a client it hasn't got and
/// come back empty, and the module change with it. It picks one of `hippie_skins`, the ones drawn for Hippie (not in tg's sheet): the
/// rest are tg's art, and the user saw the bot crew's cyborgs looking tg (2026-11-10).
/obj/item/robot_module/proc/pick_skin(mob/living/silicon/robot/R, list/skins, list/hippie_skins)
	if(!R.client && R.bot_silicon)
		return pick(length(hippie_skins) ? hippie_skins : skins)
	return tgui_input_list(R, "Select an icon!", "Robot Icon", skins)

/obj/item/robot_module/standard/be_transformed_to(obj/item/robot_module/old_module)
	var/mob/living/silicon/robot/R = loc
	var/borg_icon = pick_skin(R, list("Standard", "Classic Style", "Hydro-bot", "Captain"), list("Hydro-bot"))
	if(!borg_icon)
		return FALSE
	switch(borg_icon)
		if("Standard")
			hippie_cyborg_base_icon = "robot"
		if("Classic Style")
			hippie_cyborg_base_icon = "robot_old"
		if("Hydro-bot")
			hippie_cyborg_base_icon = "Hydrobot"
		if("Captain")
			hippie_cyborg_base_icon = "captainborg"
	return ..()

/obj/item/robot_module/medical/be_transformed_to(obj/item/robot_module/old_module)
	var/mob/living/silicon/robot/R = loc
	var/borg_icon = pick_skin(R, list("Standard", "Classic", "Humanoid"), list("Classic"))
	if(!borg_icon)
		return FALSE
	switch(borg_icon)
		if("Standard")
			hippie_cyborg_base_icon = "medical"
		if("Classic")
			hippie_cyborg_base_icon = "Medbot"
		if("Humanoid")
			hippie_cyborg_base_icon = "cmoborg"
	return ..()

/obj/item/robot_module/security/be_transformed_to(obj/item/robot_module/old_module)
	var/mob/living/silicon/robot/R = loc
	var/borg_icon = pick_skin(R, list("Standard", "Classic", "Humanoid", "Black Scheme Humanoid", "PISSED OFF BEEPSKY"), list("Classic", "PISSED OFF BEEPSKY"))
	if(!borg_icon)
		return FALSE
	switch(borg_icon)
		if("Standard")
			hippie_cyborg_base_icon = "sec"
		if("Classic")
			hippie_cyborg_base_icon = "secborg"
		if("Humanoid")
			hippie_cyborg_base_icon = "Security"
		if("Black Scheme Humanoid")
			hippie_cyborg_base_icon = "hosborg"
		if("PISSED OFF BEEPSKY")
			hippie_cyborg_base_icon = "secbot0"
	return ..()


/obj/item/robot_module/engineering/be_transformed_to(obj/item/robot_module/old_module)
	var/mob/living/silicon/robot/R = loc
	var/borg_icon = pick_skin(R, list("Standard", "Classic Style", "Tech-Priest", "Super Oldschool", "Thicc", "Humanoid"), list("Classic Style", "Tech-Priest", "Super Oldschool", "Thicc"))
	if(!borg_icon)
		return FALSE
	switch(borg_icon)
		if("Standard")
			hippie_cyborg_base_icon = "engineer"
		if("Classic Style")
			hippie_cyborg_base_icon = "Engineering_old"
		if("Tech-Priest")
			hippie_cyborg_base_icon = "Engineering2"
		if("Super Oldschool")
			hippie_cyborg_base_icon = "engineering_drone"
			special_light_key = "medical"
			hat_offset = 3
		if("Thicc")
			hippie_cyborg_base_icon = "Engineering3"
			special_light_key = null
			hat_offset = INFINITY //He is already wearing a hat
		if("Humanoid")
			hippie_cyborg_base_icon = "ceborg"
	return ..()

/obj/item/robot_module/janitor/be_transformed_to(obj/item/robot_module/old_module)
	var/mob/living/silicon/robot/R = loc
	var/borg_icon = pick_skin(R, list("Standard", "Classic", "Botany Style"), list("Classic"))
	if(!borg_icon)
		return FALSE
	switch(borg_icon)
		if("Standard")
			hippie_cyborg_base_icon = "janitor"
		if("Classic")
			hippie_cyborg_base_icon = "JanBot2"
		if("Botany Style")
			hippie_cyborg_base_icon = "botany"
	return ..()


/obj/item/robot_module/miner/be_transformed_to(obj/item/robot_module/old_module)
	var/mob/living/silicon/robot/R = loc
	var/borg_icon = pick_skin(R, list("Lavaland Colours", "Asteroid Colours", "Classic Skin", "Humanoid Borg"), list("Classic Skin"))
	if(!borg_icon)
		return FALSE
	switch(borg_icon)
		if("Asteroid Colours")
			hippie_cyborg_base_icon = "minerOLD"
		if("Classic Skin")
			hippie_cyborg_base_icon = "Miner_old"
		if("Lavaland Colours")
			hippie_cyborg_base_icon = "miner"
		if("Humanoid Borg") //was "Research Humanoid Borg", which isn't on the menu, so picking it left the default skin
			hippie_cyborg_base_icon = "rdborg"
			special_light_key = null
			hat_offset = INFINITY //I'm very lazy

	return ..()