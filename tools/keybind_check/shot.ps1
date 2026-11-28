# Pictures of the game window for nano_hud_check.dm: PrintWindow, so it doesn't need to be on top. Each name that turns up in
# data/keycheck_shot becomes data/previews/<name>.png; data/keycheck_shots_done ends it. Used by run.sh.
# Names: popup_* is a popup alone, screen_* the whole screen, desk_* the game window with its popups where they sit on it.
# data/keycheck_rects asks where the map, the game window and a popup really are (data/keycheck_rects_out).
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
			if (owner != pid || h == main || !IsWindowVisible(h)) return true;
			// Untitled, only window-sized ones (the PA console's is 230 high). tgui windows have no caption, so they're found this
			// way; a title only picks out the old HTML windows
			if (title == "" && (w <= 300 || w >= 1400 || ht <= 150)) return true;
			var size = System.Text.RegularExpressions.Regex.Match(title, @"^(\d+)x(\d+)$"); // "WxH": the popup of about that size (DPI may scale it)
			if (size.Success) {
				double sw = double.Parse(size.Groups[1].Value), sh = double.Parse(size.Groups[2].Value);
				double ratio = w / sw, scale = Math.Round(ratio * 4) / 4; // display scaling comes in 25% steps
				if (scale < 1 || Math.Abs(ratio - scale) > 0.02 || Math.Abs(ht / sh - scale) > 0.02) return true;
				found = h; return false;
			}
			if (title != "" && title != "*") { // "*": any popup, any size
				var s = new System.Text.StringBuilder(256); GetWindowText(h, s, 256);
				if (!string.Equals(s.ToString().Trim(), title, StringComparison.OrdinalIgnoreCase)) return true;
			}
			if (w * ht > area) { area = w * ht; found = h; }
			return true;
		}, IntPtr.Zero);
		return found;
	}
	// Every visible popup of this DreamSeeker as "title" WxH, for when a title isn't found
	public static string ListPopups(int pid, IntPtr main) {
		var list = new System.Text.StringBuilder();
		EnumWindows(delegate(IntPtr h, IntPtr p) {
			uint owner; GetWindowThreadProcessId(h, out owner);
			if (owner != pid || h == main || !IsWindowVisible(h)) return true;
			RECT r; GetWindowRect(h, out r);
			var s = new System.Text.StringBuilder(256); GetWindowText(h, s, 256);
			list.Append(" \"" + s.ToString() + "\" " + (r.r - r.l) + "x" + (r.b - r.t) + ";");
			return true;
		}, IntPtr.Zero);
		return list.ToString();
	}
	// Every visible popup of this DreamSeeker, the one on top first
	public static IntPtr[] Popups(int pid, IntPtr main) {
		var list = new System.Collections.Generic.List<IntPtr>();
		EnumWindows(delegate(IntPtr h, IntPtr p) {
			uint owner; GetWindowThreadProcessId(h, out owner);
			if (owner == pid && h != main && IsWindowVisible(h)) list.Add(h);
			return true;
		}, IntPtr.Zero);
		return list.ToArray();
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
	// A web window's page: the child the browser draws into (posted mouse moves there light :hover)
	public static IntPtr FindChild(IntPtr parent, string cls) {
		IntPtr found = IntPtr.Zero;
		EnumChildWindows(parent, delegate(IntPtr h, IntPtr p) {
			var s = new System.Text.StringBuilder(64); GetClassName(h, s, 64);
			if (s.ToString() == cls) { found = h; return false; }
			return true;
		}, IntPtr.Zero);
		return found;
	}
}
"@
$data = Join-Path (Get-Location) "data"
New-Item -ItemType Directory -Force "$data\previews" | Out-Null

function Say($text) { [IO.File]::AppendAllText("$data\keycheck.txt", "$text`n") }

