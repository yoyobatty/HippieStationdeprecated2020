"""Frame health from PresentMon captures of DreamSeeker (tools/light_sprites/run.sh writes data/lsp_frames_<label>_<phase>.csv).

The client's frame rate is fixed, so how fast it could go says little. What says whether a frame is healthy:
  busy    CPUBusy + GPU time it had to wait on: how much of the frame budget the client used. Headroom = 1 - busy/budget.
  CPU     CPUBusy: DreamSeeker's own work between presents (BYOND draws on the CPU side, then hands the GPU its batches)
  GPU     GPUBusy: how long the GPU was busy on the frame
  late    frames shown more than half a frame after they were due (FrameTime > 1.5 budget): hitches
  dropped frames never shown
Usage: python tools/light_sprites/frames.py <label> [budget_ms]   (budget defaults to the median frame time)
"""
import csv
import glob
import os
import statistics
import sys


def pct(values, p):
	if not values:
		return float("nan")
	values = sorted(values)
	k = (len(values) - 1) * p
	f = int(k)
	c = min(f + 1, len(values) - 1)
	return values[f] + (values[c] - values[f]) * (k - f)


def num(row, key):
	try:
		return float(row[key])
	except (KeyError, TypeError, ValueError):
		return None


def analyse(path, budget=None):
	rows = list(csv.DictReader(open(path, newline="")))
	# The map's swap chain: the one with the most presents (a popup could have its own)
	by_chain = {}
	for r in rows:
		by_chain.setdefault(r.get("SwapChainAddress"), []).append(r)
	if not by_chain:
		return None
	rows = max(by_chain.values(), key=len)
	frame = [v for v in (num(r, "FrameTime") for r in rows) if v is not None]
	cpu = [v for v in (num(r, "CPUBusy") for r in rows) if v is not None]
	gpu = [v for v in (num(r, "GPUBusy") for r in rows) if v is not None]
	dropped = sum(1 for r in rows if r.get("DisplayedTime") in ("NA", "", None) or num(r, "DisplayedTime") == 0)
	if not frame:
		return None
	budget = budget or statistics.median(frame)
	late = sum(1 for f in frame if f > budget * 1.5)
	return {
		"runtime": rows[0].get("PresentRuntime"),
		"mode": rows[0].get("PresentMode"),
		"frames": len(frame),
		"budget": budget,
		"frame_med": statistics.median(frame),
		"frame_p99": pct(frame, 0.99),
		"cpu_med": statistics.median(cpu) if cpu else float("nan"),
		"cpu_p95": pct(cpu, 0.95),
		"cpu_p99": pct(cpu, 0.99),
		"gpu_med": statistics.median(gpu) if gpu else float("nan"),
		"gpu_p95": pct(gpu, 0.95),
		"gpu_p99": pct(gpu, 0.99),
		"headroom_p95": 1 - pct(cpu, 0.95) / budget if cpu else float("nan"),
		"late": late,
		"dropped": dropped,
	}


def main():
	label = sys.argv[1] if len(sys.argv) > 1 else "bench"
	budget = float(sys.argv[2]) if len(sys.argv) > 2 else None
	files = sorted(glob.glob(f"data/lsp_frames_{label}_*.csv"), key=os.path.getmtime)
	if not files:
		print(f"no data/lsp_frames_{label}_*.csv")
		return
	cpu_per_s = {}
	cpu_file = f"data/lsp_cpu_{label}.txt"
	if os.path.exists(cpu_file):
		for line in open(cpu_file):
			parts = line.split()
			if len(parts) == 5:
				cpu_per_s[parts[0]] = (float(parts[2]) - float(parts[1])) / (float(parts[4]) - float(parts[3]))
	print(f"{'phase':<18}{'client CPU':>11}{'frames':>7}{'budget':>8}{'p99 frame':>10}{'CPU med':>9}{'p95':>7}{'p99':>7}{'GPU med':>9}{'p95':>7}{'p99':>7}{'headroom':>10}{'late':>6}{'drop':>6}")
	for path in files:
		phase = os.path.basename(path)[len(f"lsp_frames_{label}_"):-4]
		a = analyse(path, budget)
		if not a:
			print(f"{phase:<18} no frames")
			continue
		cpu = cpu_per_s.get(phase)
		cpu_text = f"{cpu / 10:.1f}%" if cpu is not None else "-"
		print(f"{phase:<18}{cpu_text:>11}{a['frames']:>7}{a['budget']:>8.1f}{a['frame_p99']:>10.1f}{a['cpu_med']:>9.2f}{a['cpu_p95']:>7.2f}{a['cpu_p99']:>7.2f}"
			f"{a['gpu_med']:>9.2f}{a['gpu_p95']:>7.2f}{a['gpu_p99']:>7.2f}{a['headroom_p95'] * 100:>9.0f}%{a['late']:>6}{a['dropped']:>6}")
	print("(client CPU: DreamSeeker's CPU time over the capture, % of one core)")
	print(f"(ms; runtime {a['runtime']}, {a['mode']}; headroom = 1 - CPU p95 / budget; late = frame time over 1.5 budgets)")


if __name__ == "__main__":
	main()
