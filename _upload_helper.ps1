# _upload_helper.ps1 — canonical Workshop upload pipeline for VMB mods.
#
# Mirrors the staging pipeline implemented in tools/vmb-launcher (UploadStager.cs +
# ModRunner.UploadAsync + ProcessRunner.RunWithEulaYesAsync) so this script and the GUI
# launcher produce identical Workshop submissions. See vmb-launcher's README for the
# rationale behind each step.
#
# Canonical pattern (all four steps matter, deviating from any of them is a known footgun):
#   1. Stage into <SDK>/ugc_uploader/sample_item/ with content="content" (relative).
#      UploadStager.cs:23-30 — custom staging folders or absolute cfg paths produce 0x2
#      "empty content directory" on at least one user's setup.
#   2. NEVER write `tags = [ ];` into the staged cfg. UploadStager.cs:124-127 — the tool
#      adds it post-upload; writing it pre-emptively breaks first-upload content transfer.
#   3. Invoke ugc_tool from cwd = ugc_uploader/ with a relative cfg path (-c sample_item/item.cfg).
#   4. Pipe "y\n" to stdin natively (no `bash -c` workaround — that hits WSL bash on systems
#      without Git Bash on PATH, per vmb-launcher README footgun #4).
#
# Per-mod upload_*.ps1 scripts should be thin wrappers that invoke this helper.

param(
    [Parameter(Mandatory=$true)] [string]$ModName,
    [string]$ExpectedVisibility = '',         # if set, abort unless cfg matches exactly
    [string]$Sdk = 'C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK',
    [switch]$AllowPublic                     # required if cfg has visibility="public"
)

$ErrorActionPreference = 'Stop'

# Resolve paths
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$modDir = Join-Path $root $ModName
$cfgPath = Join-Path $modDir 'itemV2.cfg'
$bundleDir = Join-Path $modDir 'bundleV2'
$uploaderDir = Join-Path $Sdk 'ugc_uploader'
$tool = Join-Path $uploaderDir 'ugc_tool.exe'
$stagingDir = Join-Path $uploaderDir 'sample_item'
$stagedContent = Join-Path $stagingDir 'content'
$stagedCfg = Join-Path $stagingDir 'item.cfg'

if (-not (Test-Path $cfgPath))   { throw "itemV2.cfg not found at $cfgPath" }
if (-not (Test-Path $tool))      { throw "ugc_tool.exe not found at $tool" }
if (-not (Test-Path $bundleDir)) { throw "bundleV2/ not found at $bundleDir - run VMB build first" }
$bundleFiles = @(Get-ChildItem $bundleDir -File -Filter '*.mod_bundle' -ErrorAction SilentlyContinue)
if ($bundleFiles.Count -eq 0)    { throw "No .mod_bundle files in $bundleDir - build did not produce output" }

