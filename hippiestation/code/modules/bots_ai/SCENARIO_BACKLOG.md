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

## 5. Combat (the plan's milestone 4)
**Code:** `foundation/meta_book.dm` (damage, threat, time to put somebody down; a fuel tank's blast reach), `apex/combat.dm` (kiting, choosing fights, the shove-then-hit melee).

| Scenario (`gym/scenarios_combat.dm`) | Must pass at | Status |
|---|---|---|
| combat: a robust bot with a laser keeps a swordsman coming at it at arm's length | mid and up | passing (before 0/3, after 3/3) |
| combat: an apex bot with bare hands gets out of a fight with a claymore, brave as it is | apex | passing (before 0/3, after 3/3) |
| combat: a hurt apex bot with a claymore stays in a fight with somebody unarmed | apex | passing (before 0/3, after 3/3) |
| combat: a hurt low-skill bot with a claymore runs as it always did | low | passing |
| combat: an apex bot in a gunfight steps across the line of fire, and takes fewer hits | apex | passing (hits 8 of 8 before, 1-5 after) |

Strafing is against a shooter who fires where they saw it a third of a second ago, as a player does: a bot shooter aims at where it is
now, and a laser lands almost at once, so no step dodges that.

The fuel tank tests (section 2) now shoot from past the blast as explosion realism has it: a small sealed room pushes the light blast out
further, and the casing's shards carry about ten tiles (`bot_tank_blast_reach()`). Before that, the bots were caught in it (0/2), after 3/3.

**The duel ladder** (`gym/scenarios_duels.dm`, `tools/bot_gym/apex_ladder.sh`): measures, never in the full suite. 2026-11-13, later
in the night (12 to 24 runs a pairing, so give or take ten points):
- a robust bot with a laser against a robust claymore wins 62% with the kite loop; an ordinary bot with the same laser 58% (it used to
  run from the claymore: a laser weighed as a club)
- apex against ordinary, a toolbox each: 75%; ordinary against ordinary: 33%
- a laser each: the gunfight pairings mostly measure who stops first ("they've had enough"), not aim

**Still to cover:**
- breaking line of sight, stun chains into cuffs, healing out of sight
- group play: focus fire, flanks, holding a chokepoint

## 6. The crew-kill planner (the plan's milestone 5)
**Code:** `apex/kill_planner.dm`. The user's ruling, 2026-11-13: the strike may be anything, maxcaps included.

| Scenario (`gym/scenarios_kill_plan.dm`) | Must pass at | Status |
|---|---|---|
| kill plan: an apex traitor out to kill everybody opens with a plasma fire where the people are, not a swing at one of them | apex | passing (before 0/3, after 3/3) |
| kill plan: a traitor below apex out to kill everybody goes straight for them, as it always did | below apex | passing |

Bot Shift, every traitor on the rampage plan, 12 shifts each: deaths 46 before, 78 after (37 to air and fire).

**Still to cover:**
- the other phases: gear (armory raid, R&D weapons), blinding (the AI, cameras, telecomms, power), denying escape
- a maxcap or superboom for a rampager whose job isn't Science or Chemistry (the acts are tied to the job that makes them)

## 7. Defenders (the plan's milestone 6)
**Code:** `apex/defenders.dm` (stopping it), `apex/survivors.dm` (surviving it). The user's ruling, 2026-11-13: both, full depth.

| Scenario (`gym/scenarios_defenders.dm`) | Must pass at | Status |
|---|---|---|
| defence: somebody walks into the Bar carrying a tank bomb on a timer, and the crew calls it out and gets away | anybody | passing (before 0/2, after 2/2) |
| defence: a scientist's tank bomb in the lab is nobody's business | anybody | passing |
| defence: an officer sees somebody carrying a tank bomb into the Bar, puts it on the record and goes for them | Security | passing (before 0/2, after 2/2) |
| defence: a crewman sees somebody dragging a plasma canister into the Bar and calls it in | apex always, mid usually, low sometimes | passing (before 0/2, after 2/2) |
| defence: an officer sees somebody dragging a plasma canister into the Bar and goes to stop them | Security, as above | passing (before 0/2, after 2/2) |
| defence: three bodies with the same killer's name on them, a robust officer books them for Murder | Security, mid and up | passing |
| security: three of the crew dead and the killer loose, an apex Head of Security orders the armory open | apex heads | passing (before 0/1, after 1/1) |
| survive: alone with a killer in sight, a timid crewman shuts itself in a locker, and comes out once they're cuffed | timid crew | passing (before 0/2, after 2/2) |
| survive: a brave crewman in the same room doesn't hide | brave crew | passing |
| survive: a brave, robust crewman with nothing to fight with picks up a toolbox while a killer's about | brave, mid and up | passing |

The two older armory scenarios ("at red alert with a nanosuit loose...", "a nanosuit loose a minute and no red alert...", station-wide,
not in the suite) had been timing out at the officer arming up: the suspect stood in its sight, and `dangerous_suspect_in_sight()` held it
back, as it should. The suspect is shut in out of sight now, and all three pass.

**Still to cover:**
- guarding what the kill planner goes for (the toxins lab while a bomb's made, the crowd rooms)
- lockdowns and the AI bolting a killer in
- vigilantes ambushing together rather than one at a time
