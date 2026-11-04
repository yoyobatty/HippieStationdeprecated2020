# Pictures of the game window for nano_hud_check.dm: PrintWindow, so it doesn't need to be on top. Each name that turns up in
# data/keycheck_shot becomes data/previews/<name>.png; data/keycheck_shots_done ends it. Used by run.sh.
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WindowShot {
	[StructLayout(LayoutKind.Sequential)]
	public struct RECT { public int l, t, r, b; }
	[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
	[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
	[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
	[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int how);
	[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
	public delegate bool EnumProc(IntPtr h, IntPtr p);
	[DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc f, IntPtr p);
	[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
	[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr p);
	[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
	[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
	[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
	// A popup of this DreamSeeker: its own picture, whatever's on top of it on the desktop. The biggest, or the one with this title
	// (a closed tgui window can stay about blank, the same size as the new one).
	public static IntPtr FindPopup(int pid, IntPtr main, string title) {
		IntPtr found = IntPtr.Zero; int area = 0;
		EnumWindows(delegate(IntPtr h, IntPtr p) {
			uint owner; GetWindowThreadProcessId(h, out owner);
			RECT r; GetWindowRect(h, out r);
			int w = r.r - r.l, ht = r.b - r.t;
			if (owner != pid || h == main || !IsWindowVisible(h) || w <= 300 || w >= 1400 || ht <= 300) return true;
			if (title != "") {
				var s = new System.Text.StringBuilder(256); GetWindowText(h, s, 256);
				if (!string.Equals(s.ToString().Trim(), title, StringComparison.OrdinalIgnoreCase)) return true;
			}
			if (w * ht > area) { area = w * ht; found = h; }
			return true;
		}, IntPtr.Zero);
		return found;
	}
	// The map is the biggest "Static" child (posted mouse messages only register on that one).
	public static IntPtr FindMap(IntPtr main) {
		IntPtr best = IntPtr.Zero; int area = 0;
		EnumChildWindows(main, delegate(IntPtr h, IntPtr p) {
			var s = new System.Text.StringBuilder(64); GetClassName(h, s, 64);
			RECT r; GetWindowRect(h, out r);
			int a = (r.r - r.l) * (r.b - r.t);
			if (s.ToString() == "Static" && a > area) { area = a; best = h; }
			return true;
		}, IntPtr.Zero);
		return best;
	}
}
"@
$data = Join-Path (Get-Location) "data"
New-Item -ItemType Directory -Force "$data\previews" | Out-Null

function Say($text) { [IO.File]::AppendAllText("$data\keycheck.txt", "$text`n") }

$p = Get-Process dreamseeker -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Say "no DreamSeeker window"; exit 1 }
$h = $p.MainWindowHandle
$deadline = (Get-Date).AddMinutes(3)
while ((Get-Date) -lt $deadline -and -not (Test-Path "$data\keycheck_shots_done")) {
	if (Test-Path "$data\keycheck_hover") { # window_check.dm: the mouse over the map, a few places, nothing global
		Remove-Item "$data\keycheck_hover"
		$map = [WindowShot]::FindMap($h)
		foreach ($spot in @(@(400, 300), @(420, 320), @(300, 450), @(320, 470))) {
			$lp = [IntPtr](($spot[1] -shl 16) -bor $spot[0])
			[WindowShot]::PostMessage($map, 0x200, [IntPtr]::Zero, $lp) | Out-Null
			Start-Sleep -Milliseconds 300
		}
	}
	if (Test-Path "$data\keycheck_shot") {
		Start-Sleep -Milliseconds 100
		$name = ([IO.File]::ReadAllText("$data\keycheck_shot")).Trim()
		if ([WindowShot]::IsIconic($h)) { # a minimized window is a 160 x 28 picture of nothing
			[WindowShot]::ShowWindow($h, 4) | Out-Null # shown, not given the keyboard
			Start-Sleep -Milliseconds 1500
		}
		$r = New-Object WindowShot+RECT
		[WindowShot]::GetWindowRect($h, [ref]$r) | Out-Null
		if ($name -like "screen_*") { # a popup: the screen, it being on top
			$shot = New-Object Drawing.Bitmap 2560, 1440
			$g = [Drawing.Graphics]::FromImage($shot)
			$g.CopyFromScreen(0, 0, 0, 0, $shot.Size)
			$g.Dispose()
			$shot.Save("$data\previews\$name.png", [Drawing.Imaging.ImageFormat]::Png)
			$shot.Dispose()
			Remove-Item "$data\keycheck_shot"
			continue
		}
		$shoot = $h
		if ($name -like "popup_*") {
			$title = ""
			if (Test-Path "$data\keycheck_shot_title") { $title = ([IO.File]::ReadAllText("$data\keycheck_shot_title")).Trim() }
			$shoot = [WindowShot]::FindPopup($p.Id, $h, $title)
			if ($shoot -eq [IntPtr]::Zero) { $shoot = [WindowShot]::FindPopup($p.Id, $h, "") } # nothing by that title: the biggest
			[WindowShot]::GetWindowRect($shoot, [ref]$r) | Out-Null
		}
		# A web page window that hasn't painted yet comes back pure white: wait and take it again, a few times
		for ($try = 0; $try -lt 4; $try++) {
			$bitmap = New-Object Drawing.Bitmap ($r.r - $r.l), ($r.b - $r.t)
			$g = [Drawing.Graphics]::FromImage($bitmap)
			$dc = $g.GetHdc()
			$done = [WindowShot]::PrintWindow($shoot, $dc, 2)
			$g.ReleaseHdc($dc)
			$g.Dispose()
			$white = $true
			foreach ($fx in @(0.2, 0.4, 0.5, 0.6, 0.8)) {
				foreach ($fy in @(0.2, 0.5, 0.8)) {
					$px = $bitmap.GetPixel([int]($bitmap.Width * $fx), [int]($bitmap.Height * $fy))
					if ($px.R -lt 250 -or $px.G -lt 250 -or $px.B -lt 250) { $white = $false }
				}
			}
			if (-not $white) { break }
			$bitmap.Dispose()
			Start-Sleep -Milliseconds 700
		}
		$bitmap.Save("$data\previews\$name.png", [Drawing.Imaging.ImageFormat]::Png)
		$bitmap.Dispose()
		Say "picture $name ($($r.r - $r.l) x $($r.b - $r.t)), PrintWindow $done"
		Remove-Item "$data\keycheck_shot"
	}
	Start-Sleep -Milliseconds 100
}
