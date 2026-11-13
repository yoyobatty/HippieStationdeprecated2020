#define BUCKET_LEN (world.fps*1*60) //how many ticks should we keep in the bucket. (1 minutes worth)
#define BUCKET_POS(timer) (((round((timer.timeToRun - SStimer.head_offset) / world.tick_lag)+1) % BUCKET_LEN)||BUCKET_LEN)
#define TIMER_MAX (world.time + TICKS2DS(min(BUCKET_LEN-(SStimer.practical_offset-DS2TICKS(world.time - SStimer.head_offset))-1, BUCKET_LEN-1)))
#define TIMER_ID_MAX (2**24) //max float with integer precision

SUBSYSTEM_DEF(timer)
	name = "Timer"
	wait = 1 //SS_TICKER subsystem, so wait is in ticks
	init_order = INIT_ORDER_TIMER

	flags = SS_TICKER|SS_NO_INIT

	var/list/datum/timedevent/second_queue = list() //awe, yes, you've had first queue, but what about second queue?
	/// hippie -- timer-census=1 on the stress bench: a timer's proc -> ms its timers took, and how many fired (stress_bench.dm)
	var/list/census
	var/list/census_count
	var/list/hashes = list()

	var/head_offset = 0 //world.time of the first entry in the the bucket.
	var/practical_offset = 1 //index of the first non-empty item in the bucket.
	var/bucket_resolution = 0 //world.tick_lag the bucket was designed for
	var/bucket_count = 0 //how many timers are in the buckets

	var/list/bucket_list = list() //list of buckets, each bucket holds every timer that has to run that byond tick.

	var/list/timer_id_dict = list() //list of all active timers assoicated to their timer id (for easy lookup)

	var/list/clienttime_timers = list() //special snowflake timers that run on fancy pansy "client time"

	var/last_invoke_tick = 0
	var/static/last_invoke_warning = 0
	var/static/bucket_auto_reset = TRUE

/datum/controller/subsystem/timer/PreInit()
	bucket_list.len = BUCKET_LEN
	head_offset = world.time
	bucket_resolution = world.tick_lag

/datum/controller/subsystem/timer/stat_entry(msg)
	..("B:[bucket_count] P:[length(second_queue)] H:[length(hashes)] C:[length(clienttime_timers)] S:[length(timer_id_dict)]")

