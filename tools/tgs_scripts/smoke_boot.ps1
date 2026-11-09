# Smoke boot for TGS deploys (Windows): boots the freshly compiled game headless and fails the deploy unless it gets
# through initialization. TGS runs PostCompile.bat from the instance's EventScripts folder after compiling, which runs
# this copy from the new code, so the check always matches the build it checks.
#
#   smoke_boot.ps1 -GameDir <deployment folder> -EngineVersion <BYOND version TGS compiled with>
#   smoke_boot.ps1 -GameDir . -DreamDaemon "C:\Program Files (x86)\BYOND\bin\dd.exe"      (by hand)
#
# At PostCompile TGS hasn't linked the instance's GameStaticFiles (config, data) into the deployment yet, so the boot
# uses the repository's config and writes its logs into a data folder of its own, deleted afterwards. If those are
# already links (a different TGS order), it refuses rather than write into the live server's files.
param(
	[Parameter(Mandatory = $true)][string]$GameDir,
	[string]$EngineVersion = "",
	[string]$DreamDaemon = "",
	[int]$TimeoutSeconds = 300,
	[string]$Params = ""
)
$ErrorActionPreference = "Stop"

function Fail([string]$why) {
	Write-Host "SMOKE BOOT FAILED: $why"
	exit 1
}

$GameDir = (Resolve-Path -LiteralPath $GameDir).Path
foreach ($name in @("data", "config")) {
	$path = Join-Path $GameDir $name
	if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
		Fail "$name is already linked to the instance's static files: a boot here would write into the live server's files"
	}
}

if (-not $DreamDaemon) {
	if (-not $env:TGS_INSTANCE_ROOT) {
		Fail "TGS_INSTANCE_ROOT isn't set (TGS 6.17 or newer sets it). Run by hand with -DreamDaemon <dd.exe>."
	}
	$bin = Join-Path $env:TGS_INSTANCE_ROOT "Byond\$EngineVersion\byond\bin"
	$DreamDaemon = Join-Path $bin "dd.exe"
	if (-not (Test-Path -LiteralPath $DreamDaemon)) {
		$DreamDaemon = Join-Path $bin "dreamdaemon.exe"
	}
}
if (-not (Test-Path -LiteralPath $DreamDaemon)) {
	Fail "no DreamDaemon at $DreamDaemon"
}

$dmb = Get-ChildItem -LiteralPath $GameDir -Filter *.dmb -File | Select-Object -First 1
if (-not $dmb) {
	Fail "no .dmb in $GameDir"
}

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = $listener.LocalEndpoint.Port
$listener.Stop()

$dataDir = Join-Path $GameDir "data"
$dataExisted = Test-Path -LiteralPath $dataDir
$logsDir = Join-Path $dataDir "logs"
$before = @{}
if (Test-Path -LiteralPath $logsDir) {
	Get-ChildItem -LiteralPath $logsDir -Recurse -File | ForEach-Object { $before[$_.FullName] = $true }
}

$argLine = "`"$($dmb.FullName)`" $port -trusted -invisible"
if ($Params) {
	$argLine += " -params `"$Params`""
}
Write-Host "Smoke boot: $($dmb.Name) on port $port ($DreamDaemon)"
$start = Get-Date
$proc = Start-Process -FilePath $DreamDaemon -ArgumentList $argLine -WorkingDirectory $GameDir -PassThru -WindowStyle Hidden
$ready = $null
try {
	while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {
		Start-Sleep -Seconds 1
		if (Test-Path -LiteralPath $logsDir) {
			foreach ($log in Get-ChildItem -LiteralPath $logsDir -Recurse -File -Filter *.log) {
				if ($before.ContainsKey($log.FullName)) {
					continue
				}
				if (Select-String -LiteralPath $log.FullName -Pattern "Initializations complete" -SimpleMatch -Quiet) {
					$ready = $log
					break
				}
			}
		}
		if ($ready -or $proc.HasExited) {
			break
		}
	}
}
finally {
	if (-not $proc.HasExited) {
		Stop-Process -Id $proc.Id -Force
		$proc.WaitForExit(10000) | Out-Null
	}
}
$took = [int]((Get-Date) - $start).TotalSeconds

# What went wrong on the way, for the TGS job log: runtime errors from this boot's logs
$newLogs = @()
if (Test-Path -LiteralPath $logsDir) {
	$newLogs = @(Get-ChildItem -LiteralPath $logsDir -Recurse -File -Filter *.log | Where-Object { -not $before.ContainsKey($_.FullName) })
}
$runtimes = @()
foreach ($log in $newLogs | Where-Object { $_.Name -eq "runtime.log" }) {
	$runtimes += @(Select-String -LiteralPath $log.FullName -Pattern "runtime error:" -SimpleMatch | ForEach-Object { $_.Line })
}
# A runtime in a subsystem's Initialize() only ends that proc, so the MC still says "Initializations complete"; it also
# says which subsystem didn't finish (master.dm), and that build is broken too
$unfinished = @()
foreach ($log in $newLogs) {
	$unfinished += @(Select-String -LiteralPath $log.FullName -Pattern "MC watchdog alert: (.+?) didn't finish initializing" | ForEach-Object { $_.Matches[0].Groups[1].Value })
}
$unfinished = @($unfinished | Select-Object -Unique)
$runtimeNote = "$($runtimes.Count) runtime error(s)"
if ($runtimes.Count) {
	Write-Host "Runtime errors during the boot (first 5):"
	$runtimes | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" }
}

if (-not $ready) {
	foreach ($log in $newLogs | Where-Object { $_.Name -in @("runtime.log", "config_error.log", "dd.log") }) {
		Write-Host "--- last lines of $($log.Name):"
		Get-Content -LiteralPath $log.FullName -Tail 15 | ForEach-Object { Write-Host "  $_" }
	}
}
if (-not $dataExisted -and (Test-Path -LiteralPath $dataDir)) {
	Remove-Item -LiteralPath $dataDir -Recurse -Force -ErrorAction SilentlyContinue
}
if (-not $ready) {
	if ($proc.HasExited -and $took -lt $TimeoutSeconds) {
		Fail "DreamDaemon stopped after $took s before initialization finished ($runtimeNote)"
	}
	Fail "initialization didn't finish within $TimeoutSeconds s ($runtimeNote)"
}
if ($unfinished.Count) {
	Fail "didn't finish initializing: $($unfinished -join ', ') ($runtimeNote)"
}
Write-Host "Smoke boot passed: initialized in $took s, $runtimeNote."
exit 0
