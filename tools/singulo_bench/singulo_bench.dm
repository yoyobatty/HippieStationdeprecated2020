// Singularity bench: a stage six singularity (ate a supermatter) held still on testbench, loose items littered around it and
// topped up every few seconds, timed headless. Measures how long each server tick really took (a sampler that wakes every
// tick), how far game time fell behind real time, and how long the singularity's own fires took.
//
// Run:      tools/singulo_bench/run.sh (builds before/after dmbs and runs them side by side)
// Results:  data/singulo_bench/<label>.txt

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("singulo-bench" in world.params)
		sleep_offline_after_initializations = FALSE
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_singulo_bench))
	return ..()

GLOBAL_VAR(singulo_bench_file)
GLOBAL_VAR_INIT(singulo_fire_us, 0)
GLOBAL_VAR_INIT(singulo_fire_max_us, 0)
GLOBAL_VAR_INIT(singulo_fires, 0)

/obj/singularity/process()
	if(!GLOB.singulo_bench_file)
		return ..()
	rustg_time_reset("sfire")
	. = ..()
	var/us = rustg_time_microseconds("sfire")
	GLOB.singulo_fire_us += us
	GLOB.singulo_fire_max_us = max(GLOB.singulo_fire_max_us, us)
	GLOB.singulo_fires++

/proc/singulo_bench_log(text)
	text2file(text, GLOB.singulo_bench_file)

/proc/singulo_bench_litter(turf/center, count)
	var/list/types = list(/obj/item/shard, /obj/item/stack/sheet/metal, /obj/item/stack/rods, /obj/item/wrench, /obj/item/crowbar, /obj/item/storage/toolbox/mechanical, /obj/item/clothing/suit/hazardvest, /obj/item/reagent_containers/food/drinks/soda_cans/cola)
	var/list/spots = list()
	for(var/turf/T in RANGE_TURFS(14, center))
		if(get_dist(T, center) >= 5 && !isspaceturf(T))
			spots += T
	if(!spots.len)
		return
	for(var/i in 1 to count)
		var/path = types[(i % types.len) + 1]
		new path(spots[(i * 7919) % spots.len + 1])

/proc/run_singulo_bench()
	sleep(5 SECONDS)
	var/label = world.params["singulo-bench-label"] || "bench"
	var/seconds = text2num(world.params["singulo-bench-seconds"]) || 60
	var/items = text2num(world.params["singulo-bench-items"]) || 300
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/round_deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < round_deadline)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	MCWatchdog.watch_with_nobody_on = TRUE

	// a station floor, the hallway's first if there is one
	GLOB.singulo_bench_file = "data/singulo_bench/[label].txt"
	fdel(GLOB.singulo_bench_file)
	var/turf/center
	for(var/area_type in list(/area/hallway, /area))
		for(var/area/A in GLOB.sortedAreas)
			if(!istype(A, area_type) || !is_station_level(A.z))
				continue
			for(var/turf/open/floor/F in A)
				center = F
				break
			if(center)
				break
		if(center)
			break
	if(!center)
		singulo_bench_log("no station floor")
		singulo_bench_log("done")
		return
	singulo_bench_log("center [center.x],[center.y],[center.z] ([get_area(center)])")

	var/obj/singularity/S = new(center, 4000)
	S.consumedSupermatter = 1
	S.move_self = 0
	S.dissipate = 0
	singulo_bench_litter(center, items)

	var/list/ticks = list()
	var/start_real = REALTIMEOFDAY
	var/start_time = world.time
	var/skipped_start = Master.skip_ticks
	rustg_time_reset("stick")
	var/last = 0
	var/next_litter = world.time + 5 SECONDS
	while(REALTIMEOFDAY - start_real < seconds * 10)
		sleep(world.tick_lag)
		var/now = rustg_time_microseconds("stick")
		ticks += (now - last) / 1000
		last = now
		if(world.time >= next_litter)
			next_litter = world.time + 5 SECONDS
			singulo_bench_litter(center, items / 3)
	var/real = (REALTIMEOFDAY - start_real) / 10
	var/game = (world.time - start_time) / 10
	sortTim(ticks, GLOBAL_PROC_REF(cmp_numeric_asc))
	var/n = ticks.len
	var/over100 = 0
	for(var/t in ticks)
		if(t > 100)
			over100++
	singulo_bench_log("size [S.current_size], energy [S.energy], items on z near it [length(range(15, S))]")
	singulo_bench_log("ticks seen [n] in [real] s real, [game] s game: slowdown [round(real / max(game, 0.1), 0.01)]x")
	singulo_bench_log("tick ms: p50 [round(ticks[round(n * 0.5) + 1], 0.1)] p95 [round(ticks[round(n * 0.95)], 0.1)] p99 [round(ticks[round(n * 0.99)], 0.1)] max [round(ticks[n], 0.1)], over 100 ms [over100]")
	singulo_bench_log("singularity fires [GLOB.singulo_fires]: mean [round(GLOB.singulo_fire_us / max(GLOB.singulo_fires, 1) / 1000, 0.1)] ms, max [round(GLOB.singulo_fire_max_us / 1000, 0.1)] ms")
	singulo_bench_log("world.cpu [world.cpu], MC skip_ticks now [Master.skip_ticks] (start [skipped_start])")
	singulo_bench_log("done")
	sleep(1 SECONDS)
	Master.Shutdown()
	qdel(world)
