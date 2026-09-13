# Converts a viewer eye readback (binary PPM, P6) to PNG, optionally cropped
# to a centred region (fractions of the image) and scaled, for reviewing
# world-space drawing without a headset. See the viewer's
# %TEMP%\darktidevr-shared-eye-readback.request.
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Path,
    [Parameter(Mandatory)] [string] $OutputPath,
    [ValidateRange(0.05, 1.0)] [double] $CropFraction = 1.0,
    [ValidateRange(0.1, 2.0)] [double] $Scale = 0.5,
    # Optional pixel rectangle x,y,width,height; overrides CropFraction.
    [string] $Region = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path)
$pos = 0
$tokens = New-Object System.Collections.Generic.List[string]
while ($tokens.Count -lt 4) {
    while ([char]::IsWhiteSpace([char]$bytes[$pos])) { $pos++ }
    if ([char]$bytes[$pos] -eq '#') { while ($bytes[$pos] -ne 10) { $pos++ }; continue }
    $start = $pos
    while (-not [char]::IsWhiteSpace([char]$bytes[$pos])) { $pos++ }
    $tokens.Add([Text.Encoding]::ASCII.GetString($bytes, $start, $pos - $start))
}
$pos++
if ($tokens[0] -ne 'P6') { throw "Not a binary PPM: $($tokens[0])" }
$width = [int]$tokens[1]; $height = [int]$tokens[2]
$cropW = [int]($width * $CropFraction); $cropH = [int]($height * $CropFraction)
$x0 = [int](($width - $cropW) / 2); $y0 = [int](($height - $cropH) / 2)
$regionValues = @($Region -split ',' | Where-Object { $_ -ne '' } | ForEach-Object { [int]$_ })
if ($regionValues.Count -eq 4) {
    $Region = $null
    $x0 = [Math]::Max(0, [Math]::Min($regionValues[0], $width - 1)); $y0 = [Math]::Max(0, [Math]::Min($regionValues[1], $height - 1))
    $cropW = [Math]::Min($regionValues[2], $width - $x0); $cropH = [Math]::Min($regionValues[3], $height - $y0)
}
$bitmap = New-Object System.Drawing.Bitmap $cropW, $cropH, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$data = $bitmap.LockBits((New-Object System.Drawing.Rectangle 0, 0, $cropW, $cropH),
    [System.Drawing.Imaging.ImageLockMode]::WriteOnly, $bitmap.PixelFormat)
$row = New-Object byte[] $data.Stride
for ($y = 0; $y -lt $cropH; $y++) {
    $offset = $pos + (($y0 + $y) * $width + $x0) * 3
    for ($x = 0; $x -lt $cropW; $x++) {
        $i = $offset + $x * 3
        $row[$x * 3] = $bytes[$i + 2]; $row[$x * 3 + 1] = $bytes[$i + 1]; $row[$x * 3 + 2] = $bytes[$i]
    }
    [Runtime.InteropServices.Marshal]::Copy($row, 0, [IntPtr]($data.Scan0.ToInt64() + $y * $data.Stride), $data.Stride)
}
$bitmap.UnlockBits($data)
$scaled = New-Object System.Drawing.Bitmap $bitmap, ([int]($cropW * $Scale)), ([int]($cropH * $Scale))
$scaled.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose(); $scaled.Dispose()
Write-Output "source=${width}x${height} crop=${cropW}x${cropH} output=$OutputPath"
