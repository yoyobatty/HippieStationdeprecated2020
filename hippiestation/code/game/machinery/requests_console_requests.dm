// hippie -- what requests consoles send is tracked: each message is a request the receiving department can mark "on it"
// (with who) or "done", and the sending console lists its own with where they stand. Quick requests send a common ask (a
// doctor, cleaning, repairs, Security, a breach) with the room in one click, and the Supplies tab can ask Cargo for a crate,
// into the cargo console's request list. Bot crew answer these (bots_ai/goals/station_requests.dm).
// Everything still goes out the old way, through the console's Topic() "send": the message server, the department radio,
// the beep.

/// A request went out: (datum/station_request/R). Bot crew listen for it
#define COMSIG_GLOB_STATION_REQUEST "!station_request"

GLOBAL_LIST_EMPTY(station_requests)
GLOBAL_LIST_EMPTY(station_requests_by_id)
GLOBAL_VAR_INIT(station_request_count, 0)
/// The request going out right now, for the consoles it lands on to tie their message to
GLOBAL_DATUM(station_request_sending, /datum/station_request)

/// What a quick request asks for: department, the words, icon, priority
GLOBAL_LIST_INIT(req_quick_requests, list(
	"Doctor" = list("Medbay", "A doctor is needed", "user-md", REQ_NORMAL_MESSAGE_PRIORITY),
	"Cleaning" = list("Janitorial", "Cleaning is needed", "broom", REQ_NORMAL_MESSAGE_PRIORITY),
	"Repairs" = list("Engineering", "Repairs are needed", "wrench", REQ_NORMAL_MESSAGE_PRIORITY),
	"Security" = list("Security", "Security is needed", "shield-alt", REQ_HIGH_MESSAGE_PRIORITY),
	"Breach" = list("Engineering", "There's a hull breach", "wind", REQ_HIGH_MESSAGE_PRIORITY),
))

#define REQ_QUICK_COOLDOWN (30 SECONDS)

/datum/station_request
	var/id
	var/from_dept
	var/to_dept
	var/priority
	var/body
	/// Who sent it: their ID if they swiped or wore one, or null
	var/sender
	/// Whoever was at the console, for those answering to find
	var/datum/weakref/sender_ref
	/// Where it was sent from
	var/area_name
	var/turf/location
	/// "message", a quick request's name, or "crate"
	var/kind = "message"
	var/time
	/// "new", "on it" or "done"
	var/status = "new"
	var/handler
	var/handled_time
	/// A crate request's order, in SSshuttle.requestlist
	var/datum/supply_order/order

/datum/station_request/proc/set_status(new_status, who)
	status = new_status
	handler = who
	handled_time = station_time_timestamp()

/obj/machinery/requests_console
	/// What the last button did, at the top until the next: list(text, "good"/"bad")
	var/list/req_notice
	/// When each quick request can next be sent from here
	var/list/quick_ready = list()

/// Who's at the console, by the ID they're wearing or holding, as the requests console would read a swipe
/obj/machinery/requests_console/proc/req_who(mob/user)
	var/obj/item/card/id/ID = user?.get_idcard(TRUE)
	if(istype(ID))
		return "[ID.registered_name] ([ID.assignment])"
	if(issilicon(user))
		return "[user.name] ([user.job])"
	return null

/// Sends what's set up (to_department, message, priority, the validation) through Topic() as one tracked request.
/// TRUE if it went
/obj/machinery/requests_console/proc/req_send(kind = "message", datum/supply_order/order)
	var/datum/station_request/R = new
	R.id = ++GLOB.station_request_count
	R.from_dept = department
	R.to_dept = to_department
	R.priority = priority
	R.body = comm_plain_text(message)
	R.sender = msgVerified ? comm_plain_text(msgVerified) : null
	R.sender_ref = WEAKREF(usr)
	var/area/A = get_area(src)
	R.area_name = A ? get_area_name(A, TRUE) : null
	R.location = get_turf(src)
	R.kind = kind
	R.order = order
	R.time = station_time_timestamp()
	GLOB.station_request_sending = R
	Topic(null, list("send" = "1"))
	GLOB.station_request_sending = null
	if(screen != 6) // REQ_SCREEN_SENT
		return FALSE
	GLOB.station_requests += R
	GLOB.station_requests_by_id["[R.id]"] = R
	SEND_GLOBAL_SIGNAL(COMSIG_GLOB_STATION_REQUEST, R)
	return TRUE

/// One click: the ask, the room, who's asking
/obj/machinery/requests_console/proc/req_quick(name, mob/user)
	var/list/quick = GLOB.req_quick_requests[name]
	if(!quick || !GLOB.req_console_ckey_departments[ckey(quick[1])] || ckey(quick[1]) == ckey(department))
		return
	if(quick_ready[name] > world.time)
		req_notice = list("[name] was just asked for from here. Give them a moment.", "bad")
		return
	var/area/A = get_area(src)
	to_department = GLOB.req_console_ckey_departments[ckey(quick[1])]
	message = "[quick[2]] in [A ? get_area_name(A, TRUE) : department]."
	priority = quick[4]
	var/who = req_who(user)
	msgVerified = who ? "<font color='green'><b>Verified by [who]</b></font>" : ""
	msgStamped = ""
	if(req_send(name))
		quick_ready[name] = world.time + REQ_QUICK_COOLDOWN
		req_notice = list("[name] asked for from [to_department].", "good")
	else
		req_notice = list("Couldn't reach [to_department]: the request didn't go through.", "bad")
	screen = 0
	to_department = ""
	message = ""
	msgVerified = ""

/// A crate for Cargo: into the cargo console's request list as that console's request button would put it, and a tracked
/// message to Cargo Bay so they hear about it
/obj/machinery/requests_console/proc/req_crate(pack_path, reason, mob/user)
	var/datum/supply_pack/pack = SSshuttle.supply_packs[pack_path]
	if(!istype(pack) || pack.hidden || pack.contraband || pack.DropPodOnly || (pack.special && !pack.special_enabled))
		return
	var/name = "*None Provided*"
	var/rank = "*None Provided*"
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		name = H.get_authentification_name()
		rank = H.get_assignment(hand_first = TRUE)
	else if(issilicon(user))
		name = user.real_name
		rank = "Silicon"
	reason = stripped_input_text(reason, MAX_MESSAGE_LEN) || ""
	var/datum/supply_order/SO = new(pack, name, rank, user.ckey, reason, null)
	SSshuttle.requestlist += SO
	log_game("[key_name(user)] requested a [pack.name] crate from [src] at [AREACOORD(src)].")
	if(GLOB.req_console_ckey_departments["cargobay"] && ckey(department) != "cargobay")
		to_department = GLOB.req_console_ckey_departments["cargobay"]
		message = "Crate requested: [pack.name][reason ? " ([reason])" : ""]. It's in the cargo console's requests."
		priority = REQ_NORMAL_MESSAGE_PRIORITY
		var/who = req_who(user)
		msgVerified = who ? "<font color='green'><b>Verified by [who]</b></font>" : ""
		msgStamped = ""
		req_send("crate", SO)
	req_notice = list("Requested a [pack.name] crate from Cargo: it's in their request list.", "good")
	screen = 2 // REQ_SCREEN_REQ_SUPPLIES
	to_department = ""
	message = ""
	msgVerified = ""

#undef REQ_QUICK_COOLDOWN
