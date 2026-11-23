@echo off
rem Builds the 32-bit prototype DLLs here with MSVC (VS 2022 x86 tools).
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars32.bat" >nul
cd /d "%~dp0"
cl /nologo /O2 /LD /W3 string_hash.c /link /out:string_hash.dll
cl /nologo /O2 /LD /W3 var_cache.c /link /out:var_cache.dll
cl /nologo /O2 /LD /W3 /D_CRT_SECURE_NO_WARNINGS numfmt.c /link /out:numfmt.dll
cl /nologo /O2 /LD /W3 /D_CRT_SECURE_NO_WARNINGS in_index.c /link /out:in_index.dll
cl /nologo /O2 /LD /W3 /D_CRT_SECURE_NO_WARNINGS turf_chain.c /link /out:turf_chain.dll
cl /nologo /O2 /LD /W3 /D_CRT_SECURE_NO_WARNINGS sleep_queue.c /link /out:sleep_queue.dll
