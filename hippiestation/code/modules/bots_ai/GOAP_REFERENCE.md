# Bot AI — GOAP Action Reference

Design reference for the eventual goal-directed planning layer on top of the
Milestone 1 reactive bot AI (`bot_brain.dm`/`bot_movement.dm`/`bot_items.dm`).
Not code — this is the knowledge base a future planner's action definitions
should be built from.

Compiled 2026-09-16 from four parallel research passes, each cross-checking
general tgstation/SS13 knowledge (wiki, community guides) against this
repository's actual `.dm` source. Every claim is either confirmed against a
specific file/line in this codebase, or explicitly flagged **"unverified,
wiki claim only"** / **"unverified in this pass"** — do not treat unflagged
external SS13 knowledge as true of this fork without checking; HippieStation
has diverged from upstream tgstation in places that matter (e.g. the
WIRE_IDSCAN/WIRE_OPEN hacking order was locally patched — see §2).

## Contents
1. [Job Task Loops](#1-job-task-loops) — what each job actually does round to round
2. [Antagonist Objectives](#2-antagonist-objectives) — the 23 objective types and their goal predicates
3. [Access & Security](#3-access--security) — ID/access, airlock hacking, safes/vaults, other bypasses
4. [Breaching & Destruction](#4-breaching--destruction) — chemistry, tools, explosives, mecha
5. [Item Acquisition & Economy](#5-item-acquisition--economy) — vending, cargo, crafting, theft, trading
6. [Cross-Reference Index](#6-cross-reference-index) — all actions in one table, by goal

---

# 1. Job Task Loops

*Job `.dm` files (`code/modules/jobs/job_types/*.dm`) only define structural
metadata (title, department, access, supervisors, paycheck account, spawn
loadout) — there is no in-code "duties" text. Every task-loop description
below is general tgstation player-culture knowledge, flagged **unverified,
wiki claim only** throughout. Department/supervisor/access facts were
spot-checked against the job files and do match.*

| Job | Typical loop (unverified, wiki) | Verified facts (department/access) |
|---|---|---|
| **Assistant** | No assigned duties — freelances, helps understaffed departments, scavenges tools/access, explores maintenance. | No department_head, no real access (`assistant.dm`). |
| **Station Engineer** | Solar arrays, singularity/supermatter engine maintenance, hull breach repair, power grid (SMES/wiring), airlock electronics, wall construction. | Reports to Chief Engineer (`station_engineer.dm`). |
| **Atmospheric Technician** | Atmos pipe network, gas mixing/distribution, scrubbers/canisters, breach/fire response. | Reports to Chief Engineer (`atmospheric_technician.dm`). |
| **Scientist** | R&D: experiments (xenobiology etc.), unlocks tech via protolathe, produces gear for other departments. | Reports to Research Director (`scientist.dm`). |
| **Chemist** | Synthesizes medicine, fills pill bottles/beakers for medical, supports virology/genetics. | Under CMO/medical dept (`chemist.dm`). |
| **Medical Doctor** | Treats injuries, surgery, cryo/sleeper management, triage, restocking. | Reports to CMO. |
| **Security Officer** | Patrols, responds to crime, arrests/processes prisoners, investigates, defends vs. antagonists. | Reports to HoS (`security_officer.dm`). |
| **Cargo Technician / Quartermaster** | Processes supply orders, ships crates, mines/sells salvage; QM approves large orders/manages budget. | `cargo_technician.dm`/`quartermaster.dm` dept metadata confirmed. |
| **Botanist** | Grows/mutates plants, supplies Chef/Bartender, can produce hazardous plants. | — |
| **Chef** | Cooks meals from hydroponics/cargo ingredients, stocks kitchen. | — |
| **Bartender** | Mixes/serves drinks, manages bar stock, brews alcohol. | — |
| **Janitor** | Cleans spills/hazards, replaces lights, empties trash. | — |
| **Head of Personnel** | Manages crew records/IDs/access changes, covers for absent Captain. | Department head, high access (`head_of_personnel.dm`). |
| **Captain** | Coordinates heads, authorizes nuke disk access, station announcements, shuttle call authority. | Highest access, department_head over all (`captain.dm`). |

**GOAP-relevant goal shapes**: acquire tools/access (Assistant); maintain power/atmos above threshold, repair breaches (Engineering); accumulate research, distribute tech (Science); maintain medicine/food/drink stock, fulfill requests (Chem/Medical/Chef/Bar); locate+neutralize threat, patrol, arrest (Security); fulfill supply requests, run cargo cycle (Cargo); manage access requests (HoP); protect nuke disk, coordinate heads (Captain).

---

# 2. Antagonist Objectives

All 23 objective types below are implemented as concrete `/datum/objective`
subtypes in `code/game/gamemodes/objective.dm` (base type at line 3) —
**fully verified against source**, unlike Part 1. Each has a real
`check_completion()` proc, which is the actual goal-state predicate a
planner should read directly rather than relying on this summary. Strategy
notes layered on top are general wiki/community knowledge.

| # | Objective | Goal | Typical strategies | Source (line) |
|---|---|---|---|---|
| 1 | Assassinate | Kill a specific target | Isolate from crowds/security, poison, staged accident, direct combat, disguise-ambush | `/datum/objective/assassinate` (169), `/internal` (192) |
| 2 | Mutiny | Kill/overthrow a specific head of staff | Undermine authority first, frame them, strike at a chokepoint | `/datum/objective/mutiny` (200) |
| 3 | Maroon | Leave a target behind alive when shuttle departs | Sabotage their escape route, lock them in, disable suit/pod access | `/datum/objective/maroon` (223) |
| 4 | Debrain | Kill + surgically extract a target's brain | Kill target, brain-removal surgery, escape with the organ intact | `/datum/objective/debrain` (245) |
| 5 | Protect | Keep a target alive all round | Bodyguard, warn of threats, remove threats preemptively | `/datum/objective/protect` (279), `/nonhuman` (304) |
| 6 | Hijack | Escape on the shuttle while denying others' "escaped free" status | Seize shuttle control, incapacitate escaping crew, hold shuttle hostage | `/datum/objective/hijack` (308), `check_completion` (314) |
| 7 | Block | Prevent crew (or a subset) from escaping | Sabotage shuttle call, destroy pods, barricade departure points | `/datum/objective/block` (323) |
| 8 | Purge | Eliminate a category of targets | Systematically hunt the target group, area-denial methods | `/datum/objective/purge` (337) |
| 9 | Robot Army | Convert/control N cyborgs | Hack borgs via upload console, subvert AI, deploy combat mechs | `/datum/objective/robot_army` (352) |
| 10 | Escape | Personally escape alive | Survive to round end, reach shuttle/pod, avoid combat | `/datum/objective/escape` (369), `/escape_with_identity` (382) |
| 11 | Survive | Stay alive to round end (no escape required) | Avoid detection/combat, hide, stockpile supplies | `/datum/objective/survive` (422), `/exist` (433) |
| 12 | Martyr | Die in a specific manner/context | Provoke a dramatic final confrontation, die completing other objectives | `/datum/objective/martyr` (443) |
| 13 | Nuclear | Retrieve disk, arm device, detonate on/near station | Raid vault for disk, breach station, plant in correct zone, defend timer, extract | `/datum/objective/nuclear` (456); antag wiring `code/modules/antagonists/nukeop/` |
| 14 | Steal | Acquire a specific item (or one from a pool), typically escape with it | Locate item, steal via stealth/force/social engineering, hide until extraction | `/datum/objective/steal` (467), `/special` (552, ninja), `/exchange`+`/backstab` (564/589) |
| 15 | Steal Five of Type | Acquire N copies of a category (wizard summon guns/magic) | Repeatedly acquire copies, stockpile before round end | `/datum/objective/steal_five_of_type` (822), `summon_guns` (843), `summon_magic` (848) |
| 16 | Download | Download a quantity of research data/files | Access R&D servers, hack consoles, accumulate progress while avoiding detection | `/datum/objective/download` (601) |
| 17 | Capture | Abduct crew worth a cumulative point value | Stealth kidnap high-value targets, transport to holding area, avoid alerts | `/datum/objective/capture` (635); antag wiring `code/modules/antagonists/abductor/` |
| 18 | Protect Object | Keep a specific object intact | Guard its location, repel attackers, relocate if threatened | `/datum/objective/protect_object` (681) |
| 19 | Absorb / Absorb Most / Absorb Changeling | Changeling: absorb N crew, absorb the most, or absorb another changeling | Isolate victims 1-on-1, use stealth stings, avoid detection between absorptions | `/datum/objective/absorb` (701), `/absorb_most` (743), `/absorb_changeling` (764); changeling module wiring **unverified in this pass** |
| 20 | Destroy | Sabotage/destroy a structure/object (AI core, supermatter, department) | Plant explosives, overload systems, direct destruction, time it to avoid intervention | `/datum/objective/destroy` (787), `/internal` (819) |
| 21 | Custom | Admin-defined/freeform text objective | N/A — not mechanically automatable, needs heuristic interpretation | `/datum/objective/custom` (874) |
| 22 | Changeling Team — Impersonate Department/Heads | Absorb and maintain an entire department's (or its heads') identities | Absorb every target, maintain identities/access, avoid crew noticing | `/datum/objective/changeling_team_objective` (886), `/impersonate_department` (898), `/impersonate_heads` (1048) |
| 23 | Contract | Deliver a person/item to a generated drop-off point | Capture/acquire target, transport to drop-off, evade interception | `/datum/objective/contract` (1078), `generate_dropoff()` (1084), `dropoff_check()` (1093); blood_contract wiring **unverified in this pass** |

**Not found as a distinct objective type**: "Become Captain" (likely `custom` text, unverified). Revolution's own objective file exists at `code/game/gamemodes/overthrow/objective.dm` (present, not opened). Cult conversion/rune objectives likely reuse `absorb`-style or custom counting (not opened).

**Planner note**: read `check_completion()` per objective subtype directly for precise goal-state predicates — this table summarizes but doesn't reproduce that logic.

---

# 3. Access & Security

*Full detail: `bot_ai_reference_access_security.md` in the research scratchpad. All verified against source (read 2026-09-16) unless flagged.*

## 3.1 ID / Access Model
- ~90 access-level defines in `code/__DEFINES/access.dm`: 1–70 station roles, 101–110 CentCom, 150–151 Syndicate, 200–208 away/ruins, 250–251 cult, 300–304 mech.
- ID cards (`code/game/objects/items/cards_ids.dm`) store levels in `access`; `GetAccess()` returns it.
- Master gate: `/obj/proc/allowed(mob/M)` in `code/modules/jobs/access.dm` (line 3) — order: no-requirement→TRUE; GODMODE→TRUE; silicon (non-pAI)→TRUE **unconditionally, by mob type not ID**; admin ghost→TRUE; `COMSIG_MOB_ALLOWED` signal (nanite spoofing)→TRUE if handled; else checks held/worn ID.
- `check_access_list()`: AND-logic on `req_access`, OR-logic on `req_one_access`.
- Captain's spare ID (`/obj/item/card/id/captains_spare`) access is generated live from `datum/job/captain.get_access()` — always mirrors current captain access.
- Agent ID (`/obj/item/card/id/syndicate`) starts with only maintenance+syndicate access; its `afterattack()` **copies** any swiped ID's access onto itself (antag-only unless card is `anyone`-unlocked).
- ID console (`code/game/machinery/computer/card.dm`) requires `ACCESS_HEADS`/`ACCESS_CHANGE_IDS` to log in; full edit rights need `ACCESS_CHANGE_IDS` specifically (normally HoP/Captain); dept heads get access restricted to their own region. No `emag_act` override found on this machine.

## 3.2 Airlock / Door Hacking
- Wire panel: screwdriver toggles `panel_open`; multitool = pulse, wirecutters = cut/mend (`code/game/machinery/doors/airlock.dm`, `code/datums/wires/airlock.dm`).
- **Key hack**: cut `WIRE_IDSCAN` → `requiresID()` returns false → door no longer checks access (still needs power/unbolted). This is the actual "ID-scanner hack."
- **HippieStation-specific patch**: this fork removed vanilla's requirement to cut WIRE_IDSCAN before a WIRE_OPEN pulse works (local change, commented in source) — a real divergence from upstream tgstation behavior.
- Emag (`emag_act`, line 1270): forces door open once, then bolts it and cuts main+backup power — one-shot, and blocks further WIRE_OPEN pulsing.
- **Ghetto hacking**: if door is unpowered + unbolted + unwelded, a bare crowbar (or wielded fireaxe) pries it open with zero tools/access. Bolted or welded doors cannot be crowbarred at all.
- Secure/max-security doors add physical shielding layers (welded metal cover → plasteel outer → plasteel inner → electrified grille) that must be stripped in order before the wire panel is even reachable (`airlock.dm:840-931`).
- AI-only `hack()` proc (multi-stage, sleep-gated) lets a locked-out AI regain control — not usable by ordinary bots.
- Remote control wand (`code/game/objects/items/control_wand.dm`) opens/bolts doors over NTNet if the wand's `region_access` covers the door.

## 3.3 Safes / Vaults
- **No literal "safe" object exists.** The captain's spare ID lives in `/obj/structure/closet/secure_closet/captains` (`code/game/objects/structures/crates_lockers/closets/secure/security.dm`), `req_access = ACCESS_CAPTAIN`.
- Secure closets: `max_integrity = 250`, melee hits under 20 damage do **zero** structural damage (hard floor, not just armor reduction).
- **Emag**: `emag_act()` instantly sets `broken=TRUE, locked=FALSE` — the primary fast crack method, no minigame.
- **EMP**: probabilistic — `prob(50/severity)` toggles lock state, `prob(20/severity)` either opens it (if already unlocked) or **randomizes `req_access` to one random access level** (a reroll, not a guaranteed open).
- **Brute force**: ≥20 dmg/hit weapons eventually break it past 250 integrity via `bust_open()`.
- No combination-dial minigame anywhere in this codebase.

## 3.4 Other Bypasses
- Silicon (AI/borg, non-pAI) bypasses `allowed()` entirely by mob type — not an ID mechanic at all.
- Nanite component can grant a mob passing `allowed()` via `COMSIG_MOB_ALLOWED` signal, independent of any ID.
- Camera-based door bypass: **searched, not found in this codebase** — do not assume general SS13 camera-hack lore applies here.
- Windowdoor/unpowered-door `emag_act` bodies exist separately (simpler doors, presumably simpler bypass) — presence confirmed, contents unread.

---

# 4. Breaching & Destruction

*Full detail: `bot_ai_reference_breaching.md`. Wall model: normal wall (2x metal) → girder → sheets; reinforced wall (r_wall, plasteel) has a 7-stage tool-order deconstruction and is much harder (`hardness`: normal=40, r_wall=10, lower=harder).*

## 4.1 Chemistry
| Reagent | Recipe | Effect on turf | Notes |
|---|---|---|---|
| **Thermite** | aluminium 1 + iron 1 + oxygen 1, no temp requirement | Coats turf (`amount = reac_volume*10`); needs a hot item or >1922K flame to trigger `thermite_melt()`; destroys turf only if accumulated `amount >= 50`. r_wall needs ~4x the dose (`amount *= 0.25`). Diamond/indestructible walls immune. | Two-phase (coat then ignite); component-based (`code/datums/components/thermite.dm`), not pure probability. |
| **Chlorine Trifluoride (ClF3)** | chlorine 1 + fluorine 3, **requires 424K to mix**; spawns a 3x3 fireball on creation | `reaction_turf`: plating→`prob(10+burnt+5*broken)` ScrapeAway; floor→`prob(reac_volume)` strip to plating or burn; **wall→`prob(reac_volume)` ScrapeAway directly, no girder stage**. Also ignites mobs on touch. | Confirmed real delivery path in this codebase: premade `chem_grenade/clf3` (two bluespace beakers, splashes via `chem_splash()` on prime). Probabilistic per application, no HP tracking like thermite. Hippie's `chem_splash()` override exists but wasn't diffed against upstream — partially unverified. |
| Blackpowder/nitroglycerin/sorium/liquid_dark_matter | various | Trigger `explosion()` rather than turf-scraping | Mechanism (mix→explosion) confirmed, exact blast radii **unverified in this pass**. |
| Fluacid (acid) | — | Walls have a generic `acid_act`/`acid_melt()` → `dismantle_wall(1)` proc confirmed to exist | Acid reagent's actual turf-application path/thresholds **unverified in this pass**. |

## 4.2 Tools
| Method | Speed | Result | r_wall? |
|---|---|---|---|
| Welder | ~10s channel | Wall → girder + 2x metal sheets (`dismantle_wall`) | No — r_wall needs its own 7-stage wirecutter→screwdriver→welder→wrench→welder→wirecutter→welder sequence |
| Jackhammer | Near-instant (single hit) | Same as welder (wall→girder) | Yes, but with a 50-tick `do_after` first |
| RCD deconstruct mode | 40-delay channel, 26 matter | Wall → plating **directly, no girder stage** (`ScrapeAway()`) | Only `canRturf=TRUE` variants (borg/combat RCD) — **plain starting RCD cannot breach r_walls** |
| Plasma cutter | Single use | Clears a girder → 2x metal (no wall option) | N/A (girder-stage only) |
| Mundane welder on plain girder | — | **Does not work** — welder-cutting is only wired up for cult/bronze girder subtypes | Flag: don't assume welder-on-girder always works |

## 4.3 Explosives
- **C4**: plant via `afterattack`+30-tick `do_after`, timer default 10s. **The C4-specific `prime()` override is dead/commented-out code** (`plastic.dm:211-227`, marked "did nothing but break shit") — C4 actually runs the *base* `plastic` grenade's `prime()`, which calls `target.ex_act(EXPLODE_HEAVY, target)` directly on the planted atom (full damage, no falloff) plus a weak area `explosion()` (`boom_sizes = list(0,0,3)`, light-only). Net effect: reliably destroys the directly-planted target even though its area blast is weak.
- **X4**: directional variant, `boom_sizes = list(0,2,5)` (heavy range 2), epicenter shifted one step past the target in aim direction — concentrates blast away from the user.
- **Frag/mini/IED grenades**: various `explosion()` severity profiles for area/anti-personnel use, not primarily breaching tools.
- **Explosion wall damage by severity** (`code/game/turfs/closed/walls.dm:90-109`): devastation ring → unconditional `ScrapeAway()`; heavy ring → 50% full dismantle (girder+sheets) else devastated-no-girder; light ring → `prob(hardness)` chance of dismantle (worth double-checking in-engine which direction "hardness" biases the prob() call).
- Acquisition path for C4/X4 (uplink price/category) **unverified in this pass**.

## 4.4 Mecha
- Basic drill: destroys normal walls (`do_after_mecha`, devastated removal, no girder). **Cannot** breach r_walls — refuses outright.
- Diamond-tipped drill (`DRILL_HARDENED`): required for r_walls, faster than basic.
- Mecha missile/ballistic weapons exist structurally; exact blast payload **unverified in this pass**.

---

# 5. Item Acquisition & Economy

*Full detail: `bot_ai_reference_items_economy.md`.*

## 5.1 Vending
- Purchase flow: ID→`registered_account`(bank)→price check/deduct→credit to vendor's `payment_department` budget (**free** if buyer's job department matches the vendor's payment department — e.g. bartenders get free drinks).
- Item spawns **on the floor in front of the machine**, not directly into hands.
- Hidden/contraband stock (`extended_inventory`) and premium (coin-locked) tiers exist; **emagging only sets the EMAGGED flag on the base class — whether it flips `extended_inventory` is per-vendor-subtype, not universal**. Verify per vendor type before assuming "emag = free contraband" everywhere.
- `/obj/machinery/vending/custom` (player-run shop) exists but its richer Topic()-based payment UI is dead/commented-out code — currently reuses the base vend logic.

## 5.2 Cargo / Supply
- Order via `/datum/supply_order` against the shared `ACCOUNT_CAR` budget (or a personal account if `self_paid`).
- Request-only consoles let non-cargo crew submit orders with a written reason for cargo staff to approve (`ui_act("approve"/"deny")`) — the closest thing to a structured social "trade" loop in the game.
- Hidden/contraband packs require the console to be emagged.
- Express console (bluespace drop-pod, instant single-item delivery) and cargo bounties (turn in requested items for budget) both confirmed present; exact UI verbs/bounty list **unverified in this pass**.
- Selling: export categories (`EXPORT_CARGO`/`EXPORT_CONTRABAND`/`EXPORT_EMAG`) determine what auto-sells for `ACCOUNT_CAR` credit on shuttle send.

## 5.3 Crafting
- Real system: **`code/datums/components/crafting/`** (not `code/modules/crafting/`, which doesn't exist) — `/datum/component/personal_crafting` attached to every mob.
- Recipe needs: `always_availible` or already `learned_recipes`; materials in reach (hand/adjacent turf/pockets); tools matched by type or `tool_behaviour`; `chem_catalysts` present (not consumed); custom `check_requirements()`.
- Flow: menu→pick recipe→`ui_act("make")`→`construct_item()`→`do_after(R.time)` (interruptible)→re-validate→`del_reqs()` consumes materials→spawns result into hand.
- Separate food-only "tablecraft" system at `code/modules/food_and_drinks/recipes/tablecraft/` (bread/burger/cake/pizza/etc.), triggered by combining ingredients rather than the crafting menu — exact trigger unverified in this pass.

## 5.4 Theft
- **No dedicated pickpocket/klepto skill-check system exists** (explicitly grepped and ruled out — don't import this assumption from general SS13 knowledge).
- Theft is composed of general mechanics: `show_inv()` strip-panel on an incapacitated/grabbed/unconscious target (works identically for live "pickpocketing" and dead "corpse looting" — no separate corpse loot table); forcing open lockers/secure crates (crowbar/tool/explosive depending on type; `secure/owned` cargo crates are keyed to a specific bank account and need that ID, an emag, or brute force).
- **Agent card** (`/obj/item/card/id/syndicate`) is the actual "ID forger": `attack_self()`→Forge sets display name/assignment text only (does **not** grant extra access — access is fixed at maintenance+syndicate); separately, its `afterattack()` on another ID **copies that ID's access list** onto itself — the real access-cloning theft vector, restricted to antag minds unless the card is `anyone`-unlocked.
- Chameleon disguise items (agent card auto-grants one; also standalone chameleon clothing/drone gear) change an item's displayed name/icon to mimic another type.

## 5.5 Trading / Social
- **No barter/trade datum exists.** Item exchange is base-engine hand-to-hand (drag/drop/give) with no HippieStation-specific file.
- PDA messaging (`send_message`/`receive_message` in `PDA.dm`) is the confirmed coordination substrate for arranging a trade — it doesn't move items itself.
- The cargo request-console reason-text flow (§5.2) is the closest thing to a "formal trade with a department" the game actually encodes.

---

# 6. Cross-Reference Index

Every action from §3–§5 in one place, grouped by the kind of goal it serves. Use this as the entry point; follow into the relevant section above for preconditions/steps/effects/source.

**Get past a locked door/area:**
present valid ID · cut WIRE_IDSCAN · pulse WIRE_OPEN · emag airlock · ghetto-crowbar unpowered door · strip security shielding layers · remote door control via wand · silicon bypass · AI hack locked-out airlock

**Open a secured container:**
present valid ID (togglelock) · emag secure closet · brute-force secure closet (≥20 dmg/hit) · EMP secure closet (probabilistic)

**Breach a wall/floor without authorization:**
thermite burn · ClF3 scrape/burn · weld through wall · jackhammer smash · RCD deconstruct · plasma cutter on girder · C4/X4 · frag/mini/IED grenades · mecha drill

**Acquire a specific item:**
buy from vending · buy from custom vendor · order via cargo console · order via express console · complete cargo bounty · craft from recipe · craft food item · disarm and strip · loot corpse/unconscious mob · loot locker/closet · steal objective's own logic (`/datum/objective/steal`)

**Gain access without being granted it:**
forge/clone access via agent card · reprogram ID at console · chameleon disguise · hack vending machine (contraband) · hack cargo console (contraband)

**Coordinate with other crew:**
request item via PDA message · request supplies via cargo request console · hand item to another player

**High-level round goals (antagonist):**
see full §2 table — assassinate, mutiny, maroon, debrain, protect(/object), hijack, block, purge, robot army, escape, survive, martyr, nuclear, steal(/five-of-type), download, capture, absorb(/most/changeling), destroy, custom, impersonate department/heads, contract

---

## Open Items (flagged across all four passes, for a future follow-up)
- Airlock electronics/board swap full sequence; windowdoor/unpowered-door emag bodies; camera-based door bypass (not found); nanite program specifics.
- Reagent-explosion (blackpowder/nitro/sorium) blast formulas; hippie's `chem_splash()` body vs. upstream; acid-vs-wall turf interaction; mecha missile payloads; `clusterbuster.dm`/`spawnergrenade.dm` contents.
- Cargo export sale values; express console UI verbs; bounty catalog contents.
- Tablecraft trigger mechanism; full disguisable-clothing catalog for chameleon items.
- Changeling and blood_contract antagonist-side wiring for the `absorb`/`contract` objective subtypes (mechanical datum verified, trigger file not opened).
