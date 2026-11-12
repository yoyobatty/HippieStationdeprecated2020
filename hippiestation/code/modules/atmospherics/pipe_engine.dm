// Pipe networks evened out by the tile engine (tools/atmos_engine/src/pipes.rs). reconcile_gases() reads every gas mixture on a
// network (the pipes' shared air, every machine's own air, a canister on a connector), adds them up and writes each its share:
// on the distro loop that's two hundred mixtures for one vent topping up a room. The engine keeps every mixture's air as DM
// holds it after it was last evened out, so only the ones marked changed since are sent: PIPE_AIR_TOUCH where a machine says
// it changed its air (update_parents() and the like), heat through a heat exchanging pipe, a pipe's air handed out, a reaction
// in the pipes, a canister's air (always). A network keeps its list of mixtures, and the references and numbers sent with it,
// for as long as the list comes out the same, so DM doesn't go through every mixture each time. The engine works the totals out
// in DM's own 32-bit steps and order and writes the new air into the mixtures itself; a mixture whose gas list isn't already in
// the total's order is cut and refilled by DM.
// -params "atmos-engine-pipes=shadow" leaves it to DM and has the engine check every mixture nothing marked against what it
// kept, which is how a way of changing pipe air that doesn't say so gets found; "off" leaves it all to DM.

/datum/gas_mixture
	/// The tile engine's number for this mixture once it's been on a pipe network that was evened out, 0 before
	var/tmp/pipe_engine_id = 0
	/// Something in DM changed it since its network was last evened out (PIPE_AIR_TOUCH)
	var/tmp/pipe_engine_dirty = TRUE

/datum/pipeline
	/// The mixtures last sent to the engine (reconcile_air()'s list), their references (mixture and gas list, by turns) and
	/// their numbers, kept while the list comes out the same
	var/list/datum/gas_mixture/pipe_engine_gl
	var/list/pipe_engine_refs
	var/list/pipe_engine_ids

/datum/controller/subsystem/air
	/// "on", "shadow" or "off"
	var/pipe_engine = "off"
	/// The last mixture number handed out
	var/pipe_engine_ids = 0
	/// Networks evened out by the engine and by DM, mixtures sent and kept, refilled by DM, lists made afresh (for benches)
	var/list/pipe_engine_counts = list("engine" = 0, "dm" = 0, "sent" = 0, "kept" = 0, "rewritten" = 0, "lists" = 0)

/// Turns the engine's evening out on if atmos-engine-pipes asks for it and the library has it. Needs the engine writing air
/// itself (atmos-engine-writes), or it only shadows.
/datum/controller/subsystem/air/proc/pipe_engine_setup()
	pipe_engine = "off"
	var/wanted = world.params["atmos-engine-pipes"] || "on"
	if(wanted == "off" || !tile_engine)
		return
	try
		call_ext(GLOB.tile_engine_lib, "byond:atmos_engine_pipes_check")(list())
	catch
		log_world("Atmos: the tile engine can't even out pipe networks (an older hippie_atmos), so DM does")
		return
	pipe_engine = (wanted == "shadow" || !tile_engine_writes) ? "shadow" : "on"
	for(var/datum/pipeline/net as anything in networks) // the engine starts with nothing kept
		net.pipe_engine_gl = null
	log_world("Atmos: the tile engine evens out pipe networks ([pipe_engine])")

/// atmos-engine-pipes=shadow so far: list(mixtures checked, how many differed though nothing marked them changed)
/datum/controller/subsystem/air/proc/pipe_engine_check()
	. = list()
	if(pipe_engine != "off")
		try
			call_ext(GLOB.tile_engine_lib, "byond:atmos_engine_pipes_check")(.)
		catch
			return list()

/// reconcile_gases() by the engine. Returns TRUE if it's done (atmos-engine-pipes=on); FALSE to have DM do it, as it does
/// with "shadow" (after the engine has worked out its own and checked what it kept), or for a mixture that isn't a plain one.
/datum/pipeline/proc/pipe_engine_reconcile(list/datum/gas_mixture/GL)
	var/write = SSair.pipe_engine == "on"
	var/shadow = !write
	var/all = FALSE
	if(!pipe_engine_gl || !(GL ~= pipe_engine_gl))
		// The list changed (or it's the first time): numbers and references made afresh, and every mixture sent
		var/count = length(GL)
		var/list/refs = new /list(count * 2) // set by index: Add() would put a gas list's contents in, not the list
		var/list/ids = new /list(count)
		var/k = 0
		for(var/datum/gas_mixture/G as anything in GL)
			if(G.type != /datum/gas_mixture)
				pipe_engine_gl = null
				SSair.pipe_engine_counts["dm"]++
				return FALSE
			k++
			if(!G.pipe_engine_id)
				G.pipe_engine_id = ++SSair.pipe_engine_ids
			ids[k] = G.pipe_engine_id
			refs[k * 2 - 1] = G
			refs[k * 2] = G.moles
		pipe_engine_gl = GL.Copy()
		pipe_engine_refs = refs
		pipe_engine_ids = ids
		all = TRUE
		SSair.pipe_engine_counts["lists"]++
	var/list/rows = list()
	var/list/total = list()
	var/list/rewrite = list()
	var/list/resend
	var/status = 3
	var/sent = 0
	while(status == 3)
		rows.Cut()
		sent = 0
		var/k = 0
		for(var/datum/gas_mixture/G as anything in GL)
			k++
			var/changed = G.pipe_engine_dirty || all || (resend && resend[k])
			if(changed || shadow)
				G.pipe_engine_dirty = FALSE
				var/list/moles = G.moles
				rows.Add(k, changed ? 1 : 2, G.volume, G.temperature, length(moles))
				for(var/gas_id, amount in moles)
					rows.Add(gas_id, amount)
				sent++
		total.Cut()
		rewrite.Cut()
		try
			status = call_ext(GLOB.tile_engine_lib, "byond:atmos_engine_reconcile")(write ? pipe_engine_refs : null, pipe_engine_ids, rows, write ? 1 : 2, total, rewrite)
		catch(var/exception/error)
			status = "[error]"
		if(status == 3) // it hasn't got some of them (it started afresh): the same again, with theirs
			if(resend)
				status = "asked for mixtures twice"
				break
			resend = new /list(length(GL))
			for(var/p in rewrite)
				resend[p] = TRUE
	if(status != 1)
		SSair.pipe_engine = "off"
		log_world("Atmos: the tile engine failed evening out a pipe network ([status]), DM does it from now on")
		stack_trace("Atmos: pipe evening out failed ([status])")
		return FALSE
	SSair.pipe_engine_counts["sent"] += sent
	SSair.pipe_engine_counts["kept"] += length(GL) - sent
	if(shadow)
		return FALSE
	SSair.pipe_engine_counts["engine"]++
	// The ones whose gas list wasn't in the total's order: cut and filled from the total, as reconcile_gases() does them all
	var/total_volume = total[1]
	if(length(rewrite) && total_volume > 0)
		SSair.pipe_engine_counts["rewritten"] += length(rewrite)
		for(var/p in rewrite)
			var/datum/gas_mixture/G = GL[p]
			var/share = G.volume / total_volume
			var/list/G_gases = G.moles
			G_gases.Cut()
			for(var/i in 1 to total[3])
				G_gases[total[2 + i * 2]] = total[3 + i * 2] * share
	return TRUE
