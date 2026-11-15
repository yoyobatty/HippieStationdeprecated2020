# Testkit: test servers you can steer while they run

A headless test server boots, starts its round, and then takes commands over BYOND topic packets on its port. The server only
accepts commands from this machine, and only with the key it was started with. You can spawn things, read and set vars, call
procs, use items, press tgui buttons, drive or stop bots, run Bot Gym scenarios and the self-checks, read an event stream, and
measure costs, all on one warm server.

The testkit builds its own dmb (`testkit.mdme.dmb`), so `hippiestation.dmb` is left alone. The game's code isn't touched: the
hooks are proc overrides in `dm/`, and they're compiled only into this build.

## Use

```
python tools/testkit/tk.py build [--checks tools/combat_check/combat_check.dm,...]
python tools/testkit/tk.py start [--map testbench|hippiestation] [--seed N] [--speed 0] [--params "testkit-crew=10"]
python tools/testkit/tk.py help                      # every command
python tools/testkit/tk.py spawn type=/obj/item/crowbar at=area:Bridge
python tools/testkit/tk.py bot_why bot=bot:John
python tools/testkit/tk.py events --follow --kinds death,bot.
python tools/testkit/tk.py stop
python tools/testkit/smoke.py                        # every command family, PASS/FAIL
python tools/testkit/scenario.py run [--save]        # scenarios/*.json against expectations.json: WORSE/BETTER/SAME
python tools/testkit/client_lane.py shot --at area:Bridge --name bridge   # real DreamSeeker, data/previews/testkit_bridge.png
python tools/testkit/tk.py replay data/testkit/<port>/commands.jsonl
```

To use it from Claude, run the MCP server `ss13_mcp.py`: `claude mcp add ss13 --scope local -- python tools/testkit/ss13_mcp.py`.
That gives 57 `ss_*` tools.

## Files

- `dm/testkit_core.dm`: the topic handler, jobs (commands that sleep), blobs (answers longer than one packet), and how
  values and places are read.
- `dm/testkit_commands.dm`: world commands (`spawn`, `find`, `look`, `get`/`set`/`call`, `use`), time commands (`wait`,
  `until`, `pause`, `speed`), arenas, and `reset_rect`/`reset_area`, which reload station tiles from the `.dmm`.
- `dm/testkit_events.dm`: the event stream and its hooks: deaths, attacks, say, doors, runtimes, hard deletes, MC alerts and
  bot telemetry. It also has `mark` and `invariants`.
- `dm/testkit_bots.dm`: `bots`, `bot_why`, `bot_watch`, `possess`/`release`, `bot_goal`, `gym_run`, and `run_check`.
- `dm/testkit_ui.dm`: `ui_data`/`ui_act` through a stub tgui, `verb`, `admin`, the `perf` commands, `fuzz_ui`, `fuzz_use` and
  `stall`.
- `dm/testkit_client.dm`: the real-client lane. Preferences are never saved, because the client can log in as your own key.
- `ui_scan.py`: reads every type's `ui_act()` actions, param keys and tested strings from the DM source, for `fuzz_ui`.

## Traps

- A check built in with `--checks` must not start itself or delete the world under `TESTKIT_BUILD`. `combat_check` and
  `grid_check` are guarded. Checks gated on a world param (`rped_check`) need nothing.
- Two checks that define the same helper names can't be built in together. For example, `crew_check` and `say_check` both
  define `uc_log`.
- `reset_rect` reloads whole tiles. Pipes and cables that cross its edge can come back split from the network outside it.
- By default the round never ends (`SSticker` is stopped) and has no bot crew. Pass `testkit-round-end` and `testkit-crew=N`
  to change either.
- Only one DreamSeeker runs per machine. The client lane refuses to start while your game is open.
- From Git Bash, an argument like `type=/obj/x` is rewritten as a Windows path. `tk.py` undoes this for `/obj`, `/mob`,
  `/datum`, `/turf`, `/area`, `/atom`, `/proc` and `/client`.
