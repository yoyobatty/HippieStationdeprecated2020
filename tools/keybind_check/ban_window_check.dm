// The Bans window with a real admin client: each tab pictured, and its buttons clicked the way an admin clicks them (the page's
// own buttons, not ui_act), then what that did checked on the server. Not part of the game:
//   HARNESS=ban_window_check.dm SENDER=shot.ps1 tools/keybind_check/run.sh bans
// Results in data/keycheck_bans.txt, pictures in data/previews/popup_bans_*.png. Its bans, notes and connections go to
// data/ban_window_check/, never data/bans.json and the rest.

GLOBAL_VAR_INIT(keycheck_running, FALSE)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

GLOBAL_VAR_INIT(bw_cleared, FALSE)

/datum/controller/subsystem/bans/load()
	if(!GLOB.bw_cleared)
		GLOB.bw_cleared = TRUE
		fdel("data/ban_window_check/")
	ledger_path = "data/ban_window_check/bans.json"
	seen_path = "data/ban_window_check/connections.json"
	seen_loaded = FALSE
	return ..()

/datum/controller/subsystem/notes/load()
	ledger_path = "data/ban_window_check/notes.json"
	return ..()

/proc/kc_log(text)
	text2file(text, "data/keycheck.txt")

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(50)
			ban_window_check_run(src)

/proc/bw_check(name, ok, detail = "")
	kc_log("[ok ? "PASS" : "FAIL"] [name][detail ? " ([detail])" : ""]")

