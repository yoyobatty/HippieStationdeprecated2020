# Plays data/keycheck_mouse_steps: real mouse messages posted straight to DreamSeeker's map, so the desktop's own cursor stays where it is
# and nothing else on the screen can get them. Used by run.sh with mouse_check.dm.
# Finds the map by trying each big child window until the server hears a press from it.
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class MousePost {
	[StructLayout(LayoutKind.Sequential)]
	public struct RECT { public int l, t, r, b; }
	public delegate bool EnumProc(IntPtr h, IntPtr p);
	[DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc f, IntPtr p);
	[DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
	[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
	[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
	[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
	public static List<IntPtr> Children(IntPtr main) {
		var found = new List<IntPtr>();
		EnumChildWindows(main, delegate(IntPtr h, IntPtr p) { found.Add(h); return true; }, IntPtr.Zero);
		return found;
	}
	public static string ClassOf(IntPtr h) {
		var s = new StringBuilder(256);
		GetClassName(h, s, 256);
		return s.ToString();
	}
	public static IntPtr Point(int x, int y) { return (IntPtr)(((y & 0xFFFF) << 16) | (x & 0xFFFF)); }
}
"@
$WM_MOUSEMOVE = 0x200
$down = @{ left = 0x201; right = 0x204; middle = 0x207 }
$up = @{ left = 0x202; right = 0x205; middle = 0x208 }
$flag = @{ left = 1; right = 2; middle = 0x10 }
$data = Join-Path (Get-Location) "data"

function Say($text) { [IO.File]::AppendAllText("$data\keycheck.txt", "$text`n") }
function Post($h, $message, $held, $x, $y) { [MousePost]::PostMessage($h, [uint32]$message, [IntPtr]$held, [MousePost]::Point($x, $y)) | Out-Null }

$p = Get-Process dreamseeker -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Say "no DreamSeeker window"; exit 1 }
$lines = [IO.File]::ReadAllLines("$data\keycheck_mouse_steps")
$map = $lines[0].Split(" ")
$wide = [int]$map[1]
$high = [int]$map[2]
$probe = $lines[1].Split(" ")

$candidates = @()
foreach ($h in [MousePost]::Children($p.MainWindowHandle)) {
	$r = New-Object MousePost+RECT
	if (-not [MousePost]::GetClientRect($h, [ref]$r) -or -not [MousePost]::IsWindowVisible($h)) { continue }
	$class = [MousePost]::ClassOf($h)
	$w = $r.r - $r.l
	$t = $r.b - $r.t
	if ($w -lt 100 -or $t -lt 100) { continue }
	$exact = ($w -eq $wide -and $t -eq $high)
	$candidates += [pscustomobject]@{ Handle = $h; Class = $class; W = $w; H = $t; Exact = $exact; Web = ($class -like "Chrome*" -or $class -like "Intermediate*") }
}
$candidates = $candidates | Sort-Object @{ Expression = "Exact"; Descending = $true }, Web, @{ Expression = { $_.W * $_.H }; Descending = $true }
Say "$($candidates.Count) big child windows, map wanted at $wide x $high"

$found = $null
foreach ($c in $candidates) {
	$scaleX = $c.W / $wide
	$scaleY = $c.H / $high
	$x = [int]([int]$probe[1] * $scaleX)
	$y = [int]([int]$probe[2] * $scaleY)
	Post $c.Handle $WM_MOUSEMOVE 0 $x $y
	Start-Sleep -Milliseconds 60
	Post $c.Handle $down.left 1 $x $y
	Start-Sleep -Milliseconds 90
	Post $c.Handle $up.left 0 $x $y
	Start-Sleep -Milliseconds 900
	Say "tried $($c.Class) $($c.W)x$($c.H): $(if (Test-Path "$data\keycheck_probe_ok") { 'the server heard it' } else { 'nothing' })"
	if (Test-Path "$data\keycheck_probe_ok") { $found = $c; break }
}
if (-not $found) { Say "no window took the click"; exit 1 }

$h = $found.Handle
$scaleX = $found.W / $wide
$scaleY = $found.H / $high
foreach ($line in ($lines | Select-Object -Skip 2)) {
	$s = $line.Split(" ")
	switch ($s[0]) {
		"phase" { [IO.File]::WriteAllText("$data\keycheck_phase", $line.Substring(6)) }
		"wait" { Start-Sleep -Milliseconds ([int]$s[1]) }
		"move" { Post $h $WM_MOUSEMOVE 0 ([int]([int]$s[1] * $scaleX)) ([int]([int]$s[2] * $scaleY)) }
		"down" { Post $h $down[$s[1]] $flag[$s[1]] ([int]([int]$s[2] * $scaleX)) ([int]([int]$s[3] * $scaleY)) }
		"up" { Post $h $up[$s[1]] 0 ([int]([int]$s[2] * $scaleX)) ([int]([int]$s[3] * $scaleY)) }
		"drag" { Post $h $WM_MOUSEMOVE $flag[$s[1]] ([int]([int]$s[2] * $scaleX)) ([int]([int]$s[3] * $scaleY)) }
	}
}
