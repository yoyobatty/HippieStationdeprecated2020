// The bots' telemetry (bot_telemetry.dm) for one real player: where they are, who's around them, what they click and press, what they
// carry and which machines they use. It's how a bot gets compared with a person, and what a playstyle modelled on one is built from.
// Keys, steps and what each key changed are in here too, so what the keyboard did can be checked against what the character did.
// PLAYER_LOG_CKEY in hippiestation_config.txt names the player, and nobody else is ever recorded.
//
// Hits, throws, strips and speech aren't here: attack.log, game.log and telecomms.log already have them, on the same clock.
//
// Output: data/logs/<round>/player_telemetry.jsonl, in bot_telemetry.jsonl's format: "k":"s" a sample every half second, "k":"e" an event.

#define PLAYER_LOG_SAMPLE_INTERVAL 5 //deciseconds, the same as the bots
#define PLAYER_LOG_VIEW_RANGE 7
#define PLAYER_LOG_MOST_NEARBY 6
/// Samples between looks at their job and what they are, which only change once or twice a round.
#define PLAYER_LOG_ROLE_EVERY 20

GLOBAL_DATUM(player_log, /datum/player_log)

/mob/var/datum/player_log/player_log

/datum/player_log
	var/log_file
	/// The living body the player is in, null while they're a ghost.
	var/mob/living/body
	var/last_x
	var/last_y
	var/last_z
	var/last_area
	var/last_role
	var/last_click_time = 0
	var/samples = 0
	/// Whether they were running at the last look, to catch it changing with no key behind it.
	var/last_run
	/// Set for the length of a step they asked for: anything else that moves the body wasn't them.
	var/stepping = FALSE
	/// Held against something, or stunned, it tries every tick: a line a second says as much.
	var/next_stuck_log = 0

/datum/player_log/New()
	. = ..()
	log_file = "[GLOB.log_directory]/player_telemetry.jsonl"
	sample_loop()

/datum/player_log/proc/sample_loop()
	set waitfor = FALSE
	while(TRUE)
		sample()
		sleep(PLAYER_LOG_SAMPLE_INTERVAL)

/mob/Login()
	. = ..()
	if(client?.ckey && client.ckey == CONFIG_GET(string/player_log_ckey))
		if(!GLOB.player_log)
			GLOB.player_log = new
		GLOB.player_log.now_in(src)

/datum/player_log/proc/now_in(mob/M)
	if(M == body)
		return
	if(body)
		let_go_of_body()
	if(isliving(M))
		body = M
		body.player_log = src
		RegisterSignal(body, COMSIG_PARENT_QDELETING, PROC_REF(let_go_of_body))
		RegisterSignal(body, COMSIG_MOVABLE_MOVED, PROC_REF(moved_by_something_else))
	write(list("k" = "e", "ev" = "body", "type" = "[M.type]", "name" = "[M.real_name]"))

/datum/player_log/proc/let_go_of_body()
	UnregisterSignal(body, list(COMSIG_PARENT_QDELETING, COMSIG_MOVABLE_MOVED))
	body.player_log = null
	body = null

/datum/player_log/proc/write(list/record)
	record["t"] = world.time
	record["b"] = body ? body.real_name : "?"
	WRITE_LOG(log_file, json_encode(record))

/datum/player_log/proc/log_event(kind, list/fields)
	var/list/record = list("k" = "e", "ev" = kind)
	if(fields)
		record += fields
	var/turf/T = get_turf(body)
	if(T)
		record["x"] = T.x
		record["y"] = T.y
		record["z"] = T.z
	record["hp"] = body?.health
	write(record)

/datum/player_log/proc/hands()
	var/obj/item/A = body.get_active_held_item()
	var/obj/item/B = body.get_inactive_held_item()
	return list("ah" = A ? "[A.name]" : null, "ih" = B ? "[B.name]" : null)

