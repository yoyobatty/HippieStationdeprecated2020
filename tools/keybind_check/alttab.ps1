# A real Alt-Tab, with real key events, and then the game window back. Only runs if the game has the foreground, so the keys can't
# land anywhere they'd do something. Alt on its own and Tab do nothing to any program that's switched to.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Fg {
	[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
	[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
	[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr p);
	[DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
	[DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
	[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
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
if (-not $p) { "no game window" | Out-File -Encoding ascii data/keycheck_alttab_done; exit 1 }
$before = [Fg]::GetForegroundWindow()
[Fg]::SwitchToThisWindow($p.MainWindowHandle, $true)
Start-Sleep -Milliseconds 500
if ([Fg]::GetForegroundWindow() -ne $p.MainWindowHandle) {
	"game wouldn't take the foreground, skipped" | Out-File -Encoding ascii data/keycheck_alttab_done
	exit 1
}
[Fg]::keybd_event(0x12, 0x38, 0, [UIntPtr]::Zero)      # Alt down
Start-Sleep -Milliseconds 500
[Fg]::keybd_event(0x09, 0x0F, 0, [UIntPtr]::Zero)      # Tab
Start-Sleep -Milliseconds 80
[Fg]::keybd_event(0x09, 0x0F, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 300
[Fg]::keybd_event(0x12, 0x38, 2, [UIntPtr]::Zero)      # Alt up, in whatever has the keyboard now
Start-Sleep -Milliseconds 800
$away = [Fg]::GetForegroundWindow() -ne $p.MainWindowHandle
"switched away: $away" | Out-File -Encoding ascii data/keycheck_alttab_done
for ($i = 0; $i -lt 60 -and -not (Test-Path data/keycheck_alttab_back); $i++) { Start-Sleep -Milliseconds 100 }
[void][Fg]::Give($p.MainWindowHandle)