/proc/bw_shot(name)
	fdel("data/keycheck_shot_title")
	text2file("popup_bans_[name]", "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/datum/tgui/bw_stub/New()
	status = UI_INTERACTIVE

/proc/bw_act(datum/src_object, mob/user, action, list/params = list())
	var/datum/tgui/bw_stub/stub = new
	usr = user
	. = src_object.ui_act(action, params, stub, GLOB.admin_state)
	SStgui.update_uis(src_object)

/proc/bw_ui(mob/user, datum/src_object)
	var/deadline = world.time + 15 SECONDS
	while(world.time < deadline)
		for(var/datum/tgui/open as anything in user.open_uis)
			if(open.src_object == src_object && open.initialized)
				return open
		sleep(2)

/// One thing done on the page, then a second for the server to hear it and the page to redraw. "click:<text>" presses the first
/// button whose text starts with it; "pick:<css>|<text>" clicks the first element matching css whose text starts with text;
/// "pickin:<css>|<inner css>|<container text>|<text>" the same inside the first container that has container text;
/// "textarea:<text>" fills the first box of text; "type<N>:<text>" types in the Nth one-line box and leaves it.
/proc/bw_do(client/C, datum/tgui/ui, action)
	var/js
	if(findtext(action, "click:") == 1)
		js = "var t=[json_encode(copytext(action, 7))];var b=Array.prototype.slice.call(document.querySelectorAll('.Button')).filter(function(e){return e.textContent.trim().indexOf(t)===0;})\[0\];if(b){b.click();}"
	else if(findtext(action, "pick:") == 1)
		var/list/bits = splittext(copytext(action, 6), "|")
		js = "var t=[json_encode(bits[2])];var b=Array.prototype.slice.call(document.querySelectorAll([json_encode(bits[1])])).filter(function(e){return e.textContent.trim().indexOf(t)===0;})\[0\];if(b){b.click();}"
	else if(findtext(action, "pickin:") == 1)
		var/list/bits = splittext(copytext(action, 8), "|")
		js = "var c=Array.prototype.slice.call(document.querySelectorAll([json_encode(bits[1])])).filter(function(e){return e.textContent.indexOf([json_encode(bits[3])])>=0;})\[0\];if(c){var t=[json_encode(bits[4])];var b=Array.prototype.slice.call(c.querySelectorAll([json_encode(bits[2])])).filter(function(e){return e.textContent.trim().indexOf(t)===0;})\[0\];if(b){b.click();}}"
	else if(findtext(action, "textarea:") == 1)
		js = "var a=document.querySelector('textarea');if(a){a.focus();a.value=[json_encode(copytext(action, 10))];a.dispatchEvent(new Event('input',{bubbles:true}));}"
	else if(findtext(action, "type") == 1)
		var/colon = findtext(action, ":")
		var/index = text2num(copytext(action, 5, colon))
		js = "var i=document.querySelectorAll('input')\[[index]\];if(i){i.focus();i.value=[json_encode(copytext(action, colon + 1))];i.dispatchEvent(new Event('input',{bubbles:true}));i.blur();}"
	else if(findtext(action, "scroll:") == 1)
		var/list/bits = splittext(copytext(action, 8), "|")
		js = "var e=document.querySelector([json_encode(bits[1])]);if(e){e.scrollTop=[text2num(bits[2])];}"
	if(js)
		C << output(url_encode(js), "[ui.window_id].browser:eval")
	sleep(10)

/proc/bw_record(role, player_ckey, key, ip, cid, reason, hours_ago, length_hours)
	var/datum/ban_record/B = new
	B.role = role
	B.ckey = player_ckey
	B.key = key
	B.ip = ip
	B.cid = cid
	B.bantime_rt = world.realtime - hours_ago * 36000
	B.bantime = SQLtime(B.bantime_rt)
	if(length_hours)
		B.amount = length_hours
		B.unit = "HOUR"
		B.expire_rt = B.bantime_rt + length_hours * 36000
	B.reason = reason
	B.a_ckey = "moderatormaya"
	B.a_key = "Moderator Maya"
	B.round_id = "1041"
	return B

/proc/bw_note(kind, player_ckey, key, text, severity, days_ago, secret = TRUE)
	SSnotes.add(kind, player_ckey, key, "moderatormaya", "Moderator Maya", text, secret, null, severity, SQLtime(world.realtime - days_ago * 864000))
	var/datum/note_record/R = SSnotes.records[SSnotes.records[SSnotes.records.len]]
	R.timestamp_rt = world.realtime - days_ago * 864000

/proc/bw_seed()
	SSbans.note_seen("griefermcgee", "Griefer McGee", "203.0.113.7", "1234567890")
	SSbans.note_seen("griefermcgee", "Griefer McGee", "203.0.113.8", "1234567890")
	SSbans.note_seen("altaccount", "Alt Account", "203.0.113.50", "1234567890")
	SSbans.note_seen("roommate", "Room Mate", "203.0.113.8", "5550001111")
	SSbans.note_seen("regularrita", "Regular Rita", "198.51.100.4", "2223334444")
	SSbans.note_left("griefermcgee", "Greg Tide", "Assistant")
	SSbans.note_left("regularrita", "Rita Ross", "Botanist")
	SSbans.note_left("roommate", "Ronald Mate", "Cook")
	SSbans.add_bans(list(bw_record("Cook", "griefermcgee", "Griefer McGee", null, "1234567890", "Put plasma in the burgers", 20, 48)))
	var/list/rascal = list()
	for(var/role in list("Security Officer", "Warden", "Detective"))
		rascal += bw_record(role, "rolerascal", "Role Rascal", null, "7778889999", "Valid-hunted as Security three rounds running", 5, 72)
	SSbans.add_bans(rascal)
	SSbans.add_bans(list(bw_record("Server", "permapete", "Perma Pete", "192.0.2.10", "4445556666", "Ban evasion on three alts", 200, 0)))
	SSbans.add_bans(list(bw_record("Server", "shortsteve", "Short Steve", null, "1112223333", "Spamming OOC after a warning", 1, 3)))
	SSbans.add_bans(list(bw_record("Server", "oldoffender", "Old Offender", null, null, "Self-antagging", 80, 24)))
	var/datum/ban_record/lifted = bw_record("Server", "liftedlarry", "Lifted Larry", null, null, "Mistaken identity", 30, 168)
	SSbans.add_bans(list(lifted))
	SSbans.lift(lifted.id, "moderatormaya", "Moderator Maya", "127.0.0.1", "1")
	var/list/antags = list()
	for(var/role in list(ROLE_TRAITOR, ROLE_CHANGELING, ROLE_OPERATIVE))
		antags += bw_record(role, "antagannie", "Antag Annie", null, null, "Killed the whole crew as a traitor with no objective to", 30, 336)
	SSbans.add_bans(antags)
	bw_note("note", "griefermcgee", "Griefer McGee", "Threw glasses at people in the bar. Warned.", "minor", 40)
	bw_note("note", "griefermcgee", "Griefer McGee", "Plasma in the burgers: banned from Cook for two days.", "medium", 1)
	bw_note("watchlist entry", "griefermcgee", "Griefer McGee", "Watch for bar and kitchen griefing.", null, 1)
	bw_note("message", "regularrita", "Regular Rita", "Please read the botany rules before planting kudzu again.", null, 3, FALSE)
	bw_note("memo", "moderatormaya", "Moderator Maya", "Remember: ban appeals go on the forum, not in ahelps.", null, 5, FALSE)

/proc/ban_window_check_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	var/turf/home = get_turf(pick(SSjob.latejoin_trackers))
	var/mob/living/carbon/human/H = new(home)
	H.mind_initialize()
	H.fully_replace_character_name(null, "Alex Admin")
	H.equipOutfit(/datum/outfit/job/assistant)
	H.ckey = C.ckey
	sleep(3 SECONDS)
	if(!C.holder)
		var/datum/admins/A = new(new /datum/admin_rank("!localhost!", R_EVERYTHING, R_DBRANKS, R_EVERYTHING), C.ckey, 1, 1)
		A.associate(C)
	sleep(2 SECONDS)
	usr = H
	bw_check("the admin's own connection is remembered", SSbans.seen[C.ckey] && SSbans.seen[C.ckey]["key"] == C.key)
	bw_seed()
	bw_new_ban(C, H)
	bw_list(C, H)
	bw_sticky(C, H)
	bw_notes(C, H)
	bw_old_links(C, H)
	bw_kept(C, H)
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)

