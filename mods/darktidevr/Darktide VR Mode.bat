@echo off
setlocal
rem Switches Darktide between VR mode and flat mode. Run from inside the game
rem folder at mods\darktidevr. Darktide must be closed.
echo Darktide VR mode switch
echo.
rem Opened from inside the zip, Windows copies only this file to a temporary
rem folder and runs it there, without the script beside it (reported
rem 17 October 2026). Say so instead of leaving PowerShell's error.
if not exist "%~dp0darktidevr-mode.ps1" (
    echo This file was run without the rest of the mod beside it, most likely
    echo straight from inside the zip.
    echo.
    echo Extract the whole archive into the Darktide game folder first ^(the
    echo folder that contains "binaries", "bundle" and "mods"^), then run
    echo mods\darktidevr\Darktide VR Mode.bat from there.
    goto :end
)
if not exist "%~dp0..\..\binaries\Darktide.exe" (
    echo This mod folder is not inside the Darktide game folder.
    echo.
    echo Extract the archive into the game folder ^(the folder that contains
    echo "binaries", "bundle" and "mods"^) so that mods\darktidevr sits beside
    echo mods\dmf, then run mods\darktidevr\Darktide VR Mode.bat from there.
    goto :end
)
echo   1  VR mode    (patch the executable, install the d3d12 proxy, enable the mod)
echo   2  Flat mode  (restore the original executable, remove the proxy, disable the mod)
echo   3  Status only
echo   4  Restore settings (the newest copy the mod saved at a good launch)
echo.
set /p choice=Choose 1, 2, 3 or 4:
if "%choice%"=="1" set mode=vr
if "%choice%"=="2" set mode=flat
if "%choice%"=="3" set mode=status
if "%choice%"=="4" set mode=restore-settings
if not defined mode (
    echo Nothing chosen.
    goto :end
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0darktidevr-mode.ps1" -Mode %mode%
if errorlevel 1 (
    echo.
    echo The switch did not complete. Read the message above.
)
:end
echo.
pause
