# Pictures of the game window for nano_hud_check.dm: PrintWindow, so it doesn't need to be on top. Each name that turns up in
# data/keycheck_shot becomes data/previews/<name>.png; data/keycheck_shots_done ends it. Used by run.sh.
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WindowShot {
	[StructLayout(LayoutKind.Sequential)]
	public struct RECT { public int l, t, r, b; }
	[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
	[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
	[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
	[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int how);
}
"@
$data = Join-Path (Get-Location) "data"
New-Item -ItemType Directory -Force "$data\previews" | Out-Null

function Say($text) { [IO.File]::AppendAllText("$data\keycheck.txt", "$text`n") }

$p = Get-Process dreamseeker -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Say "no DreamSeeker window"; exit 1 }
$h = $p.MainWindowHandle
$deadline = (Get-Date).AddMinutes(3)
while ((Get-Date) -lt $deadline -and -not (Test-Path "$data\keycheck_shots_done")) {
	if (Test-Path "$data\keycheck_shot") {
		Start-Sleep -Milliseconds 100
		$name = ([IO.File]::ReadAllText("$data\keycheck_shot")).Trim()
		if ([WindowShot]::IsIconic($h)) { # a minimized window is a 160 x 28 picture of nothing
			[WindowShot]::ShowWindow($h, 4) | Out-Null # shown, not given the keyboard
			Start-Sleep -Milliseconds 1500
		}
		$r = New-Object WindowShot+RECT
		[WindowShot]::GetWindowRect($h, [ref]$r) | Out-Null
		$bitmap = New-Object Drawing.Bitmap ($r.r - $r.l), ($r.b - $r.t)
		$g = [Drawing.Graphics]::FromImage($bitmap)
		$dc = $g.GetHdc()
		$done = [WindowShot]::PrintWindow($h, $dc, 2)
		$g.ReleaseHdc($dc)
		$g.Dispose()
		$bitmap.Save("$data\previews\$name.png", [Drawing.Imaging.ImageFormat]::Png)
		$bitmap.Dispose()
		Say "picture $name ($($r.r - $r.l) x $($r.b - $r.t)), PrintWindow $done"
		Remove-Item "$data\keycheck_shot"
	}
	Start-Sleep -Milliseconds 100
}
