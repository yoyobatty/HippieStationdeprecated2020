@echo off
cd "%~dp0\.."
REM Opens the tgui designer in your browser. Close this window to stop it.
node packages\tgui-designer\server.js %*
