[CmdletBinding(DefaultParameterSetName = 'ByName')]
param(
    [Parameter(Mandatory, ParameterSetName = 'ById')]
    [ValidateRange(1, [int]::MaxValue)]
    [int] $ProcessId,

    [Parameter(Mandatory, ParameterSetName = 'ByName')]
    [ValidateNotNullOrEmpty()]
    [string] $ProcessName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ('DarktideVr.WaitChain.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace DarktideVr.WaitChain {
  public static class Native {
    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern IntPtr OpenThreadWaitChainSession(
        uint flags, IntPtr callback);

    [DllImport("advapi32.dll")]
    public static extern void CloseThreadWaitChainSession(IntPtr session);

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetThreadWaitChain(
        IntPtr session, IntPtr context, uint flags, uint threadId,
        ref uint nodeCount, IntPtr nodes,
        [MarshalAs(UnmanagedType.Bool)] out bool cycle);
  }
}
'@
}

$process = if ($PSCmdlet.ParameterSetName -eq 'ById') {
    Get-Process -Id $ProcessId -ErrorAction Stop
}
else {
    $matches = @(Get-Process -Name $ProcessName -ErrorAction Stop)
    if ($matches.Count -ne 1) {
        throw "Expected exactly one '$ProcessName' process; found $($matches.Count)."
    }
    $matches[0]
}

# WAITCHAIN_NODE_INFO is 280 bytes on 64-bit Windows. Read the discriminated
# union manually so managed reference fields never overlap its native thread
# fields. WCTP_GETINFO_ALL_FLAGS requests COM, critical-section and network
# dependencies as well as ordinary thread/process waits.
$nodeSize = 280
$maximumNodes = 16
$buffer = [Runtime.InteropServices.Marshal]::AllocHGlobal(
    $nodeSize * $maximumNodes)
$session = [DarktideVr.WaitChain.Native]::OpenThreadWaitChainSession(
    0, [IntPtr]::Zero)
if ($session -eq [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)
    throw "OpenThreadWaitChainSession failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
}

$typeNames = @(
    'CriticalSection', 'SendMessage', 'Mutex', 'Alpc', 'Com', 'ThreadWait',
    'ProcessWait', 'Thread', 'ComActivation', 'Unknown', 'SocketIo', 'SmbIo')
$statusNames = @(
    'NoAccess', 'Running', 'Blocked', 'PidOnly', 'PidOnlyRpcss', 'Owned',
    'NotOwned', 'Abandoned', 'Unknown', 'Error')

try {
    foreach ($thread in $process.Threads) {
        for ($offset = 0; $offset -lt $nodeSize * $maximumNodes;
                $offset += 4) {
            [Runtime.InteropServices.Marshal]::WriteInt32($buffer, $offset, 0)
        }
        [uint32] $nodeCount = $maximumNodes
        $cycle = $false
        $ok = [DarktideVr.WaitChain.Native]::GetThreadWaitChain(
            $session,
            [IntPtr]::Zero,
            9,
            [uint32] $thread.Id,
            [ref] $nodeCount,
            $buffer,
            [ref] $cycle)
        if (-not $ok) {
            [pscustomobject]@{
                ProcessId = $process.Id
                RootThreadId = $thread.Id
                NodeIndex = -1
                ObjectType = 'QueryError'
                ObjectStatus =
                    [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                BlockingProcessId = 0
                BlockingThreadId = 0
                ObjectName = ''
                Cycle = $false
            }
            continue
        }
        for ($index = 0; $index -lt $nodeCount; $index++) {
            $node = [IntPtr]::Add($buffer, $index * $nodeSize)
            $objectType = [Runtime.InteropServices.Marshal]::ReadInt32($node, 0)
            $objectStatus =
                [Runtime.InteropServices.Marshal]::ReadInt32($node, 4)
            $threadNode = $objectType -eq 8
            [pscustomobject]@{
                ProcessId = $process.Id
                RootThreadId = $thread.Id
                NodeIndex = $index
                ObjectType = if ($objectType -ge 1 -and
                        $objectType -le $typeNames.Count) {
                    $typeNames[$objectType - 1]
                }
                else {
                    "Type$objectType"
                }
                ObjectStatus = if ($objectStatus -ge 1 -and
                        $objectStatus -le $statusNames.Count) {
                    $statusNames[$objectStatus - 1]
                }
                else {
                    "Status$objectStatus"
                }
                BlockingProcessId = if ($threadNode) {
                    [uint32] [Runtime.InteropServices.Marshal]::ReadInt32(
                        $node, 8)
                }
                else { 0 }
                BlockingThreadId = if ($threadNode) {
                    [uint32] [Runtime.InteropServices.Marshal]::ReadInt32(
                        $node, 12)
                }
                else { 0 }
                ObjectName = if ($threadNode) {
                    ''
                }
                else {
                    [Runtime.InteropServices.Marshal]::PtrToStringUni(
                        [IntPtr]::Add($node, 8), 128).Trim([char] 0)
                }
                Cycle = $cycle
            }
        }
    }
}
finally {
    [DarktideVr.WaitChain.Native]::CloseThreadWaitChainSession($session)
    [Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)
}
