@rem Build script for Vermintide 2 mods.
@rem Calls the SDK compiler using tweaker as the mod to build.

@setlocal
@set SDK_DIR=C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK
@set MOD_NAME=tweaker

@rem Allow overriding mod name via argument
@if "%~1" neq "" (
    @set MOD_NAME=%~1
)

@set REPO_DIR=%~dp0
@set MODDIR=%REPO_DIR%%MOD_NAME%
@set DATADIR=%MODDIR%\.build\data
@set BUNDLEDIR=%MODDIR%\.build\bundle
@set OUTDIR=%MODDIR%\.build\OUT

@echo Building mod: %MOD_NAME%
@if not exist "%OUTDIR%" mkdir "%OUTDIR%"
@if errorlevel 1 goto :BAD

@"%SDK_DIR%\bin\stingray_win64_dev_x64.exe" ^
    --compile-for win32 ^
    --source-dir "%MODDIR%" ^
    --data-dir "%DATADIR%" ^
    --bundle-dir "%BUNDLEDIR%" ^
    --map-source-dir core "%SDK_DIR%"
@if errorlevel 1 goto :BAD

@copy "%BUNDLEDIR%\*." "%OUTDIR%\*."
@copy "%BUNDLEDIR%\*.stream" "%OUTDIR%\*.stream" 2>nul
@copy "%MODDIR%\*.mod" "%OUTDIR%\*.mod"

@echo.
@echo Build succeeded. Output is in: %OUTDIR%
@goto :END

:BAD
@echo.
@echo Build FAILED -- check the error messages above.

:END
@pause
