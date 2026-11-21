#!/usr/bin/env python3
"""gpu_share.py - HippieStation runs share this PC with Last Light's sessions, whose timed runs (perf, budget) need a
quiet GPU and CPU. Last Light keeps a lock and a queue for that (its tools/gpulock.py: %TEMP%/lastlight_gpu.lock and
lastlight_gpu.queue); this uses the same files, so a Hippie boot waits for their timed run and a Hippie timed run
queues with theirs.

    python tools/gpu_share.py                    who holds the GPU, the queue, what Last Light runs now
    python tools/gpu_share.py wait WHAT          before booting dd/DreamSeeker, a testkit ss_start or a dm build:
                                                 returns once no Last Light timed run holds or has reserved the GPU
    python tools/gpu_share.py reserve NAME [min] before a Hippie timed run (lighting_bench, atmos_bench, ss_perf A/B):
    python tools/gpu_share.py release NAME       queue it like Last Light's own, then announce it by message

Untimed Hippie runs (screenshots, tests, debugging) may run alongside Last Light's untimed ones; they only wait on a
timed run. Never leave a testkit server or client up idle: a reserved timed run waits for the machine to go quiet, so
an idle dd.exe whose session waits here is a standoff. While waiting this prints STANDOFF lines naming the blockers
(devkit `dk.py gpu` shows the whole picture). If Last Light's tools can't be found, this says so and lets the run go (exit 0).
"""
import os
import sys

LAST_LIGHT = os.environ.get('LAST_LIGHT_ROOT', os.path.join(os.path.expanduser('~'), 'Downloads', 'Game Maker 6.1.REPACK',
                                                            'My Games', 'Last Light'))


def load():
    tools = os.path.join(LAST_LIGHT, 'tools')
    if not os.path.exists(os.path.join(tools, 'gpulock.py')):
        print('gpu_share: Last Light gpulock.py not found under %s (set LAST_LIGHT_ROOT); not waiting' % tools)
        return None
    sys.path.insert(0, tools)
    import gpulock
    return gpulock


def standoff_watch(gl, every=60):
    """While a wait runs: every minute, devkit's standoff check (a reserved timed run waiting on idle games or servers,
    maybe this project's own testkit servers). 2026-11-21: an idle testkit dd.exe held Last Light's r2up 20 min while
    four Hippie sessions waited on r2up. Prints who blocks whom; stops nothing. Without devkit it does nothing."""
    import threading
    done = threading.Event()
    devkit = os.environ.get('DEVKIT_ROOT', os.path.join(os.path.expanduser('~'), 'devkit'))

    def watch():
        while not done.wait(every):
            try:
                if devkit not in sys.path:
                    sys.path.insert(0, devkit)
                from devkit.tools import gpu
                for line in gpu.standoff_lines(gl):
                    print('gpu_share: ' + line, flush=True)
            except Exception:
                return

    threading.Thread(target=watch, daemon=True).start()
    return done


def main():
    gl = load()
    if gl is None:
        return 0
    args = sys.argv[1:]
    if not args:
        os.chdir(os.path.join(LAST_LIGHT, 'tools'))
        sys.argv = ['gpulock.py']
        return gl.main() if hasattr(gl, 'main') else os.system('python gpulock.py')
    cmd = args[0]
    if cmd == 'wait':
        stop = standoff_watch(gl)
        try:
            gl.wait('HippieStation: ' + (' '.join(args[1:]) or 'a run'))
        finally:
            stop.set()
        print('gpu_share: clear')
    elif cmd == 'reserve':
        gl.reserve('hippie-' + args[1], int(args[2]) if len(args) > 2 else 20)
    elif cmd == 'release':
        gl.release('hippie-' + args[1])
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main() or 0)