/proc/bw_new_ban(client/C, mob/living/carbon/human/H)
	C.open_ban_window("new", list("key" = "Griefer McGee"))
	var/datum/ban_window/W = C.ban_window
	var/datum/tgui/ui = bw_ui(H, W)
	bw_check("the window opens on New ban for the player", ui && W.tab == "new")
	sleep(2 SECONDS)
	bw_check("the form gets their last IP and computer, with no database", W.prefill["ip"] == "203.0.113.8" && W.prefill["cid"] == "1234567890", "[W.prefill["ip"]] [W.prefill["cid"]]")
	bw_check("their record: left as Greg Tide, the alt on their computer, the Cook ban, their notes", W.record && W.record["status"] == "left" && W.record["name"] == "Greg Tide" && ("Alt Account" in W.record["same_computer"]) && ("Room Mate" in W.record["same_ip"]) && W.record["role_bans_raw"]["cook"] && length(W.record["notes_raw"]) == 3)
	bw_shot("new_record")
	bw_do(C, ui, "click:Players")
	bw_shot("new_picker")
	bw_do(C, ui, "click:Players")
	//a ban with no reason is refused, in the window
	bw_do(C, ui, "click:Ban")
	bw_do(C, ui, "click:Ban")
	var/server_before = 0
	for(var/datum/ban_record/B in SSbans.matching("griefermcgee"))
		if(B.role == "Server")
			server_before++
	bw_check("a ban with no reason or severity isn't made, and the window says why", W.notice_bad && findtext(W.notice, "Write a reason") && findtext(W.notice, "severity") && !server_before, W.notice)
	bw_do(C, ui, "click:3d")
	bw_do(C, ui, "pick:.BanWindow__check|IP")
	bw_do(C, ui, "click:Medium")
	bw_do(C, ui, "textarea:Threw glasses at people in the bar again, after a warning.")
	bw_shot("new_filled")
	bw_do(C, ui, "click:Ban")
	bw_do(C, ui, "click:Ban")
	sleep(1 SECONDS)
	var/list/server_bans = list()
	for(var/datum/ban_record/B in SSbans.matching("griefermcgee"))
		if(B.role == "Server")
			server_bans += B
	var/datum/ban_record/made = length(server_bans) ? server_bans[1] : null
	bw_check("clicking Ban twice makes the server ban, with the IP and computer from the last connection", made && made.ip == "203.0.113.8" && made.cid == "1234567890" && made.a_ckey == C.ckey, made ? "[made.ip] [made.cid] [made.a_ckey]" : W.notice)
	bw_check("three days long", made && abs((made.expire_rt - made.bantime_rt) - 3 * 864000) < 1000)
	var/list/kept_out = world.IsBanned("Alt Account", "203.0.113.50", "1234567890", "world")
	bw_check("it keeps out the alt on the same computer", islist(kept_out))
	var/list/note = null
	for(var/list/row in SSnotes.rows_for("griefermcgee"))
		if(findtext(row["text"], "Banned from the server"))
			note = row
	bw_check("it writes the note with its severity, with no database", note && note["severity"] == "medium", note ? note["text"] : "no note")
	bw_check("the window says what was done", !W.notice_bad && findtext(W.notice, "Banned Griefer McGee from the server for 3d"), W.notice)
	bw_shot("new_banned")
	//a role ban, picked on the grid
	bw_do(C, ui, "click:Roles")
	bw_do(C, ui, "pick:.BanWindow__chip|Botanist")
	bw_do(C, ui, "pick:.BanWindow__chip|Bartender")
	bw_do(C, ui, "click:1w")
	bw_do(C, ui, "click:Minor")
	bw_do(C, ui, "textarea:Cut down the trays to make a kudzu farm.")
	bw_do(C, ui, "scroll:.BanWindow__form|400")
	bw_shot("new_roles")
	bw_do(C, ui, "click:Ban")
	bw_do(C, ui, "click:Ban")
	sleep(1 SECONDS)
	bw_check("a role ban from the grid holds both roles", is_banned_from("griefermcgee", "Botanist") && is_banned_from("griefermcgee", "Bartender") && !is_banned_from("griefermcgee", "Janitor"))
	var/list/rows = W.find_rows("griefermcgee", null, list("active"))
	var/list/groups = W.group_rows(rows)
	bw_check("and the two are one ban in the list", length(groups) == 3, "[length(groups)] groups: [length(rows)] rows")
	bw_check("the grid marks them banned, with the time left", W.record && W.record["role_bans_raw"]["botanist"] && W.record["role_bans_raw"]["bartender"])
	//lifting the Cook ban from the grid's x
	bw_do(C, ui, "click:Roles")
	bw_do(C, ui, "scroll:.BanWindow__form|400")
	bw_shot("new_grid_banned")
	bw_do(C, ui, "pickin:.BanWindow__chip--banned|.BanWindow__chipX|Cook|")
	sleep(1 SECONDS)
	bw_check("the x on a banned role lifts it", !is_banned_from("griefermcgee", "Cook") && is_banned_from("griefermcgee", "Botanist") && findtext(W.notice, "Lifted"), W.notice)

