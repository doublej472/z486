@echo off
if "%1" == "" goto usage
if "%2" == "" goto usage

set DHRY_ITERS=%1
set DHRY_OPT=%2

if exist success.ok del success.ok
if exist dhry.bin del dhry.bin
if exist dhry.map del dhry.map

wasm -zq -fo=startup.obj startup.asm
if errorlevel 1 goto failed

wcc386 -zq -bt=dos -mf -3r -s -zl -zp4 %DHRY_OPT% -DDHRY_EMBEDDED -DDHRY_ITERS=%DHRY_ITERS% -DREG=register -fo=main.obj main.c
if errorlevel 1 goto failed
wcc386 -zq -bt=dos -mf -3r -s -zl -zp4 %DHRY_OPT% -DDHRY_EMBEDDED -DDHRY_ITERS=%DHRY_ITERS% -DREG=register -fo=dhry_1.obj dhry_1.c
if errorlevel 1 goto failed
wcc386 -zq -bt=dos -mf -3r -s -zl -zp4 %DHRY_OPT% -DDHRY_EMBEDDED -DDHRY_ITERS=%DHRY_ITERS% -DREG=register -fo=dhry_2.obj dhry_2.c
if errorlevel 1 goto failed
wcc386 -zq -bt=dos -mf -3r -s -zl -zp4 %DHRY_OPT% -DDHRY_EMBEDDED -DDHRY_ITERS=%DHRY_ITERS% -DREG=register -fo=support.obj support.c
if errorlevel 1 goto failed

wlink @watcom.lnk
if errorlevel 1 goto failed

wdis -a -l=main.lst main.obj
wdis -a -l=dhry_1.lst dhry_1.obj
wdis -a -l=dhry_2.lst dhry_2.obj
wdis -a -l=support.lst support.obj

echo PASS>success.ok
goto end

:usage
echo Usage: WATCOM_BUILD iterations compiler_options
goto failed

:failed
echo Open Watcom build failed.
if exist success.ok del success.ok

:end
