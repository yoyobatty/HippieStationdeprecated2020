# For trip_clock.dm: grabs the game window as fast as it can while a phase runs, keeping a strip of the map with the clock marker
# and the time of each grab, so how old each frame on the screen was can be worked out (tools/keybind_check/clock_read.py).
# data/trip_clock_go holds "phase,seconds"; it's deleted when the phase's grabs are done. data/keycheck_shots_done ends it.
# Also runs shot.ps1 alongside for ordinary pictures. Used by run.sh as SENDER.
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ClockShot {
	[StructLayout(LayoutKind.Sequential)]
	public struct RECT { public int l, t, r, b; }
	[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
	[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
}
"@
$data = Join-Path (Get-Location) "data"
New-Item -ItemType Directory -Force "$data\clock" | Out-Null
Remove-Item "$data\clock\*" -ErrorAction SilentlyContinue
$csv = "$data\clock\grabs.csv"
"phase,n,ms" | Set-Content $csv
$shooter = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\shot.ps1`"" -PassThru -WindowStyle Hidden
$p = Get-Process dreamseeker -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { exit 1 }
$h = $p.MainWindowHandle
$watch = [Diagnostics.Stopwatch]::StartNew()
$deadline = (Get-Date).AddMinutes(8)
while ((Get-Date) -lt $deadline -and -not (Test-Path "$data\keycheck_shots_done")) {
	if (Test-Path "$data\trip_clock_go") {
		Start-Sleep -Milliseconds 50
		$order = ([IO.File]::ReadAllText("$data\trip_clock_go")).Trim().Split(',')
		$phase = $order[0]
		$until = $watch.ElapsedMilliseconds + [int]$order[1] * 1000
		$r = New-Object ClockShot+RECT
		[ClockShot]::GetWindowRect($h, [ref]$r) | Out-Null
		$w = $r.r - $r.l; $ht = $r.b - $r.t
		$n = 0
		$lines = New-Object System.Collections.Generic.List[string]
		while ($watch.ElapsedMilliseconds -lt $until) {
			$bitmap = New-Object Drawing.Bitmap $w, $ht
			$g = [Drawing.Graphics]::FromImage($bitmap)
			$dc = $g.GetHdc()
			$before = $watch.ElapsedMilliseconds
			[ClockShot]::PrintWindow($h, $dc, 2) | Out-Null
			$after = $watch.ElapsedMilliseconds
			$g.ReleaseHdc($dc)
			$g.Dispose()
			# the map's third row up from the bottom, where the marker runs
			$strip = $bitmap.Clone((New-Object Drawing.Rectangle 8, (31 + 1369 - 3 * 92), 1369, 92), $bitmap.PixelFormat)
			$strip.Save("$data\clock\$($phase)_$n.png", [Drawing.Imaging.ImageFormat]::Png)
			$strip.Dispose()
			$bitmap.Dispose()
			$lines.Add("$phase,$n,$([math]::Round(($before + $after) / 2))")
			$n++
		}
		$lines | Add-Content $csv
		Remove-Item "$data\trip_clock_go"
	}
	Start-Sleep -Milliseconds 50
}
$shooter.WaitForExit(20000) | Out-Null
