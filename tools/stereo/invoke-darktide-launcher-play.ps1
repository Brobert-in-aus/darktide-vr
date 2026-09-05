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
$gamePath = Join-Path $GameRoot 'binaries\Darktide.exe'
if (-not (Test-Path -LiteralPath $gamePath -PathType Leaf)) {
    throw "Darktide executable not found: $gamePath"
}
$gamePath = (Resolve-Path -LiteralPath $gamePath).Path
if (Get-Process Darktide -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $_.Path -ieq $gamePath
            }
            catch {
                $false
            }
        }) {
    throw 'Darktide is already running; refusing to press launcher Play.'
}

if ($null -eq ('DarktideVrLauncherInput' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Text;
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

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(
        IntPtr window, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(
        IntPtr window, StringBuilder text, int maxCount);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    private static extern bool AttachThreadInput(
        uint attach, uint attachTo, bool value);

    [DllImport("user32.dll")]
    private static extern bool ShowWindowAsync(IntPtr window, int command);

    [DllImport("user32.dll")]
    private static extern bool BringWindowToTop(IntPtr window);

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

    public static bool IsOwnedWindow(
        IntPtr window, uint expectedProcessId, string expectedTitle)
    {
        uint processId;
        if (window == IntPtr.Zero ||
            GetWindowThreadProcessId(window, out processId) == 0 ||
            processId != expectedProcessId)
            return false;
        var title = new StringBuilder(256);
        GetWindowText(window, title, title.Capacity);
        return title.ToString() == expectedTitle;
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
            var foreground = GetForegroundWindow();
            var currentThread = GetCurrentThreadId();
            uint ignored;
            var foregroundThread = foreground == IntPtr.Zero
                ? 0 : GetWindowThreadProcessId(foreground, out ignored);
            var targetThread = GetWindowThreadProcessId(window, out ignored);
            var attachedForeground = foregroundThread != 0 &&
                foregroundThread != currentThread &&
                AttachThreadInput(currentThread, foregroundThread, true);
            var attachedTarget = targetThread != 0 &&
                targetThread != currentThread &&
                targetThread != foregroundThread &&
                AttachThreadInput(currentThread, targetThread, true);
            try
            {
                ShowWindowAsync(window, 9); // SW_RESTORE
                BringWindowToTop(window);
                SetForegroundWindow(window);
            }
            finally
            {
                if (attachedTarget)
                    AttachThreadInput(currentThread, targetThread, false);
                if (attachedForeground)
                    AttachThreadInput(currentThread, foregroundThread, false);
            }
            System.Threading.Thread.Sleep(50);
            if (GetForegroundWindow() != window)
            {
                throw new InvalidOperationException(
                    "Could not foreground the Fatshark launcher");
            }
            if (!SetCursorPos(target.X, target.Y))
            {
                throw new System.ComponentModel.Win32Exception(
                    Marshal.GetLastWin32Error(), "SetCursorPos failed");
            }
            mouse_event(MouseEventLeftDown, 0, 0, 0, UIntPtr.Zero);
            // WebView2 dispatches the WPF-hosted button asynchronously. A
            // zero-duration down/up followed by an immediate cursor restore
            // can deliver hover-leave before the web control accepts click.
            System.Threading.Thread.Sleep(100);
            mouse_event(MouseEventLeftUp, 0, 0, 0, UIntPtr.Zero);
            System.Threading.Thread.Sleep(150);
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
                -not $_.HasExited -and $_.Path -eq $launcherPath
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

function Get-StartedDarktideProcess {
    Get-Process Darktide -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $_.StartTime -ge $started -and $_.Path -ieq $gamePath
            }
            catch {
                $false
            }
        } |
        Select-Object -First 1
}

function Invoke-ConfirmedLauncherClick {
    param(
        [IntPtr] $Window,
        [int] $X,
        [int] $Y
    )

    # A manual Play press or a retained launcher request can start the game
    # between our window check and foreground activation. In that case the
    # disappearing launcher is a successful transition, not a launch failure.
    $game = Get-StartedDarktideProcess
    if ($game) {
        return $game
    }
    try {
        [DarktideVrLauncherInput]::ClickClient($Window, $X, $Y)
    }
    catch {
        $clickError = $_
        $transitionDeadline = (Get-Date).AddSeconds(5)
        if ($transitionDeadline -gt $deadline) {
            $transitionDeadline = $deadline
        }
        do {
            $game = Get-StartedDarktideProcess
            if ($game) {
                return $game
            }
            if ((Get-Date) -ge $transitionDeadline) {
                break
            }
            Start-Sleep -Milliseconds 100
        } while ($true)
        # Preserve the original failure when no new authenticated game exists.
        # Never send an unverified click to whichever app acquired focus.
        throw $clickError
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

# The native WPF window becomes targetable several seconds before its WebView2
# document reports OnLauncherReady. Clicking during that gap is silently
# discarded even though foregrounding and mouse injection both succeed.
# Allow the embedded document to finish initialization before resolving and
# activating its stable Play region.
Start-Sleep -Seconds 6
$launcher.Refresh()
if ($launcher.HasExited -or
        $launcher.MainWindowHandle -eq [IntPtr]::Zero -or
        $launcher.MainWindowTitle -ne 'Launcher') {
    # Steam/Fatshark can consume a retained launch request and close the
    # launcher before its WebView Play control reaches our readiness delay.
    # That is a successful authenticated launch, not an XR failure. Confirm a
    # new game process before accepting it; otherwise retain the fail-closed
    # behavior for a genuinely vanished launcher.
    while ((Get-Date) -lt $deadline) {
        $game = Get-Process Darktide -ErrorAction SilentlyContinue |
            Where-Object {
                try {
                    $_.StartTime -ge $started -and $_.Path -ieq $gamePath
                }
                catch {
                    $false
                }
            } |
            Select-Object -First 1
        if ($game) {
            Write-Output "Authenticated Darktide process started during launcher transition: PID $($game.Id)."
            exit 0
        }
        Start-Sleep -Milliseconds 100
    }
    throw 'Fatshark launcher changed state and no authenticated Darktide process appeared.'
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
$launchWindowHandle = $launcher.MainWindowHandle
$transitionGame = Invoke-ConfirmedLauncherClick `
    -Window $launchWindowHandle -X $playX -Y $playY
if ($transitionGame) {
    Write-Output "Authenticated Darktide process started during Play activation: PID $($transitionGame.Id)."
    exit 0
}
Write-Output "Invoked Fatshark launcher Play at client ${playX},${playY} in ${width}x${height}."

# Confirm the launch action rather than treating a successfully queued mouse
# message as proof. WebView2 can acknowledge the first press by moving focus
# while its launch handler is still settling, leaving the authenticated window
# alive without starting the game. Retry the same verified Play region at a
# bounded interval; retain the original window handle because WPF may promote
# a tiny auxiliary window to Process.MainWindowHandle after the first press.
# The XR wrapper starts only after a new game process exists.
$nextPlayRetry = (Get-Date).AddSeconds(3)
$playRetries = 0
while ((Get-Date) -lt $deadline) {
    $game = Get-Process Darktide -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $_.StartTime -ge $started -and $_.Path -ieq $gamePath
            }
            catch {
                $false
            }
        } |
        Select-Object -First 1
    if ($game) {
        Write-Output "Authenticated Darktide process started: PID $($game.Id)."
        exit 0
    }
    if ((Get-Date) -ge $nextPlayRetry) {
        if (-not [DarktideVrLauncherInput]::IsOwnedWindow(
                $launchWindowHandle, [uint32] $launcher.Id, 'Launcher')) {
            throw 'Fatshark launcher Play window changed identity before the game started.'
        }
        $retrySize = [DarktideVrLauncherInput]::GetClientSize(
            $launchWindowHandle)
        if ($retrySize[0] -ne $width -or $retrySize[1] -ne $height) {
            throw "Fatshark launcher Play window geometry changed from ${width}x${height} to $($retrySize[0])x$($retrySize[1])."
        }
        $transitionGame = Invoke-ConfirmedLauncherClick `
            -Window $launchWindowHandle -X $playX -Y $playY
        if ($transitionGame) {
            Write-Output "Authenticated Darktide process started during Play retry: PID $($transitionGame.Id)."
            exit 0
        }
        $playRetries++
        Write-Output "Retried Fatshark launcher Play ($playRetries)."
        $nextPlayRetry = (Get-Date).AddSeconds(3)
    }
    Start-Sleep -Milliseconds 100
}
throw "Launcher Play was invoked, but Darktide did not start within $TimeoutSeconds seconds."
