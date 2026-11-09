// Discord admin commands through TGS (status, ahelp, namecheck, adminwho, sdql in code/modules/admin/chat_commands.dm)
// run only for a Discord account linked to a game admin with the rights. Like tg's validated chat commands, but with
// no unchecked fallback: when the link can't be checked (no database) the command is refused.
// Linking: Link Discord Account in game (code/modules/discord/accountlink.dm), then "verify <ckey>" in Discord.

/datum/config_entry/flag/secure_chat_commands	// Discord admin commands need the sender linked to an admin with the rights; 0 turns the check off
	config_entry_value = TRUE

/datum/tgs_chat_command/validated
	ignore_type = /datum/tgs_chat_command/validated
	admin_only = TRUE
	/// Rights the linked admin needs (R_ flags, any one of them); 0 is any admin
	var/required_rights = 0

/datum/tgs_chat_command/validated/Run(datum/tgs_chat_user/sender, params)
	if(!CONFIG_GET(flag/secure_chat_commands))
		return Validated_Run(sender, params)
	var/refusal = chat_admin_refusal(sender, required_rights)
	if(refusal)
		log_admin_private("Chat command [name] refused for [sender.friendly_name] ([sender.mention]): [refusal]")
		return new /datum/tgs_message_content(refusal)
	return Validated_Run(sender, params)

/// The command itself, once the sender has passed the check (or the check is off). Returns a /datum/tgs_message_content.
/datum/tgs_chat_command/validated/proc/Validated_Run(datum/tgs_chat_user/sender, params)
	RETURN_TYPE(/datum/tgs_message_content)
	CRASH("[type] has no Validated_Run()")

/// Why sender can't run an admin chat command that needs rights, or null when they can
/proc/chat_admin_refusal(datum/tgs_chat_user/sender, rights)
	var/discord_id = discord_id_from_mention(sender?.mention)
	if(!discord_id)
		return "Admin commands need a Discord account linked to a game admin."
	if(!SSdbcore.Connect())
		return "Can't check your Discord link: no database."
	var/linked_ckey = ckey(SSdiscord.lookup_ckey(discord_id))
	if(!linked_ckey)
		return "Your Discord account isn't linked. In game: Link Discord Account, then `verify <ckey>` here."
	var/datum/admins/holder = GLOB.admin_datums[linked_ckey] || GLOB.deadmins[linked_ckey]
	if(!holder)
		return "`[linked_ckey]` isn't an admin."
	if(rights && !holder.check_for_rights(rights))
		return "`[linked_ckey]` needs [rights2text(rights, " ")]."
	return null

/// The Discord user ID in a mention (<@123> or <@!123>), or null for anything else (an IRC nick)
/proc/discord_id_from_mention(mention)
	var/static/regex/discord_mention = regex(@"^<@!?(\d+)>$")
	if(!istext(mention) || !discord_mention.Find(mention))
		return null
	return discord_mention.group[1]
