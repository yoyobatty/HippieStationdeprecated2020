/proc/log_mentor(text)
	GLOB.mentorlog.Add(text)
	WRITE_LOG(GLOB.world_game_log, "MENTOR: [text]")

/shutdown_logging()
	hippie_log_close_all() // everything still queued goes to the drive first (log_writer.dm)
	. = ..()
	quickwrite_close_all()
