Title: Reuse job threads instead of starting one per job

Every async job (http, sql, iconforge, unzip, sqlite) started its own OS thread, and so did every `http_request_fire_and_forget`. The thread gets started during the call, so it's BYOND's main thread that waits for it.

Jobs now run on a pool in jobs.rs. A job goes to a thread that's waiting for one if there's one free, and gets a new thread if not. A slow job, like an HTTP request that hangs until it times out, still never holds up the others. A thread that's had nothing to do for 60 seconds exits. If a job panics it still reports `JOB PANICKED`, and the thread moves on to the next job. `http_request_fire_and_forget` uses the same threads through a new `jobs::run_detached`.

This needs the module pin PR first (pin-module-on-windows). An idle pool thread wakes up to exit, and if rust_g.dll has been unloaded by then, that's the same crash.

## Testing

I made a world in dd.exe that times its calls with rust-g's microsecond clock, against a local HTTP server that answers right away. Here's the main thread's time for each batch, median of 15 rounds (before is 7.1.0 with the pin):

| | Before | This PR |
|---|---|---|
| Starting 1000 `http_request_async` jobs | 37.6 ms | 19.1 ms |
| 1000 `http_request_fire_and_forget` calls | 27.2 ms | 3.3 ms |
| Until all 1000 job results are back | 1.17 s | 1.17 s |

The last row mostly measures how often the world checked (once a tick), so it's only there to show nothing got slower.

- I added tests: 50 jobs each return their own result, a panicking job reports `JOB PANICKED` and the next job still runs, and a fast job finishes while a 2 second one is still going.
- I built all our spritesheets with iconforge's async jobs on it and got the same sheets.
- `cargo fmt --check`, clippy (i686, all features, `-D warnings`) and the lib tests pass.
