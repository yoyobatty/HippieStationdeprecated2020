Title: Pin rust_g.dll on Windows so a world restart can't crash Dream Daemon

Dream Daemon can crash a few seconds after a world restarts, with the faulting module `rust_g.dll_unloaded`. Our server crashed like this nine times in five days after we moved our spritesheets to iconforge.

Closes #273. That asks for a shutdown export to close threads, but rayon's global pool can't be shut down, so I went with keeping the dll loaded instead.

## Why it crashes

Whenever a world stops or reboots, BYOND unloads the libraries it opened with `call_ext`, so rust-g gets a `FreeLibrary`. I checked this in dd.exe: rust_g.dll is gone from the process right after `world.Reboot()`, and the next world loads it again. Any threads rust-g started keep running after that, but their code's gone. The pdb puts the crash in `rayon_core::sleep::Sleep::sleep`, which is an idle worker from rayon's global pool. iconforge, cellularnoise, worleynoise and the cave generator all start that pool, and its threads never exit. They get away with it as long as nothing else gets put where the dll used to be, which is why most restarts are fine. Once something does and a worker wakes up, DD crashes. Threads from `jobs`, `http` and `redis_pubsub` could do the same if a world stops while they're running.

#155 tried detaching threads on `/world/Del`, but a detached thread still outlives the dll, and there's no way to shut down rayon's global pool anyway.

## Fix

I added a `DllMain` that pins the module when it loads (`GetModuleHandleExW` with `GET_MODULE_HANDLE_EX_FLAG_PIN | GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS` on `DLL_PROCESS_ATTACH`). After that, `FreeLibrary` leaves rust-g loaded until the process exits, so those threads always have code to run. The next world's `LoadLibrary` gets the same copy back and reuses the same rayon pool. It's Windows only.

There are two side effects. rust-g's statics now last as long as the DD process instead of one world, so anything the old world didn't close, like log files or SQL connections, stays open. The dll also stays locked until DD closes, so you can't swap it out between rounds.

## Testing

I made a small Python host that does what DD does: it loads `rust_g64.dll`, calls `cnoise_generate` to start the rayon pool, and then calls `FreeLibrary`. After that it puts other memory where the dll was, like a busy 32-bit DD would.
- On 7.1.0, all 16 rayon workers were still running from the unloaded range and the process segfaulted within a second.
- With this PR, the dll stayed loaded. Loading it again reused the same 16 workers instead of starting 16 more, and the host was still up 20 seconds later.
- It doesn't even need the memory taken. I ran a fresh host 6 times that loads 7.1.0, calls `cnoise_generate` once and unloads it, and 2 of them segfaulted.
- Since nothing gets reloaded, a world's first rayon call is quicker too: loading the dll plus the first `cnoise_generate` took about 1.6 ms on 7.1.0 and 0.4 ms with this PR.
- I ran a world in dd.exe that starts the pool and calls `world.Reboot()`. On 7.1.0 rust_g.dll was unloaded after the reboot, and with this PR it stayed loaded.
- I built all our spritesheets with iconforge on the patched i686 dll and got the same sheets as on 7.1.0.
- `cargo fmt --check` and `cargo clippy --target i686-pc-windows-msvc --features all -- -D warnings` both pass.
