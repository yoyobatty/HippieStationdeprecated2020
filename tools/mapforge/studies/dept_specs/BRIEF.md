# Department function pass: shared brief (2026-11-26)

## What the user wants

The user, reviewing our generated station (HippieStation, SS13, a 2020 /tg/station fork):

> "double check every room and hallway one by one, make sure it's sensical, functional like an ss13 map with good
> human like pathing, design and function"
>
> "check how rooms and hallways and departments fit and join together holistically with each other and the entire
> station, so we don't get patterns like chemistry tables opening into walls / useless rooms that players can't get
> to. Think one by one how a department and its rooms really feel ... compare side by side: is this a real proper
> ss13 map with a nice good layout, would an engineer like the setup, would each role and player and a human eye
> think this looks generated or not."
>
> "not just counters my friend, the entire station: kitchen needs a serving window, engineering needs safety,
> showers, equipment. Think exactly what each department does, don't follow my words one by one, you need to really
> go crazy here and think properly ... I think we should work engineering properly. Get it right. The department
> and other departments will be random so it can vary in size, shape just like real maps but overall it will follow
> the same functional patterns."

So: departments vary in size and shape from build to build (that stays), but each one must follow the functional
patterns of real SS13 departments: the rooms it needs, what each room is for and holds (work kit, safety gear,
storage), how its rooms join each other (doors, desks, windows, which rooms sit together), how the public reaches
its front and the staff its back, and how it joins the halls and the departments it works with. Judge as a player
of each role would: can I do my job here, quickly, without walking through a store or a wall-facing desk?

## The repo and the generator

- Repo root: `H:\HippieStationdeprecated2020-master\HippieStationdeprecated2020-master` (Git Bash: `/h/...`).
  Work from `tools/mapforge`. Read `tools/mapforge/studies/function_pass_2026_11_26.md` first (what was done and
  measured today) and skim `tools/mapforge/studies/full_generator_plan.md` (the pipeline).
- Pipeline (`gen/build.py`): blocks and spokes (`gen/compose.py`), departments planned by the learned floorplanner
  (`gen/learn/floorplan.py`: a room program per department from the stock maps, rooms laid in strips along a stem
  corridor, cells/pens carved as "pieces"), furnished from stock room motifs (`gen/learn/synth.py`, `roomdb.py`),
  kit per room type (`gen/essentials.py`), dressing, then function passes: `gen/learn/settle.py`, `density.py`,
  `doorcount.py`, `fixtures.py` (alarms, switches, extinguishers), `gen/learn/doordb.py` (airlock styles/access),
  `gen/learn/desks.py` (NEW tonight: counters/desks/hatches between a working room and what it serves),
  `gen/audit.py` (function audit), `gen/walls.py` (merge_doubles, join_corners, seal_hull), `gen/net.py` (power,
  pipes, disposals, the engine block, solars). Atmospherics and the AI satellite are composed blocks.
- The current generated map: `data/mapforge/gen_learn/f22_c100_s7.dmm` (crew 100, seed 7). If it is not there
  yet, use `data/mapforge/gen_learn/f21c_c100_s7.dmm` (same pipeline without tonight's last small fixes).
- Stock maps (the bar): `forge.corpus.MAPS` under `_maps/map_files/` - MetaStation, BoxStation, DeltaStation2,
  hippiestation, PubbyStation, Donutstation, EndoStation, MetaLake (Meta copy). Meta, Box, Delta are the best models.
- Code: game code in `code/` and `hippiestation/code/`; job access lists in `code/modules/jobs/job_types/*.dm`;
  access numbers in `code/__DEFINES/access.dm`. Bot crew (they play the jobs) in
  `hippiestation/code/modules/bots_ai/goals/` - what each role's bot needs from the map (e.g. `bartender.dm`,
  `cook.dm`, `toxins.dm`) is a hard functional requirement.

## Tools (use them; build new reusable ones in tools/mapforge/gen or studies with a docstring if needed)

