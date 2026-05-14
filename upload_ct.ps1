# upload_ct.ps1 — upload Chaos Wastes Tweaker to Steam Workshop.
#
# Direct ugc_tool invocation with the mod's own itemV2.cfg.
#
# Per the user's memory `reference_vmblauncher_headless.md`, the canonical
# launcher (`tools/vmb-launcher/bin/.../VMBLauncher.exe`) is the source of truth
# for build / deploy / list / info / doctor. But its `upload` verb currently
# stages but doesn't reliably transfer for established Workshop mods — verified
# 2026-05-14: `vmblauncher upload <established-mod>` reports "Upload finished"
# while Workshop file_size doesn't change. Until that's fixed, this wrapper
# uses the direct-call pattern that does transfer.
#
# ct is the only Tweaker mod whose intended visibility is "public". The script
# aborts if cfg drifted away from visibility="public" (catches accidental
# regressions before they hit Workshop).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$modName = 'chaos_wastes_tweaker'
$modDir = Join-Path $root $modName
$cfgPath = Join-Path $modDir 'itemV2.cfg'
$bundleDir = Join-Path $modDir 'bundleV2'
$sdk = 'C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK'
$tool = Join-Path $sdk 'ugc_uploader\ugc_tool.exe'

if (-not (Test-Path $cfgPath))   { throw "itemV2.cfg not found at $cfgPath" }
if (-not (Test-Path $tool))      { throw "ugc_tool.exe not found at $tool" }
if (-not (Test-Path $bundleDir)) { throw "bundleV2/ not found at $bundleDir - run VMB build first" }
$bundleFiles = @(Get-ChildItem $bundleDir -File -Filter '*.mod_bundle' -ErrorAction SilentlyContinue)
if ($bundleFiles.Count -eq 0)    { throw "No .mod_bundle files in $bundleDir - build did not produce output" }

# Read cfg with explicit UTF-8 — PS 5.1's Get-Content -Raw uses the system code
# page (Win-1252) and silently mangles multi-byte chars on write-back. We don't
# write-back here, only inspect, but use the right primitive anyway.
$cfgRaw = [System.IO.File]::ReadAllText($cfgPath, [System.Text.Encoding]::UTF8)
function Get-CfgString {
    param([string]$key)
    $regex = [regex]"$([regex]::Escape($key))\s*=\s*`"((?:[^`"\\]|\\.)*)`""
    $m = $regex.Match($cfgRaw)
    if ($m.Success) { return $m.Groups[1].Value -replace '\\n',"`n" -replace '\\"','"' -replace '\\\\','\' }
    return $null
}
$visibility = Get-CfgString 'visibility'
$title      = Get-CfgString 'title'
if ($cfgRaw -match 'published_id\s*=\s*(\d+)L?') { $publishedId = $matches[1] } else { $publishedId = '0' }

if ($visibility -ne 'public') {
    throw "itemV2.cfg has visibility='$visibility' but ct must be 'public'. Aborting to prevent accidental visibility regression."
}

Write-Host "[upload] $modName  visibility=$visibility  published_id=$publishedId  title=$title" -ForegroundColor Cyan

# ugc_tool needs the EULA "Y" piped on stdin. Native PowerShell stdin piping is
# rejected by ugc_tool, cmd's `echo y|` passes EULA but fails content with 0x2,
# so use Git Bash's pipe semantics which work for both phases.
$gitBash = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path $gitBash)) { $gitBash = 'bash' }
$toolFwd = ($tool -replace '\\','/').Replace(' ','\ ')
$cfgFwd  = ($cfgPath -replace '\\','/').Replace(' ','\ ')
$bashCmd = "echo y | $toolFwd -c $cfgFwd -x"

$stdoutLog = Join-Path $env:TEMP "ugc_ct_stdout_$([System.IO.Path]::GetRandomFileName()).log"
$stderrLog = Join-Path $env:TEMP "ugc_ct_stderr_$([System.IO.Path]::GetRandomFileName()).log"
$proc = Start-Process -FilePath $gitBash -ArgumentList @('-c', $bashCmd) -NoNewWindow -PassThru -Wait `
    -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
$stdoutText = if (Test-Path $stdoutLog) { Get-Content $stdoutLog -Raw -ErrorAction SilentlyContinue } else { '' }
$stderrText = if (Test-Path $stderrLog) { Get-Content $stderrLog -Raw -ErrorAction SilentlyContinue } else { '' }
Remove-Item -LiteralPath $stdoutLog,$stderrLog -ErrorAction SilentlyContinue
if ($stdoutText) { Write-Host '[ugc_tool stdout]' -ForegroundColor DarkGray; Write-Host $stdoutText }
if ($stderrText) { Write-Host '[ugc_tool stderr]' -ForegroundColor DarkYellow; Write-Host $stderrText }
if ($proc.ExitCode -ne 0) { throw "ugc_tool exited with code $($proc.ExitCode)" }
if ($stdoutText -match '\[ERROR\]|Upload [Ff]ailed|0x[0-9A-Fa-f]+\)') {
    throw "ugc_tool reported an error in its output (exit code 0 was misleading): $($matches[0])"
}

# Cross-check transfer via Steam Web API. ugc_tool's "Upload finished" message
# does not confirm transfer — file_size / time_updated from
# GetPublishedFileDetails is the authoritative signal.
if ($publishedId -ne '0') {
    try {
        $api = Invoke-RestMethod -Method Post -Uri 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/' `
            -Body @{ itemcount = 1; 'publishedfileids[0]' = $publishedId } -TimeoutSec 30
        $d = $api.response.publishedfiledetails[0]
        Write-Host ('[verify] live: title="{0}" visibility={1} file_size={2} time_updated={3}' -f `
            $d.title, $d.visibility, $d.file_size, $d.time_updated) -ForegroundColor Green
    } catch {
        Write-Host "[verify] Steam Web API verify failed: $_" -ForegroundColor Yellow
    }
}
