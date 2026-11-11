# HippieStation: where things are

A 2020 /tg/station fork (upstream HippieStation/HippieStationdeprecated2020) brought back on BYOND 516: bot crew, native atmos and lighting, tgui everywhere. Work happens on `fast-atmos`. This file is the map; history, rulings and traps live in auto-memory.

## Layout
- `code/`: /tg/ code. Change it only when a hook won't do. Mark each change `// hippie -- reason`, or `// hippie start -- reason` ... `// hippie end`, and list the file in `hippiestation/changes.md`. Full rules are in `hippiestation/README.md`.
- `hippiestation/code/`: Hippie's own code, with the same paths as `code/`. The dme includes it after all of `code/`, so a proc defined here for a tg type replaces tg's (`..()` calls tg's). A tg file that's rewritten whole is copied here and the original is taken out of the dme.
- `code/__DEFINES/~hippie_defines/`: Hippie's defines, one file per topic (`bots_ai.dm`, `hooks.dm`, ...).
- `hippiestation/icons`, `hippiestation/sound`: all new icons and sounds. A Hippie sheet at a tg sheet's path overrides it: `tools/icon_merge` merges it into the tg sheet at build time (never hand-edit those `icons/` files; see `hippiestation/README.md`).
- `hippiestation/interface/skin.dmf`: the live window skin (not `interface/skin.dmf`).
- `_maps/<name>.json` + `_maps/map_files/`: maps. The Hippie station is classic DMM, not TGM. `_maps/testbench.json` is Runtime Station with no Lavaland or ruins. Boot tests on it (`bot-map=testbench`) unless they need the real station.
- `config/`: server config. `data/`: runtime output (logs in `data/logs/YYYY/MM/DD/`, tool results).
- `hippiestation.dme` is the only dme. Never touch `tgstation.dme`.

## Systems
- **Bot crew:** `hippiestation/code/modules/bots_ai/`. `bot_brain.dm` holds the states (wander, combat, goal, arrest), `goals/` has one file per job or task, `gym/` has the test scenarios, and `GOAP_REFERENCE.md` covers job loops and objectives. For any change, use the `bot-ai-testing` skill.
- **tgui:**
  - DM side: `code/modules/tgui/` (`ui_interact`, `ui_data`, `ui_act`).
  - Windows: `tgui-next/packages/tgui/interfaces/*.js` (Inferno), each registered in `routes.js` `ROUTES` under its interface name in snake_case.
  - Build with `tgui-next/bin/tgui-build.bat`. The built `public/tgui.bundle.js` is committed.
  - A window with no route still loads the old Ractive `tgui/`, which is still in use.
  - `input()` and `alert()` go through `hippiestation/code/modules/tgui/tgui_prompt.dm`. `tools/tgui_convert` converts the old calls.
- **Atmos:** LINDA lives in `code/modules/atmospherics/`. The native engine is `hippiestation/code/modules/atmospherics/tile_engine.dm` plus `hippie_atmos.dll` (Rust, built with `tools/atmos_engine/build.sh` for the i686 target). Without the DLL, the game falls back to LINDA.
- **Lighting:** `hippiestation/code/modules/lighting/lighting_engine.dm` plus `hippie_lighting.dll` (`tools/lighting_engine`).
- **Admin windows** (hub, Find, bans, tickets): `hippiestation/code/modules/admin/`. **Keybinds:** `hippiestation/code/modules/keybindings/`. **Circuits:** `hippiestation/code/modules/integrated_electronics/`.

## Build and check
- Compile: `"/c/Program Files (x86)/BYOND/bin/dm.exe" hippiestation.dme`, then `tools/lint/run_lint.sh`. A new lint error blocks. Passing lint doesn't mean it compiles, and compiling doesn't mean it works.
- To test behaviour, run headless: `dd.exe <dmb> <port> -trusted -invisible -params "..."`. Start the round first, because SSair, SSobj and SSexplosions don't run in the lobby. Most tools build their own dmb, so `hippiestation.dmb` stays free for other sessions.
- Shell scripts start with `unset __COMPAT_LAYER` (dm.exe leaks handles with it set).

## Tools (`tools/`)
- `bot_gym/`: `ab_gym.sh` (before/after), `run_bot_gym.sh`, `run_bot_shift.sh`, `run_live_round.sh`, digests and death stories.
- `lint/`: dreamchecker against a baseline. `gc_hunt/`: hard-delete hunts.
- `atmos_bench/`, `lighting_bench/`, `speed_bench/`, `boot_bench/`: performance A/B.
- `power_check/`, `smooth_check/`, `circuit_check/`, `ban_check/`, `code_sweep/`: headless self-tests.
- `keybind_check/`: real-client harnesses and screenshots (`shot.ps1`).
- `timewarp/`: fast-forwards headless runs. `byond_reports/`: BYOND engine bug repros.

## Working in this tree
- Other Claude sessions share this folder and its git index. Add and commit named paths only (`git commit -F msg -- <paths>`). Never revert a file you didn't change. Stage `hippiestation.dme` one line at a time (`stage_dme_line.py` in the skill).
- Keep each file's line endings, since many are upstream CRLF. Use Edit, and check with `git diff --stat`.
- Commit or push only when asked. No Claude attribution lines in commits.
