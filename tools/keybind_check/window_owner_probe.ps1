# For tgui_pool_zorder.dm: how Windows treats DreamSeeker's popups. For each title given: its owner (the game window or none),
# whether it has a taskbar button, and whether it's still above the game window after the game window is brought to the front.
# "close:<title>" posts WM_CLOSE to that window instead, as its title bar's X would. Writes data/window_owner_probe.txt.
param([string]$Titles)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class OwnerProbe {
	public delegate bool EnumProc(IntPtr h, IntPtr p);
	[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr p);
	[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
	[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
	[DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
	[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int index);
	[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
	[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
	[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
	public static IntPtr Find(int pid, string title) {
		IntPtr found = IntPtr.Zero;
		EnumWindows(delegate(IntPtr h, IntPtr p) {
			uint owner; GetWindowThreadProcessId(h, out owner);
			if (owner != pid) return true;
			var s = new System.Text.StringBuilder(256); GetWindowText(h, s, 256);
			if (string.Equals(s.ToString().Trim(), title, StringComparison.OrdinalIgnoreCase)) { found = h; return false; }
			return true;
		}, IntPtr.Zero);
		return found;
	}
	// Is a above b in the z-order?
	public static bool Above(IntPtr a, IntPtr b) {
		for (IntPtr h = GetWindow(a, 2); h != IntPtr.Zero; h = GetWindow(h, 2)) { if (h == b) return true; } // GW_HWNDNEXT
		return false;
	}
}
"@
$data = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "data"
$out = Join-Path $data "window_owner_probe.txt"
$p = Get-Process dreamseeker -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { "no dreamseeker" | Set-Content -Encoding utf8 $out; exit }
$main = $p.MainWindowHandle
$lines = @()
foreach ($title in $Titles.Split('|')) {
	if ($title.StartsWith("close:")) {
		$name = $title.Substring(6)
		$h = [OwnerProbe]::Find($p.Id, $name)
		if ($h -eq [IntPtr]::Zero) { $lines += "$name : not found" } else { [OwnerProbe]::PostMessage($h, 0x10, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null; $lines += "$name : WM_CLOSE sent" }
		continue
	}
	$h = [OwnerProbe]::Find($p.Id, $title)
	if ($h -eq [IntPtr]::Zero) { $lines += "$title : not found"; continue }
	$owner = [OwnerProbe]::GetWindow($h, 4) # GW_OWNER
	$ex = [OwnerProbe]::GetWindowLong($h, -20) # GWL_EXSTYLE
	$taskbar = (($ex -band 0x40000) -ne 0) -or ($owner -eq [IntPtr]::Zero -and ($ex -band 0x80) -eq 0)
	[OwnerProbe]::SetForegroundWindow($main) | Out-Null
	Start-Sleep -Milliseconds 300
	$above = [OwnerProbe]::Above($h, $main)
	$lines += "$title : owner $(if ($owner -eq $main) { 'game window' } elseif ($owner -eq [IntPtr]::Zero) { 'none' } else { 'other ' + $owner }), taskbar button $taskbar, above the game window after it's brought to the front $above, visible $([OwnerProbe]::IsWindowVisible($h))"
}
$lines | Set-Content -Encoding utf8 $out