/proc/bw_list(client/C, mob/living/carbon/human/H)
	var/datum/ban_window/W = C.ban_window
	var/datum/tgui/ui = bw_ui(H, W)
	bw_do(C, ui, "pick:.BanWindow__tab|Bans")
	sleep(1 SECONDS)
	bw_check("the Bans tab opens on the active bans", W.tab == "bans" && W.show_active && !W.show_lifted && length(W.groups) >= 6, "[length(W.groups)] groups")
	var/list/rascal
	for(var/list/G in W.groups)
		var/list/first = G["rows"][1]
		if(first["ckey"] == "rolerascal")
			rascal = G
	bw_check("the three role bans made together are one row", rascal && length(rascal["rows"]) == 3)
	var/list/order = list()
	for(var/list/G in W.groups)
		var/list/first = G["rows"][1]
		order |= first["ckey"]
	bw_check("ending soonest first, permanent ones after", order.Find("shortsteve") < order.Find("rolerascal") && order.Find("rolerascal") < order.Find("permapete"), order.Join(", "))
	bw_shot("list")
	//one role lifted from its chip: a click arms it, the next lifts
	bw_do(C, ui, "pickin:.BanWindow__group|.BanWindow__chip|Role Rascal|Warden")
	bw_do(C, ui, "pickin:.BanWindow__group|.BanWindow__chip|Role Rascal|Warden")
	sleep(1 SECONDS)
	bw_check("a role chip's two clicks lift just that role", !is_banned_from("rolerascal", "Warden") && is_banned_from("rolerascal", "Detective") && is_banned_from("rolerascal", "Security Officer"))
	//the group edited: Detective off, Head of Security on, a week, a new reason
	bw_do(C, ui, "pickin:.BanWindow__group|.Button|Role Rascal|Edit")
	bw_do(C, ui, "pickin:.BanWindow__edit|.BanWindow__chip|Roles|Detective")
	bw_do(C, ui, "pickin:.BanWindow__edit|.BanWindow__chip|Roles|Head of Security")
	bw_do(C, ui, "pickin:.BanWindow__edit|.Button|Roles|1w")
	bw_do(C, ui, "textarea:Valid-hunted as Security three rounds running, then argued in ahelp.")
	bw_shot("list_edit")
	bw_do(C, ui, "pickin:.BanWindow__edit|.Button|Roles|Save")
	sleep(1 SECONDS)
	bw_check("the edit lifts the role taken off and bans the one added", !is_banned_from("rolerascal", "Detective") && is_banned_from("rolerascal", "Head of Security") && is_banned_from("rolerascal", "Security Officer"), W.notice)
	var/list/rascal_rows = W.find_rows("rolerascal", null, list("active"))
	var/list/rascal_groups = W.group_rows(rascal_rows)
	var/list/kept = rascal_groups.len ? rascal_groups[1] : null
	var/same_time = kept && length(kept["rows"]) == 2
	var/new_reason = TRUE
	var/week = TRUE
	for(var/list/row in rascal_rows)
		if(!findtext(row["reason"], "argued in ahelp"))
			new_reason = FALSE
		if(abs((row["expire_rt"] - row["bantime_rt"]) - 7 * 864000) > 1000)
			week = FALSE
	bw_check("the added role joins the same ban, with the new reason and a week from when it was made", same_time && new_reason && week, "[length(rascal_groups)] groups, [W.notice]")
	bw_shot("list_after")
	//searching, and the lifted ones
	bw_do(C, ui, "type0:perma")
	sleep(1 SECONDS)
	bw_check("search by part of a key", length(W.groups) == 1 && W.search == "perma", "[length(W.groups)]")
	bw_do(C, ui, "type0:")
	bw_do(C, ui, "pick:.BanWindow__chip|Lifted")
	sleep(1 SECONDS)
	var/has_larry = FALSE
	for(var/list/G in W.groups)
		var/list/first = G["rows"][1]
		if(first["ckey"] == "liftedlarry")
			has_larry = TRUE
	bw_check("Lifted shows the lifted ones too", W.show_lifted && has_larry)

