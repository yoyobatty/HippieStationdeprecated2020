# Key presses, typing and pictures for kb_panel_check.dm: it writes one command to data/kp_cmd, this does it and answers in
# data/kp_ack. "key <hex vk>" presses a key in whatever has DreamSeeker's keyboard, "type <text>" types it there and presses Enter
# (Escape after, if a prompt is still open). Pictures go through shot.ps1, run alongside.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$shots = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$here\shot.ps1`"" -NoNewWindow -PassThru -WorkingDirectory (Get-Location)
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class KpPost {
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
	[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
	[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
	[DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
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
		StringBuilder t = new StringBuilder(256);
		GetWindowText(GetAncestor(h, 2), t, 256);
		return "class " + c.ToString() + " in \"" + t.ToString() + "\"";
	}
	public static void Press(IntPtr h, uint vk) {
		uint scan = MapVirtualKey(vk, 0);
		PostMessage(h, 0x0100, (IntPtr)vk, (IntPtr)(1 | (scan << 16)));
		System.Threading.Thread.Sleep(90);
		PostMessage(h, 0x0101, (IntPtr)vk, (IntPtr)(unchecked((int)0xC0000001) | (int)(scan << 16)));
		System.Threading.Thread.Sleep(90);
	}
	public static void Char(IntPtr h, char ch) {
		PostMessage(h, 0x0102, (IntPtr)ch, (IntPtr)1);
		System.Threading.Thread.Sleep(60);
	}
}
"@
$data = Join-Path (Get-Location) "data"
$p = Get-Process dreamseeker -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { "no DreamSeeker window" | Out-File -Encoding ascii "$data\kp_ack"; exit 1 }
$main = $p.MainWindowHandle
$deadline = (Get-Date).AddMinutes(4)
while ((Get-Date) -lt $deadline -and -not (Test-Path "$data\keycheck_shots_done")) {
	if (Test-Path "$data\kp_cmd") {
		Start-Sleep -Milliseconds 50
		$cmd = ([IO.File]::ReadAllText("$data\kp_cmd")).Trim()
		Remove-Item "$data\kp_cmd"
		$answer = ""
		if ($cmd -like "key *") {
			$vk = [Convert]::ToUInt32($cmd.Substring(4), 16)
			$d = [KpPost]::FocusOf($main)
			[KpPost]::Press($d, $vk)
			$answer = "pressed $($cmd.Substring(4)) into " + [KpPost]::Describe($d)
		} elseif ($cmd -like "type *") {
			Start-Sleep -Milliseconds 900
			$d = [KpPost]::FocusOf($main)
			$answer = "typing into " + [KpPost]::Describe($d)
			foreach ($ch in $cmd.Substring(5).ToCharArray()) { [KpPost]::Char($d, $ch) }
			Start-Sleep -Milliseconds 200
			[KpPost]::Press($d, 0x0D)
			Start-Sleep -Milliseconds 800
			if ([KpPost]::FocusOf($main) -eq $d -and ([KpPost]::Describe($d) -notlike "*Static*")) {
				[KpPost]::Press($d, 0x1B)
				$answer += ", still open after Enter: Escape"
			}
		}
		$answer | Out-File -Encoding ascii "$data\kp_ack"
	}
	Start-Sleep -Milliseconds 50
}
$shots.WaitForExit(5000) | Out-Null
