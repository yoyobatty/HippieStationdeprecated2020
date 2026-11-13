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

**Still to cover:**
- an apex traitor parks a tank at a chokepoint on the target's route and waits
- a tank pushed at the bot: apex shoots it first
- Security using the set-up against a lethal target
