@echo off
setlocal

rem ================================================================
rem  Installs tweaker as a local mod.
rem
rem  This places the compiled bundles in the Steam Workshop content
rem  directory under a local-only ID, then adds the mod entry to
rem  user_settings.config so the launcher shows it.
rem
rem  To share with a friend, have them run this same script after
rem  copying the .build\OUT folder and this script to their machine.
rem ================================================================

set "WORKSHOP_ID=9000000001"
set "WORKSHOP_DIR=C:\Program Files (x86)\Steam\steamapps\workshop\content\552500\%WORKSHOP_ID%"
set "OUT_DIR=%~dp0tweaker\.build\OUT"
set "USER_CFG=%APPDATA%\Fatshark\Vermintide 2\user_settings.config"
set "USER_CFG_BAK=%APPDATA%\Fatshark\Vermintide 2\user_settings.config.bak"

echo === Tweaker - Local Installer ===
echo.

rem -- 1. Verify build output exists --------------------------------
if not exist "%OUT_DIR%\tweaker.mod" (
    echo ERROR: Build output not found at:
    echo   %OUT_DIR%
    echo.
    echo Run build.bat first.
    goto :FAIL
)

rem -- 2. Create workshop content directory -------------------------
if not exist "%WORKSHOP_DIR%" (
    echo Creating workshop directory...
    mkdir "%WORKSHOP_DIR%"
    if errorlevel 1 (
        echo ERROR: Could not create workshop directory.
        echo You may need to run this script as Administrator.
        goto :FAIL
    )
)

rem -- 3. Copy bundle files (rename to .mod_bundle) ----------------
echo Copying mod files to:
echo   %WORKSHOP_DIR%
echo.

for %%F in ("%OUT_DIR%\*") do (
    set "FNAME=%%~nxF"
    rem .mod files are copied as-is; everything else gets .mod_bundle
    if "%%~xF" == ".mod" (
        copy /y "%%F" "%WORKSHOP_DIR%\%%~nxF" >nul
    ) else (
        copy /y "%%F" "%WORKSHOP_DIR%\%%~nF.mod_bundle" >nul
    )
)

echo Files installed.
echo.

rem -- 4. Backup user_settings.config ------------------------------
echo Backing up user_settings.config...
copy /y "%USER_CFG%" "%USER_CFG_BAK%" >nul
if errorlevel 1 (
    echo ERROR: Could not back up user_settings.config.
    goto :FAIL
)

rem -- 5. Enable developer_mode in mod_settings --------------------
rem     (makes the game load mods it finds even without launcher setup)
echo Enabling developer_mode in mod_settings...
powershell -Command ^
  "(Get-Content '%USER_CFG%') -replace 'developer_mode = false', 'developer_mode = true' | Set-Content '%USER_CFG%'"
if errorlevel 1 (
    echo WARNING: Could not enable developer_mode. You may need to set it manually.
)

echo.
echo ================================================================
echo  Installation complete!
echo.
echo  - Mod installed to: %WORKSHOP_DIR%
echo  - user_settings.config backup: %USER_CFG_BAK%
echo  - developer_mode enabled in mod_settings
echo.
echo  Start Warhammer: Vermintide 2, open the Mods screen in the
echo  launcher, enable "Tweaker", then play in the MODDED REALM.
echo.
echo  To uninstall: delete the folder above and restore
echo  user_settings.config.bak.
echo ================================================================
echo.
goto :END

:FAIL
echo.
echo Installation failed. See errors above.
exit /b 1

:END
pause
