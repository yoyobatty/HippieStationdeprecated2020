# DreamSeeker's CPU time so far, in ms (all its processes), for run.sh to difference over a PresentMon capture
$ms = 0
Get-Process dreamseeker -ErrorAction SilentlyContinue | ForEach-Object { $ms += $_.TotalProcessorTime.TotalMilliseconds }
Write-Output ([math]::Round($ms))
