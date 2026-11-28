#!/usr/bin/env python3
"""gpu_load.py - puts a known load on this PC's graphics card for a while, to reproduce what a game client draws when
something else (a Last Light run, a benchmark) is working the card hard. Two kinds of load, separately or together:

  --vram GB      holds that much of the card's memory (CUDA allocations), so the client's textures and render surfaces
                 compete for what's left
  --busy         keeps the card's compute busy with back-to-back matrix products (utilisation near 100%)

    python tools/gpu_load/gpu_load.py --seconds 300 --vram 7 --busy
    python tools/gpu_load/gpu_load.py --seconds 120 --vram 8          memory only
    python tools/gpu_load/gpu_load.py --seconds 120 --busy            compute only

It reserves the shared GPU queue first (tools/gpu_share.py reserve, so Last Light's timed runs wait instead of being
spoilt) and releases it when done or interrupted. Prints the card's memory and utilisation (nvidia-smi) once it's
loaded. Needs torch with CUDA. Stops by itself after --seconds; Ctrl+C, or creating the --stop-file, stops it sooner and
still releases the queue. Don't kill it from a script (Git Bash `kill`, taskkill /F): that skips the release, and the
reservation then holds Last Light's timed runs until it times out (python tools/gpu_share.py release gpu_load clears it).

First used 2026-11-28 to test whether a loaded card made two sky_shots.dm `layers` runs draw a rainbow smear over the map:
with 7 GB held and the card 100% busy the sky drew right, so load wasn't it (tools/sky_gen/v2/notes/README.md).
"""
import argparse
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SHARE = os.path.join(HERE, '..', 'gpu_share.py')


def smi():
    try:
        out = subprocess.run(['nvidia-smi', '--query-gpu=memory.used,memory.total,utilization.gpu', '--format=csv,noheader'],
                             capture_output=True, text=True, timeout=10).stdout.strip()
        return out
    except Exception as e:  # the load still runs without the report
        return 'nvidia-smi unavailable: %r' % e


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--seconds', type=float, default=120)
    ap.add_argument('--vram', type=float, default=0, help='GB of card memory to hold')
    ap.add_argument('--busy', action='store_true', help='keep the card computing')
    ap.add_argument('--name', default='gpu_load', help='name in the shared GPU queue')
    ap.add_argument('--stop-file', help='stop as soon as this file exists (a script running alongside creates it when done)')
    ap.add_argument('--no-reserve', action='store_true', help="don't take the shared GPU queue (only if nothing timed can run)")
    args = ap.parse_args()
    if not args.vram and not args.busy:
        ap.error('nothing to load: give --vram GB and/or --busy')

    import torch
    if not torch.cuda.is_available():
        sys.exit('gpu_load: torch has no CUDA device')

    reserved = False
    if not args.no_reserve:
        minutes = max(1, int(args.seconds / 60 + 1))
        subprocess.run([sys.executable, SHARE, 'reserve', args.name, str(minutes)])
        reserved = True
    held = []
    try:
        if args.vram:
            chunk = 256 * 1024 * 1024  # bytes per allocation
            for _ in range(int(args.vram * 1024 ** 3 / chunk)):
                held.append(torch.empty(chunk, dtype=torch.uint8, device='cuda').fill_(1))
        a = b = None
        if args.busy:
            a = torch.randn(4096, 4096, device='cuda')
            b = torch.randn(4096, 4096, device='cuda')
        torch.cuda.synchronize()
        print('gpu_load: holding %.1f GB, busy %s, for %.0f s; card now: %s' % (
            len(held) * 0.25, args.busy, args.seconds, smi()), flush=True)
        end = time.time() + args.seconds
        reported = False
        while time.time() < end:
            if args.stop_file and os.path.exists(args.stop_file):
                print('gpu_load: stop file found', flush=True)
                break
            if args.busy:
                for _ in range(20):
                    a = torch.mm(a, b) * 1e-3
                torch.cuda.synchronize()
                if not reported and time.time() > end - args.seconds + 5:
                    print('gpu_load: under load: %s' % smi(), flush=True)
                    reported = True
            else:
                time.sleep(0.5)
    except KeyboardInterrupt:
        print('gpu_load: stopped early', flush=True)
    finally:
        held.clear()
        torch.cuda.empty_cache()
        if reserved:
            subprocess.run([sys.executable, SHARE, 'release', args.name])
        print('gpu_load: done; card now: %s' % smi(), flush=True)


if __name__ == '__main__':
    main()
