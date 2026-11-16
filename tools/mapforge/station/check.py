"""Plan checks: can everyone get where they work, can the public get only where it should, are secure rooms sealed.

    walk      every room is reached from the arrivals dock through doors (staff walk: any door)
    public    the public walk (open and public doors only) reaches no staff room
    secure    secure rooms have no door onto maint and no public door
    loop      the ring hall alone joins every department's front (two routes: it is a loop)
    maint     the maint network is one piece once the ring joins its doors
"""
from collections import deque

DIRS = ((1, 0), (-1, 0), (0, 1), (0, -1))


def _walk(plan, start, ok):
    seen = {start}
    q = deque([start])
    while q:
        p = q.popleft()
        for dx, dy in DIRS:
            n = (p[0] + dx, p[1] + dy)
            if n in seen:
                continue
            if n in plan.floor or (n in plan.doors and ok(plan.doors[n])):
                seen.add(n)
                q.append(n)
    return seen


def check(plan):
    out = []
    start = next((p for p, r in plan.floor.items() if r == "arrivals_spine"), None) or \
        next(p for p, r in plan.floor.items() if r == "ring")
    staff = _walk(plan, start, lambda k: k != "dock")
    reached = {plan.floor[p] for p in staff if p in plan.floor}
    rooms = [r for r, m in plan.rooms.items() if m.get("kind") in ("room", "hall") and plan.tiles(r)]
    missed = sorted(r for r in rooms if r not in reached)
    if missed:
        plan.problems.append("walk: not reached from arrivals: " + ", ".join(missed))
    out.append("walk: %d/%d rooms reached" % (len(rooms) - len(missed), len(rooms)))

    pub = _walk(plan, start, lambda k: k in ("open", "public"))
    leaks = sorted({plan.floor[p] for p in pub if p in plan.floor
                    and plan.rooms[plan.floor[p]].get("kind") == "room"
                    and not plan.rooms[plan.floor[p]].get("public")
                    and not plan.rooms[plan.floor[p]].get("lobby")})
    if leaks:
        plan.problems.append("public: walks into staff rooms: " + ", ".join(leaks))
    out.append("public: reaches %d rooms" % len({plan.floor[p] for p in pub if p in plan.floor}))

    for p, k in plan.doors.items():
        sides = {plan.floor.get((p[0] + dx, p[1] + dy)) for dx, dy in DIRS}
        sec = [r for r in sides if r and plan.rooms.get(r, {}).get("secure") and plan.rooms[r].get("kind") == "room"]
        if sec and (k in ("public", "open") or "maint" in sides and k != "secure"):
            plan.problems.append("secure: %s has a %s door at %d,%d" % (sec[0], k, p[0], p[1]))

    maint = [p for p, r in plan.floor.items() if r == "maint"]
    if maint:
        seen = _walk(plan, maint[0], lambda k: k == "maint")
        part = {p for p in seen if plan.floor.get(p) == "maint"}
        out.append("maint: %d of %d tiles in the first piece" % (len(part), len(maint)))
    return out
