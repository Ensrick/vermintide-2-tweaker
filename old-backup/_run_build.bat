@echo off
setlocal

set "SDK_DIR=C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK"
set "MODDIR=C:\Users\danjo\source\repos\vermintide-2-tweaker\tweaker"
set "DATADIR=%MODDIR%\.build\data"
set "BUNDLEDIR=%MODDIR%\.build\bundle"
set "OUTDIR=%MODDIR%\.build\OUT"

echo Building mod: tweaker
echo.

if not exist "%OUTDIR%" mkdir "%OUTDIR%"

"%SDK_DIR%\bin\stingray_win64_dev_x64.exe" ^
    --compile-for win32 ^
    --source-dir "%MODDIR%" ^
    --data-dir "%DATADIR%" ^
    --bundle-dir "%BUNDLEDIR%" ^
    --map-source-dir core "%SDK_DIR%"

if errorlevel 1 (
    echo.
    echo Build FAILED.
    exit /b 1
)

copy /y "%BUNDLEDIR%\*." "%OUTDIR%\" >nul 2>&1
copy /y "%BUNDLEDIR%\*.stream" "%OUTDIR%\" >nul 2>&1
copy /y "%MODDIR%\*.mod" "%OUTDIR%\" >nul 2>&1

echo.
echo Build succeeded. Output is in:
echo   %OUTDIR%
exit /b 0
