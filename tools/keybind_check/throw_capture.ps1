# For throw_shots.dm: grabs the game window's map as fast as it can while a phase runs, keeping each grab and its time, so the thrown
# thing's place in each picture can be found and its steps measured (tools/keybind_check/throw_read.py).
# data/throw_capture_go holds "phase,seconds"; it's deleted when the phase's grabs are done. data/keycheck_shots_done ends it.
# Used by run.sh as SENDER.
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ThrowShot {
	[StructLayout(LayoutKind.Sequential)]
	public struct RECT { public int l, t, r, b; }
	[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
	[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
}
"@
$data = Join-Path (Get-Location) "data"
New-Item -ItemType Directory -Force "$data\throw_capture" | Out-Null
Remove-Item "$data\throw_capture\*" -ErrorAction SilentlyContinue
$csv = "$data\throw_capture\grabs.csv"
"phase,n,ms" | Set-Content $csv
$p = $null
for ($i = 0; $i -lt 60 -and -not $p; $i++) {
	$p = Get-Process dreamseeker -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
	if (-not $p) { Start-Sleep -Milliseconds 500 }
}
if (-not $p) { exit 1 }
$h = $p.MainWindowHandle
$watch = [Diagnostics.Stopwatch]::StartNew()
$deadline = (Get-Date).AddMinutes(6)
while ((Get-Date) -lt $deadline -and -not (Test-Path "$data\keycheck_shots_done")) {
	if (Test-Path "$data\throw_capture_go") {
		Start-Sleep -Milliseconds 30
		$order = ([IO.File]::ReadAllText("$data\throw_capture_go")).Trim().Split(',')
		$phase = $order[0]
		$until = $watch.ElapsedMilliseconds + [double]$order[1] * 1000
		$r = New-Object ThrowShot+RECT
		[ThrowShot]::GetWindowRect($h, [ref]$r) | Out-Null
		$w = $r.r - $r.l; $ht = $r.b - $r.t
		$n = 0
		$lines = New-Object System.Collections.Generic.List[string]
		$frames = New-Object System.Collections.Generic.List[object]
		while ($watch.ElapsedMilliseconds -lt $until) {
			$bitmap = New-Object Drawing.Bitmap $w, $ht
			$g = [Drawing.Graphics]::FromImage($bitmap)
			$dc = $g.GetHdc()
			$before = $watch.ElapsedMilliseconds
			[ThrowShot]::PrintWindow($h, $dc, 2) | Out-Null
			$after = $watch.ElapsedMilliseconds
			$g.ReleaseHdc($dc)
			$g.Dispose()
			$frames.Add($bitmap)
			$lines.Add("$phase,$n,$([math]::Round(($before + $after) / 2))")
			$n++
		}
		# saved after, so saving doesn't slow the grabs
		for ($i = 0; $i -lt $frames.Count; $i++) {
			$frames[$i].Save("$data\throw_capture\$($phase)_$i.png", [Drawing.Imaging.ImageFormat]::Png)
			$frames[$i].Dispose()
		}
		$lines | Add-Content $csv
		Remove-Item "$data\throw_capture_go"
	}
	Start-Sleep -Milliseconds 30
}
