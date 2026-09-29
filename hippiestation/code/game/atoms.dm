/atom
	var/icon_hippie
	var/next_spam_shot = 0

///The icon states of each icon_hippie file, as state = TRUE; icon_states() rebuilds its whole list every call (~24us)
GLOBAL_LIST_EMPTY(hippie_icon_states)

/atom/proc/check_hippie_icon()
	if (!icon || !istext(icon_state) || !icon_state || !icon_hippie)
		return
	var/list/states = GLOB.hippie_icon_states[icon_hippie]
	if (!states)
		states = list()
		if (length(icon_hippie) > 0)
			for (var/state in icon_states(icon_hippie))
				states[state] = TRUE
		GLOB.hippie_icon_states[icon_hippie] = states
	if (!states[icon_state])
		return
	icon = icon_hippie

/atom/Initialize()
	. = ..()
	if(icon_hippie) // hippie -- skip the proc call entirely for the vast majority of atoms that never set this
		check_hippie_icon()
