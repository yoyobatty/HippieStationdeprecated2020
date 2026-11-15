# One picture of a DreamSeeker's game window by PrintWindow (it needn't be on top): shot.ps1 <pid> <out.png>
# Used by tools/testkit/client_lane.py. A minimized window is shown first, without taking the keyboard.
param([int]$ClientPid, [string]$Out)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class TkShot {
	[StructLayout(LayoutKind.Sequential)]
	public struct RECT { public int l, t, r, b; }
	[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
	[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
	[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
	[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int how);
}
"@
$p = Get-Process -Id $ClientPid -ErrorAction SilentlyContinue
if (-not $p -or $p.MainWindowHandle -eq 0) { Write-Output "error: no window for pid $ClientPid"; exit 1 }
$h = $p.MainWindowHandle
if ([TkShot]::IsIconic($h)) {
	[TkShot]::ShowWindow($h, 4) | Out-Null
	Start-Sleep -Milliseconds 1500
}
$r = New-Object TkShot+RECT
[TkShot]::GetWindowRect($h, [ref]$r) | Out-Null
$bitmap = New-Object Drawing.Bitmap ($r.r - $r.l), ($r.b - $r.t)
$g = [Drawing.Graphics]::FromImage($bitmap)
$dc = $g.GetHdc()
$done = [TkShot]::PrintWindow($h, $dc, 2)
$g.ReleaseHdc($dc)
$g.Dispose()
$bitmap.Save($Out, [Drawing.Imaging.ImageFormat]::Png)
Write-Output "ok $($r.r - $r.l)x$($r.b - $r.t) printwindow=$done"
$bitmap.Dispose()
