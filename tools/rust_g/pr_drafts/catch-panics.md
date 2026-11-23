Title: Catch panics in exported functions instead of aborting Dream Daemon

Any panic in a rust-g function takes Dream Daemon down with it. Since Rust 1.81, a panic that unwinds out of an `extern "C"` function aborts the whole process, and the `byond_fn!` exports don't catch theirs (only iconforge and sqlite use `catch_panic`). Closes #118.

#120 tried this and got closed as mostly done by #160, but #160 only added `catch_panic` for iconforge's own calls. Everything else still aborts.

`byond_fn!` now runs the body through `catch_panic` (new `run_byond_fn` in byond.rs). A panic comes back to DM as the same string `catch_panic` already gives, `Panic during function execution: <message>`, and the next call works as normal.

I also fixed the panic hook. Only the zero-argument arm of the macro installed it, so a panic in a function with arguments didn't get written to `rustg-panic.log` unless something like `get_version` had been called first. Both arms install it now.

## Testing

- I added a test with a `byond_fn` that unwraps a parse. On 7.1.0's macro the test process aborts with "panic in a function that cannot unwind". With this PR it gets the error string back, and the calls before and after it return normally.
- I timed 100,000 `get_version` calls from a world in dd.exe: 30.1 ms before and 29.4 ms after (median of 15 rounds), so the catch doesn't cost anything you can measure.
- `cargo fmt --check`, clippy (i686, all features, `-D warnings`) and the lib tests pass.
