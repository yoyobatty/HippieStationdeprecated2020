# Runs varread.dmb and reads dd.exe's private bytes 1.5 s after each PHASE line.
$dir = $PSScriptRoot
Remove-Item "$dir\varread.log" -ErrorAction SilentlyContinue
$env:__COMPAT_LAYER = $null
$p = Start-Process "C:\Program Files (x86)\BYOND\bin\dd.exe" -ArgumentList "`"$dir\varread.dmb`" -invisible -trusted -logself" -PassThru -WindowStyle Hidden
$seen = 0
while (-not $p.HasExited) {
	Start-Sleep -Milliseconds 300
	$lines = @(Get-Content "$dir\varread.log" -ErrorAction SilentlyContinue)
	for ($i = $seen; $i -lt $lines.Count; $i++) {
		$l = $lines[$i]
		if ($l -like "PHASE*") {
			Start-Sleep -Milliseconds 1500
			$p.Refresh()
			"{0,-50} private {1,8:N1} MB" -f $l.Substring(0, [Math]::Min(48, $l.Length)), ($p.PrivateMemorySize64 / 1MB)
		} elseif ($l -like "READ*" -or $l -like "DONE*") { $l }
	}
	$seen = $lines.Count
}
