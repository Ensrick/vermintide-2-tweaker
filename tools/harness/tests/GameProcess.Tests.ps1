#requires -Version 7
<#
.SYNOPSIS
  Offline test of tools/harness/GameProcess.cs (no game): starts cmd.exe on a private desktop with two
  child-only environment variables and checks exit code, windows and the parent environment. WP-H-10: the PNG
  writer on known pixels, and a still request against a console process (no game window).

.DESCRIPTION
  The child runs  cmd.exe /c <check both variables> exit 7 , so exit code 7 proves the child saw both
  child-only variables. Asserts: exit code 7, the desktop name is a private Vt2Rig-* desktop, no window of the
  job reached the user's desktop while it ran, and the parent's process and user environment are unchanged.
  Exit codes: 0 pass, 2 failure.
#>
[CmdletBinding()]
param([switch] $Quiet)
$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool] $condition, [string] $label) {
    if ($condition) { if (-not $Quiet) { Write-Host "  [PASS] $label" } }
    else { $failures.Add($label); Write-Host "  [FAIL] $label" -ForegroundColor Red }
}
function Get-EnvSnapshot {
    $map = [System.Collections.Generic.SortedDictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($e in [System.Environment]::GetEnvironmentVariables().GetEnumerator()) { $map[[string]$e.Key] = [string]$e.Value }
    ($map.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n"
}

$source = Join-Path (Split-Path $PSScriptRoot) 'GameProcess.cs'
if (-not ('Vt2GameProcess' -as [type])) { Add-Type -Path $source }

$names = 'VT2_RIG_TEST_ALPHA', 'VT2_RIG_TEST_BETA'
foreach ($n in $names) {
    if ([System.Environment]::GetEnvironmentVariable($n)) { Write-Host "[GameProcess.Tests] ERROR -- $n is already set in the parent." -ForegroundColor Red; exit 2 }
}
$userBefore = @{}; foreach ($n in $names) { $userBefore[$n] = [System.Environment]::GetEnvironmentVariable($n, 'User') }
$parentBefore = Get-EnvSnapshot

$cmd = Join-Path ([System.Environment]::SystemDirectory) 'cmd.exe'
$arguments = '/c if "%VT2_RIG_TEST_ALPHA%"=="alpha" if "%VT2_RIG_TEST_BETA%"=="beta" exit 7'
$childEnv = @{ VT2_RIG_TEST_ALPHA = 'alpha'; VT2_RIG_TEST_BETA = 'beta' }
$windows = [System.Collections.Generic.List[string]]::new()
$proc = $null
try {
    $proc = [Vt2GameProcess]::Start($cmd, $arguments, ([System.Environment]::SystemDirectory), $childEnv, $true)
    Assert-True ($proc.DesktopName -like 'Vt2Rig-*') "child runs on a private desktop ($($proc.DesktopName))"
    $deadline = (Get-Date).AddSeconds(30)
    while (-not $proc.WaitForExit(50)) {
        foreach ($w in $proc.WindowsOnUserDesktop()) { $windows.Add($w) }
        if ((Get-Date) -ge $deadline) { $proc.Kill(); break }
    }
    foreach ($w in $proc.WindowsOnUserDesktop()) { $windows.Add($w) }
    $code = $proc.ExitCode
    Assert-True ($code -eq 7) "exit code is 7, so the child saw both child-only variables (got $code)"
    Assert-True ($windows.Count -eq 0) "no window on the user desktop ($($windows -join '; '))"
}
finally {
    if ($proc) { $proc.Dispose() }
}

Assert-True ((Get-EnvSnapshot) -ceq $parentBefore) 'parent process environment unchanged'
foreach ($n in $names) {
    Assert-True ($null -eq [System.Environment]::GetEnvironmentVariable($n)) "$n absent from the parent"
    Assert-True ([System.Environment]::GetEnvironmentVariable($n, 'User') -eq $userBefore[$n]) "$n not written to the user environment"
}

# ---- WP-H-10: the PNG writer on known pixels, and a still request against a process with no game window ----
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('vt2-rig-still-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    # 3 x 2 top-down BGRA: red, green, blue / white, black, grey (128)
    $bgra = [byte[]]@(0, 0, 255, 255, 0, 255, 0, 255, 255, 0, 0, 255, 255, 255, 255, 255, 0, 0, 0, 255, 128, 128, 128, 255)
    $still = [Vt2Still]::new()
    $png = Join-Path $tmp 'known.png'
    [Vt2Png]::Write($png, $bgra, 3, 2, $still)
    $bytes = [System.IO.File]::ReadAllBytes($png)
    Assert-True ($still.Ok -and $still.Width -eq 3 -and $still.Height -eq 2) 'PNG writer: size recorded'
    Assert-True ((@($bytes[0..7]) -join ',') -eq '137,80,78,71,13,10,26,10') 'PNG writer: PNG signature'
    function Get-BE([byte[]] $b, [int] $o) { ([long]$b[$o] -shl 24) -bor ([long]$b[$o + 1] -shl 16) -bor ([long]$b[$o + 2] -shl 8) -bor [long]$b[$o + 3] }
    Assert-True ([System.Text.Encoding]::ASCII.GetString($bytes, 12, 4) -eq 'IHDR' -and (Get-BE $bytes 16) -eq 3 -and (Get-BE $bytes 20) -eq 2 -and $bytes[24] -eq 8 -and $bytes[25] -eq 2) 'PNG writer: IHDR says 3x2, 8-bit RGB'
    $idatLen = [int](Get-BE $bytes 33)
    Assert-True ([System.Text.Encoding]::ASCII.GetString($bytes, 37, 4) -eq 'IDAT') 'PNG writer: IDAT follows IHDR'
    $ms = [System.IO.MemoryStream]::new($bytes, 41, $idatLen)
    $z = [System.IO.Compression.ZLibStream]::new($ms, [System.IO.Compression.CompressionMode]::Decompress)
    $out = [System.IO.MemoryStream]::new(); $z.CopyTo($out); $z.Dispose()
    $raw = $out.ToArray()
    Assert-True (($raw -join ',') -eq '0,255,0,0,0,255,0,0,0,255,0,255,255,255,0,0,0,128,128,128') "PNG writer: filter byte 0 and RGB rows in order ($($raw -join ','))"
    $want = ((0.299 * 255) + (0.587 * 255) + (0.114 * 255) + 255 + 0 + 128) / 6
    Assert-True ([math]::Abs($still.MeanBrightness - $want) -lt 0.01) "PNG writer: mean brightness ($([math]::Round($still.MeanBrightness, 2)), want $([math]::Round($want, 2)))"
    Assert-True ([System.Text.Encoding]::ASCII.GetString($bytes, $bytes.Length - 8, 4) -eq 'IEND') 'PNG writer: IEND last'
    function Get-Crc32([byte[]] $b, [int] $o, [int] $n) {
        [long]$c = 4294967295
        for ($i = $o; $i -lt $o + $n; $i++) { $c = $c -bxor [long]$b[$i]; for ($k = 0; $k -lt 8; $k++) { if ($c -band 1) { $c = 3988292384 -bxor ($c -shr 1) } else { $c = $c -shr 1 } } }
        $c -bxor 4294967295
    }
    $crcOk = $true; $pos = 8
    while ($pos -lt $bytes.Length) { $len = [int](Get-BE $bytes $pos); if ((Get-Crc32 $bytes ($pos + 4) ($len + 4)) -ne (Get-BE $bytes ($pos + 8 + $len))) { $crcOk = $false }; $pos += 12 + $len }
    Assert-True ($crcOk -and $pos -eq $bytes.Length) 'PNG writer: every chunk CRC is right'

    # a still of a console process on a private desktop: no game window, so a clean "not captured", never an exception
    $p2 = [Vt2GameProcess]::Start($cmd, '/c ping -n 3 127.0.0.1 >nul', ([System.Environment]::SystemDirectory), @{}, $true)
    try {
        Start-Sleep -Milliseconds 500
        $s2 = $p2.CaptureStill((Join-Path $tmp 'console.png'))
        Assert-True ($null -ne $s2 -and ($s2.Ok -or $s2.Error)) "CaptureStill on a private desktop returns a result (ok=$($s2.Ok) error=$($s2.Error) window=$($s2.Window))"
        Assert-True ($s2.Ok -or -not (Test-Path -LiteralPath (Join-Path $tmp 'console.png'))) 'no file is written when nothing was captured'
        Assert-True (@($p2.WindowsOnUserDesktop()).Count -eq 0) 'the capture brought no window to the user desktop'
        [void]$p2.WaitForExit(10000)
    }
    finally { $p2.Dispose() }
}
finally { Remove-Item -LiteralPath $tmp -Recurse -Force }

if ($failures.Count) { Write-Host "[GameProcess.Tests] FAILED -- $($failures.Count) assertion(s)." -ForegroundColor Red; exit 2 }
Write-Host '[GameProcess.Tests] OK -- private desktop, child-only environment, exit code, window checks, PNG writer and still capture passed.'
exit 0