/// What a key or a click can change, to compare before and after.
/datum/player_log/proc/state_now()
	. = hands()
	.["hand"] = body.active_hand_index
	.["int"] = body.a_intent
	.["run"] = body.m_intent == MOVE_INTENT_RUN ? 1 : 0
	.["thr"] = body.in_throw_mode ? 1 : 0
	.["zone"] = body.zone_selected
	.["rest"] = body.resting ? 1 : 0
	.["pull"] = body.pulling ? "[body.pulling]" : null

/datum/player_log/proc/sample()
	if(QDELETED(body) || !body.client) //a ghost, or logged out
		return
	var/turf/T = get_turf(body)
	if(!T)
		return
	var/moved = T.z == last_z ? max(abs(T.x - last_x), abs(T.y - last_y)) : 0
	last_x = T.x
	last_y = T.y
	last_z = T.z
	var/area/A = T.loc
	if(A.name != last_area)
		last_area = A.name
		log_event("area", list("area" = last_area))
	if(!(samples++ % PLAYER_LOG_ROLE_EVERY))
		note_role()
	var/list/record = list(
		"k" = "s",
		"x" = T.x, "y" = T.y, "z" = T.z,
		"d" = body.dir,
		"mv" = moved,
		"hp" = body.health,
		"stam" = body.getStaminaLoss(),
		"stat" = body.stat,
		"inc" = body.incapacitated() ? 1 : 0,
		"cpu" = world.cpu,
	)
	record += state_now()
	if(!isnull(last_run) && record["run"] != last_run)
		log_event("walk_flip", list("run" = record["run"], "held" = held_keys(body.client)))
	last_run = record["run"]
	// Name, where they are from the player, whether they're up, and their health: how close they fight, and whether they back off
	var/list/near = list()
	for(var/mob/living/carbon/human/H in view(PLAYER_LOG_VIEW_RANGE, body))
		if(H == body)
			continue
		near[++near.len] = list(H.real_name, H.x - T.x, H.y - T.y, H.stat, H.health)
		if(length(near) >= PLAYER_LOG_MOST_NEARBY)
			break
	if(length(near))
		record["near"] = near
	write(record)

/datum/player_log/proc/note_role()
	var/datum/mind/M = body.mind
	if(!M)
		return
	var/list/antags = list()
	for(var/datum/antagonist/A in M.antag_datums)
		antags += A.name
	var/list/objectives = list()
	for(var/datum/objective/O in M.get_all_objectives())
		objectives += O.explanation_text
	var/role = "[M.assigned_role]|[jointext(antags, ",")]|[jointext(objectives, "|")]"
	if(role != last_role)
		last_role = role
		log_event("role", list("job" = M.assigned_role, "antags" = antags, "objectives" = objectives))

// ---------------------------------------------------------------------------------------------
// Clicks and keys
// ---------------------------------------------------------------------------------------------

// Up here rather than on ClickOn(): the HUD, the action buttons and the inventory never get there.
/client/Click(atom/object, atom/location, control, params)
	if(mob?.player_log)
		mob.player_log.clicked(object, params)
	return ..()

/client/MouseDrop(src_object, over_object, src_location, over_location, src_control, over_control, params)
	if(mob?.player_log)
		mob.player_log.dragged(src_object, over_object)
	return ..()

/datum/player_log/proc/clicked(atom/A, params)
	if(!istype(A))
		return
	var/list/record = list("target" = "[A.name]", "target_type" = bot_telemetry_short(A.type), "gap" = world.time - last_click_time,
		"int" = body.a_intent, "zone" = body.zone_selected, "thr" = body.in_throw_mode ? 1 : 0, "cd" = body.next_move > world.time ? 1 : 0)
	last_click_time = world.time
	var/list/mods = params2list(params)
	for(var/modifier in list("shift", "ctrl", "alt", "right", "middle"))
		if(mods[modifier])
			record[modifier] = 1
	var/turf/TT = get_turf(A)
	if(TT)
		record["tx"] = TT.x
		record["ty"] = TT.y
		record["dist"] = get_dist(body, TT)
		record["adj"] = body.Adjacent(A) ? 1 : 0
	if(isliving(A))
		var/mob/living/L = A
		record["tgt_hp"] = L.health
		record["tgt_stat"] = L.stat
	record += hands()
	log_event("click", record)

