@echo off
rem TGS custom event HippieUpdate (Windows): %1 is the running game's folder, %2 the ckey of the admin who asked.
rem Runs HippieUpdate.ps1 from this EventScripts folder (not from the game's code, so a test merge can't change it).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0HippieUpdate.ps1" -GameDir "%~1" -Ckey "%~2"
exit /b %ERRORLEVEL%
