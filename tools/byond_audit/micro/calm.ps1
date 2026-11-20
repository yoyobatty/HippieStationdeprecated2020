# Waits until the machine is calm enough to benchmark: total CPU under $Max % for $Need samples in a row (2 s each),
# and no dd.exe/dm.exe other than ours. Gives up after $TimeoutMin minutes (exit 1). Prints the load it saw.
param([double]$Max = 18, [int]$Need = 3, [int]$TimeoutMin = 30)
$deadline = (Get-Date).AddMinutes($TimeoutMin)
$ok = 0
while ((Get-Date) -lt $deadline) {
	$v = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 2 -MaxSamples 1).CounterSamples.CookedValue
	$busy = @(Get-Process -Name dd, dreamdaemon, dm -ErrorAction SilentlyContinue).Count
	if ($v -lt $Max -and $busy -eq 0) { $ok++ } else { $ok = 0 }
	if ($ok -ge $Need) { "calm cpu=$([math]::Round($v,1))"; exit 0 }
}
"not calm after $TimeoutMin min (last cpu=$([math]::Round($v,1)), byond procs=$busy)"
exit 1