/datum/controller/subsystem/timer/fire(resumed = FALSE)
	var/lit = last_invoke_tick
	var/last_check = world.time - TICKS2DS(BUCKET_LEN*1.5)
	var/list/bucket_list = src.bucket_list

	if(!bucket_count)
		last_invoke_tick = world.time

	if(lit && lit < last_check && head_offset < last_check && last_invoke_warning < last_check)
		last_invoke_warning = world.time
		var/msg = "No regular timers processed in the last [BUCKET_LEN*1.5] ticks[bucket_auto_reset ? ", resetting buckets" : ""]!"
		message_admins(msg)
		WARNING(msg)
		if(bucket_auto_reset)
			bucket_resolution = 0

		log_world("Timer bucket reset. world.time: [world.time], head_offset: [head_offset], practical_offset: [practical_offset]")
		for (var/i in 1 to length(bucket_list))
			var/datum/timedevent/bucket_head = bucket_list[i]
			if (!bucket_head)
				continue

			log_world("Active timers at index [i]:")

			var/datum/timedevent/bucket_node = bucket_head
			var/anti_loop_check = 1000
			do
				log_world(get_timer_debug_string(bucket_node))
				bucket_node = bucket_node.next
				anti_loop_check--
			while(bucket_node && bucket_node != bucket_head && anti_loop_check)
		log_world("Active timers in the second_queue queue:")
		for(var/I in second_queue)
			log_world(get_timer_debug_string(I))

	// hippie start -- each client-time timer comes off the list before it runs, instead of the run ones being cut off the front at
	// the end. A TIMER_LOOP timer went back in with its new time while its old place was still in the list, leaving the list out of
	// order until that cut, so a timer a later callback in the same pass added could binary-insert in front of where the loop had got
	// to. Everything run so far moved along one, the loop met a spent, deleted timer again and CRASHed ("Invalid timer", a geiger
	// counter's first sound_loop, 2026-11-12), and the CRASH skipped the cut, so the pass's other spent timers each crashed SStimer
	// once more, a tick apart, putting off that tick's regular timers every time.
	while (length(clienttime_timers))
		if (MC_TICK_CHECK)
			break
		var/datum/timedevent/ctime_timer = clienttime_timers[1]
		if (ctime_timer.timeToRun > REALTIMEOFDAY)
			break
		clienttime_timers.Cut(1, 2)

		var/datum/callback/callBack = ctime_timer.callBack
		if (!callBack)
			stack_trace("Invalid timer: [get_timer_debug_string(ctime_timer)] world.time: [world.time], head_offset: [head_offset], practical_offset: [practical_offset], REALTIMEOFDAY: [REALTIMEOFDAY]")
			continue

		ctime_timer.spent = REALTIMEOFDAY
		callBack.InvokeAsync()

		if (QDELETED(ctime_timer)) // deleted by its own callback
			continue
		if(ctime_timer.flags & TIMER_LOOP)
			ctime_timer.spent = 0
			ctime_timer.timeToRun = REALTIMEOFDAY + ctime_timer.wait
			BINARY_INSERT(ctime_timer, clienttime_timers, datum/timedevent, timeToRun)
		else
			qdel(ctime_timer)
	// hippie end

	if (MC_TICK_CHECK)
		return

	var/static/list/spent = list()
	var/static/datum/timedevent/timer
	/// hippie -- a bucket's been started and not finished: `spent` has timers still in it (see process_spent() below)
	var/static/mid_bucket = FALSE
	if (practical_offset > BUCKET_LEN)
		head_offset += TICKS2DS(BUCKET_LEN)
		practical_offset = 1
		resumed = FALSE

	if ((length(bucket_list) != BUCKET_LEN) || (world.tick_lag != bucket_resolution))
		reset_buckets()
		bucket_list = src.bucket_list
		resumed = FALSE


	if (!resumed)
		timer = null

	while (practical_offset <= BUCKET_LEN && head_offset + ((practical_offset-1)*world.tick_lag) <= world.time)
		// hippie start -- the timers of the buckets already run are let go before the next bucket, a tick's worth at a time. They
		// were all kept until SStimer caught up with world.time: behind for minutes under a flood of new timers, it held millions,
		// ran out of room in the list ("cannot append to list", every pass after that) and, the one time it caught up, spent 6 s
		// deleting them in one tick (2026-11-13, reagent vapour from a pile of cascade grenades). Not while a bucket's half run: a
		// pass cut off mid-bucket (the MC restarted) starts that bucket again from its head, and a spent timer deleted there first
		// could be that head, with no callback ("Invalid timer")
		if (!mid_bucket && length(spent) && !process_spent(spent))
			return
		mid_bucket = TRUE
		// hippie end
		var/datum/timedevent/head = bucket_list[practical_offset]
		if (!timer || !head || timer == head)
			head = bucket_list[practical_offset]
			timer = head
		while (timer)
			var/datum/callback/callBack = timer.callBack
			if (!callBack)
				bucket_resolution = null //force bucket recreation
				CRASH("Invalid timer: [get_timer_debug_string(timer)] world.time: [world.time], head_offset: [head_offset], practical_offset: [practical_offset]")

			if (!timer.spent)
				spent += timer
				timer.spent = world.time
				if(census) // hippie -- timer-census=1 on the stress bench: what each kind of timer costs (stress_bench.dm)
					var/started = TICK_USAGE_REAL
					callBack.InvokeAsync()
					var/key = "[callBack.delegate]"
					census[key] += TICK_USAGE_TO_MS(started)
					census_count[key]++
				else
					callBack.InvokeAsync()
				last_invoke_tick = world.time

			if (MC_TICK_CHECK)
				return

			timer = timer.next
			if (timer == head)
				break


		bucket_list[practical_offset++] = null
		mid_bucket = FALSE // hippie

		//we freed up a bucket, lets see if anything in second_queue needs to be shifted to that bucket.
		var/i = 0
		var/L = length(second_queue)
		for (i in 1 to L)
			timer = second_queue[i]
			if (timer.timeToRun >= TIMER_MAX)
				i--
				break

			if (timer.timeToRun < head_offset)
				bucket_resolution = null //force bucket recreation
				stack_trace("[i] Invalid timer state: Timer in long run queue with a time to run less then head_offset. [get_timer_debug_string(timer)] world.time: [world.time], head_offset: [head_offset], practical_offset: [practical_offset]")

				if (timer.callBack && !timer.spent)
					timer.callBack.InvokeAsync()
					spent += timer
					bucket_count++
				else if(!QDELETED(timer))
					qdel(timer)
				continue

			if (timer.timeToRun < head_offset + TICKS2DS(practical_offset-1))
				bucket_resolution = null //force bucket recreation
				stack_trace("[i] Invalid timer state: Timer in long run queue that would require a backtrack to transfer to short run queue. [get_timer_debug_string(timer)] world.time: [world.time], head_offset: [head_offset], practical_offset: [practical_offset]")
				if (timer.callBack && !timer.spent)
					timer.callBack.InvokeAsync()
					spent += timer
					bucket_count++
				else if(!QDELETED(timer))
					qdel(timer)
				continue

			bucket_count++
			var/bucket_pos = max(1, BUCKET_POS(timer))
			timer.bucket_pos = bucket_pos // hippie
			timer.bucket_joined = TRUE

			var/datum/timedevent/bucket_head = bucket_list[bucket_pos]
			if (!bucket_head)
				bucket_list[bucket_pos] = timer
				timer.next = null
				timer.prev = null
				continue

			if (!bucket_head.prev)
				bucket_head.prev = bucket_head
			timer.next = bucket_head
			timer.prev = bucket_head.prev
			timer.next.prev = timer
			timer.prev.next = timer
		if (i)
			second_queue.Cut(1, i+1)

		timer = null

	if (!mid_bucket) // hippie -- see above
		process_spent(spent)

