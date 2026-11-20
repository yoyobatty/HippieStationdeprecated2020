// Bot walk steps (hippie, 2026-11-19). A bot's walk takes its next step a movement delay after the last (step_next_node(),
// bot_movement.dm). That was an addtimer() a step: a callback, a timedevent, a text id in SStimer.timer_id_dict, a bucket join,
// a qdel() and a call() with arglist when it fired, ~10 us a step, and 60% of every timer made in a 30-bot round (~140 a
// second). Timer was the costliest subsystem.
//
// Here a step is a brain in a list: a ring with one list per tick, a few seconds long. schedule() puts the brain in the list
// for its tick and notes that tick on it (step_due); fire() runs the lists that are due. A brain has one step at a time, as
// stuck_timer_id had one timer: scheduling again or cancel_step() just changes step_due, and the old entry is passed over when
// its tick comes (step_due no longer says that tick). A wait longer than the ring goes to a timer as before (rare: a long
// stand still).

#define BOT_STEP_RING_SECONDS 5

SUBSYSTEM_DEF(bot_steps)
	name = "Bot Steps"
	wait = 1 // SS_TICKER: ticks
	flags = SS_TICKER|SS_NO_INIT
	idle_check = TRUE
	/// One list of brains per tick, slot (tick % ring_ticks) + 1
	var/list/ring
	var/ring_ticks = 0
	/// world.tick_lag the ring was made for: tick numbers mean nothing after it changes
	var/ring_tick_lag = 0
	/// The next tick to run, so a tick the MC skipped is still run late, as SStimer does
	var/next_tick = 0
	/// Entries in the ring, stale ones too: has_work() and the stat panel
	var/pending = 0
	/// Steps run, for the stat panel
	var/ran = 0

/datum/controller/subsystem/bot_steps/stat_entry(msg)
	return ..("P:[pending] R:[ran]")

/datum/controller/subsystem/bot_steps/has_work()
	return pending

/// The current tick's number
#define BOT_STEP_NOW (round(world.time / world.tick_lag + 0.5))

/datum/controller/subsystem/bot_steps/proc/make_ring()
	var/list/waiting = list()
	for(var/list/L in ring)
		for(var/datum/bot_brain/B as anything in L)
			if(B.step_due && !(B in waiting))
				waiting[B] = B.step_due * ring_tick_lag // as world.time
	ring_tick_lag = world.tick_lag
	ring_ticks = max(2, CEILING(BOT_STEP_RING_SECONDS * 10 / ring_tick_lag, 1))
	ring = new /list(ring_ticks)
	pending = 0
	next_tick = BOT_STEP_NOW
	for(var/datum/bot_brain/B as anything in waiting)
		B.step_due = 0
		var/due = max(next_tick, round(waiting[B] / ring_tick_lag + 0.5))
		add(B, due)

/datum/controller/subsystem/bot_steps/proc/add(datum/bot_brain/B, due_tick)
	B.step_due = due_tick
	var/slot = (due_tick % ring_ticks) + 1
	var/list/L = ring[slot]
	if(L)
		L += B
	else
		ring[slot] = list(B)
	pending++

/// Puts B's next step `delay` deciseconds from now (at least a tick, rounded up to whole ticks, as addtimer() does). FALSE: too far
/// for the ring, the caller uses a timer.
/datum/controller/subsystem/bot_steps/proc/schedule(datum/bot_brain/B, delay)
	if(world.tick_lag != ring_tick_lag)
		make_ring()
	var/ticks = max(1, CEILING(delay / ring_tick_lag, 1))
	if(ticks >= ring_ticks)
		return FALSE
	add(B, BOT_STEP_NOW + ticks)
	return TRUE

/datum/controller/subsystem/bot_steps/fire(resumed)
	if(world.tick_lag != ring_tick_lag)
		make_ring()
	var/now = BOT_STEP_NOW
	var/tick = max(next_tick, now - ring_ticks + 1)
	var/list/ring = src.ring
	var/size = ring_ticks
	while(tick <= now)
		var/slot = (tick % size) + 1
		var/list/L = ring[slot]
		if(L)
			ring[slot] = null
			var/list/later
			for(var/datum/bot_brain/B as anything in L)
				var/due = B.step_due
				if(due > tick) // a later lap's (a stall longer than the ring), or put back a lap on since: not yet
					if(due % size + 1 == slot)
						LAZYADD(later, B)
						continue
					pending--
					continue
				pending--
				if(due != tick && (due <= 0 || due < next_tick))
					continue // cancelled, or moved to another tick and run there
				B.step_due = 0
				ran++
				try
					B.run_scheduled_step()
				catch(var/exception/e) // the rest of this tick's steps still go
					bot_log_exception(B, "scheduled step", e)
			if(later)
				var/list/now_there = ring[slot]
				ring[slot] = now_there ? (later + now_there) : later
		tick++
	next_tick = now + 1

#undef BOT_STEP_NOW
#undef BOT_STEP_RING_SECONDS