# Parse cfg fields (matches ModDiscovery.ExtractString / ExtractPublishedId).
# Use .NET ReadAllText with explicit UTF-8 — PowerShell 5.1's `Get-Content -Raw`
# defaults to the system code page (Windows-1252 on en-US), which silently mangles
# multi-byte UTF-8 in the description (bullets •, em-dashes —, accented chars like
# ö get round-tripped through Win-1252 → re-written as UTF-8 garbage). Symmetry
# with the WriteAllText below, which already uses UTF-8 no-BOM.
$cfgRaw = [System.IO.File]::ReadAllText($cfgPath, [System.Text.Encoding]::UTF8)
function Get-CfgString {
    param([string]$key)
    $regex = [regex]"$([regex]::Escape($key))\s*=\s*`"((?:[^`"\\]|\\.)*)`""
    $m = $regex.Match($cfgRaw)
    if ($m.Success) { return $m.Groups[1].Value -replace '\\n',"`n" -replace '\\"','"' -replace '\\\\','\' }
    return $null
}
$title       = Get-CfgString 'title'
$description = Get-CfgString 'description'
$language    = Get-CfgString 'language';   if (-not $language)   { $language   = 'english' }
$visibility  = Get-CfgString 'visibility'; if (-not $visibility) { $visibility = 'private' }
if ($cfgRaw -match 'published_id\s*=\s*(\d+)L?') { $publishedId = $matches[1] } else { $publishedId = '0' }

# Visibility guards
if ($ExpectedVisibility -and $visibility -ne $ExpectedVisibility) {
    throw "itemV2.cfg visibility='$visibility' but expected '$ExpectedVisibility'. Aborting; confirm with user before uploading."
}
if ($visibility -eq 'public' -and -not $AllowPublic) {
    throw "itemV2.cfg has visibility='public'. Re-run with -AllowPublic to confirm. Public mods that get flagged are removed irreversibly."
}

# Wipe & recreate staging dir
if (Test-Path $stagingDir) { Remove-Item -LiteralPath $stagingDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stagedContent | Out-Null

# Copy every file from bundleV2/ into content/
$copied = 0
foreach ($f in Get-ChildItem $bundleDir -File) {
    Copy-Item $f.FullName (Join-Path $stagedContent $f.Name) -Force
    $copied++
}
if ($copied -eq 0) { throw "No files copied from $bundleDir" }

# Copy preview into staging root (NOT content/) — order matches UploadStager.cs:69
$stagedPreviewName = 'item_preview.png'
foreach ($candidate in 'item_preview.png','preview.jpg','preview.png') {
    $src = Join-Path $modDir $candidate
    if (Test-Path $src) {
        $stagedPreviewName = $candidate
        Copy-Item $src (Join-Path $stagingDir $candidate) -Force
        break
    }
}

# Escape for cfg double-quoted strings: \, ", and newlines.
function Escape-CfgString {
    param([string]$s)
    if ($null -eq $s) { return '' }
    return $s.Replace('\','\\').Replace('"','\"').Replace("`r",'').Replace("`n",'\n')
}

# Write the staged item.cfg. DO NOT write `tags = [ ];` — see header.
$lines = @(
    'title = "{0}";' -f (Escape-CfgString $title)
    'description = "{0}";' -f (Escape-CfgString $description)
    'preview = "{0}";' -f $stagedPreviewName
    'content = "content";'
    'language = "{0}";' -f $language
    'visibility = "{0}";' -f $visibility
    'published_id = {0}L;' -f $publishedId
    'apply_for_sanctioned_status = false;'
)
# PowerShell 5.1's `Set-Content -Encoding utf8` writes a UTF-8 BOM, which ugc_tool refuses
# to parse ("item config file not found" despite the file being on disk — verified). Use
# .NET WriteAllText with an explicit no-BOM UTF-8 encoder.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($stagedCfg, ($lines -join "`r`n"), $utf8NoBom)

Write-Host ('[upload] {0} visibility={1} published_id={2}' -f $ModName,$visibility,$publishedId) -ForegroundColor Cyan
Write-Host ('[upload] staged {0} file(s) -> {1}' -f $copied,$stagingDir) -ForegroundColor DarkGray

# Run ugc_tool via Git Bash with `echo y |` for the EULA. Empirically the only stdin
# delivery approach that BOTH:
#   (a) gets the tool past the EULA prompt (.NET StandardInput.Write/WriteLine is rejected
#       with "You did not agree to the EULA")
#   (b) doesn't subsequently 0x2 in the content-upload step (cmd's `echo y|` passes EULA
#       but then fails Workshop content transfer with "empty content directory" 0x2)
# This is the same trick the legacy upload_*.ps1 scripts use, but with the bash path
# resolved explicitly so it doesn't accidentally hit WSL bash (which can't read Windows
# paths and is the default `bash` on Windows 10/11 without Git Bash on PATH).
$gitBash = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path $gitBash)) {
    # Fall back to whatever `bash` resolves to on PATH — works in Git-Bash-on-PATH setups
    # but will silently use WSL bash otherwise (which fails with "No such file" on the
    # tool's Windows path). The launcher's README documents this as footgun #4.
    $gitBash = 'bash'
}
$toolFwd = $tool -replace '\\','/'
$uploaderFwd = $uploaderDir -replace '\\','/'
$bashCmd = "cd '$uploaderFwd' && echo y | '$toolFwd' -c sample_item/item.cfg -x"
# Capture stdout+stderr so we can see ugc_tool's actual messages (Start-Process
# -NoNewWindow without redirects swallows them, which hid real failures during
# the v0.7.5-alpha "Upload finished" but content-not-transferred saga).
$stdoutLog = Join-Path $env:TEMP "ugc_tool_stdout_$([System.IO.Path]::GetRandomFileName()).log"
$stderrLog = Join-Path $env:TEMP "ugc_tool_stderr_$([System.IO.Path]::GetRandomFileName()).log"
$proc = Start-Process -FilePath $gitBash -ArgumentList @('-c', $bashCmd) -NoNewWindow -PassThru -Wait `
    -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
$stdoutText = if (Test-Path $stdoutLog) { Get-Content $stdoutLog -Raw -ErrorAction SilentlyContinue } else { '' }
$stderrText = if (Test-Path $stderrLog) { Get-Content $stderrLog -Raw -ErrorAction SilentlyContinue } else { '' }
Remove-Item -LiteralPath $stdoutLog,$stderrLog -ErrorAction SilentlyContinue
if ($stdoutText) { Write-Host '[ugc_tool stdout]' -ForegroundColor DarkGray; Write-Host $stdoutText }
if ($stderrText) { Write-Host '[ugc_tool stderr]' -ForegroundColor DarkYellow; Write-Host $stderrText }

if ($proc.ExitCode -ne 0) {
    throw "ugc_tool exited with code $($proc.ExitCode)"
}
# Pattern-match ugc_tool's messages — it returns 0 even when content transfer
# fails. Surface known error strings to the caller so they fail loud.
if ($stdoutText -match '\[ERROR\]|Upload [Ff]ailed|0x[0-9A-Fa-f]+\)') {
    throw "ugc_tool reported an error in its output (exit code 0 was misleading): $($matches[0])"
}

# Propagate new published_id back if this was a first upload.
if ($publishedId -eq '0') {
    $stagedRaw = [System.IO.File]::ReadAllText($stagedCfg, [System.Text.Encoding]::UTF8)
    if ($stagedRaw -match 'published_id\s*=\s*(\d+)L?' -and $matches[1] -ne '0') {
        $newId = $matches[1]
        # Same UTF-8 reasoning as the initial ReadAllText above — Get-Content -Raw
        # mangles multi-byte characters.
        $cfgRaw2 = [System.IO.File]::ReadAllText($cfgPath, [System.Text.Encoding]::UTF8)
        $cfgRaw2 = $cfgRaw2 -replace '(?m)^\s*published_id\s*=\s*\d+L?\s*;.*$', ('published_id = {0}L;' -f $newId)
        # Same no-BOM concern as the staged cfg write above.
        [System.IO.File]::WriteAllText($cfgPath, $cfgRaw2, $utf8NoBom)
        Write-Host ('[upload] new Workshop ID {0} written back into {1}' -f $newId,$cfgPath) -ForegroundColor Green
    }
}

Write-Host '[upload] ugc_tool reported finished. VERIFY the Workshop page file size -- ugc_tool prints success even on transfer failures.' -ForegroundColor Green