/// hippie -- deletes (or, looping, puts back) the timers that have run, until the tick runs out. FALSE if it stopped short: the rest
/// stay in `spent` for the next pass
/datum/controller/subsystem/timer/proc/process_spent(list/spent)
	var/done = 0
	for (var/datum/timedevent/qtimer as anything in spent)
		done++
		bucket_count--
		if (MC_TICK_CHECK) // checked first, so a pause leaves this timer to start the next pass with
			done--
			bucket_count++
			break
		if(QDELETED(qtimer))
			bucket_count++
			continue
		if(!(qtimer.flags & TIMER_LOOP))
			// hippie start -- a spent timer's qdel(), without the rest of qdel(). Its Destroy() always answers QDEL_HINT_IWILLGC, so it was
			// never queued, but every timer that fired still paid for qdel()'s type lookup and counts, two signal checks, a copied
			// argument list and the SSdemo call. One with a signal listener still goes the long way round.
			if(qtimer.comp_lookup)
				qdel(qtimer)
				continue
			qtimer.gc_destroyed = GC_CURRENTLY_BEING_QDELETED
			qtimer.Destroy()
			qtimer.gc_destroyed = world.time
			// hippie end
		else
			bucket_count++
			qtimer.spent = 0
			qtimer.bucketEject()
			if(qtimer.flags & TIMER_CLIENT_TIME)
				qtimer.timeToRun = REALTIMEOFDAY + qtimer.wait
			else
				qtimer.timeToRun = world.time + qtimer.wait
			qtimer.bucketJoin()

	if(done >= length(spent))
		spent.len = 0
		return TRUE
	spent.Cut(1, done + 1)
	return FALSE

//formated this way to be runtime resistant
/datum/controller/subsystem/timer/proc/get_timer_debug_string(datum/timedevent/TE)
	. = "Timer: [TE]"
	. += "Prev: [TE.prev ? TE.prev : "NULL"], Next: [TE.next ? TE.next : "NULL"]"
	if(TE.spent)
		. += ", SPENT([TE.spent])"
	if(QDELETED(TE))
		. += ", QDELETED"
	if(!TE.callBack)
		. += ", NO CALLBACK"

