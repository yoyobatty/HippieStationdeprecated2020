#define SINGULARITY_SWALLOWS_PER_SECOND 25 // a big singularity eats far more a second than anyone can watch

/**
  * Things a singularity eats spiral into it: a copy of the thing rounds the far side of it, shrinking and fading as it
  * reaches the middle. From Paradise (24f91e81a2). Only from stage three up, and only so many a second.
  */
/obj/singularity
	var/swallow_second = -1 // which second the swallow visuals are being counted for
	var/swallows_left = 0 // how many more it can show in that second

/obj/singularity/consume(atom/A)
	show_swallow(A)
	return ..()

/// Shows A spiralling into us as it's eaten.
/obj/singularity/proc/show_swallow(atom/A)
	if(current_size < STAGE_THREE || A.invisibility || !A.alpha || iseffect(A))
		return
	// eat() consumes every turf in reach each fire, space it already ate included: only a turf it really tears up shows
	if(isspaceturf(A) || istype(A, /turf/open/openspace))
		return
	var/second = world.time - (world.time % 10)
	if(second != swallow_second)
		swallow_second = second
		swallows_left = SINGULARITY_SWALLOWS_PER_SECOND
	if(swallows_left <= 0)
		return
	var/turf/T = get_turf(A)
	if(!T)
		return
	swallows_left--
	new /obj/effect/temp_visual/singularity_swallow(T, A, src)

/obj/effect/temp_visual/singularity_swallow
	duration = 8
	randomdir = FALSE
	layer = MASSIVE_OBJ_LAYER
	appearance_flags = KEEP_TOGETHER | PIXEL_SCALE

/obj/effect/temp_visual/singularity_swallow/Initialize(mapload, atom/eaten, obj/singularity/S)
	. = ..()
	if(!eaten || !S)
		return INITIALIZE_HINT_QDEL
	appearance = eaten.appearance
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	plane = GAME_PLANE
	layer = MASSIVE_OBJ_LAYER - 0.01
	appearance_flags |= KEEP_TOGETHER | PIXEL_SCALE
	name = ""
	// Round the far side of it, shrinking and fading as it reaches the middle
	var/dx = (S.x - x) * world.icon_size
	var/dy = (S.y - y) * world.icon_size
	var/turn = pick(-1, 1) * 120
	var/matrix/halfway = matrix()
	halfway.Scale(0.7)
	halfway.Turn(turn)
	var/matrix/gone = matrix()
	gone.Scale(0.05)
	gone.Turn(turn * 3)
	animate(src, pixel_x = pixel_x + dx * 0.4 - dy * 0.3, pixel_y = pixel_y + dy * 0.4 + dx * 0.3, transform = halfway, time = 4, easing = SINE_EASING | EASE_IN)
	animate(pixel_x = pixel_x + dx, pixel_y = pixel_y + dy, transform = gone, alpha = 0, time = 4, easing = QUAD_EASING | EASE_IN)

#undef SINGULARITY_SWALLOWS_PER_SECOND
