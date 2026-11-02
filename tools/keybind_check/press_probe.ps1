# Times a key press to the screen for client_cost.dm. Keys are posted straight to the DreamSeeker window and the picture comes from
# PrintWindow, so the window needn't be on top and nothing global is sent. Used by run.sh as SENDER.
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Threading;
public class PressProbe {
	[StructLayout(LayoutKind.Sequential)]
	public struct RECT { public int l, t, r, b; }
	[StructLayout(LayoutKind.Sequential)]
	public struct GUITHREADINFO {
		public int cbSize, flags;
		public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret;
		public RECT rcCaret;
	}
	[DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
	[DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
	[DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
	[DllImport("user32.dll")] static extern uint MapVirtualKey(uint c, uint t);
	[DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr p);
	[DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint t, ref GUITHREADINFO g);
	[DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
	[DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int how);
	[DllImport("gdi32.dll")] static extern uint GetPixel(IntPtr dc, int x, int y);

	static IntPtr main, focus;
	static Bitmap shot;
	static Graphics canvas;
	static int spotX, spotY;

	public static void Attach(IntPtr window) {
		main = window;
		if (IsIconic(main)) { // a minimized window is a 160 x 28 picture of nothing
			ShowWindow(main, 4); // shown, not given the keyboard
			Thread.Sleep(1500);
		}
		GUITHREADINFO g = new GUITHREADINFO();
		g.cbSize = Marshal.SizeOf(g);
		uint t = GetWindowThreadProcessId(main, IntPtr.Zero);
		focus = GetGUIThreadInfo(t, ref g) && g.hwndFocus != IntPtr.Zero ? g.hwndFocus : main;
		RECT r;
		GetWindowRect(main, out r);
		shot = new Bitmap(r.r - r.l, r.b - r.t, PixelFormat.Format32bppRgb);
		canvas = Graphics.FromImage(shot);
	}

	static void Post(uint vk, bool down) {
		uint scan = MapVirtualKey(vk, 0);
		if (down) PostMessage(focus, 0x0100, (IntPtr)vk, (IntPtr)(1 | (scan << 16)));
		else PostMessage(focus, 0x0101, (IntPtr)vk, (IntPtr)(unchecked((int)0xC0000001) | (int)(scan << 16)));
	}

	static void Tap(uint vk) {
		Post(vk, true);
		Thread.Sleep(30);
		Post(vk, false);
	}

	static int Difference(int a, int b) {
		int red = Math.Abs(((a >> 16) & 255) - ((b >> 16) & 255));
		int green = Math.Abs(((a >> 8) & 255) - ((b >> 8) & 255));
		int blue = Math.Abs((a & 255) - (b & 255));
		return Math.Max(red, Math.Max(green, blue));
	}

	static int[] Snapshot() {
		IntPtr dc = canvas.GetHdc();
		PrintWindow(main, dc, 2);
		canvas.ReleaseHdc(dc);
		Rectangle all = new Rectangle(0, 0, shot.Width, shot.Height);
		BitmapData bits = shot.LockBits(all, ImageLockMode.ReadOnly, PixelFormat.Format32bppRgb);
		int[] pixels = new int[shot.Width * shot.Height];
		for (int y = 0; y < shot.Height; y++)
			Marshal.Copy(IntPtr.Add(bits.Scan0, y * bits.Stride), pixels, y * shot.Width, shot.Width);
		shot.UnlockBits(bits);
		return pixels;
	}

	// The plate: whatever flips one way with the key and flips back with the next press. Medians, in case something walks past.
	public static string FindPlate(uint vk) {
		int[] a = Snapshot();
		Tap(vk);
		Thread.Sleep(600);
		int[] b = Snapshot();
		Tap(vk);
		Thread.Sleep(600);
		int[] c = Snapshot();
		List<int> xs = new List<int>();
		List<int> ys = new List<int>();
		for (int y = 0; y < shot.Height; y++) {
			for (int x = 0; x < shot.Width; x++) {
				int i = y * shot.Width + x;
				if (Difference(a[i], b[i]) > 60 && Difference(b[i], c[i]) > 60) { xs.Add(x); ys.Add(y); }
			}
		}
		if (xs.Count == 0) return null;
		xs.Sort();
		ys.Sort();
		spotX = xs[xs.Count / 2];
		spotY = ys[ys.Count / 2];
		return "plate at " + spotX + "," + spotY + ", " + xs.Count + " pixels flipped from " + xs[0] + "," + ys[0] + " to " + xs[xs.Count - 1] + "," + ys[ys.Count - 1] + ", window " + shot.Width + " x " + shot.Height;
	}

	static int Pixel() {
		IntPtr dc = canvas.GetHdc();
		PrintWindow(main, dc, 2);
		uint colour = GetPixel(dc, spotX, spotY);
		canvas.ReleaseHdc(dc);
		return (int)(colour & 0xFFFFFF);
	}

	public static string Time(uint vk, int presses) {
		List<double> times = new List<double>();
		Random random = new Random();
		Stopwatch clock = new Stopwatch();
		double looking = 0;
		int looks = 0;
		int lost = 0;
		for (int i = 0; i < presses; i++) {
			Thread.Sleep(180 + random.Next(0, 120)); // so the presses land anywhere in a tick
			int before = Pixel();
			clock.Restart();
			Post(vk, true);
			bool seen = false;
			while (clock.ElapsedMilliseconds < 600) {
				double started = clock.Elapsed.TotalMilliseconds;
				int now = Pixel();
				looks++;
				looking += clock.Elapsed.TotalMilliseconds - started;
				if (Difference(now, before) > 60) { seen = true; break; }
			}
			double ms = clock.Elapsed.TotalMilliseconds;
			Post(vk, false);
			if (seen) times.Add(ms); else lost++;
		}
		if (times.Count == 0) return "nothing ever showed, " + lost + " presses lost";
		times.Sort();
		double total = 0;
		foreach (double t in times) total += t;
		return String.Format("{0} presses, best {1:F0} ms, median {2:F0}, mean {3:F0}, worst 5% {4:F0}, worst {5:F0}; {6} never showed; one look at the window took {7:F1} ms",
			times.Count, times[0], times[times.Count / 2], total / times.Count, times[(int)(times.Count * 0.95)], times[times.Count - 1], lost, looking / Math.Max(looks, 1));
	}
}
'@
$data = Join-Path (Get-Location) "data"

function Say($text) { [IO.File]::AppendAllText("$data\keycheck.txt", "$text`n") }

$p = Get-Process dreamseeker -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Say "no DreamSeeker window"; exit 1 }
[PressProbe]::Attach($p.MainWindowHandle)
$located = $false
$deadline = (Get-Date).AddMinutes(8)
while ((Get-Date) -lt $deadline) {
	if ((Test-Path "$data\keycheck.txt") -and (Select-String -Path "$data\keycheck.txt" -Pattern "^done" -Quiet)) { break }
	if (Test-Path "$data\press_find") {
		$found = [PressProbe]::FindPlate(0x78)
		if ($found) { $located = $true; Say "probe: $found" } else { Say "probe: couldn't find the plate" }
		Remove-Item "$data\press_find"
		[IO.File]::WriteAllText("$data\press_found", "done")
	}
	if (Test-Path "$data\press_go") {
		$rate = ([IO.File]::ReadAllText("$data\press_go")).Trim()
		if ($located) {
			Say "$rate ticks, hotkey: $([PressProbe]::Time(0x78, 60))"
			Say "$rate ticks, movement: $([PressProbe]::Time(0x77, 60))"
		}
		Remove-Item "$data\press_go"
		[IO.File]::WriteAllText("$data\press_done", "done")
	}
	Start-Sleep -Milliseconds 100
}