/datum/controller/subsystem/timer/proc/reset_buckets()
	var/list/bucket_list = src.bucket_list
	var/list/alltimers = list()
	//collect the timers currently in the bucket
	for (var/bucket_head in bucket_list)
		if (!bucket_head)
			continue
		var/datum/timedevent/bucket_node = bucket_head
		do
			alltimers += bucket_node
			bucket_node = bucket_node.next
		while(bucket_node && bucket_node != bucket_head)

	bucket_list.len = 0
	bucket_list.len = BUCKET_LEN

	practical_offset = 1
	bucket_count = 0
	head_offset = world.time
	bucket_resolution = world.tick_lag

	alltimers += second_queue
	for (var/datum/timedevent/t as anything in alltimers) // hippie -- placed afresh below
		t.bucket_joined = FALSE
		t.bucket_pos = -1
		t.prev = null
		t.next = null
	if (!length(alltimers))
		return

	sortTim(alltimers, GLOBAL_PROC_REF(cmp_timer))

	var/datum/timedevent/head = alltimers[1]

	if (head.timeToRun < head_offset)
		head_offset = head.timeToRun

	var/new_bucket_count
	var/i = 1
	for (i in 1 to length(alltimers))
		var/datum/timedevent/timer = alltimers[i]
		if (!timer)
			continue

		var/bucket_pos = BUCKET_POS(timer)
		if (timer.timeToRun >= TIMER_MAX)
			i--
			break


		if (!timer.callBack || timer.spent)
			WARNING("Invalid timer: [get_timer_debug_string(timer)] world.time: [world.time], head_offset: [head_offset], practical_offset: [practical_offset]")
			if (timer.callBack)
				qdel(timer)
			continue

		new_bucket_count++
		timer.bucket_pos = bucket_pos // hippie
		timer.bucket_joined = TRUE
		var/datum/timedevent/bucket_head = bucket_list[bucket_pos]
		if (!bucket_head)
			bucket_list[bucket_pos] = timer
			timer.next = null
			timer.prev = null
			continue

		if (!bucket_head.prev)
			bucket_head.prev = bucket_head
		timer.next = bucket_head
		timer.prev = bucket_head.prev
		timer.next.prev = timer
		timer.prev.next = timer
	if (i)
		alltimers.Cut(1, i+1)
	second_queue = alltimers
	bucket_count = new_bucket_count


/datum/controller/subsystem/timer/Recover()
	second_queue |= SStimer.second_queue
	hashes |= SStimer.hashes
	timer_id_dict |= SStimer.timer_id_dict
	bucket_list |= SStimer.bucket_list

/datum/timedevent
	var/id
	var/datum/callback/callBack
	var/timeToRun
	var/wait
	var/hash
	var/list/flags
	var/spent = 0 //time we ran the timer.
	/// hippie -- for easy debugging: list(id, timeToRun, wait, flags, "[callBack.object]", its type, callBack.delegate), turned into
	/// text by operator""() only when something prints the timer (as in tgstation). Building the whole string up front in New(),
	/// \refs and all, cost ~50us a timer. Holds no datums, so it can't keep anything alive.
	/// hippie -- that list went too: a list, two texts and a proc call for every timer made. What can't be read off the timer once
	/// its callback is gone is kept as it comes, the object's type (or GLOBAL_PROC) and the proc: no text is built until it's printed.
	var/info_type
	var/info_proc
	/// hippie -- (from tg) whether it's in a bucket, and which: bucketEject() used to work that out again from TIMER_MAX, which
	/// moves on every tick. A timer that joined the second queue right at its edge and was deleted a tick or more later looked
	/// like it was in a bucket, so it was never taken out of the second queue; moved into a bucket later, spent and deleted, it
	/// made SStimer runtime ("Invalid timer") and drop the rest of that tick's bucket until the buckets were rebuilt.
	var/bucket_joined = FALSE
	var/bucket_pos = -1
	//cicular doublely linked list
	var/datum/timedevent/next
	var/datum/timedevent/prev

/datum/timedevent/New(datum/callback/callBack, wait, flags, hash)
	var/static/nextid = 1
	id = TIMER_ID_NULL
	src.callBack = callBack
	src.wait = wait
	src.flags = flags
	src.hash = hash

	if (flags & TIMER_CLIENT_TIME)
		timeToRun = REALTIMEOFDAY + wait
	else
		timeToRun = world.time + wait

	if (flags & TIMER_UNIQUE)
		SStimer.hashes[hash] = src

	if (flags & TIMER_STOPPABLE)
		id = num2text(nextid, 100)
		if (nextid >= SHORT_REAL_LIMIT)
			nextid += min(1, 2**round(nextid/SHORT_REAL_LIMIT))
		else
			nextid++
		SStimer.timer_id_dict[id] = src

	info_type = (callBack.object == GLOBAL_PROC) ? GLOBAL_PROC : callBack.object?.type // hippie -- see info_type
	info_proc = callBack.delegate

	if ((timeToRun < world.time || timeToRun < SStimer.head_offset) && !(flags & TIMER_CLIENT_TIME))
		CRASH("Invalid timer state: Timer created that would require a backtrack to run (addtimer would never let this happen): [SStimer.get_timer_debug_string(src)]")

	if (callBack.object != GLOBAL_PROC && !QDESTROYING(callBack.object))
		LAZYADD(callBack.object.active_timers, src)

	bucketJoin()

