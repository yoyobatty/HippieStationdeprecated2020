@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars32.bat" >nul
cd /d "%~dp0"
cl /nologo /O2 /openmp /W3 /D_CRT_SECURE_NO_WARNINGS numfmt_check.c /Fe:numfmt_check.exe
