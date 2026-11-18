# mapforge: plan for generations that pass as human-made

Written 2026-11-18. The aim is generated stations and departments that a mapper can't tell from human work, that play
at least as well as MetaStation, and that still vary from seed to seed. This plan says how we measure that, which
methods from 2D top-down procedural generation fit each layer of a station, what to build, and in what order.

## 1. Why the generator misses today

1. **Greedy layers with no feedback.** `station/to_dmm.py` runs layout, then rooms, then furniture, then
   infrastructure, then dressing, one pass each. A later layer can't push back. If a room can't be furnished well,
   nothing reshapes its walls; the furnisher makes do. Every "makes do" is a visible flaw.
2. **Knowledge arrives one complaint at a time.** Each ruling the user gives becomes a rule (squeezes, double walls,
   one piece per wall face, chevrons on hazards only...). That's correct, but it only covers flaws someone has
   already seen. Nothing finds the next one first.
3. **Flat statistics copy looks, not purpose.** Corpus clusters and whole-room templates scored badly ("randomize on
   the character generator"). Authored kits plus workflow rules (Science v3) scored "brilliant". The lesson: learn
   the *rules of use* by hand, and use data to judge and to tune, not to copy.
4. **No number for "human-like".** Checks say what is broken. Nothing says how far a map is from human work, or
   where. The known gaps were found by hand: odd-shaped rooms ~20% vs human (grown footprints are still notched
   boxes), wall corners 78 vs 107, halls 17-28% of floor on small ring/spine stations vs human 12-16%, Security seeds
   look alike.
5. **Two generators, split knowledge.** The department node graph (`forge/proc`, `assets/`) and the whole-station
   path (`station/grow.py`, fresh rooms in `to_dmm.py`) each hold rules the other lacks.

## 2. The bar, made measurable

"No compromises" needs a test. The release bar has four parts, and a map ships only when it passes all four.

| test | how | pass |
| --- | --- | --- |
| Blind test | the user sees two crops rendered the same way: one human, one generated, same department or room type. They pick the human one. Run at four scales: whole station, department, room, 15x15 tile patch. | the user picks right at most 55% of the time over 40 pairs per scale (chance is 50%) |
| Hard checks | `forge/check.py` + `forge/function.py` + the rule registry (4.C1) + a headless boot | 0 problems, 0 runtimes, 0 open pipe ends, every vent on a network |
| Play | Bot Shift batches on the generated map against MetaStation | task success, failed path searches, travel time per job and deaths within MetaStation's own spread |
| Fingerprint | every feature in 4.B1 | inside the range the human maps span, at every scale |
| Variety | expressive range (4.B3) over 50 seeds | covers at least the spread of the human maps; no two seeds closer than the two closest human maps |

## 3. Methods from 2D top-down generation, and where each fits

No single method gets there. Each one is strong at one layer and weak elsewhere.

| method | known from | good at | bad at | use here |
| --- | --- | --- | --- | --- |
| Room accretion / constrained growth | Lopes et al. 2010 floor plans; Brogue; our `grow.py` | organic, branching outlines | no global goal; boxes with notches | keep as a fast proposal source only |
| Slicing trees (BSP) | classic roguelikes; our `solve.py` | guaranteed tiling, adjacency | boxy, every cut a straight line | inner blocks of a department only |
| Mission/space graph grammars, cyclic generation | Dormans 2010; Unexplored (2017) | topology first: loops, lock and key, depth | geometry left to another step | **station topology**: access tiers are lock-and-key (public, department lobby, staff, secure), maint is the second loop |
| Graph-to-layout with a shape library ("configuration space") | Ma et al. 2014, *Game level layout from design specification* | real room shapes from a library meeting a graph's adjacencies | needs a shape library | **room footprints**, shapes mined from human rooms (L, T, U, cut corners) instead of notching boxes |
| Learned program + stochastic optimisation | Merrell, Schkufza, Koltun 2010, *Computer-generated residential building layouts* | room counts, sizes and adjacencies learned from examples, then laid out by optimisation | data-driven part needs many examples | **program layer** (which rooms, how big, who neighbours whom), learned from the parsed corpus |
| Deep floor-plan generators | RPLAN (Wu et al. 2019), Graph2Plan 2020, House-GAN++ 2021, HouseDiffusion 2023 | graph-conditioned plans | need 10k-80k plans; we have ~15 stations | not as generators. The graph-conditioned idea carries over to the solver |
| Constraint solving (ASP, CP-SAT, SAT) | Smith and Mateas 2011 (ASP for PCG); Sturgeon (Cooper 2022) | hard rules stated once and always met; global, not greedy | slow when the grid is big | **footprints inside a block**, **room interiors**, **repair** |
| Model synthesis / WaveFunctionCollapse | Merrell 2007; Gumin 2016; Karth and Smith 2017; Bad North; Caves of Qud | local texture from one example | no purpose, no long range structure | **look layer only** (floor colour, grime, clutter): already started in `look_wfc.py` |
| Markov chains over tiles | Snodgrass and Ontañón | same as WFC | same | covered by the WFC layer |
| Furniture arrangement by optimisation | Yu et al. 2011 *Make it home*; Merrell et al. 2011 design guidelines; Fisher et al. 2012 example-based arrangement | pairwise relations (faces, beside, against wall) learned from examples, then annealed | needs relations, not raw positions | **interiors**: soft priors on top of our authored kits |
| Learned scene synthesis | PlanIT 2019, ATISS 2021 | object-by-object from data | data hungry | idea only: a room as an ordered list of kits |
| LLM proposes, solver places | LayoutGPT 2023, Holodeck 2024 | turning a written room program into constraints | LLMs are poor at exact geometry | Claude writes **workflow specs and kits**; the solver does geometry |
| Search-based PCG, quality-diversity | Togelius et al. 2011; MAP-Elites (Mouret and Clune 2015) | best candidates *and* many different ones | needs a good score | **outer search loop** over whole stations |
| Expressive range analysis | Smith and Whitehead 2010 | showing what a generator can and can't make | measurement only | **variety test** |
| Space syntax | Hillier and Hanson 1984 | numbers for "how it plays": depth, integration, chokepoints, what the public can reach | measurement only | **play critic**, fast, no boot |
| Playtest agents | PCGRL (Khalifa 2020) uses agents as reward | judging function by running it | slow | **our bot crew**: few generators have real agents that play the full game; use them |
| Templates with variation | Spelunky; Enter the Gungeon (flow graph + room templates) | authored quality with variety | authored cost | our **kits** are this, keep them |
| Inverse procedural modelling | fitting generator parameters to examples | tuning dials from data | needs a distance | **auto-tune** dials to match the human fingerprint |

What the survey says, in short: topology from a grammar, footprints and interiors from constraint solvers, look from
WFC, and *learning used to judge and to tune*, not to draw. With about 15 human stations we don't have enough data
for an end-to-end learned generator. We do have enough to train judges, mine shapes and kits, and fit dials.

## 4. What to build

### A. Corpus and parser (the foundation)

- **A1. Bigger corpus.** Local today: Meta, Delta, Box, Pubby, Donut, Hippie, Mini, Endo, MetaLake. Add current tg
  master maps (IceBox, Tram, Kilo, NorthStar, Birdshot...) and other tg forks' stations, pinned by commit (see the
  tg-ports memory rule). A type alias table maps their paths to ours; types with no match become
  "unknown machine / unknown structure" so judges can't key on spelling.