/datum/timedevent/Destroy()
	// hippie -- /datum/Destroy() clears a tag, a weak reference, timers, components and signals. A timer has none of them unless
	// something gave it one (View Variables and SDQL can), so it's only called then: for every other timer it was a call and a
	// dozen reads that found nothing. The tag is tested too: a datum with a tag is never garbage collected. Anything
	// /datum/Destroy() learns to clean up has to be added to this test.
	if (weak_reference || active_timers || datum_components || comp_lookup || signal_procs || datum_flags || tag)
		..()
	if (flags & TIMER_UNIQUE && hash)
		SStimer.hashes -= hash

	if (callBack && callBack.object && callBack.object != GLOBAL_PROC && callBack.object.active_timers)
		callBack.object.active_timers -= src
		UNSETEMPTY(callBack.object.active_timers)

	callBack = null

	if (flags & TIMER_STOPPABLE)
		SStimer.timer_id_dict -= id

	if (flags & TIMER_CLIENT_TIME)
		if (!spent)
			spent = world.time
			SStimer.clienttime_timers -= src
		return QDEL_HINT_IWILLGC

	if (!spent)
		spent = world.time
		bucketEject()
	else
		if (prev && prev.next == src)
			prev.next = next
		if (next && next.prev == src)
			next.prev = prev
	next = null
	prev = null
	return QDEL_HINT_IWILLGC

/datum/timedevent/proc/bucketEject()
	// hippie -- where it joined, as bucketJoin() noted it (from tg), not worked out again now
	var/list/bucket_list = SStimer.bucket_list
	var/list/second_queue = SStimer.second_queue
	var/datum/timedevent/buckethead
	if(bucket_pos > 0)
		buckethead = bucket_list[bucket_pos]
	if(buckethead == src)
		bucket_list[bucket_pos] = (next == src) ? null : next
		SStimer.bucket_count--
	else if(bucket_joined)
		SStimer.bucket_count--
	else
		var/l = length(second_queue)
		second_queue -= src
		if(l == length(second_queue))
			SStimer.bucket_count--
	if(prev == next)
		// one other timer in the ring (or none): it's alone now
		if(prev && prev != src)
			prev.next = null
			prev.prev = null
	else
		if(prev && prev.next == src)
			prev.next = next
		if(next && next.prev == src)
			next.prev = prev
	prev = next = null
	bucket_pos = -1
	bucket_joined = FALSE

/datum/timedevent/proc/bucketJoin()
	var/list/L

	if (flags & TIMER_CLIENT_TIME)
		L = SStimer.clienttime_timers
	else if (timeToRun >= TIMER_MAX)
		L = SStimer.second_queue

	if(L)
		BINARY_INSERT(src, L, datum/timedevent, timeToRun)
		return

	//get the list of buckets
	var/list/bucket_list = SStimer.bucket_list

	//calculate our place in the bucket list
	bucket_pos = BUCKET_POS(src)
	// hippie -- (from tg) a bucket SStimer has already gone past this lap would hold it for a whole minute
	if (bucket_pos < SStimer.practical_offset && timeToRun < (SStimer.head_offset + TICKS2DS(BUCKET_LEN)))
		WARNING("Bucket pos in past: bucket_pos = [bucket_pos] < practical_offset = [SStimer.practical_offset] && timeToRun = [timeToRun] < [SStimer.head_offset + TICKS2DS(BUCKET_LEN)], Timer: [src]")
		bucket_pos = SStimer.practical_offset
	bucket_joined = TRUE

	//get the bucket for our tick
	var/datum/timedevent/bucket_head = bucket_list[bucket_pos]
	SStimer.bucket_count++
	//empty bucket, we will just add ourselves
	if (!bucket_head)
		bucket_list[bucket_pos] = src
		return
	//other wise, lets do a simplified linked list add.
	if (!bucket_head.prev)
		bucket_head.prev = bucket_head
	next = bucket_head
	prev = bucket_head.prev
	next.prev = src
	prev.next = src