/datum/player_log/proc/dragged(atom/from, atom/over)
	if(istype(from) && istype(over))
		log_event("drag", list("from" = "[from.name]", "from_type" = bot_telemetry_short(from.type), "over" = "[over.name]", "over_type" = bot_telemetry_short(over.type)))

// ---------------------------------------------------------------------------------------------
// Keys and steps: what was pressed against what happened
// ---------------------------------------------------------------------------------------------

/client/keyDown(_key as text)
	set instant = TRUE
	set hidden = TRUE
	var/datum/player_log/P = mob?.player_log
	if(!P)
		return ..()
	var/list/before = P.state_now()
	var/via = caller?.name
	. = ..()
	P.key_went_down(src, _key, before, via)

/client/keyUp(_key as text)
	set instant = TRUE
	set hidden = TRUE
	var/datum/player_log/P = mob?.player_log
	if(!P)
		return ..()
	var/list/before = P.state_now()
	var/via = caller?.name //a real key comes straight from the client. Topic is a tgui window passing it on, and anything else is the server letting go of a key whose release never came
	. = ..()
	P.key_came_up(src, _key, before, via)

/client/Move(n, direct)
	var/datum/player_log/P = mob?.player_log
	if(!P || !n || !direct || world.time < move_delay) //it's called every tick, key or no key: these are the only calls that can be a step
		return ..()
	var/atom/from = mob.loc
	P.stepping = TRUE
	. = ..()
	P.stepping = FALSE
	P.tried_step(src, direct, from)

/datum/player_log/proc/held_keys(client/C)
	var/list/held = list()
	for(var/i in 1 to HELD_KEY_BUFFER_LENGTH)
		if(C.keys_held[i])
			held += C.keys_held[i]
	return jointext(held, "+")

/// What pressing or letting go of a key changed. Only what's really different, so a hotkey that did nothing shows as nothing.
/datum/player_log/proc/changes_since(list/before)
	var/list/after = state_now()
	last_run = after["run"]
	. = list()
	for(var/thing in after)
		if(after[thing] != before[thing])
			.[thing] = list(before[thing], after[thing])

/datum/player_log/proc/key_went_down(client/C, key, list/before, via)
	if(!body)
		return
	var/mods = "[C.keys_held["Alt"] ? "Alt" : ""][C.keys_held["Ctrl"] ? "Ctrl" : ""][C.keys_held["Shift"] ? "Shift" : ""]"
	var/full_key = (key in list("Alt", "Ctrl", "Shift")) ? mods : "[mods][key]"
	var/list/record = list("key" = key, "held" = held_keys(C), "binds" = C.prefs.key_bindings[full_key], "dir" = C.movement_keys[key])
	var/list/changed = changes_since(before)
	if(length(changed))
		record["chg"] = changed
	if(!C.prefs.hotkeys)
		record["chat"] = 1 //it went to the chat bar instead
	if(via)
		record["via"] = via
	log_event("key", record)

/datum/player_log/proc/key_came_up(client/C, key, list/before, via)
	if(!body)
		return
	var/list/record = list("key" = key, "held" = held_keys(C), "dir" = C.movement_keys[key])
	var/list/changed = changes_since(before)
	if(length(changed))
		record["chg"] = changed
	if(via)
		record["via"] = via
	log_event("key_up", record)

