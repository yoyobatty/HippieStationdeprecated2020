# Posts K, Ctrl+K and J straight to the DreamSeeker window for macro_probe.dm (see there).
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class KeyPost {
	[StructLayout(LayoutKind.Sequential)]
	public struct RECT { public int l, t, r, b; }
	[StructLayout(LayoutKind.Sequential)]
	public struct GUITHREADINFO {
		public int cbSize, flags;
		public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret;
		public RECT rcCaret;
	}
	[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
	[DllImport("user32.dll")] public static extern uint MapVirtualKey(uint c, uint t);
	[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr p);
	[DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint t, ref GUITHREADINFO g);
	public static IntPtr FocusOf(IntPtr main) {
		GUITHREADINFO g = new GUITHREADINFO();
		g.cbSize = Marshal.SizeOf(g);
		uint t = GetWindowThreadProcessId(main, IntPtr.Zero);
		if (GetGUIThreadInfo(t, ref g) && g.hwndFocus != IntPtr.Zero) return g.hwndFocus;
		return main;
	}
	public static void Down(IntPtr h, uint vk) {
		uint scan = MapVirtualKey(vk, 0);
		PostMessage(h, 0x0100, (IntPtr)vk, (IntPtr)(1 | (scan << 16)));
		System.Threading.Thread.Sleep(90);
	}
	public static void Up(IntPtr h, uint vk) {
		uint scan = MapVirtualKey(vk, 0);
		PostMessage(h, 0x0101, (IntPtr)vk, (IntPtr)(unchecked((int)0xC0000001) | (int)(scan << 16)));
		System.Threading.Thread.Sleep(90);
	}
}
"@
$p = Get-Process dreamseeker -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Write-Output "no DreamSeeker window"; exit 1 }
$h = [KeyPost]::FocusOf($p.MainWindowHandle)
Write-Output "posting to window $h of process $($p.Id)"
[KeyPost]::Down($h, 0x4B); [KeyPost]::Up($h, 0x4B)          # K
Start-Sleep -Milliseconds 300
[KeyPost]::Down($h, 0x11); [KeyPost]::Down($h, 0x4B); [KeyPost]::Up($h, 0x4B); [KeyPost]::Up($h, 0x11)   # Ctrl+K
Start-Sleep -Milliseconds 300
[KeyPost]::Down($h, 0x4A); [KeyPost]::Up($h, 0x4A)          # J
