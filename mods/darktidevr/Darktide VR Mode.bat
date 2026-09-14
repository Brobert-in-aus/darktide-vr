@echo off
setlocal
rem Switches Darktide between VR mode and flat mode. Run from inside the game
rem folder at mods\darktidevr. Darktide must be closed.
echo Darktide VR mode switch
echo.
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