/proc/bw_sticky(client/C, mob/living/carbon/human/H)
	var/datum/ban_window/W = C.ban_window
	var/datum/tgui/ui = bw_ui(H, W)
	bw_do(C, ui, "pick:.BanWindow__tab|Sticky")
	bw_do(C, ui, "type0:Sticky Sam")
	bw_do(C, ui, "type1:Ban evasion: every alt gets caught")
	bw_do(C, ui, "click:Sticky ban")
	sleep(1 SECONDS)
	bw_check("a sticky ban made in the window", get_stickyban_from_ckey("stickysam") && length(W.sticky) == 1, "[length(W.sticky)]")
	bw_shot("sticky")
	bw_do(C, ui, "pickin:.BanWindow__group|.Button|stickysam|Remove")
	bw_do(C, ui, "pickin:.BanWindow__group|.Button|stickysam|Remove it?")
	sleep(1 SECONDS)
	var/still_there = FALSE
	for(var/list/S in W.sticky)
		if(S["ckey"] == "stickysam")
			still_there = TRUE
	bw_check("and removed with two clicks, no popup", !get_stickyban_from_ckey("stickysam") && !still_there)
	//BYOND keeps sticky bans for every SS13 world on this machine (Documents/BYOND/cfg/ban.txt): never leave one behind
	if(get_stickyban_from_ckey("stickysam"))
		world.SetConfig("ban", "stickysam", null)

