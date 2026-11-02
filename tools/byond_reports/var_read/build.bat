@echo off
rem Builds var_read.dll (32-bit, like BYOND) next to this file. Needs Visual Studio 2022 with the C++ x86 tools.
setlocal
if not defined BYONDAPI set "BYONDAPI=%ProgramFiles(x86)%\BYOND\byondapi"
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
cl /nologo /O2 /MT /LD /EHsc /W3 /DWIN32 /I"%BYONDAPI%" var_read.cpp /Fo:build\ /Fe:var_read.dll /link /NOLOGO /IMPLIB:build\var_read.lib "%BYONDAPI%\byondapi.lib"
exit /b %ERRORLEVEL%
