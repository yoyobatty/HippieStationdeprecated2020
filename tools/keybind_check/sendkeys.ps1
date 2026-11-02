# Posts real key messages straight to the DreamSeeker window, so they can't land in anything else on the desktop.
# Used by run.sh: what the harness then sees in keyDown() is BYOND's own name for each key.
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
	public static void Press(IntPtr h, uint vk) {
		uint scan = MapVirtualKey(vk, 0);
		PostMessage(h, 0x0100, (IntPtr)vk, (IntPtr)(1 | (scan << 16)));
		System.Threading.Thread.Sleep(90);
		PostMessage(h, 0x0101, (IntPtr)vk, (IntPtr)(unchecked((int)0xC0000001) | (int)(scan << 16)));
		System.Threading.Thread.Sleep(90);
	}
}
"@
$p = Get-Process dreamseeker -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Write-Output "no DreamSeeker window"; exit 1 }
$h = [KeyPost]::FocusOf($p.MainWindowHandle)
Write-Output "posting to window $h of process $($p.Id)"
# In order: W, 1, the punctuation row, the numpad with its operators, then the named keys.
$keys = 0x57, 0x31, 0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0, 0xDB, 0xDC, 0xDD, 0xDE, 0x60, 0x65, 0x6A, 0x6B, 0x6D, 0x6E, 0x6F, 0x0D, 0x08, 0x09, 0x20, 0x25, 0x26, 0x27, 0x28, 0x24, 0x23, 0x21, 0x22, 0x2D, 0x2E, 0x70, 0x13, 0x5D
foreach ($k in $keys) { [KeyPost]::Press($h, [uint32]$k) }
