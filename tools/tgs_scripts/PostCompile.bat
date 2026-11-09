@echo off
rem TGS PostCompile (Windows): %1 is the new deployment folder, %2 the BYOND version it was compiled with.
rem Boots the new build headless with the smoke boot shipped in that build, and fails the deploy if it doesn't initialize.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~1\tools\tgs_scripts\smoke_boot.ps1" -GameDir "%~1" -EngineVersion "%~2"
exit /b %ERRORLEVEL%
