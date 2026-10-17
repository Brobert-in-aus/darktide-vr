@echo off
setlocal
rem Switches Darktide between VR mode and flat mode, or installs the mod.
rem Inside the game folder at mods\darktidevr it is the mode switch. Anywhere
rem else it finds Darktide (Steam, or the Microsoft Store / Game Pass) and
rem installs the mod there. Darktide must be closed.
echo Darktide VR mode switch
echo.
rem Opened from inside the zip, Windows copies only this file to a temporary
rem folder and runs it there, without the scripts beside it (reported
rem 17 October 2026). The zip is found by its name and installed from; the
rem command is tools\release\zip-recovery.ps1, encoded.
if not exist "%~dp0darktidevr-mode.ps1" (
    set "DTVR_HERE=%~dp0"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand JABQAHIAbwBnAHIAZQBzAHMAUAByAGUAZgBlAHIAZQBuAGMAZQAgAD0AIAAnAFMAaQBsAGUAbgB0AGwAeQBDAG8AbgB0AGkAbgB1AGUAJwAKACQAaABlAHIAZQAgAD0AIAAkAGUAbgB2ADoARABUAFYAUgBfAEgARQBSAEUACgBpAGYAIAAoACQAaABlAHIAZQAgAC0AbgBvAHQAbQBhAHQAYwBoACAAJwBcAFwAWwAwAC0AOQBhAC0AZgBBAC0ARgAtAF0AewAzADYAfQBfACgAWwBeAFwAXABdACsAXAAuAHoAaQBwACkAXAAuAFsAXgBcAFwAXQArAFwAXABtAG8AZABzAFwAXABkAGEAcgBrAHQAaQBkAGUAdgByAFwAXAA/ACQAJwApACAAewAgAGUAeABpAHQAIAAyACAAfQAKACQAbgBhAG0AZQAgAD0AIAAkAE0AYQB0AGMAaABlAHMAWwAxAF0ACgAkAHIAbwBvAHQAcwAgAD0AIABAACgAKQAKAGkAZgAgACgAJABlAG4AdgA6AEQAVABWAFIAXwBaAEkAUABfAFMARQBBAFIAQwBIACkAIAB7ACAAJAByAG8AbwB0AHMAIAA9ACAAQAAoACQAZQBuAHYAOgBEAFQAVgBSAF8AWgBJAFAAXwBTAEUAQQBSAEMASAAgAC0AcwBwAGwAaQB0ACAAJwA7ACcAKQAgAH0AIABlAGwAcwBlACAAewAKACAAIAAgACAAdAByAHkAIAB7ACAAJAByAG8AbwB0AHMAIAArAD0AIAAoAE4AZQB3AC0ATwBiAGoAZQBjAHQAIAAtAEMAbwBtAE8AYgBqAGUAYwB0ACAAUwBoAGUAbABsAC4AQQBwAHAAbABpAGMAYQB0AGkAbwBuACkALgBOAGEAbQBlAFMAcABhAGMAZQAoACcAcwBoAGUAbABsADoARABvAHcAbgBsAG8AYQBkAHMAJwApAC4AUwBlAGwAZgAuAFAAYQB0AGgAIAB9ACAAYwBhAHQAYwBoACAAewAgAH0ACgAgACAAIAAgACQAcgBvAG8AdABzACAAKwA9ACAAQAAoACgASgBvAGkAbgAtAFAAYQB0AGgAIAAkAGUAbgB2ADoAVQBTAEUAUgBQAFIATwBGAEkATABFACAAJwBEAG8AdwBuAGwAbwBhAGQAcwAnACkALAAgAFsARQBuAHYAaQByAG8AbgBtAGUAbgB0AF0AOgA6AEcAZQB0AEYAbwBsAGQAZQByAFAAYQB0AGgAKAAnAEQAZQBzAGsAdABvAHAAJwApACwAIABbAEUAbgB2AGkAcgBvAG4AbQBlAG4AdABdADoAOgBHAGUAdABGAG8AbABkAGUAcgBQAGEAdABoACgAJwBNAHkARABvAGMAdQBtAGUAbgB0AHMAJwApACkACgB9AAoAJAB6AGkAcAAgAD0AIAAkAHIAbwBvAHQAcwAgAHwAIABXAGgAZQByAGUALQBPAGIAagBlAGMAdAAgAHsAIAAkAF8AIAAtAGEAbgBkACAAKABUAGUAcwB0AC0AUABhAHQAaAAgAC0ATABpAHQAZQByAGEAbABQAGEAdABoACAAJABfACkAIAB9ACAAfAAgAEYAbwByAEUAYQBjAGgALQBPAGIAagBlAGMAdAAgAHsACgAgACAAIAAgAEcAZQB0AC0AQwBoAGkAbABkAEkAdABlAG0AIAAtAEwAaQB0AGUAcgBhAGwAUABhAHQAaAAgACQAXwAgAC0ARgBpAGwAdABlAHIAIAAkAG4AYQBtAGUAIAAtAEYAaQBsAGUAIAAtAFIAZQBjAHUAcgBzAGUAIAAtAEQAZQBwAHQAaAAgADIAIAAtAEUAcgByAG8AcgBBAGMAdABpAG8AbgAgAFMAaQBsAGUAbgB0AGwAeQBDAG8AbgB0AGkAbgB1AGUACgB9ACAAfAAgAFMAbwByAHQALQBPAGIAagBlAGMAdAAgAEwAYQBzAHQAVwByAGkAdABlAFQAaQBtAGUAIAAtAEQAZQBzAGMAZQBuAGQAaQBuAGcAIAB8ACAAUwBlAGwAZQBjAHQALQBPAGIAagBlAGMAdAAgAC0ARgBpAHIAcwB0ACAAMQAKAGkAZgAgACgALQBuAG8AdAAgACQAegBpAHAAKQAgAHsAIABlAHgAaQB0ACAAMwAgAH0ACgBXAHIAaQB0AGUALQBPAHUAdABwAHUAdAAgACIASQBuAHMAdABhAGwAbABpAG4AZwAgAGYAcgBvAG0AIAAkACgAJAB6AGkAcAAuAEYAdQBsAGwATgBhAG0AZQApACIACgAkAG8AdQB0ACAAPQAgAEoAbwBpAG4ALQBQAGEAdABoACAAJABlAG4AdgA6AFQARQBNAFAAIAAoACcAZABhAHIAawB0AGkAZABlAHYAcgAtAGkAbgBzAHQAYQBsAGwALQAnACAAKwAgAFsAZwB1AGkAZABdADoAOgBOAGUAdwBHAHUAaQBkACgAKQAuAFQAbwBTAHQAcgBpAG4AZwAoACcATgAnACkAKQAKAEUAeABwAGEAbgBkAC0AQQByAGMAaABpAHYAZQAgAC0ATABpAHQAZQByAGEAbABQAGEAdABoACAAJAB6AGkAcAAuAEYAdQBsAGwATgBhAG0AZQAgAC0ARABlAHMAdABpAG4AYQB0AGkAbwBuAFAAYQB0AGgAIAAkAG8AdQB0AAoAJgAgAHAAbwB3AGUAcgBzAGgAZQBsAGwALgBlAHgAZQAgAC0ATgBvAFAAcgBvAGYAaQBsAGUAIAAtAEUAeABlAGMAdQB0AGkAbwBuAFAAbwBsAGkAYwB5ACAAQgB5AHAAYQBzAHMAIAAtAEYAaQBsAGUAIAAoAEoAbwBpAG4ALQBQAGEAdABoACAAJABvAHUAdAAgACcAbQBvAGQAcwBcAGQAYQByAGsAdABpAGQAZQB2AHIAXABkAGEAcgBrAHQAaQBkAGUAdgByAC0AaQBuAHMAdABhAGwAbAAuAHAAcwAxACcAKQAKACQAYwBvAGQAZQAgAD0AIAAkAEwAQQBTAFQARQBYAEkAVABDAE8ARABFAAoAUgBlAG0AbwB2AGUALQBJAHQAZQBtACAALQBMAGkAdABlAHIAYQBsAFAAYQB0AGgAIAAkAG8AdQB0ACAALQBSAGUAYwB1AHIAcwBlACAALQBGAG8AcgBjAGUAIAAtAEUAcgByAG8AcgBBAGMAdABpAG8AbgAgAFMAaQBsAGUAbgB0AGwAeQBDAG8AbgB0AGkAbgB1AGUACgBlAHgAaQB0ACAAJABjAG8AZABlAA==
    if errorlevel 2 (
        echo.
        echo This file was run without the rest of the mod beside it, most likely
        echo straight from inside the zip, and the zip could not be found.
        echo.
        echo Extract the whole archive ^(right-click it, Extract All^), then run
        echo mods\darktidevr\Darktide VR Mode.bat from the extracted folder.
    )
    goto :end
)
rem Extracted anywhere but the game folder: install into the game.
if not exist "%~dp0..\..\binaries\Darktide.exe" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0darktidevr-install.ps1"
    if errorlevel 1 (
        echo.
        echo The install did not complete. Read the message above.
    )
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
