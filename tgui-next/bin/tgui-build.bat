@echo off
cd "%~dp0\.."
REM Modern Node.js (17+) removed the legacy MD4 hash this old webpack version
REM relies on; this flag restores it so the build doesn't crash with an
REM "error:0308010C:digital envelope routines::unsupported" error.
set NODE_OPTIONS=--openssl-legacy-provider
call yarn install
call yarn run build
timeout /t 9