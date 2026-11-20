"""Inclusive breakdown of procs under a root proc from a hippie_prof profiler.json (self/total per proc, no call tree, so a
callee's total is all its time from anywhere: read the share as an upper bound for the ones also called outside the root).
python tools/byond_audit/micro/step_breakdown.py data/logs/<round>/profiler.json [root] [names...]
"""
import json, sys

d = json.load(open(sys.argv[1]))
root = sys.argv[2] if len(sys.argv) > 2 else "/datum/bot_brain/proc/do_step_next_node"
names = sys.argv[3:] or ["bot_step_towards", "slip_on", "bot_link_blocked_strict", "real_move_blocker", "mind_the_footing",
    "beam_ahead", "grab_passing_tools", "swat_passing_mice", "close_airlock_behind", "movement_delay", "try_clear_obstruction",
    "weld_shut_behind", "incapacitated", "bot_log_verbose_line", "finish_pursuit", "repath", "bot_steps_into_pool", "yields_tile",
    "try_slip_trap", "set_glide_size", "make_way_through", "Move", "has_gravity", "schedule_step", "bot_turf_is_deadly",
    "bot_reachable_strict", "plan_clear_way", "cw_try", "cw_next", "cw_occupant", "bot_turf_has_pushoff_backup", "is_shut_in",
    "on_pursuit_finished", "advance_goal_step", "hippie_log_write", "get_num_legs", "has_status_effect", "IsParalyzed"]
by = {x["name"]: x for x in d}
base = by[root]["total"]
print(f"{root}: total {base:.3f} s, self {by[root]['self']:.3f} s")
rows = [x for x in d if any(x["name"].endswith("/" + n) for n in names)]
for x in sorted(rows, key=lambda x: -x["total"])[:50]:
    print(f"{100 * x['total'] / base:6.1f}%  total {x['total']:7.3f}  self {x['self']:7.3f}  {x['name']}")
