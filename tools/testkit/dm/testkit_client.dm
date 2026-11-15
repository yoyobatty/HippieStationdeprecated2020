// Testkit real-client lane: a DreamSeeker on this machine connects (tools/testkit/client_lane.py), its view is put where a picture is
// wanted, and the script takes the window's picture. The client can come in as the user's own BYOND key, so nothing it does is saved.

/datum/preferences/save_preferences()
	if(GLOB.testkit)
		return TRUE // a test client may be the user's own key: their saved preferences stay as they are
	return ..()

/datum/preferences/save_character()
	if(GLOB.testkit)
		return TRUE
	return ..()

/datum/testkit
	/// The client that connected last
	var/client/viewer
	var/mob/dead/observer/viewer_eye

/client/New()
	. = ..()
	if(GLOB.testkit)
		GLOB.testkit.viewer = src
		GLOB.testkit.event("client.login", list("ckey" = ckey))

/datum/testkit/proc/cmd_client_view(list/a)
	var/client/C = viewer
	if(!C)
		CRASH("no client connected")
	var/turf/T = a["at"] ? need(where(a["at"]), "place [json_encode(a["at"])]") : null
	if(!T)
		T = get_turf(C.mob) || arena_middle("[next_arena]")
	if(QDELETED(viewer_eye) || C.mob != viewer_eye)
		viewer_eye = new(null) // observer/New() takes its argument as a body, not a place
		viewer_eye.name = "Testkit Camera"
		viewer_eye.ckey = C.ckey
	viewer_eye.forceMove(T)
	if(a["zoom"])
		C.change_view(a["zoom"])
	return list("at" = out(T), "ckey" = C.ckey, "view" = C.view)

/// winset() on the client: "command=.quit" closes it, "mapwindow.map.zoom=2" and so on
/datum/testkit/proc/cmd_client_winset(list/a)
	if(!viewer)
		CRASH("no client connected")
	winset(viewer, a["control"], a["params"])
	return TRUE

/datum/testkit/proc/cmd_client_info(list/a)
	if(!viewer)
		return null
	return list("ckey" = viewer.ckey, "mob" = out(viewer.mob), "view" = viewer.view, "hwmode" = winget(viewer, null, "hwmode"))
