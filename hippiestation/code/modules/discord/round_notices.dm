// Round notices for Discord through TGS, as embeds. Chats without embeds (IRC) get the text line instead.
// They go to the channels tagged CHAT_ANNOUNCE_NEW_GAME (config.txt), sent from SSticker.fire() when the lobby opens
// and from SSticker.declare_completion() at round end.

#define ROUND_NOTICE_COLOUR_START "#3fb950"
#define ROUND_NOTICE_COLOUR_END "#58a6ff"
#define ROUND_NOTICE_COLOUR_NUKED "#f85149"

/// The lobby has opened on a new round
/proc/round_start_chat_message()
	var/map_name = SSmapping.config?.map_name || "an unknown map"
	var/datum/tgs_message_content/message = new("New round starting on [map_name]!")
	var/datum/tgs_chat_embed/structure/embed = new
	message.embed = embed
	embed.title = GLOB.round_id ? "Round #[GLOB.round_id]" : "New round"
	embed.description = "The lobby is open on [map_name]."
	embed.colour = ROUND_NOTICE_COLOUR_START
	embed.timestamp = time2text(world.timeofday, "YYYY-MM-DD hh:mm:ss")
	embed.fields = list(round_notice_field("Map", map_name))
	var/address = round_notice_address()
	if(address)
		embed.fields += round_notice_field("Join", address)
	embed.footer = new /datum/tgs_chat_embed/footer(station_name())
	return message

/// The round is over. popcount is gather_roundend_feedback()'s list.
/proc/round_end_chat_message(list/popcount)
	var/round_name = GLOB.round_id ? "Round #[GLOB.round_id]" : "The round"
	var/datum/game_mode/mode = SSticker.mode
	var/mode_name = mode?.name || "unknown"
	var/length_text = SSticker.round_start_time ? DisplayTimeText(world.time - SSticker.round_start_time, 60) : "no time"
	var/nuked = mode?.station_was_nuked
	var/crew = length(GLOB.joined_player_list)
	var/bots = GLOB.bot_population?.joined
	var/survived = popcount?["survivors"] || 0
	var/escaped = popcount?["escapees"] || 0

	var/datum/tgs_message_content/message = new("[round_name] has ended: [mode_name], [length_text]. [survived] of [crew] survived, [escaped] escaped.")
	var/datum/tgs_chat_embed/structure/embed = new
	message.embed = embed
	embed.title = "[round_name] has ended"
	embed.description = nuked ? "The station was destroyed." : "Station integrity [popcount?["station_integrity"] || 0]%."
	embed.colour = nuked ? ROUND_NOTICE_COLOUR_NUKED : ROUND_NOTICE_COLOUR_END
	embed.timestamp = time2text(world.timeofday, "YYYY-MM-DD hh:mm:ss")
	embed.fields = list(
		round_notice_field("Mode", mode_name),
		round_notice_field("Length", length_text),
		round_notice_field("Map", SSmapping.config?.map_name || "unknown"),
		round_notice_field("Crew", bots ? "[crew] ([bots] bot\s)" : "[crew]"),
		round_notice_field("Survived", "[survived]"),
		round_notice_field("Escaped", "[escaped]"),
	)
	embed.footer = new /datum/tgs_chat_embed/footer(station_name())
	return message

/proc/round_notice_field(name, value)
	var/datum/tgs_chat_embed/field/field = new(name, "[value]")
	field.is_inline = TRUE
	return field

/// Where to connect: the SERVER config entry, else this world's address, else nothing
/proc/round_notice_address()
	var/server = CONFIG_GET(string/server)
	if(server)
		return findtext(server, "byond://") == 1 ? server : "byond://[server]"
	if(world.internet_address && world.port)
		return "byond://[world.internet_address]:[world.port]"
	return null

#undef ROUND_NOTICE_COLOUR_START
#undef ROUND_NOTICE_COLOUR_END
#undef ROUND_NOTICE_COLOUR_NUKED
