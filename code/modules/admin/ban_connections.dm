//Every key that connects is remembered here: the IPs and computer IDs it came from (the last few of each), when it was first and
//last seen, and the character it last played, in data/connections.json. With no database there was no record of anyone once they'd
//gone, so a griefer who left before an admin got to them could only be banned by key. The ban window's player picker and record
//read it, and ban_lookup_player() falls back on it when the database has no row for a key, or there's no database.

//How many of each a key keeps: the newest
#define SEEN_ADDRESSES_KEPT 5

/datum/controller/subsystem/bans
	//ckey = list("key", "first", "last", "count", "ips" = list(ip = when), "cids" = list(cid = when), "name", "job", "left"):
	//the times are world.realtime as text, since json_encode keeps six digits of a number
	var/list/seen = list()
	var/list/seen_by_ip = list() //ip = list(ckey = TRUE), for the keys that came from the same address
	var/list/seen_by_cid = list() //computer ID = list(ckey = TRUE), for the keys on the same computer
	var/list/left_this_round = list() //ckey = TRUE for everyone who disconnected since the server started
	var/seen_path = "data/connections.json"
	var/seen_loaded = FALSE
	var/seen_dirty = FALSE

/datum/controller/subsystem/bans/Shutdown()
	save_seen()

/datum/controller/subsystem/bans/proc/load_seen()
	seen_loaded = TRUE
	seen = list()
	seen_by_ip = list()
	seen_by_cid = list()
	var/list/data = read_seen(seen_path)
	if(!data)
		data = read_seen("[seen_path].bak")
	if(!data)
		return
	var/list/entries = data["seen"]
	for(var/player_ckey in entries)
		var/list/entry = entries[player_ckey]
		if(!islist(entry))
			continue
		seen[player_ckey] = entry
		for(var/ip in entry["ips"])
			seen_index_add(seen_by_ip, ip, player_ckey)
		for(var/cid in entry["cids"])
			seen_index_add(seen_by_cid, cid, player_ckey)
	log_world("Bans: [seen.len] keys remembered from [seen_path]")

/datum/controller/subsystem/bans/proc/read_seen(path)
	if(!fexists(path))
		return
	var/text = file2text(path)
	if(!length(text))
		return
	var/list/data
	try
		data = json_decode(text)
	catch
		return
	if(islist(data) && islist(data["seen"]))
		return data

/datum/controller/subsystem/bans/proc/save_seen()
	if(!seen_loaded || !seen_dirty)
		return
	var/text = json_encode(list("version" = 1, "seen" = seen))
	if(fexists(seen_path))
		fcopy(seen_path, "[seen_path].bak")
	fdel(seen_path)
	text2file(text, seen_path)
	seen_dirty = FALSE

/datum/controller/subsystem/bans/proc/seen_index_add(list/index, address, player_ckey)
	var/list/holders = index[address]
	if(!holders)
		holders = index[address] = list()
	holders[player_ckey] = TRUE

/datum/controller/subsystem/bans/proc/seen_index_remove(list/index, address, player_ckey)
	var/list/holders = index[address]
	if(!holders)
		return
	holders -= player_ckey
	if(!holders.len)
		index -= address

//At login, from client/New()
/datum/controller/subsystem/bans/proc/note_connection(client/C)
	if(C?.ckey)
		note_seen(C.ckey, C.key, C.address, C.computer_id)

/datum/controller/subsystem/bans/proc/note_seen(player_ckey, player_key, address, cid)
	if(!seen_loaded)
		load_seen()
	var/now = num2text(world.realtime, 12)
	var/list/entry = seen[player_ckey]
	if(!entry)
		entry = list("first" = now, "count" = 0, "ips" = list(), "cids" = list())
		seen[player_ckey] = entry
	entry["key"] = player_key
	entry["last"] = now
	entry["count"] = (text2num(entry["count"]) || 0) + 1
	if(address) //the host's is empty
		seen_address(player_ckey, entry, "ips", seen_by_ip, address, now)
	if(cid)
		seen_address(player_ckey, entry, "cids", seen_by_cid, cid, now)
	left_this_round -= player_ckey
	seen_dirty = TRUE

//An address goes to the end of the key's list (newest last), and the oldest drop off past SEEN_ADDRESSES_KEPT
/datum/controller/subsystem/bans/proc/seen_address(player_ckey, list/entry, field, list/index, address, now)
	var/list/addresses = entry[field]
	if(!islist(addresses))
		addresses = entry[field] = list()
	addresses -= address
	addresses[address] = now
	while(addresses.len > SEEN_ADDRESSES_KEPT)
		var/oldest = addresses[1]
		addresses.Cut(1, 2)
		seen_index_remove(index, oldest, player_ckey)
	seen_index_add(index, address, player_ckey)

//At logout, from client/Destroy(): who they were playing, for the list of those who left
/datum/controller/subsystem/bans/proc/note_departure(client/C)
	if(!C?.ckey)
		return
	var/mob/M = C.mob
	if(M && !isnewplayer(M))
		note_left(C.ckey, M.real_name, M.mind?.assigned_role)
	else
		note_left(C.ckey)

/datum/controller/subsystem/bans/proc/note_left(player_ckey, name, job)
	var/list/entry = seen[player_ckey]
	if(!entry)
		return
	if(name)
		entry["name"] = name
		entry["job"] = job
	entry["left"] = num2text(world.realtime, 12)
	left_this_round[player_ckey] = TRUE
	seen_dirty = TRUE

//The newest IP ("ips") or computer ID ("cids") a key came from, or null
/datum/controller/subsystem/bans/proc/last_seen_address(player_ckey, field)
	var/list/entry = seen[player_ckey]
	var/list/addresses = entry ? entry[field] : null
	if(length(addresses))
		return addresses[addresses.len]

//The other keys that came from any of this key's IPs ("ips") or computer IDs ("cids")
/datum/controller/subsystem/bans/proc/seen_sharing(player_ckey, field)
	var/list/index = field == "ips" ? seen_by_ip : seen_by_cid
	var/list/entry = seen[player_ckey]
	. = list()
	if(!entry)
		return
	for(var/address in entry[field])
		for(var/other in index[address])
			if(other != player_ckey)
				. |= other

#undef SEEN_ADDRESSES_KEPT
