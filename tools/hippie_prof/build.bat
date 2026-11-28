@echo off
rem Builds hippie_prof.dll (32-bit, like BYOND) into the repository root, or to the path given: build.bat C:\scratch\hippie_prof_test.dll
rem (a build to try with -params "prof-lib=..." while running servers have the root one open; its .obj and .lib go beside it).
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
set "OUT=..\..\hippie_prof.dll"
set "OBJ=build\"
if not "%~1"=="" (
	set "OUT=%~f1"
	set "OBJ=%~dp1"
)
if not exist "%OBJ%" mkdir "%OBJ%"
cl /nologo /O2 /MT /LD /W3 /D_CRT_SECURE_NO_WARNINGS hippie_prof.c /Fo:"%OBJ%hippie_prof.obj" /Fe:"%OUT%" /link /NOLOGO /IMPLIB:"%OBJ%hippie_prof.lib"
exit /b %ERRORLEVEL%
