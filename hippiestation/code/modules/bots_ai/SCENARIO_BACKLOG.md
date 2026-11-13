# Scenario backlog

Situations the user has described for the clever-bots work. Each one becomes a Bot Gym test that bots must pass. The plan is in the user's notes; the skill dial is in `foundation/skill.dm`.

Every milestone ends with the whole backlog run and this file updated.

**Skill levels:**
- **low:** below 0.6, most of the crew
- **mid:** 0.6 and up, robust players and powergamers
- **apex:** 0.9 and up, antagonists by default

**Status values:** todo, failing, passing.

**Running it:** `NOCOMPILE=1 tools/bot_gym/run_bot_gym.sh "<scenario name>" 3`

## 1. Two movable structures in a maintenance corridor
**The user, 2026-11-13:** "A scenario bots might find themselves in is a maint pathway with 2 moveable structures that get them stuck."

**Why it failed:**
- No route went through a closed locker, canister or tank, so a lawful errand ended in "no path".
- Pushing the first structure into the second jams it.

**Code:** `foundation/clear_way.dm`, `foundation/movables.dm`.

| Scenario (`gym/scenarios_clear_way.dm`) | Must pass at | Status |
|---|---|---|
| climbs two crates in a one-wide corridor | low and up | passing (before 0/2, after 2/2) |
| opens two lockers in a corridor and walks through | low and up | passing (before 0/2, after 2/2) |
| pulls a locked locker back out of the way and pushes the other along | mid and up | passing (before 0/2, after 2/2) |
| gets a canister and a fuel tank out of a corridor | mid and up | passing (before 0/2, after 2/2) |
| low skill: can't see a way past two locked lockers, says so | low | passing (before 0/2, after 2/2) |

**Still to cover:**
- a dead end where the only way out is back
- a welded locker cut apart with a welder (apex)

**Related (from the plan, not a user case):** escape rooms in `gym/scenarios_escape.dm`, code in `foundation/escape.dm`.

| Scenario | Must pass at | Status |
|---|---|---|
| escape: apex, shut in behind a window, breaks out | apex | passing (before 0/2, after 2/2) |
| escape: mid skill, shut in behind a window, leaves it alone | mid | passing |
| escape: apex on its everyday work doesn't break out | apex | passing |
| escape: apex officer after a minor charge behind a window leaves the window alone | apex | passing (before 0/2, after 2/2) |
| escape: apex officer after a murderer behind a window goes through it | apex | passing |
| a lawful walk doesn't climb a desk when nothing movable is in the way (`scenarios_clear_way.dm`) | all | passing (before 0/2, after 2/2) |
| escape room: cuffed, it gets them off and goes | apex | passing (already did) |
| escape room: a bola round its legs, it gets it off and goes | apex | passing (already did) |
| escape room: bolted in, it hacks the bolts up with the tools to hand | apex | passing (already did) |
| escape room: cuffed to a chair, it gets free and goes | apex | passing (already did) |
| escape room: zipped in a body bag, it gets out and goes | apex | passing (already did) |
| escape room: walled in, it cuts through the wall with the tools to hand | apex | passing (before 0/2, after 2/2) |

## 2. The fuel tank
**The user, 2026-11-13:** "A fuel tank, dragging it, pushing it into a player, backing off and shooting it, dealing an easy stunning blow."

**Mechanics:**
- `fueltank/bullet_act()` only goes off for a BRUTE or BURN shot: lasers and bullets, not disablers or tasers.
- The blast is `explosion(0, 1, 5, flame_range = 5)`.

**Code:** `foundation/tactics.dm`, `foundation/threat_read.dm`.

| Scenario (`gym/scenarios_tactics.dm`) | Must pass at | Status |
|---|---|---|
| tactics: an apex killer drags a fuel tank to its mark, backs off and shoots it | apex | passing (before 0/2, after 2/2) |
| tactics: a robust crewman in a fight shoots the fuel tank the killer is stood beside | mid and up | passing (before 0/2, after 2/2) |
| tactics: a low-skill crewman in the same fight doesn't think of the tank | low | passing |
| tactics: a robust crewman doesn't set off a tank with somebody else beside it | mid | passing |
| threat: stood by a fuel tank, a gunman across the room, it gets away from the tank | apex always, mid usually, low sometimes | passing (before 0/2, after 3/3) |
| threat: the one it's fighting drags a fuel tank up to it, it gets clear | apex always, mid usually, low sometimes | passing (before 0/2, after 2/2) |

| tactics: an apex killer parks a fuel tank at the only way out of its mark's room and waits | apex | passing (before 0/2, after 2/2) |
| tactics: a robust officer after an armed murderer stood by a fuel tank shoots the tank | mid and up | passing (before 0/2, after 2/2) |

**Still to cover:**
- parking a tank on a runner's predicted route (needs milestone 3's route prediction)

## 3. More tactics and threats (the plan's milestone 2, not a user case)
| Scenario (`gym/scenarios_tactics.dm`) | Must pass at | Status |
|---|---|---|
| tactics: run into a room from a killer, a robust bot drags a locker across the door | mid and up | passing (before 0/2, after 2/2) |
| threat: a gunman across the room and nothing to shoot back with, it gets into cover | apex always, mid usually | passing (before 0/2, after 2/2) |
| upkeep: an engineer cuts open a door welded in the round | engineers | passing (the user's ruling, 2026-11-13) |
| upkeep: an engineer leaves a door that was welded when the round began | engineers | passing |
| tactics: running from a killer through a door, a robust bot welds it shut behind it | mid and up | passing (before 0/2, after 2/2) |
| tactics: a low-skill bot running through a door doesn't weld it | low | passing |
| threat: a plasma canister let go in the room, it gets out before the air goes | apex always, mid usually, low sometimes | passing (before 0/2, after 2/2) |

## 4. Hide and seek (the plan's milestone 3)
**Code:** `foundation/hunt.dm` (the search, every hunter), `apex/director.dm` (clues for apex hunters).

| Scenario (`gym/scenarios_hunt.dm`) | Must pass at | Status |
|---|---|---|
| hunt: an officer loses a murderer and searches the lockers till it finds him | mid and up | passing (before 0/2, after 2/2) |
| hunt: a low-skill officer opens a couple of lockers and gives up | low | passing |
| hunt: an apex officer, steered by the director, finds a murderer hidden across the room | apex | passing (before 0/2, after 2/2) |
| hunt: a robust officer with no director searches where he was seen, not across the room | mid | passing |
| hunt: a vigilante at a murderer's last sighting finds nobody, and searches the lockers | mid | passing (before 0/2, after 2/2) |
| hunt: an apex killer that's never seen its mark goes by the director's word | apex | passing (before 0/2, after 2/2) |
| hunt: a killer with nothing to go on doesn't walk straight to its mark | mid | passing (before 0/2, after 2/2) |
| hunt: a robust officer runs at where somebody running across in front of it will be | mid and up | passing (the decision, asked straight out) |
| hunt: somebody running straight away from an officer is just followed | mid | passing |
| hunt: a low-skill officer just follows somebody running across in front of it | low | passing |

**Still to cover:**
- cutting a runner off at a chokepoint they'll pass through further on (the tactical map's chokepoints)
- an evader that moves like the user does (from player telemetry)
