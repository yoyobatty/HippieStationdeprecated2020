// Verb to manipulate IDs and ckeys
/client/proc/discord_id_manipulation()
	set name = "Discord Manipulation"
	set category = "Admin"

	if(!check_rights(R_ADMIN))
		return

	holder.discord_manipulation() 


/datum/admins/proc/discord_manipulation()
	if(!usr.client.holder)
		return

	if(!SSdiscord.enabled)
		to_chat(usr, "<span class='warning'>TGS is not enabled</span>")
		return

	var/lookup_choice = tgui_alert(usr, "Do you wish to lookup account by ID or ckey?", "Lookup Type", list("ID", "Ckey", "Cancel"))
	switch(lookup_choice)
		if("ID")
			var/lookup_id = tgui_input_text(usr, "Enter Discord ID to lookup ckey", allow_cancel = FALSE)
			var/returned_ckey = SSdiscord.lookup_ckey(lookup_id)
			if(returned_ckey)
				var/unlink_choice = tgui_alert(usr, "Discord ID [lookup_id] is linked to Ckey [returned_ckey]. Do you wish to unlink or cancel?", "Account Found", list("Unlink", "Cancel"))
				if(unlink_choice == "Unlink")
					SSdiscord.unlink_account(returned_ckey)
			else
				to_chat(usr, "<span class='warning'>Discord ID <b>[lookup_id]</b> has no associated ckey</span>")
		if("Ckey")
			var/lookup_ckey = tgui_input_text(usr, "Enter Ckey to lookup ID", allow_cancel = FALSE)
			var/returned_id = SSdiscord.lookup_id(lookup_ckey)
			if(returned_id)
				to_chat(usr, "<span class='notice'>Ckey <b>[lookup_ckey]</b> is assigned to Discord ID <b>[returned_id]</b></span>")
				to_chat(usr, "<span class='notice'>Discord mention format: <b>&lt;@[returned_id]&gt;</b></span>") // &lt; and &gt; print < > in HTML without using them as tags	