/// hippie -- what name used to say (see info_type), minus the callback's arguments
/datum/timedevent/proc/operator""()
	var/who = callBack ? "[callBack.object]" : "?" // the callback goes in Destroy()
	var/its_type = (info_type == GLOBAL_PROC) ? "GLOBAL_PROC" : "[info_type]"
	var/static/list/flag_names = list("TIMER_UNIQUE", "TIMER_OVERRIDE", "TIMER_CLIENT_TIME", "TIMER_STOPPABLE", "TIMER_NO_HASH_WAIT", "TIMER_LOOP")
	return "Timer: [id] (\ref[src]), TTR: [timeToRun], wait: [wait], Flags: [jointext(bitfield2list(flags, flag_names), ", ")], callBack.object: [who]([its_type]), callBack.delegate: [info_proc]"

/datum/timedevent/proc/getcallingtype()
	. = "ERROR"
	if (callBack.object == GLOBAL_PROC)
		. = "GLOBAL_PROC"
	else
		. = "[callBack.object.type]"

/proc/addtimer(datum/callback/callback, wait = 0, flags = 0)
	if (!callback)
		CRASH("addtimer called without a callback")

	if (wait < 0)
		stack_trace("addtimer called with a negative wait. Converting to [world.tick_lag]")

	if (callback.object != GLOBAL_PROC && QDELETED(callback.object) && !QDESTROYING(callback.object))
		stack_trace("addtimer called with a callback assigned to a qdeleted object. In the future such timers will not be supported and may refuse to run or run with a 0 wait")

	wait = max(CEILING(wait, world.tick_lag), world.tick_lag)

	if(wait >= INFINITY)
		CRASH("Attempted to create timer with INFINITY delay")

	var/hash

	if (flags & TIMER_UNIQUE)
		var/list/hashlist
		if(flags & TIMER_NO_HASH_WAIT)
			hashlist = list(callback.object, "([REF(callback.object)])", callback.delegate, flags & TIMER_CLIENT_TIME)
		else
			hashlist = list(callback.object, "([REF(callback.object)])", callback.delegate, wait, flags & TIMER_CLIENT_TIME)
		hashlist += callback.arguments
		hash = hashlist.Join("|||||||")

		var/datum/timedevent/hash_timer = SStimer.hashes[hash]
		if(hash_timer)
			if (hash_timer.spent) //it's pending deletion, pretend it doesn't exist.
				hash_timer.hash = null //but keep it from accidentally deleting us
			else
				if (flags & TIMER_OVERRIDE)
					hash_timer.hash = null //no need having it delete it's hash if we are going to replace it
					qdel(hash_timer)
				else
					if (hash_timer.flags & TIMER_STOPPABLE)
						. = hash_timer.id
					return
	else if(flags & TIMER_OVERRIDE)
		stack_trace("TIMER_OVERRIDE used without TIMER_UNIQUE")

	var/datum/timedevent/timer = new(callback, wait, flags, hash)
	return timer.id

/proc/deltimer(id)
	if (!id)
		return FALSE
	if (id == TIMER_ID_NULL)
		CRASH("Tried to delete a null timerid. Use TIMER_STOPPABLE flag")
	if (!istext(id))
		if (istype(id, /datum/timedevent))
			qdel(id)
			return TRUE
	//id is string
	var/datum/timedevent/timer = SStimer.timer_id_dict[id]
	if (timer && (!timer.spent || timer.flags & TIMER_DELETE_ME))
		qdel(timer)
		return TRUE
	return FALSE

// How long left on a timer
/proc/timeleft(id)
	if (!id)
		return null
	if (id == TIMER_ID_NULL)
		CRASH("Tried to get timeleft of a null timerid. Use TIMER_STOPPABLE flag")
	if (!istext(id))
		if (istype(id, /datum/timedevent))
			var/datum/timedevent/timer = id
			return timer.timeToRun - world.time
	//id is string
	var/datum/timedevent/timer = SStimer.timer_id_dict[id]
	if (timer && !timer.spent)
		return timer.timeToRun - world.time
	return null

#undef BUCKET_LEN
#undef BUCKET_POS
#undef TIMER_MAX
#undef TIMER_ID_MAX
