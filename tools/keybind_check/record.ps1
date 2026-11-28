# Films the game window for a harness: motion a screenshot can't show (a wobble, a judder, a glide that darts).
# Start it before tools/keybind_check/run.sh, in the background:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/keybind_check/record.ps1
# A harness asks for a clip by writing data/keycheck_record as "<name> <seconds> [x y w h]" and waits for
# data/keycheck_record_done. The clip is data/previews/<name>/frame_NNNN.png, a box of the game window (window pixels; default
# a strip of sky across the top of a maximized map pane, clear of the mob in the middle and the HUD), taken as fast as
# PrintWindow goes (about 20-40 a second), with each frame's time in ms in times.txt.
# PrintWindow, as shot.ps1: the window's own picture, so it needn't be on top. Never the desktop: a screen grab films whatever
# the player has open over the test client (2026-11-28, an ffmpeg gdigrab clip caught the desktop instead and was deleted).
# Stops when the harness writes data/keycheck_shots_done (one written after this started) or after 15 minutes.
# First used for the sky's wobble as a ghost flies (sky_shots.dm `walk`, 2026-11-28); tools/sky_gen/v2/sky_motion.py reads clips.

Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
public class RecWin {
	[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
	[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
	[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
	[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

	public static string Burst(IntPtr h, int x, int y, int w, int ht, double seconds, string dir) {
		RECT r;
		GetWindowRect(h, out r);
		int ww = r.Right - r.Left, wh = r.Bottom - r.Top;
		x = Math.Max(0, Math.Min(x, ww - 1)); y = Math.Max(0, Math.Min(y, wh - 1));
		w = Math.Min(w, ww - x); ht = Math.Min(ht, wh - y);
		var frames = new List<Bitmap>();
		var times = new List<double>();
		var sw = Stopwatch.StartNew();
		using (var full = new Bitmap(ww, wh, PixelFormat.Format32bppArgb)) {
			while (sw.Elapsed.TotalSeconds < seconds) {
				double t = sw.Elapsed.TotalMilliseconds;
				using (var g = Graphics.FromImage(full)) {
					IntPtr dc = g.GetHdc();
					PrintWindow(h, dc, 2);
					g.ReleaseHdc(dc);
				}
				frames.Add(full.Clone(new Rectangle(x, y, w, ht), PixelFormat.Format24bppRgb));
				times.Add(t);
			}
		}
		Directory.CreateDirectory(dir);
		foreach (var old in Directory.GetFiles(dir, "frame_*.png")) File.Delete(old);
		var lines = new List<string>();
		for (int i = 0; i < frames.Count; i++) {
			frames[i].Save(Path.Combine(dir, string.Format("frame_{0:D4}.png", i)), ImageFormat.Png);
			frames[i].Dispose();
			lines.Add(string.Format("{0} {1:F1}", i, times[i]));
		}
		File.WriteAllLines(Path.Combine(dir, "times.txt"), lines);
		return string.Format("{0} frames in {1:F1} s, box {2}x{3} at {4},{5} of a {6}x{7} window", frames.Count, seconds, w, ht, x, y, ww, wh);
	}
}
"@
[RecWin]::SetProcessDPIAware() | Out-Null

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$data = Join-Path $root "data"
$out = Join-Path $data "previews"

$started = Get-Date
$deadline = $started.AddMinutes(15)
# Only a done-file written after this started ends it: the last run's is still there until run.sh clears it
function Test-Done { $f = Get-Item "$data\keycheck_shots_done" -ErrorAction SilentlyContinue; return ($f -and $f.LastWriteTime -gt $started) }
while ((Get-Date) -lt $deadline -and -not (Test-Done)) {
	if (Test-Path "$data\keycheck_record") {
		$ask = ([IO.File]::ReadAllText("$data\keycheck_record")).Trim() -split '\s+'
		$name = $ask[0]
		$seconds = if ($ask.Count -gt 1) { [double]$ask[1] } else { 5 }
		$box = if ($ask.Count -gt 5) { @([int]$ask[2], [int]$ask[3], [int]$ask[4], [int]$ask[5]) } else { @(150, 100, 1400, 420) }
		$p = Get-Process dreamseeker -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
		if ($p) {
			$said = [RecWin]::Burst($p.MainWindowHandle, $box[0], $box[1], $box[2], $box[3], $seconds, (Join-Path $out $name))
			Write-Output "record.ps1: $name $said"
		} else {
			Write-Output "record.ps1: no DreamSeeker window for $name"
		}
		Remove-Item "$data\keycheck_record" -ErrorAction SilentlyContinue
		[IO.File]::WriteAllText("$data\keycheck_record_done", $name)
	}
	Start-Sleep -Milliseconds 100
}
