// Verb to link discord accounts to BYOND accounts
/client/verb/linkdiscord()
	set category = "Special Verbs"
	set name = "Link Discord Account"
	set desc = "Link your discord account to your BYOND account."

	// Safety checks
	if(!CONFIG_GET(flag/sql_enabled))
		to_chat(src, "<span class='warning'>This feature requires the SQL backend to be running.</span>")
		return

	if(!SSdiscord) // SS is still starting
		to_chat(src, "<span class='notice'>The server is still starting up. Please wait before attempting to link your account!</span>")
		return

	if(!SSdiscord.enabled)
		to_chat(src, "<span class='warning'>This feature requires the server is running on the TGS toolkit.</span>")
		return

	var/stored_id = SSdiscord.lookup_id(usr.ckey)
	if(!stored_id) // Account is not linked
		var/know_how = tgui_alert(usr, "Do you know how to get a Discord user ID? This ID is NOT your Discord username and numbers! (Pressing NO will open a guide.)", "Question", list("Yes", "No", "Cancel Linking"))
		if(know_how == "No") // Opens discord support on how to collect IDs
			src << link("https://support.discordapp.com/hc/en-us/articles/206346498-Where-can-I-find-my-User-Server-Message-ID")
		if(know_how == "Cancel Linking")
			return
		var/entered_id = tgui_input_text(usr, "Please enter your Discord ID (18-ish digits)", "Enter Discord ID")
		SSdiscord.account_link_cache[replacetext(lowertext(usr.ckey), " ", "")] = "[entered_id]" // Prepares for TGS-side verification, also fuck spaces
		tgui_alert(usr, "Account link started. Please ping the bot of the server you\'re currently on, followed by \"verify [usr.ckey]\" in Discord to successfully verify your account (Example: @Mr_Terry verify [usr.ckey])")

	else // Account is already linked
		var/choice = tgui_alert(usr, "You already have the Discord Account [stored_id] linked to [usr.ckey]. Would you like to link a different account?", "Already Linked", list("Yes", "No"))
		if(choice == "Yes")
			var/know_how = tgui_alert(usr, "Do you know how to get a Discord user ID? This ID is NOT your Discord username and numbers! (Pressing NO will open a guide.)", "Question", list("Yes", "No", "Cancel Linking"))
			if(know_how == "No") // Opens discord support on how to collect IDs
				src << link("https://support.discordapp.com/hc/en-us/articles/206346498-Where-can-I-find-my-User-Server-Message-ID")

			if(know_how == "Cancel Linking")
				return

			var/entered_id = tgui_input_text(usr, "Please enter your Discord ID (18-ish digits)", "Enter Discord ID")
			SSdiscord.account_link_cache[replacetext(lowertext(usr.ckey), " ", "")] = "[entered_id]" // Prepares for TGS-side verification, also fuck spaces
			tgui_alert(usr, "Account link started. Please ping the bot of the server you\'re currently on, followed by \"verify [usr.ckey]\" in Discord to successfully verify your account (Example: @Mr_Terry verify [usr.ckey])")
			// This is so people cant fill the notify list with a fuckload of ckeys
			SSdiscord.notify_members -= "[stored_id]" // The list uses strings because BYOND cannot handle a 17 digit integer
