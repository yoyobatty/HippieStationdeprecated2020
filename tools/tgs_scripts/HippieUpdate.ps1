# Update Server (the in-game +SERVER verb, hippiestation/code/modules/tgs/tgs_update.dm), Windows side.
# TGS runs HippieUpdate.bat from the instance's EventScripts folder when the game asks (TgsTriggerEvent), which runs this.
# It logs in to TGS, pulls the tracked branch from GitHub into the instance's repository (test merges stay; a merge
# conflict stops it), starts a deployment, and writes how it went to <game folder>\data\tgs_update.json for the game.
#
# TGS runs an instance's event scripts one at a time, and the pull raises events of its own (RepoFetch, RepoCheckout) that
# wait their turn: so this only marks the update as running, starts itself again as a separate -Worker process to do it,
# and returns at once. Waiting here instead hangs the pull until this script gives up.
#
# Needs hippie_update.json beside it (copy hippie_update.example.json): the TGS address and a TGS login that can update
# this instance's repository and deploy. Keep that login to just those rights.
param(
	[string]$GameDir = "",
	[string]$Ckey = "",
	[switch]$Worker
)
$ErrorActionPreference = "Stop"

function Save-State([hashtable]$state) {
	if ($GameDir -and (Test-Path -LiteralPath $GameDir)) {
		$data = Join-Path $GameDir "data"
		if (-not (Test-Path -LiteralPath $data)) {
			New-Item -ItemType Directory -Path $data | Out-Null
		}
		$state.ckey = $Ckey
		$state.at = (Get-Date).ToString("s")
		[IO.File]::WriteAllText((Join-Path $data "tgs_update.json"), ($state | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
	}
}

function Write-Result([bool]$ok, [string]$message) {
	Write-Host ($(if ($ok) { "OK: " } else { "FAILED: " }) + $message)
	Save-State @{ running = $false; ok = $ok; message = $message }
	exit $(if ($ok) { 0 } else { 1 })
}

if (-not $Worker) {
	Save-State @{ running = $true; message = "pulling from GitHub" }
	$workerArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"", "-GameDir", "`"$GameDir`"", "-Ckey", "`"$Ckey`"", "-Worker")
	Start-Process -FilePath "powershell" -ArgumentList $workerArgs -WindowStyle Hidden
	Write-Host "Update started in a separate process; it reports to $GameDir\data\tgs_update.json"
	exit 0
}

function Short([string]$sha) {
	if ($sha -and $sha.Length -gt 8) { return $sha.Substring(0, 8) }
	return $sha
}

$configPath = Join-Path $PSScriptRoot "hippie_update.json"
if (-not (Test-Path -LiteralPath $configPath)) {
	Write-Result $false "hippie_update.json is missing from TGS's EventScripts folder"
}
try {
	$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
}
catch {
	Write-Result $false "hippie_update.json isn't valid JSON"
}
$base = "$($config.url)".TrimEnd("/")
$headers = @{
	"Api" = "Tgstation.Server.Api/10.0.0"
	"User-Agent" = "HippieUpdate/1.0"
	"Accept" = "application/json"
}

function Invoke-Tgs([string]$method, [string]$path, $body = $null) {
	$params = @{ Method = $method; Uri = "$base$path"; Headers = $headers; ContentType = "application/json" }
	if ($null -ne $body) {
		$params.Body = ($body | ConvertTo-Json -Compress)
	}
	return Invoke-RestMethod @params
}

function Wait-Job($job, [int]$timeoutSeconds) {
	$start = Get-Date
	while (-not $job.stoppedAt) {
		if (((Get-Date) - $start).TotalSeconds -gt $timeoutSeconds) {
			Write-Result $false "TGS job $($job.id) ($($job.description)) is still running after $timeoutSeconds s"
		}
		Start-Sleep -Seconds 2
		$job = Invoke-Tgs GET "/api/Job/$($job.id)"
	}
	return $job
}

try {
	$auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($config.username):$($config.password)"))
	$headers["Authorization"] = "Basic $auth"
	$token = Invoke-Tgs POST "/api"
	$headers["Authorization"] = "Bearer $($token.bearer)"
}
catch {
	Write-Result $false "couldn't log in to TGS at ${base}: $($_.Exception.Message)"
}

try {
	$instanceId = $config.instance
	if (-not $instanceId) {
		$root = "$env:TGS_INSTANCE_ROOT".TrimEnd("\", "/")
		$list = Invoke-Tgs GET "/api/Instance/List?pageSize=100"
		foreach ($instance in $list.content) {
			if ("$($instance.path)".TrimEnd("\", "/") -eq $root) {
				$instanceId = $instance.id
			}
		}
		if (-not $instanceId) {
			Write-Result $false "couldn't tell which TGS instance this is: set `"instance`" in hippie_update.json"
		}
	}
	$headers["Instance"] = "$instanceId"

	$before = Invoke-Tgs GET "/api/Repository"
	if ($before.activeJob) {
		Write-Result $false "the repository is busy: $($before.activeJob.description)"
	}
	$oldOrigin = $before.revisionInformation.originCommitSha
	$update = Invoke-Tgs POST "/api/Repository" @{ updateFromOrigin = $true }
	if ($update.activeJob) {
		$job = Wait-Job $update.activeJob 900
		if ($job.cancelled) {
			Write-Result $false "the pull was cancelled in TGS"
		}
		if ($job.errorCode -or $job.exceptionDetails) {
			$why = "$($job.exceptionDetails)".Split("`n")[0]
			Write-Result $false "pulling failed (TGS error $($job.errorCode)): $why"
		}
	}
	$after = Invoke-Tgs GET "/api/Repository"
	$newOrigin = $after.revisionInformation.originCommitSha
	$testMerges = @($after.revisionInformation.activeTestMerges).Count
	$pulled = if ($oldOrigin -eq $newOrigin) { "already up to date at $(Short $newOrigin)" } else { "$(Short $oldOrigin) -> $(Short $newOrigin)" }
	if ($testMerges) {
		$pulled += ", $testMerges test merge(s) kept"
	}

	$deploy = Invoke-Tgs PUT "/api/DreamMaker"
	Write-Result $true "$pulled; deploying (TGS job $($deploy.id)). It goes live next round."
}
catch {
	$detail = $_.ErrorDetails.Message
	if (-not $detail) {
		$detail = $_.Exception.Message
	}
	Write-Result $false "TGS refused: $detail"
}
