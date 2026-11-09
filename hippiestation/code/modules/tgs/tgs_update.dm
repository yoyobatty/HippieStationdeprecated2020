// Update Server (+SERVER): pulls the latest code from GitHub into TGS's repository, keeping test merges, then deploys it;
// it goes live next round. The game only asks. TGS runs the HippieUpdate script in the instance's EventScripts folder
// (from tools/tgs_scripts), which holds a TGS login and makes the calls, then writes how it went to data/tgs_update.json.
// TgsTriggerDeployment() alone would only rebuild the code TGS already has.

#define TGS_UPDATE_EVENT "HippieUpdate"
#define TGS_UPDATE_RESULT_FILE "data/tgs_update.json"
/// How long to wait for the pull before telling the admin to look in TGS
#define TGS_UPDATE_WAIT (20 MINUTES)

GLOBAL_VAR_INIT(tgs_update_running, FALSE)
GLOBAL_PROTECT(tgs_update_running)

/world/AVerbsServer()
	. = ..()
	. += /client/proc/tgs_update_server

/client/proc/tgs_update_server()
	set category = "Server"
	set name = "Update Server"
	set desc = "Pull the latest code from GitHub and deploy it through TGS. It goes live next round."
	if(!check_rights(R_SERVER))
		return
	if(!world.TgsAvailable())
		to_chat(usr, "<span class='warning'>Not running under TGS.</span>")
		return
	if(GLOB.tgs_update_running)
		to_chat(usr, "<span class='warning'>An update is already running.</span>")
		return
	if(tgui_alert(usr, "Pull the latest code from GitHub and deploy it? Test merges stay. It goes live next round.", "Update Server", list("Update", "Cancel")) != "Update")
		return
	if(GLOB.tgs_update_running)
		return
	log_admin("[key_name(usr)] started a server update through TGS.")
	message_admins("[key_name_admin(usr)] started a server update: pulling from GitHub, then deploying.")
	var/list/result = tgs_update_run(ckey)
	log_admin("Server update by [key_name(usr)]: [result["ok"] ? "deploying" : "failed"]: [result["message"]]")
	message_admins("Server update [result["ok"] ? "pulled" : "failed"]: [html_encode(result["message"])]")

/// Has TGS run the HippieUpdate script and waits for it to finish: list("ok" = TRUE/FALSE, "message" = what happened).
/// The script marks the update as running and does the work in a process of its own (TGS runs one event script at a time
/// per instance, and the pull raises events that must wait their turn), so the event returns at once and this watches the file.
/proc/tgs_update_run(asked_by)
	GLOB.tgs_update_running = TRUE
	fdel(TGS_UPDATE_RESULT_FILE)
	var/started = world.TgsTriggerEvent(TGS_UPDATE_EVENT, list(asked_by), TRUE)
	var/list/result = tgs_update_result()
	var/give_up = REALTIMEOFDAY + TGS_UPDATE_WAIT
	while(result?["running"] && REALTIMEOFDAY < give_up)
		sleep(2 SECONDS)
		result = tgs_update_result()
	GLOB.tgs_update_running = FALSE
	if(!started)
		return list("ok" = FALSE, "message" = "TGS didn't run the update script.")
	if(!result)
		return list("ok" = FALSE, "message" = "the update script didn't run: is HippieUpdate in TGS's EventScripts folder?")
	if(result["running"])
		return list("ok" = FALSE, "message" = "no word from the update after [DisplayTimeText(TGS_UPDATE_WAIT)]: see TGS's jobs.")
	return list("ok" = !!result["ok"], "message" = result["message"] || "no message")

/// What the HippieUpdate script wrote: list("running" = TRUE/FALSE, "ok" = TRUE/FALSE, "message" = text), or null
/proc/tgs_update_result()
	if(!fexists(TGS_UPDATE_RESULT_FILE))
		return null
	var/list/result
	try
		result = json_decode(file2text(TGS_UPDATE_RESULT_FILE))
	catch
		return null
	return islist(result) ? result : null

#undef TGS_UPDATE_EVENT
#undef TGS_UPDATE_RESULT_FILE
#undef TGS_UPDATE_WAIT
