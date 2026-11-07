# Used by say_focus_check.dm through run.sh (SENDER=say_focus.ps1). Answers the say prompt the harness opens, after the wait in
# milliseconds it wrote into data/sf_prompt_<n>: types "hi" and Enter with messages posted straight to the prompt, so nothing
# lands anywhere else on the desktop. The game window needn't be in front for this (keys posted to its map while it's behind
# another program are let go of at once by BYOND, so held keys are driven through keyDown() by the harness instead).
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class SayPost {
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
	[DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
	[DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
	[DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
	[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
	[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
	[DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
	[DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr h, bool alt);
	[DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
	public static bool Front(IntPtr h) {
		SwitchToThisWindow(h, true);
		uint fg = GetWindowThreadProcessId(GetForegroundWindow(), IntPtr.Zero);
		uint me = GetCurrentThreadId();
		AttachThreadInput(me, fg, true);
		bool ok = SetForegroundWindow(h);
		AttachThreadInput(me, fg, false);
		return ok;
	}
	public static IntPtr FocusOf(IntPtr main) {
		GUITHREADINFO g = new GUITHREADINFO();
		g.cbSize = Marshal.SizeOf(g);
		uint t = GetWindowThreadProcessId(main, IntPtr.Zero);
		if (GetGUIThreadInfo(t, ref g) && g.hwndFocus != IntPtr.Zero) return g.hwndFocus;
		return main;
	}
	public static string Describe(IntPtr h) {
		StringBuilder c = new StringBuilder(256);
		GetClassName(h, c, 256);
		IntPtr root = GetAncestor(h, 2);
		StringBuilder t = new StringBuilder(256);
		GetWindowText(root, t, 256);
		return h.ToString() + " class " + c.ToString() + " in \"" + t.ToString() + "\"";
	}
	public static void Down(IntPtr h, uint vk) {
		uint scan = MapVirtualKey(vk, 0);
		PostMessage(h, 0x0100, (IntPtr)vk, (IntPtr)(1 | (scan << 16)));
	}
	public static void Up(IntPtr h, uint vk) {
		uint scan = MapVirtualKey(vk, 0);
		PostMessage(h, 0x0101, (IntPtr)vk, (IntPtr)(unchecked((int)0xC0000001) | (int)(scan << 16)));
	}
	public static void Press(IntPtr h, uint vk) {
		Down(h, vk);
		System.Threading.Thread.Sleep(90);
		Up(h, vk);
		System.Threading.Thread.Sleep(90);
	}
	public static void Char(IntPtr h, char ch) {
		PostMessage(h, 0x0102, (IntPtr)ch, (IntPtr)1);
		System.Threading.Thread.Sleep(60);
	}
}
"@
function Log($m) { Write-Output ("{0} {1}" -f (Get-Date -Format "HH:mm:ss.fff"), $m) }
$p = Get-Process dreamseeker -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Log "no DreamSeeker window"; exit 1 }
$main = $p.MainWindowHandle
foreach ($n in 1..1) {
	$deadline = (Get-Date).AddSeconds(40)
	while (-not (Test-Path "data/sf_prompt_$n") -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100 }
	if (-not (Test-Path "data/sf_prompt_$n")) { Log "${n}: no prompt asked for"; break }
	$wait = [int](Get-Content "data/sf_prompt_$n" -Raw).Trim()
	Start-Sleep -Milliseconds $wait
	$d = [SayPost]::FocusOf($main)
	Log ("${n}: prompt focus " + [SayPost]::Describe($d))
	[SayPost]::Char($d, 'h'); [SayPost]::Char($d, 'i')
	Start-Sleep -Milliseconds 200
	[SayPost]::Press($d, 0x0D)
	Start-Sleep -Milliseconds 800
	$after = [SayPost]::FocusOf($main)
	if ($after -eq $d) {
		Log "${n}: prompt still open after Enter: Escape"
		[SayPost]::Press($d, 0x1B)
	}
	"done" | Out-File -Encoding ascii "data/sf_answered_$n"
}
Start-Sleep -Milliseconds 4000
Log "sent"
