@echo off
rem Double-click to view every random maint room, or drag .dmm files / folders onto this to view those.
python "%~dp0mapviewer.py" %*
if errorlevel 1 pause
