# upload_ct.ps1 - Upload Chaos Wastes Tweaker to Steam Workshop.
#
# ct is the only Tweaker mod whose intended visibility is "public". The script
# aborts if cfg drifted away from visibility="public" (catches accidental
# private->public or public->private edits before they hit Workshop).
#
# Calls ugc_tool DIRECTLY with the mod's own itemV2.cfg (which has
# content="bundleV2"). The staging helper at _upload_helper.ps1 mirrors the
# vmb-launcher staging pipeline but doesn't successfully transfer for at least
# this published-id mod in this environment — verified 2026-05-14: helper runs
# report "Upload finished" but Workshop file_size doesn't change. Suspect: when
# cwd=<uploader>/ and cfg's content="content", ugc_tool resolves to
# <uploader>/content/ (empty) instead of <uploader>/sample_item/content/.
# Direct call sidesteps the issue. See feedback_ugc_tool_direct_call_for_established.md.
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

# Sanity-check cfg fields before letting ugc_tool overwrite the live Workshop entry.
# Read with explicit UTF-8 — PowerShell 5.1's Get-Content -Raw uses the system code page
# and would mangle multi-byte UTF-8 (bullets, em-dashes) on a follow-up write-back.
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
Write-Host "[upload] cfg: $cfgPath" -ForegroundColor DarkGray
Write-Host "[upload] bundleV2 file count: $($bundleFiles.Count)" -ForegroundColor DarkGray

# Run ugc_tool via Git Bash with `echo y |` for the EULA. PowerShell's native stdin
# piping is rejected by ugc_tool ("You did not agree to the EULA"); cmd's `echo y|`
# passes EULA but then fails content transfer with 0x2.
$gitBash = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path $gitBash)) { $gitBash = 'bash' }
$toolFwd = ($tool -replace '\\','/').Replace(' ','\ ')
$cfgFwd  = ($cfgPath -replace '\\','/').Replace(' ','\ ')
$bashCmd = "echo y | $toolFwd -c $cfgFwd -x"

# Capture stdout/stderr so failed uploads show real errors instead of hiding
# them behind "Upload finished" + exit 0. ugc_tool prints "[Info]: Upload
# finished" even when no content actually transferred — we have to verify
# externally with the Steam Web API (below).
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

# Verify transfer via Steam Web API. ugc_tool's "Upload finished" message does NOT
# confirm transfer; the file_size reported by GetPublishedFileDetails is the
# authoritative signal.
if ($publishedId -ne '0') {
    Write-Host '[upload] verifying via Steam Web API...' -ForegroundColor DarkGray
    try {
        $api = Invoke-RestMethod -Method Post -Uri 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/' `
            -Body @{ itemcount = 1; 'publishedfileids[0]' = $publishedId } -TimeoutSec 30
        $details = $api.response.publishedfiledetails[0]
        Write-Host ('[upload] live: title="{0}" visibility={1} file_size={2} time_updated={3}' -f `
            $details.title, $details.visibility, $details.file_size, $details.time_updated) -ForegroundColor Green
    } catch {
        Write-Host "[upload] API verify failed: $_" -ForegroundColor Yellow
    }
}
