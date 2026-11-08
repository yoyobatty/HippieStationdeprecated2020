@echo off
rem Builds hippie_prof.dll (32-bit, like BYOND) into the repository root.
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
cl /nologo /O2 /MT /LD /W3 /D_CRT_SECURE_NO_WARNINGS hippie_prof.c /Fo:build\ /Fe:..\..\hippie_prof.dll /link /NOLOGO /IMPLIB:build\hippie_prof.lib
exit /b %ERRORLEVEL%
