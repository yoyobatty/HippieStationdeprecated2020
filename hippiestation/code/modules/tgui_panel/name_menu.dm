// hippie -- clicking a speaker's name in the chat (compose_message() marks it with the speaker's ref when that gives nothing
// away) opens a small menu. What's on it, and whether each one may be done, is decided here, on the click: Examine when
// they're in view, Follow for ghosts, PM and Player panel for admins.

/datum/chatOutput/proc/name_menu_target(ref)
	if(!istext(ref))
		return null
	var/mob/M = locate(ref)
	if(!istype(M) || QDELETED(M))
		return null
	return M

/datum/chatOutput/proc/name_menu_actions(mob/M)
	var/mob/user = owner?.mob
	. = list()
	if(!user || !M)
		return
	if(isobserver(user) || (M in view(user)))
		. += "examine"
	if(isobserver(user) && M != user)
		. += "follow"
	if(owner.holder)
		if(M.client && M.client != owner)
			. += "pm"
		. += "player_panel"

/// The page asked what can be done with a name: answer with the menu
/datum/chatOutput/proc/name_menu_open(list/payload)
	var/mob/M = name_menu_target(payload?["ref"])
	if(!M)
		return
	var/list/actions = name_menu_actions(M)
	if(!length(actions))
		return
	panel_send("hippie/nameMenu", list("ref" = payload["ref"], "name" = "[M.name]", "actions" = actions))

/// A menu entry was clicked: checked again, as the world may have moved since the menu opened
/datum/chatOutput/proc/name_menu_act(list/payload)
	var/mob/M = name_menu_target(payload?["ref"])
	var/action = payload?["action"]
	if(!M || !(action in name_menu_actions(M)))
		return
	var/mob/user = owner.mob
	switch(action)
		if("examine")
			user.examinate(M)
		if("follow")
			var/mob/dead/observer/ghost = user
			ghost.ManualFollow(M)
		if("pm")
			owner.cmd_admin_pm(M.client, null)
		if("player_panel")
			owner.holder.show_player_panel(M)