- **A2. Semantic parser** (`forge/parse.py`): `.dmm` -> one structure every layer shares, `SemanticMap`:
  - rooms as wall-bounded regions (not `/area`, which spans rooms; the 77% "odd" human figure was mostly that),
  - halls vs rooms vs maint vs space, doors with their access (`req_access`, `req_one_access`), windows, glass doors,
  - departments, access tiers (depth from Arrivals through doors you need access for),
  - **kits recognised** in each room by matching our authored kits against the furniture (this also tells us which
    human rooms our kits can't explain: those are the missing kits),
  - stand tiles (the use tile in front of each machine), wall faces and what hangs on them,
  - pipe/cable/disposal networks.
  The generator writes the same structure, so every measurement and judge runs on human and generated maps alike.
- **A3. Mine human corrections from git history.** tg's map history is thousands of commits where mappers fixed
  their own maps. Each map PR gives before/after pairs ("this tile was wrong, this is right"). That's exactly the
  data we lack: negative examples written by humans, labelled by the fix. Parse both sides, keep diffs under ~400
  tiles, tag by commit message (fix, decal, pipe, lighting, remap). Also log every fix the user asks for here as a
  pair.

### B. Measurement

- **B1. Fingerprint** (`forge/fingerprint.py`), about 60 numbers at four scales, each with the human min/median/max:
  - station: floor per crew, hall %, maint %, departments' distance from centre, loops, hull roughness, docks;
  - department: room count, odd-shape %, corners per 100 tiles, mean room area and spread, lobby depth, doors per
    room, glass share, maint contact;
  - room: aspect, fill (dense tiles / floor), free floor in one piece, kits per room, wall usage, stand-tile clearance,
    mirror symmetry score, light/vent/alarm counts per area;
  - tile: 3x3 pattern frequencies (structure and look), decal densities, sprite overlap count.
  Report: one line per feature, flagged when outside the human range, with a picture of the worst spot.
- **B2. Space syntax** on the walkable graph: mean depth from Arrivals, integration (how central each hall is),
  chokepoints (cut vertices), public reach (what an unaccessed crewman can enter), visibility from department fronts.
  These encode the Perihelion rulings (secure rooms behind foyers, departments behind lobbies) as numbers.
- **B3. Expressive range plots**: 50 seeds per layout on two axes at a time (hall %, odd rooms, linearity,
  department spread), human maps drawn on the same plot. Shows at a glance what the generator can't make.
- **B4. Regression gallery**: fixed seeds x fixed crops, rebuilt after every change, before/after side by side in
  `data/previews/mapforge/gallery/`, plus the fingerprint delta. No change merges without it.

### C. Judges (critics)

Each judge gives a score *and a place* (tile heatmap), so a fault can be repaired where it is.

- **C1. Rule registry** (`forge/rules/`): every user ruling becomes one entry: id, the user's words, date, a check
  function, and a fixture crop that must fail before the fix and pass after. Start by converting the ~60 rulings
  already in memory (practical layouts, decals and vents, Meta style, design for play, Perihelion access). New
  rulings get an entry the same day. `check.py` runs the registry.
- **C2. Learned discriminator: "does this look human?"** Input is the semantic tile tensor from A2 (channels: wall,
  window, door, floor kind, dense, machine class, decal class, hung piece, pipe, cable), not pixels, so it can't key
  on sprites. Two models:
  - a small CNN over 24x24 patches (8 symmetries, random crops, type dropout for augmentation),
  - a graph network over the room graph (room features + adjacency) for department scale.
  Train human vs generated, with hard negatives from A3's "before fix" states and from every rejected build.
  Its gradient heatmap (Grad-CAM) points at the inhuman tiles. Small data means it will overfit: hold out whole
  maps, calibrate, retrain each time the generator improves (a slow adversarial loop through data, not gradients),
  and treat it as one vote, never as law. Runs on the RTX 3080 in minutes.
- **C3. The user's taste, learned.** Each review becomes pairwise picks (A better than B) and tile tags. A
  Bradley-Terry model over fingerprint features (and later the C2 embedding) learns what the user prefers. Active
  learning picks the pairs it is least sure about, so each review teaches the most.
- **C4. Play judge, two speeds.**
  - Fast, no boot (seconds): walkers on job routes taken from the job loops in `GOAP_REFERENCE.md` (spawn to post,
    post to supply, supply to delivery). Route lengths, how often routes share a tile (congestion), dead ends,
    detours forced by furniture. Runs inside the search loop.
  - Slow, real (minutes): Bot Shift batches (`run_bot_shift.sh`, 12 shifts, 6 at a time), headless boot zone checks,
    failed path searches by tile. Runs on finalists only.
- **C5. Claude review pass.** Before a picture reaches the user, Claude reviews rendered crops against the registry
  rubric ("sprites drawn over each other? practical and pretty? would a mapper do this?") and tags tiles. Catches
  what checks can't state yet. Each tag it confirms becomes a C1 rule candidate.

### D. Generators, rebuilt per layer

- **D1. Program** (what the station needs): room list per department and crew size, sizes and neighbour
  likelihoods learned from the parsed corpus (Merrell 2010 style), plus the hand-written workflow specs.
- **D2. Topology**: a graph grammar over zones. Rules produce the hall loop or spine, department lobbies, access
  tiers, maint as a second network with its own loop, docks, satellite tunnel. Constraints: two routes to every
  department, secure rooms behind a foyer, departments open only onto their own hall. Output: a graph, checked
  with B2 before any geometry.
- **D3. Footprints**: CP-SAT (OR-Tools) places room polygons on the grid inside each block. Shapes come from a
  library mined from human rooms (A2), normalised and scaled, so L, T and cut-corner rooms come from how humans
  draw them, not from notching. Hard: adjacency from D2, door frontage, single walls between rooms (no
  floor-wall-wall-floor), no corner-only joins, walls meet edge to edge. Soft: fingerprint distance, room area
  targets, C3 preference.
- **D4. Interiors**: authored kits stay (they are what worked). New:
  - a workflow spec per room type: inputs, outputs, stand spots, open work areas (mech 3x3), machine links verified
    in the game code, public/staff side. About 60 room types. Claude writes them from code and the human maps; the
    user approves each department's set.
  - kit mining: clusters the parser can't explain are proposed as new kits for review.
  - placement by CP-SAT: kits on walls and floor, hard rules (stand tiles free, aisles open at both ends, no
    diagonal squeeze, tall pieces off glass, one piece per wall face, doors clear both sides); soft pairwise priors
    learned from human rooms (Fisher 2012: faces, beside, against wall, mirrored across the room). Then a short
    simulated-annealing polish for symmetry and spacing (*Make it home*).
- **D5. Infrastructure**: keep the router. Add style: supply and scrubber runs in parallel, under hall centre lines
  or along one side, fewest bends, matching how human maps run them (measured by B1). Lights, vents and scrubbers
  laid in lines and boxes by rule (the vents ruling).
- **D6. Look**: finish `look_wfc.py` (colour, grime, clutter), trained on Meta and Delta, gated by C2 on tile
  patches. Functional decals stay rule-driven (hazards, loading, delivery).
- **D7. Repair** (the step that gets from good to perfect): large neighbourhood search. Take the worst region from
  the judges' heatmaps, free it (a room interior, a pair of rooms, a hall stretch), keep its border fixed, re-solve
  just that region with D3/D4, and keep the change if the combined score improves. Repeat until no region improves.
  This replaces "makes do" with "fix it where it is".

### E. Search over whole stations

- **E1. Quality-diversity archive (MAP-Elites).** Axes: layout family, hall %, department arrangement, odd-room
  share. Each cell keeps the best station by the combined judge score. A nightly run generates a few hundred,
  repairs the finalists (D7), runs the slow play judge on the top cell holders, and keeps the archive. Seeds then
  come from the archive, so every seed is a good one and they differ.
- **E2. Auto-tune dials**: CMA-ES (or plain Bayesian optimisation) over generator parameters, minimising
  fingerprint distance to the human maps plus the play penalty. Replaces hand-tuning numbers like notch rate 0.8.

### F. The user in the loop

- **F1. Review page**: zoomable station render, click a tile to tag it (ugly, impractical, wrong, good) with a note,
  A/B pairs for C3. Tags are saved as labelled data, become fixtures, and feed C2 and C3.
- **F2. Blind test mode**: the bar from section 2, run at each milestone.
- **F3. Ruling capture**: every new ruling goes to the registry (C1), memory, and a fixture, in that order, before
  the fix is written.

## 5. Order of work, with exit criteria

| phase | build | exit |
| --- | --- | --- |
| P0 Measure | A2 parser, B1 fingerprint, B4 gallery, C1 registry from existing rulings | a report: generated vs human per feature, with the worst spots pictured; every ruling has a check and a fixture |
| P1 Judges | B2 space syntax, C4 fast play judge, C5 review pass, F1 review page, F2 blind test baseline | baseline blind-test numbers at four scales (expect the user to spot generated work 85-95% of the time) |
| P2 Corpus | A1 more maps + alias table, A3 git fix mining, C2 discriminator v1 | discriminator beats chance on held-out maps; its heatmaps point at real faults the user agrees with |
| P3 Footprints | D2 grammar, D3 CP-SAT + shape library | odd-room share and corners inside human range; hall % in range at crew 40; 0 doubled or corner-only walls by construction |
| P4 Interiors | workflow specs for all room types, kit mining, D4 solver placement | department-scale blind test at or below 65%; 0 check problems over 50 seeds |
| P5 Repair and search | D7 repair, E1 archive, E2 auto-tune, C3 preference model | station-scale blind test at or below 60%; expressive range covers the human maps |
| P6 Finish | D5 infra style, D6 look layer, Bot Shift parity runs | the full bar in section 2 |

P0 and P1 come first because every later step needs their numbers to show it helped. Each phase ends with pictures
and a question to the user.

## 6. Risks and traps

- **Small data.** About 15 stations. No end-to-end deep generator. Learned parts are judges, priors, shape and kit
  libraries, and dial fitting. Augment by symmetry; grow the corpus with forks (A1) and git history (A3).
- **Judges that learn the wrong cue.** A discriminator can learn "Hippie-only type = generated". Feed semantic
  channels, alias types, hold out whole maps, and check its heatmaps against user tags.
- **Goodhart.** Matching the fingerprint can give statistical mimicry without purpose (the corpus-template
  failure). Workflow specs and the play judge are hard gates; statistics only choose among maps that already work.
- **Solver time.** CP-SAT on a whole station is too big. Solve per block and per room, with D2's graph fixing the
  borders. Budget seconds per room, minutes per station.
- **Cost of real play tests.** Bot shifts take ~12 minutes a batch. Use the fast judge inside loops, shifts for
  finalists. Shifts stalled on full generated stations before (the lobby build trap, fixed); keep the testbench
  rule for anything that doesn't need a station.
- **Disk.** Batches have filled the drive before. Store tensors and archives compactly, prune previews per run.
- **Dependencies.** Not installed yet: `ortools`, `torch` (CUDA, RTX 3080 available), `networkx`, `scipy`. Pin
  versions in `tools/mapforge/requirements.txt`.

## 7. Decisions for the user

1. Corpus: may we parse other tg forks' station maps and tg's git history as training and judging data? (Used for
   measurement and judges, never copied into our maps.)
2. Blind test: are four scales x 40 pairs per milestone acceptable review time (about 15 minutes each)?
3. Where to start: P0 + P1 (measure and judge first) is the recommended order.
4. Scope: one unified generator (department graph and station path merged on `SemanticMap`), or keep both?
