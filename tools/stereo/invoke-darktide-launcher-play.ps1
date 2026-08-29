[CmdletBinding()]
param(
    [ValidateRange(5, 1800)]
    [int] $TimeoutSeconds = 120,

    [string] $GameRoot =
        'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$launcherPath = Join-Path $GameRoot 'launcher\Launcher.exe'
if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
    throw "Fatshark launcher not found: $launcherPath"
}
$launcherPath = (Resolve-Path -LiteralPath $launcherPath).Path
if (Get-Process Darktide -ErrorAction SilentlyContinue) {
    throw 'Darktide is already running; refusing to press launcher Play.'
}

if ($null -eq ('DarktideVrLauncherInput' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class DarktideVrLauncherInput
{
    [StructLayout(LayoutKind.Sequential)]
    public struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct Point
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetClientRect(IntPtr window, out Rect rect);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr window);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool ClientToScreen(IntPtr window, ref Point point);

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out Point point);

    [DllImport("user32.dll")]
    private static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    private static extern void mouse_event(
        uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);

    public static int[] GetClientSize(IntPtr window)
    {
        Rect rect;
        if (!GetClientRect(window, out rect))
        {
            throw new System.ComponentModel.Win32Exception(
                Marshal.GetLastWin32Error(), "GetClientRect failed");
        }
        return new[] { rect.Right - rect.Left, rect.Bottom - rect.Top };
    }

    public static void ClickClient(IntPtr window, int x, int y)
    {
        const uint MouseEventLeftDown = 0x0002;
        const uint MouseEventLeftUp = 0x0004;
        Point original;
        if (!GetCursorPos(out original))
        {
            throw new System.ComponentModel.Win32Exception(
                Marshal.GetLastWin32Error(), "GetCursorPos failed");
        }
        var target = new Point { X = x, Y = y };
        if (!ClientToScreen(window, ref target))
        {
            throw new System.ComponentModel.Win32Exception(
                Marshal.GetLastWin32Error(), "ClientToScreen failed");
        }
        try
        {
            if (!SetForegroundWindow(window))
            {
                throw new InvalidOperationException(
                    "Could not foreground the Fatshark launcher");
            }
            System.Threading.Thread.Sleep(50);
            if (!SetCursorPos(target.X, target.Y))
            {
                throw new System.ComponentModel.Win32Exception(
                    Marshal.GetLastWin32Error(), "SetCursorPos failed");
            }
            mouse_event(MouseEventLeftDown, 0, 0, 0, UIntPtr.Zero);
            mouse_event(MouseEventLeftUp, 0, 0, 0, UIntPtr.Zero);
        }
        finally
        {
            SetCursorPos(original.X, original.Y);
        }
    }
}
'@
}

function Get-ExactLauncherProcess {
    $matches = @(Get-Process Launcher -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $_.Path -eq $launcherPath
            }
            catch {
                $false
            }
        })
    if ($matches.Count -gt 1) {
        throw "Expected one Darktide launcher, found $($matches.Count)."
    }
    if ($matches.Count -eq 1) {
        return $matches[0]
    }
    return $null
}

$started = Get-Date
$deadline = $started.AddSeconds($TimeoutSeconds)
$launcher = $null
while ((Get-Date) -lt $deadline) {
    $launcher = Get-ExactLauncherProcess
    if ($launcher) {
        $launcher.Refresh()
        if ($launcher.MainWindowHandle -ne [IntPtr]::Zero) {
            break
        }
    }
    Start-Sleep -Milliseconds 100
}
if (-not $launcher -or $launcher.MainWindowHandle -eq [IntPtr]::Zero) {
    throw "Timed out waiting for the Darktide launcher window after $TimeoutSeconds seconds."
}
if ($launcher.MainWindowTitle -ne 'Launcher') {
    throw "Unexpected Fatshark launcher title: '$($launcher.MainWindowTitle)'"
}

# The current Fatshark launcher exposes no external UI Automation tree. Its
# native WPF Play button occupies this stable normalized region in the fixed-
# aspect launcher client. Validate the exact process, title and geometry before
# issuing a client-relative click. The helper restores the original cursor
# immediately; it never retains or guesses a global screen coordinate.
$size = [DarktideVrLauncherInput]::GetClientSize(
    $launcher.MainWindowHandle)
$width = $size[0]
$height = $size[1]
$aspect = $width / [double] $height
if ($width -lt 1000 -or $height -lt 600 -or
        $aspect -lt 1.55 -or $aspect -gt 1.67) {
    throw "Unexpected launcher client geometry: ${width}x${height} (aspect $aspect)."
}
$playX = [int] [Math]::Round($width * 0.818)
$playY = [int] [Math]::Round($height * 0.870)
[DarktideVrLauncherInput]::ClickClient(
    $launcher.MainWindowHandle, $playX, $playY)
Write-Output "Invoked Fatshark launcher Play at client ${playX},${playY} in ${width}x${height}."

# Confirm the launch action rather than treating a successfully queued mouse
# message as proof. The XR wrapper starts only after a new game process exists.
while ((Get-Date) -lt $deadline) {
    $game = Get-Process Darktide -ErrorAction SilentlyContinue |
        Where-Object StartTime -ge $started |
        Select-Object -First 1
    if ($game) {
        Write-Output "Authenticated Darktide process started: PID $($game.Id)."
        exit 0
    }
    Start-Sleep -Milliseconds 100
}
throw "Launcher Play was invoked, but Darktide did not start within $TimeoutSeconds seconds."