/datum/player_log/proc/tried_step(client/C, direct, atom/from)
	if(QDELETED(body))
		return
	var/moved = body.loc != from
	if(!moved)
		if(world.time < next_stuck_log)
			return
		next_stuck_log = world.time + 1 SECONDS
	log_event("step", list("dir" = direct, "ok" = moved ? 1 : 0, "why" = moved ? null : why_stuck(direct), "held" = held_keys(C), "next" = C.move_delay - world.time))

/datum/player_log/proc/why_stuck(direct)
	if(!(body.mobility_flags & MOBILITY_MOVE))
		return "can't move"
	if(body.pulledby)
		return "held by [body.pulledby]"
	if(body.buckled)
		return "buckled to [body.buckled]"
	if(!isturf(body.loc))
		return "inside [body.loc]"
	var/turf/T = get_step(body, direct)
	if(T?.density)
		return "wall"
	for(var/atom/movable/AM in T)
		if(AM.density)
			return "[AM.name]"
	return "nothing in the way"

/// Shoved, pulled, thrown, conveyed, teleported or carried: a move no key asked for.
/datum/player_log/proc/moved_by_something_else(datum/source, atom/oldloc, dir)
	if(stepping)
		return
	var/turf/was = get_turf(oldloc)
	log_event("moved", list("from_x" = was?.x, "from_y" = was?.y, "from_z" = was?.z, "dir" = dir,
		"by" = body.pulledby ? "pulled by [body.pulledby]" : (body.buckled ? "with [body.buckled]" : (body.throwing ? "thrown" : null))))

// ---------------------------------------------------------------------------------------------
// Machines
// ---------------------------------------------------------------------------------------------

/datum/tgui/Topic(href, href_list)
	var/action = href_list["action"]
	if(user?.player_log && user == usr && action && findtext(action, "tgui:") != 1)
		user.player_log.used_ui(src_object, action, href_list)
	return ..()

/datum/player_log/proc/used_ui(datum/machine, action, list/href_list)
	var/list/details = href_list.Copy()
	details -= "action"
	details -= "src"
	log_event("ui_action", list("machine" = "[machine]", "machine_type" = bot_telemetry_short(machine?.type), "action" = action, "details" = details))

// ---------------------------------------------------------------------------------------------
// Items, on the body the same way the bots' are
// ---------------------------------------------------------------------------------------------

/mob/living/carbon/human/put_in_hand(obj/item/I, hand_index, forced = FALSE, ignore_anim = TRUE)
	if(!player_log || !I)
		return ..()
	var/where = bot_item_where(src, I)
	var/from_type = bot_telemetry_short(I.loc?.type)
	. = ..()
	if(. && where != "active_hand" && where != "inactive_hand")
		player_log.log_event(findtext(where, "carried:") == 1 || where == "worn" ? "draw" : "pickup", list("item" = "[I.name]", "type" = bot_telemetry_short(I.type), "from" = where, "from_type" = from_type))

/mob/living/carbon/human/doUnEquip(obj/item/I, force, newloc, no_move, invdrop = TRUE)
	if(!player_log || !I)
		return ..()
	var/where = bot_item_where(src, I)
	. = ..()
	if(. && !QDELETED(I) && where != "floor" && findtext(where, "in:") != 1)
		player_log.log_event(isturf(I.loc) ? "drop" : "unequip", list("item" = "[I.name]", "was" = where, "to" = isturf(I.loc) ? "floor" : "in:[bot_telemetry_short(I.loc?.type)]"))

/mob/living/carbon/human/equip_to_slot(obj/item/I, slot)
	if(!player_log || !I)
		return ..()
	var/where = bot_item_where(src, I)
	. = ..()
	player_log.log_event("equip", list("item" = "[I.name]", "slot" = slot, "from" = where))

#undef PLAYER_LOG_SAMPLE_INTERVAL
#undef PLAYER_LOG_VIEW_RANGE
#undef PLAYER_LOG_MOST_NEARBY
#undef PLAYER_LOG_ROLE_EVERY
