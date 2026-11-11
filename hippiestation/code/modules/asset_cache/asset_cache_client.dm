/// hippie -- replaces tg's asset_flush (code/modules/asset_cache/asset_cache_client.dm). Two fixes:
/// - It waits by world.time, from Paradise tgui-reliability 0d30d5980d. tg's counted its waits, not time: in the lobby stoplag(1) is
///   one tick, so at FPS 40 it gave up after a quarter of the timeout (1.25 s of 5), and in the round each wait is a decisecond or
///   more, longer under load. It also said the send failed when the answer came on the last wait.
/// - A later flush's answer counts for this one too. Every flush loads its page into the same hidden window, so when two run at once
///   (getFilesSlow for the connection's preload and for assets built after init) the second page can replace the first before it
///   answers, and the first waited out its whole timeout (a real client, 2026-11-11: 1 of 40). The browse queue keeps its order, so a
///   later page answering means everything sent before this one has arrived.
/client/asset_flush(timeout = 50)
	var/job = ++last_asset_job
	var/give_up_at = world.time + timeout
	src << browse({"<script>window.location.href="?asset_cache_confirm_arrival=[job]"</script>"}, "window=asset_cache_browser&file=asset_cache_send_verify.htm")

	while(last_completed_asset_job < job && world.time < give_up_at) // Reception is handled in Topic()
		stoplag(1) // Lock up the caller until this is received.
	if(last_completed_asset_job >= job)
		return TRUE
