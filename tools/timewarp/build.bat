@echo off
rem Builds timewarp.dll (32-bit, like BYOND) into the repository root, next to rust_g.dll.
rem Needs Visual Studio with the C++ x86 tools. Set VCVARSALL to override where it's looked for.
setlocal
if not defined VCVARSALL (
	for %%E in (Community Professional Enterprise BuildTools) do (
		if exist "%ProgramFiles%\Microsoft Visual Studio\2022\%%E\VC\Auxiliary\Build\vcvarsall.bat" set "VCVARSALL=%ProgramFiles%\Microsoft Visual Studio\2022\%%E\VC\Auxiliary\Build\vcvarsall.bat"
	)
)
if not defined VCVARSALL (
	echo Visual Studio 2022 with the C++ tools wasn't found. Set VCVARSALL to your vcvarsall.bat.
	exit /b 1
)
call "%VCVARSALL%" x64_x86 >nul 2>&1
cd /d "%~dp0"
if not exist build mkdir build
cl /nologo /O2 /MT /LD /W3 /D_CRT_SECURE_NO_WARNINGS timewarp.c /Fo:build\ /Fe:..\..\timewarp.dll /link /NOLOGO /IMPLIB:build\timewarp.lib winmm.lib
exit /b %ERRORLEVEL%
