# Right-clicks for pile_menu_check.dm: real button messages posted to DreamSeeker's map (the desktop cursor stays put), each timed from
# the press to BYOND's menu window (#32768) coming up, then closed with Escape. Commands come one at a time in data/pm_cmd:
#   rclick <x> <y> <label> <ms to wait for the menu> [nomove]     quit
# A right-click answers with the wall clock ms of the press, then the menu's ms or "none".
# The map is found as mouseclick.ps1 finds it: each big child window is tried until the server hears a press from it.
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class PileMenu {
	[StructLayout(LayoutKind.Sequential)]
	public struct RECT { public int l, t, r, b; }
	public delegate bool EnumProc(IntPtr h, IntPtr p);
	[DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc f, IntPtr p);
	[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr p);
	[DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
	[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
	[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
	[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
	[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
	[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
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
	/// A visible popup menu window of that process, or zero
	public static IntPtr MenuOf(uint pid) {
		IntPtr found = IntPtr.Zero;
		EnumWindows(delegate(IntPtr h, IntPtr p) {
			uint owner;
			GetWindowThreadProcessId(h, out owner);
			if (owner == pid && IsWindowVisible(h) && ClassOf(h) == "#32768") { found = h; return false; }
			return true;
		}, IntPtr.Zero);
		return found;
	}
	/// How many items the menu has (MN_GETHMENU, then GetMenuItemCount)
	[DllImport("user32.dll")] public static extern int GetMenuItemCount(IntPtr menu);
	public static int ItemsOf(IntPtr menuWindow) {
		IntPtr menu = SendMessage(menuWindow, 0x01E1, IntPtr.Zero, IntPtr.Zero);
		return menu == IntPtr.Zero ? -1 : GetMenuItemCount(menu);
	}
	[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetMenuString(IntPtr menu, uint item, StringBuilder s, int n, uint flags);
	[DllImport("user32.dll")] public static extern IntPtr GetSubMenu(IntPtr menu, int pos);
	/// The first few entries, each with its submenu's entries in brackets
	public static string SampleOf(IntPtr menuWindow) {
		IntPtr menu = SendMessage(menuWindow, 0x01E1, IntPtr.Zero, IntPtr.Zero);
		if (menu == IntPtr.Zero) return "";
		var parts = new List<string>();
		int count = GetMenuItemCount(menu);
		for (int i = 0; i < count && i < 3; i++) {
			var s = new StringBuilder(256);
			GetMenuString(menu, (uint)i, s, 256, 0x400);
			string text = s.ToString();
			IntPtr sub = GetSubMenu(menu, i);
			if (sub != IntPtr.Zero) {
				var verbs = new List<string>();
				int subCount = GetMenuItemCount(sub);
				for (int j = 0; j < subCount; j++) {
					var v = new StringBuilder(256);
					GetMenuString(sub, (uint)j, v, 256, 0x400);
					verbs.Add(v.ToString());
				}
				text += " [" + string.Join(", ", verbs) + "]";
			}
			parts.Add(text);
		}
		return string.Join("; ", parts);
	}
	public static IntPtr Point(int x, int y) { return (IntPtr)(((y & 0xFFFF) << 16) | (x & 0xFFFF)); }
}
"@
$data = Join-Path (Get-Location) "data"
function Say($text) { [IO.File]::AppendAllText("$data\keycheck.txt", "$text`n") }
function Post($h, $message, $held, $x, $y) { [PileMenu]::PostMessage($h, [uint32]$message, [IntPtr]$held, [PileMenu]::Point($x, $y)) | Out-Null }

$p = Get-Process dreamseeker -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Say "no DreamSeeker window"; exit 1 }
$procId = [uint32]$p.Id
$lines = [IO.File]::ReadAllLines("$data\keycheck_mouse_steps")
$map = $lines[0].Split(" ")
$wide = [int]$map[1]
$high = [int]$map[2]
$probe = $lines[1].Split(" ")

$candidates = @()
foreach ($h in [PileMenu]::Children($p.MainWindowHandle)) {
	$r = New-Object PileMenu+RECT
	if (-not [PileMenu]::GetClientRect($h, [ref]$r) -or -not [PileMenu]::IsWindowVisible($h)) { continue }
	$class = [PileMenu]::ClassOf($h)
	$w = $r.r - $r.l
	$t = $r.b - $r.t
	if ($w -lt 100 -or $t -lt 100) { continue }
	$candidates += [pscustomobject]@{ Handle = $h; Class = $class; W = $w; H = $t; Exact = ($w -eq $wide -and $t -eq $high); Web = ($class -like "Chrome*" -or $class -like "Intermediate*") }
}
$candidates = $candidates | Sort-Object @{ Expression = "Exact"; Descending = $true }, Web, @{ Expression = { $_.W * $_.H }; Descending = $true }
$found = $null
foreach ($c in $candidates) {
	$x = [int]([int]$probe[1] * $c.W / $wide)
	$y = [int]([int]$probe[2] * $c.H / $high)
	Post $c.Handle 0x200 0 $x $y
	Start-Sleep -Milliseconds 60
	Post $c.Handle 0x201 1 $x $y
	Start-Sleep -Milliseconds 90
	Post $c.Handle 0x202 0 $x $y
	Start-Sleep -Milliseconds 900
	if (Test-Path "$data\keycheck_probe_ok") { $found = $c; break }
}
if (-not $found) { Say "no window took the click"; exit 1 }
$h = $found.Handle
$scaleX = $found.W / $wide
$scaleY = $found.H / $high

$idleSince = [Diagnostics.Stopwatch]::StartNew()
while ($true) {
	if (-not (Test-Path "$data\pm_cmd")) {
		if ($idleSince.Elapsed.TotalSeconds -gt 240 -or $p.HasExited) { Say "pile_menu.ps1: no command for 240 s, stopped"; break }
		Start-Sleep -Milliseconds 20
		continue
	}
	$cmd = ([IO.File]::ReadAllText("$data\pm_cmd")).Trim().Split(" ")
	Remove-Item "$data\pm_cmd"
	if ($cmd[0] -eq "quit") { [IO.File]::WriteAllText("$data\pm_cmd_done", "ok"); break }
	if ($cmd[0] -eq "rclick") {
		$x = [int]([int]$cmd[1] * $scaleX)
		$y = [int]([int]$cmd[2] * $scaleY)
		$wait = if ($cmd.Count -gt 4) { [int]$cmd[4] } else { 90000 }
		# "nomove": the server has set the hover itself. A posted move gets undone: BYOND works out what the mouse is over from
		# the real cursor too, and that's wherever the desktop's cursor is.
		if ($cmd.Count -le 5 -or $cmd[5] -ne "nomove") { Post $h 0x200 0 $x $y }
		Start-Sleep -Milliseconds 300 # the hover gets to the server first, as with a hand on the mouse
		$watch = [Diagnostics.Stopwatch]::StartNew()
		$pressedAt = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
		Post $h 0x204 2 $x $y
		Start-Sleep -Milliseconds 40
		Post $h 0x205 0 $x $y
		$menu = [IntPtr]::Zero
		while ($watch.Elapsed.TotalMilliseconds -lt $wait) {
			$menu = [PileMenu]::MenuOf($procId)
			if ($menu -ne [IntPtr]::Zero) { break }
			Start-Sleep -Milliseconds 2
		}
		$ms = [math]::Round($watch.Elapsed.TotalMilliseconds)
		$answer = "$pressedAt none"
		if ($menu -eq [IntPtr]::Zero) {
			Say "    right-click $($cmd[3]): no menu in $wait ms"
		} else {
			$answer = "$pressedAt $ms"
			Start-Sleep -Milliseconds 150
			$items = [PileMenu]::ItemsOf($menu)
			Say "    right-click $($cmd[3]): menu up in $ms ms, $items entries: $([PileMenu]::SampleOf($menu))"
			# Escape closes it; WM_CANCELMODE to the game window if it doesn't
			[PileMenu]::PostMessage($menu, 0x0100, [IntPtr]0x1B, [IntPtr]0x00010001) | Out-Null
			[PileMenu]::PostMessage($menu, 0x0101, [IntPtr]0x1B, [IntPtr]([int]0xC0010001)) | Out-Null
			$closing = [Diagnostics.Stopwatch]::StartNew()
			while ([PileMenu]::MenuOf($procId) -ne [IntPtr]::Zero -and $closing.Elapsed.TotalSeconds -lt 3) { Start-Sleep -Milliseconds 20 }
			if ([PileMenu]::MenuOf($procId) -ne [IntPtr]::Zero) {
				[PileMenu]::PostMessage($p.MainWindowHandle, 0x001F, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
				Start-Sleep -Milliseconds 300
				if ([PileMenu]::MenuOf($procId) -ne [IntPtr]::Zero) { Say "    (the menu wouldn't close)" }
			}
		}
	}
	[IO.File]::WriteAllText("$data\pm_cmd_done", $(if ($cmd[0] -eq "rclick") { $answer } else { "ok" }))
	$idleSince.Restart()
}
