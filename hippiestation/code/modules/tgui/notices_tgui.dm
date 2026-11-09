// hippie -- OOC pages that were plain HTML popups, in a tgui window (interfaces/HtmlNotice.js): Show Policy, View tracked playtime and
// the warning that your BYOND version is getting old. Their text is the server's own HTML (the policy config, get_exp_report(), the
// warn message config), shown as it always was.

/datum/html_notice
	var/datum/weakref/client_ref
	var/title
	var/html
	var/icon

/datum/html_notice/New(client/C, title, html, icon)
	client_ref = WEAKREF(C)
	src.title = title
	src.html = html
	src.icon = icon

/// Opens a notice for this client; the window goes away when it's closed
/proc/show_html_notice(client/C, title, html, icon = "info-circle", width = 520, height = 480)
	if(!C?.mob)
		return
	var/datum/html_notice/N = new(C, title, html, icon)
	N.open(C.mob, width, height)

/datum/html_notice/proc/open(mob/user, width, height)
	var/datum/tgui/ui = new(user, src, "main", "html_notice", title, width, height, null, GLOB.always_state)
	ui.open()

/datum/html_notice/ui_status(mob/user, datum/ui_state/state)
	var/client/C = client_ref?.resolve()
	return (C && user.client == C) ? UI_INTERACTIVE : UI_CLOSE

/datum/html_notice/ui_close(mob/user)
	qdel(src)

/datum/html_notice/ui_static_data(mob/user)
	return list("title" = title, "html" = html, "icon" = icon)

// Show Policy
/client/policy()
	set name = "Show Policy"
	set desc = "Show special server rules related to your current character."
	set category = "OOC"
	var/list/keywords = mob.get_policy_keywords()
	var/list/policytext = list(get_policy(POLICY_VERB_HEADER), "<hr>")
	var/anything = FALSE
	for(var/keyword in keywords)
		var/p = get_policy(keyword)
		if(p)
			policytext += p
			policytext += "<hr>"
			anything = TRUE
	if(!anything)
		policytext += "No related rules found."
	show_html_notice(src, "Policy", policytext.Join(""), "gavel")

// View tracked playtime
/client/self_playtime()
	set name = "View tracked playtime"
	set category = "OOC"
	set desc = "View the amount of playtime for roles the server has tracked."
	if(!CONFIG_GET(flag/use_exp_tracking))
		to_chat(usr, "<span class='notice'>Sorry, tracking is currently disabled.</span>")
		return
	var/datum/playtime_window/W = new(src) // admin_logs_tgui.dm: the admin's playtime report, without the admin's buttons
	W.ui_interact(mob)