/proc/bw_notes(client/C, mob/living/carbon/human/H)
	var/datum/ban_window/W = C.ban_window
	var/datum/tgui/ui = bw_ui(H, W)
	bw_do(C, ui, "pick:.BanWindow__tab|Notes")
	bw_do(C, ui, "pick:.BanWindow__player|Griefer McGee")
	sleep(1 SECONDS)
	bw_check("Notes: the players with notes, and one picked", W.notes_view == "player" && W.notes_ckey == "griefermcgee" && length(W.notes_players) == 2, "[length(W.notes_players)] players")
	bw_shot("notes")
	bw_do(C, ui, "click:Note")
	bw_do(C, ui, "click:High")
	bw_do(C, ui, "textarea:Admitted the glasses were on purpose.")
	bw_shot("notes_compose")
	bw_do(C, ui, "click:Add")
	sleep(1 SECONDS)
	var/list/added
	for(var/list/row in SSnotes.rows_for("griefermcgee"))
		if(findtext(row["text"], "on purpose"))
			added = row
	bw_check("a note written in the window, with its severity, kept with no database", added && added["severity"] == "high" && added["local"], W.notice)
	bw_act(W, H, "note_severity", list("id" = added?["id"], "severity" = "minor"))
	bw_check("its severity changed", SSnotes.get_row(added?["id"])?["severity"] == "minor")
	bw_do(C, ui, "click:Memos")
	sleep(1 SECONDS)
	bw_check("Memos", W.notes_view == "memos" && length(W.notes_rows) == 1)
	bw_shot("memos")
	bw_do(C, ui, "click:Watchlist")
	sleep(1 SECONDS)
	bw_check("Watchlist", W.notes_view == "watchlist" && length(W.notes_rows) == 1)
	bw_shot("watchlist")

//The old ways in: the player panel's Ban link, the notes links, the verbs
/proc/bw_old_links(client/C, mob/living/carbon/human/H)
	var/datum/ban_window/W = C.ban_window
	C.holder.ban_panel("Regular Rita")
	bw_check("the player panel's Ban link opens New ban for them", W.tab == "new" && W.record?["key"] == "Regular Rita" && W.prefill["cid"] == "2223334444")
	C.holder.unban_panel("Perma Pete")
	bw_check("the old Unbanning Panel opens the list on them", W.tab == "bans" && W.search == "Perma Pete" && length(W.groups) == 1)
	browse_messages(target_ckey = "regularrita")
	bw_check("a player's notes link opens Notes on them", W.tab == "notes" && W.notes_view == "player" && W.notes_ckey == "regularrita")
	create_message("watchlist entry", "Regular Rita", secret = 1)
	bw_check("Add to watchlist opens the box to write it", W.compose && W.compose["kind"] == "watchlist entry")
	C.holder.stickyban_show()
	bw_check("the Sticky Ban Panel verb opens Sticky", W.tab == "sticky")
	C.cmd_admin_notes()
	bw_check("the Notes verb opens Notes", W.tab == "notes" && W.notes_view == "index")

//Everything made in the window still there after a restart
/proc/bw_kept(client/C, mob/living/carbon/human/H)
	var/bans = SSbans.records.len
	var/notes = SSnotes.records.len
	SSbans.save_seen()
	SSbans.load()
	SSnotes.load()
	bw_check("after a restart the bans, notes and connections are all back", SSbans.records.len == bans && SSnotes.records.len == notes && SSbans.last_seen_address("griefermcgee", "cids") == "1234567890" && is_banned_from("griefermcgee", "Botanist"), "[SSbans.records.len]/[bans] [SSnotes.records.len]/[notes]")
