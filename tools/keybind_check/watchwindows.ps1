# Every window DreamSeeker or its WebView2 puts up while a check runs, for tgui_bridge_check.dm: that's how the "open BYOND" prompt
# shows itself. Goes on until data/keycheck_shots_done turns up. Lines land in data/keycheck_windows.txt, and the first window that
# wasn't there at the start gets a picture of the screen in data/previews/.
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class WindowList {
	public delegate bool Each(IntPtr h, IntPtr l);
	[DllImport("user32.dll")] public static extern bool EnumWindows(Each f, IntPtr l);
	[DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, Each f, IntPtr l);
	[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
	[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
	[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
	[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
	[StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
	[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
	public static List<string> Visible() {
		var found = new List<string>();
		EnumWindows((h, l) => {
			if (!IsWindowVisible(h)) return true;
			uint pid; GetWindowThreadProcessId(h, out pid);
			var title = new StringBuilder(256); GetWindowText(h, title, 256);
			var cls = new StringBuilder(256); GetClassName(h, cls, 256);
			RECT r; GetWindowRect(h, out r);
			found.Add(pid + "|" + cls + "|" + title + "|" + (r.r - r.l) + "x" + (r.b - r.t));
			EnumChildWindows(h, (c, l2) => { // the prompt is drawn by the WebView, inside the window it came from
				if (!IsWindowVisible(c)) return true;
				var ct = new StringBuilder(256); GetWindowText(c, ct, 256);
				var cc = new StringBuilder(256); GetClassName(c, cc, 256);
				RECT cr; GetWindowRect(c, out cr);
				found.Add(pid + "|child " + cc + "|" + ct + "|" + (cr.r - cr.l) + "x" + (cr.b - cr.t));
				return true;
			}, IntPtr.Zero);
			return true;
		}, IntPtr.Zero);
		return found;
	}
}
"@
$data = Join-Path (Get-Location) "data"
New-Item -ItemType Directory -Force "$data\previews" | Out-Null
$out = "$data\keycheck_windows.txt"
$seen = @{}
$shot = 0
$label = if ($env:SHOT_LABEL) { $env:SHOT_LABEL } else { "tgui_prompt" }
$deadline = (Get-Date).AddMinutes(4)
$ticks = 0
while ((Get-Date) -lt $deadline -and -not (Test-Path "$data\keycheck_shots_done")) {
	$names = @{}
	Get-Process dreamseeker, msedgewebview2 -ErrorAction SilentlyContinue | ForEach-Object { $names[[string]$_.Id] = $_.ProcessName }
	foreach ($line in [WindowList]::Visible()) {
		$pid_text = $line.Split("|")[0]
		if (-not $names.ContainsKey($pid_text) -or $seen.ContainsKey($line)) { continue }
		$seen[$line] = $true
		$stamp = (Get-Date).ToString("HH:mm:ss.fff")
		[IO.File]::AppendAllText($out, "$stamp $($names[$pid_text]) $line`n")
		if ($names[$pid_text] -eq "msedgewebview2" -and $shot -lt 3) {
			$shot++
			Start-Sleep -Milliseconds 400
			$b = [Windows.Forms.Screen]::PrimaryScreen 2>$null
			$bounds = [System.Drawing.Rectangle]::new(0, 0, 2560, 1440)
			$bitmap = New-Object Drawing.Bitmap $bounds.Width, $bounds.Height
			$g = [Drawing.Graphics]::FromImage($bitmap)
			$g.CopyFromScreen(0, 0, 0, 0, $bitmap.Size)
			$g.Dispose()
			$bitmap.Save("$data\previews\$label`_$shot.png")
			$bitmap.Dispose()
		}
	}
	if (Test-Path "$data\keycheck_shot") { # a picture of the screen when the check asks for one, prompt or no prompt
		$name = ([IO.File]::ReadAllText("$data\keycheck_shot")).Trim()
		Remove-Item "$data\keycheck_shot"
		$bitmap = New-Object Drawing.Bitmap 2560, 1440
		$g = [Drawing.Graphics]::FromImage($bitmap)
		$g.CopyFromScreen(0, 0, 0, 0, $bitmap.Size)
		$g.Dispose()
		$bitmap.Save("$data\previews\$name.png")
		$bitmap.Dispose()
	}
	Start-Sleep -Milliseconds 120
}