- `python gen/roomreview.py <dmm> --out <dir> [--only <area text>] [--scale 0.75]`: one picture per room/hall
  segment with a card (doors, style, access, what's beyond, contents, findings). Works on stock maps too: use it
  side by side (e.g. `--only engine` on MetaStation.dmm and on ours).
- `python gen/pictures.py <name> --path <dmm> --grid 40` (labelled squares) and `forge/render.py`
  `render(dmm, png, region=(x0,y0,x1,y1), scale=...)` for any crop. Pictures are dmm-tools renders (no game needed).
- `python gen/audit.py <dmm> --list`, `--rooms <dept>`, `--stock`; `python gen/learn/placestudy.py --check <dmm>`.
- `forge/dmm.py` (read/write maps: `m.tiles[(x,y,z)]` Tile with `.objs` [Atom path, vars], `.turf`, `.area`,
  `m.get(x,y)`), `forge/corpus.py` (CO.solid, CO.mounted, CO.mount_side), `forge/function.py` (FN.is_dense),
  `studies/stations.py` (group_of(area) -> department group).
- Python on Windows: write files with `open(p, "w", newline="")` (LF); in Git Bash prefix commands that take
  `/area/...` arguments with `MSYS_NO_PATHCONV=1`; Bash heredocs mangle backslashes, use the Write tool for code.

## Your task (each agent: one department, see your prompt)

1. Study the department on the stock maps, room by room, with pictures side by side (Meta, Box, Delta at least,
   the others for frequencies). For each room: what it is for, who uses it and how (step by step for each role),
   what it holds (work kit, safety gear - showers, eyewash/emergency showers, fire/radiation/emergency closets,
   extinguishers -, storage, signs), where in the department it sits, which rooms it adjoins and how it opens
   (door, windoor desk, window, shutters), what the public sees and reaches, what is staff-only, how the department
   joins the halls and the departments it works with. Count frequencies over the 8 maps.
2. Write the spec: `tools/mapforge/studies/dept_specs/<dept>.md` - required rooms (and optional ones with their
   stock frequency), adjacency and joins, per-room function and kit including safety and equipment, desks/windows,
   access, the role workflows, and a list of CHECKABLE rules (each with its stock frequency or count). Be concrete.
3. Review our map's department one room at a time (roomreview pictures + cards) against the spec, and the
   department as a whole side by side with Meta/Box/Delta. List every defect with coordinates and its cause in the
   generator (which pass or table produces it).
4. Implement what can be fixed on a finished layout in a NEW file `tools/mapforge/gen/learn/fn_<dept>.py`:
   `check(m) -> list of (x, y, text)` (the spec's checkable rules) and `fix(m, seed=1, log=print) -> int` (adds,
   moves or swaps kit, safety gear, desks/windows, signs; repurposes a wrongly placed piece; never breaks walkability,
   never puts a dense piece on a door front, keeps every room reached from its doors). Make it runnable as
   `python gen/learn/fn_<dept>.py <in.dmm> <out.dmm>` printing check() before and after. Test it on the current map
   and render before/after pictures of the rooms it changes (into `data/previews/mapforge/dept_<dept>/`).
5. Layout-level problems a finished map can't fix (missing rooms, wrong neighbours, room sizes, a room that should
   join the hall) - write the exact proposed generator change (file, function, what to change, why, the stock
   numbers) in the spec's "Generator changes" section. Do NOT edit shared files yourself.

## Rules

- Only create your own new files (your spec, your `fn_<dept>.py`, scratch files under your own folder
  `tools/mapforge/studies/dept_specs/<dept>_work/`, pictures under `data/previews/mapforge/dept_<dept>/`). Do not
  edit any existing file. Other agents work in the same tree at the same time.
- Do not run `gen/build.py`, DreamDaemon/dd.exe, Dream Seeker or dm.exe (the main session runs builds and boots;
  the PC is shared). Python scripts on maps and dmm-tools renders are fine. Keep CPU light.
- Do not commit or push. Do not touch `hippiestation.dme` or `tgstation.dme`.
- No subagents.
- Final report (your last message, under 500 words): what you found (top defects with coordinates and cause),
  what your `fn_<dept>.py` fixes (check counts before/after on the current map), the generator changes you propose
  (short list, in priority order), and the paths of your spec and pictures.