$p = Get-Process dreamseeker -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Say "no DreamSeeker window"; exit 1 }
$h = $p.MainWindowHandle
$deadline = (Get-Date).AddMinutes($(if ($env:SHOT_MINUTES) { [int]$env:SHOT_MINUTES } else { 3 }))
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
	if (Test-Path "$data\keycheck_hover_popup") { # "fx,fy": the mouse over the biggest popup's page at that fraction of its size
		$spot = ([IO.File]::ReadAllText("$data\keycheck_hover_popup")).Trim().Split(',')
		Remove-Item "$data\keycheck_hover_popup"
		$popup = [WindowShot]::FindPopup($p.Id, $h, "")
		$page = [WindowShot]::FindChild($popup, "Chrome_RenderWidgetHostHWND")
		if ($page -eq [IntPtr]::Zero) { Say "hover: no page in the popup" } else {
			$pr = New-Object WindowShot+RECT
			[WindowShot]::GetWindowRect($page, [ref]$pr) | Out-Null
			$x = [int](($pr.r - $pr.l) * [double]$spot[0]); $y = [int](($pr.b - $pr.t) * [double]$spot[1])
			[WindowShot]::PostMessage($page, 0x200, [IntPtr]::Zero, [IntPtr](($y -shl 16) -bor $x)) | Out-Null
			Say "hover: page at $x,$y"
		}
	}
	if (Test-Path "$data\keycheck_rects") { # where the windows really are, from Windows, not BYOND: the map's own window, the game
		# window and the popup of that "WxH" (or the biggest), as "name left top right bottom" lines in data/keycheck_rects_out
		$want = ([IO.File]::ReadAllText("$data\keycheck_rects")).Trim()
		Remove-Item "$data\keycheck_rects"
		$out = New-Object System.Text.StringBuilder
		$rr = New-Object WindowShot+RECT
		[WindowShot]::GetWindowRect([WindowShot]::FindMap($h), [ref]$rr) | Out-Null
		[void]$out.AppendLine("map $($rr.l) $($rr.t) $($rr.r) $($rr.b)")
		[WindowShot]::GetWindowRect($h, [ref]$rr) | Out-Null
		[void]$out.AppendLine("main $($rr.l) $($rr.t) $($rr.r) $($rr.b)")
		$popup = [WindowShot]::FindPopup($p.Id, $h, $want)
		if ($popup -eq [IntPtr]::Zero -and $want -ne "") { $popup = [WindowShot]::FindPopup($p.Id, $h, "") } # a title bar makes it taller
		if ($popup -eq [IntPtr]::Zero) { $popup = [WindowShot]::FindPopup($p.Id, $h, "*") }
		if ($popup -eq [IntPtr]::Zero) { [void]$out.AppendLine("popup none") } else {
			[WindowShot]::GetWindowRect($popup, [ref]$rr) | Out-Null
			[void]$out.AppendLine("popup $($rr.l) $($rr.t) $($rr.r) $($rr.b)")
		}
		[IO.File]::WriteAllText("$data\keycheck_rects_out.tmp", $out.ToString())
		Move-Item -Force "$data\keycheck_rects_out.tmp" "$data\keycheck_rects_out"
	}
	if (Test-Path "$data\keycheck_shot") {
		Start-Sleep -Milliseconds 100
		$name = ([IO.File]::ReadAllText("$data\keycheck_shot")).Trim()
		if ($name -like "desk_*") { # the game window with its popups where they are on the screen, each taken with PrintWindow, so
			# whatever else is on the desktop doesn't get in the picture
			$r = New-Object WindowShot+RECT
			[WindowShot]::GetWindowRect($h, [ref]$r) | Out-Null
			$shot = New-Object Drawing.Bitmap ($r.r - $r.l), ($r.b - $r.t)
			$g = [Drawing.Graphics]::FromImage($shot)
			$layers = New-Object System.Collections.ArrayList
			[void]$layers.Add($h)
			$tops = [WindowShot]::Popups($p.Id, $h)
			for ($i = $tops.Length - 1; $i -ge 0; $i--) { [void]$layers.Add($tops[$i]) } # top first: drawn last
			foreach ($layer in $layers) {
				$lr = New-Object WindowShot+RECT
				[WindowShot]::GetWindowRect($layer, [ref]$lr) | Out-Null
				if ($lr.r -le $lr.l -or $lr.b -le $lr.t) { continue }
				$part = New-Object Drawing.Bitmap ($lr.r - $lr.l), ($lr.b - $lr.t)
				$pg = [Drawing.Graphics]::FromImage($part)
				$dc = $pg.GetHdc()
				[WindowShot]::PrintWindow($layer, $dc, 2) | Out-Null
				$pg.ReleaseHdc($dc)
				$pg.Dispose()
				$g.DrawImage($part, $lr.l - $r.l, $lr.t - $r.t)
				$part.Dispose()
			}
			$g.Dispose()
			$shot.Save("$data\previews\$name.png", [Drawing.Imaging.ImageFormat]::Png)
			$shot.Dispose()
			Say "picture $name ($($r.r - $r.l) x $($r.b - $r.t), $($layers.Count - 1) popups)"
			Remove-Item "$data\keycheck_shot"
			continue
		}
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
			if ($shoot -eq [IntPtr]::Zero -and $title -ne "") { Say "no popup titled '$title' (516 gives the old windows no caption); popups:$([WindowShot]::ListPopups($p.Id, $h))" }
			if ($shoot -eq [IntPtr]::Zero) { $shoot = [WindowShot]::FindPopup($p.Id, $h, "") } # nothing by that title: the biggest
			if ($shoot -eq [IntPtr]::Zero) { $shoot = [WindowShot]::FindPopup($p.Id, $h, "*") } # a small one: still the biggest
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
			if (-not $white -or $try -eq 3) { break } # the last try is kept whatever it is, and said to be white
			$bitmap.Dispose()
			Start-Sleep -Milliseconds 700
		}
		$bitmap.Save("$data\previews\$name.png", [Drawing.Imaging.ImageFormat]::Png)
		$bitmap.Dispose()
		Say "picture $name ($($r.r - $r.l) x $($r.b - $r.t)), PrintWindow $done$(if ($white) { ', STILL WHITE' } else { '' })"
		Remove-Item "$data\keycheck_shot"
	}
	Start-Sleep -Milliseconds 100
}
