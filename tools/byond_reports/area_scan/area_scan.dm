// What reaching an area's contents costs as the world grows, with the area itself staying the same size.
// Stand-alone, nothing else in the project: dm area_scan.dm, then dd area_scan.dmb -invisible. Results go to world.log.
// The reference documents this ("actually loops through every turf in the world"), so this is the size of it, not a surprise.

#define REPEATS 10

/world
	fps = 20
	maxx = 20
	maxy = 20
	maxz = 1

/area/small

var/global/area/small/small_area
var/global/list/same_turfs = list()

/proc/ms_since(start)
	return (world.tick_usage - start) * world.tick_lag

/proc/time_case(label)
	var/total = 0
	var/n = 0
	for(var/i in 1 to REPEATS)
		var/start = world.tick_usage
		switch(label)
			if("area.contents.len")
				n = small_area.contents.len
			if("for(turf in area)")
				n = 0
				for(var/turf/T in small_area)
					n++
			if("area.contents.Copy()")
				var/list/copy = small_area.contents.Copy()
				n = copy.len
			if("locate(/turf) in area")
				n = (locate(/turf) in small_area) ? 1 : 0
			if("for(turf in a plain list of the same turfs)")
				n = 0
				for(var/turf/T as anything in same_turfs)
					n++
		total += ms_since(start)
		sleep(1)
	return "[label] [round(total / REPEATS, 0.01)] ms ([n])"

/proc/run_cases()
	world.log << "BYOND [world.byond_version].[world.byond_build]"
	small_area = new
	for(var/turf/T in block(locate(1, 1, 1), locate(20, 10, 1)))
		small_area.contents += T
		same_turfs += T
	world.log << "area holds [length(same_turfs)] turfs"
	for(var/list/size in list(list(100, 100, 1), list(255, 255, 1), list(255, 255, 4), list(255, 255, 8), list(255, 255, 12)))
		world.maxx = size[1]
		world.maxy = size[2]
		world.maxz = size[3]
		sleep(5)
		var/list/lines = list()
		for(var/label in list("area.contents.len", "for(turf in area)", "area.contents.Copy()", "locate(/turf) in area", "for(turf in a plain list of the same turfs)"))
			lines += time_case(label)
		world.log << "[world.maxx * world.maxy * world.maxz] turfs in the world: [jointext(lines, "; ")]"
	world.log << "done"
	del(world)

/world/New()
	. = ..()
	spawn(5)
		run_cases()
