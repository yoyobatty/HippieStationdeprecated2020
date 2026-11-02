# Takes the keyboard away from the game the way Alt-Tab does, without touching any other program: the taskbar gets it for a few
# seconds, then the game window has it back. No keys are sent, so nothing can land anywhere else.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Fg {
	[DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string n);
	[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
	[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
	[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr p);
	[DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
	[DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
	[DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr h, bool alt);
	public static bool Give(IntPtr h) {
		uint fg = GetWindowThreadProcessId(GetForegroundWindow(), IntPtr.Zero);
		uint me = GetCurrentThreadId();
		AttachThreadInput(me, fg, true);
		bool ok = SetForegroundWindow(h);
		AttachThreadInput(me, fg, false);
		return ok;
	}
}
"@
$p = Get-Process dreamseeker -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
# The game has to have had the keyboard to lose it: a window that never did goes on saying it's focused.
[Fg]::SwitchToThisWindow($p.MainWindowHandle, $true)
Start-Sleep -Milliseconds 500
$had = [Fg]::GetForegroundWindow() -eq $p.MainWindowHandle
$tray = [Fg]::FindWindow("Shell_TrayWnd", $null)
$ok = [Fg]::Give($tray)
Write-Output "game had the keyboard: $had, given to the taskbar: $ok, game has it now: $([Fg]::GetForegroundWindow() -eq $p.MainWindowHandle)"
$(if ($had) { "had it" } else { "never" }) | Out-File -Encoding ascii data/keycheck_focus_gone
for ($i = 0; $i -lt 100 -and -not (Test-Path data/keycheck_focus_back); $i++) { Start-Sleep -Milliseconds 100 }
if ($p) { [void][Fg]::Give($p.MainWindowHandle) }
