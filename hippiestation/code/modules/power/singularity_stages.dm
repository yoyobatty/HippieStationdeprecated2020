/**
  * Stage four loses 3 energy a second (30 every fifth fire, a fire every 2 s), more than a particle accelerator on
  * setting 2 feeds it, so a stage four on setting 2 can't creep into stage five. tg's 10 every eleventh fire let it.
  * From Paradise (6817061ee9). expand() only sets these when it lands on a stage, so they're put right after it.
  */
/obj/singularity/expand(force_size = 0)
	. = ..()
	if(current_size == STAGE_FOUR)
		dissipate_delay = 4
		dissipate_strength = 30
