# Offline adversarial fixture for all six weapon-history source reproducers.
# The Tweaker repository itself is an intentionally incomplete source checkout:
# it has .git, but none of the required source commits/paths. No fixture repo,
# fetch, network access, source mutation, or recursive cleanup is needed.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }

function Invoke-HostScript {
    param(
        [Parameter(Mandatory)][string]$HostPath,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $priorPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $HostPath @Arguments 2>&1)
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = ($output | ForEach-Object { [string]$_ }) -join "`n"
        }
    }
    finally { $ErrorActionPreference = $priorPreference }
}

if (-not $SelfTest) {
    if (-not $Quiet) {
        Write-Host '[check_wt_history_source_checkout] fixture-only check; use -SelfTest.' -ForegroundColor DarkGray
    }
    exit 0
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$hostPath = (Get-Process -Id $PID).Path
if (-not $hostPath -or -not (Test-Path -LiteralPath $hostPath -PathType Leaf)) {
    Write-Host '[check_wt_history_source_checkout:selftest] FAILED - current PowerShell host is unavailable.' -ForegroundColor Red
    exit 2
}

$checks = @(
    [pscustomobject]@{
        Name = 'Patch 4.1.1'
        Path = Join-Path $PSScriptRoot 'check_wt_history_patch_4_1_1_reproducibility.ps1'
    },
    [pscustomobject]@{
        Name = 'Patch 4.6'
        Path = Join-Path $PSScriptRoot 'check_wt_history_patch_4_6_reproducibility.ps1'
    },
    [pscustomobject]@{
        Name = 'Patch 5.2'
        Path = Join-Path $PSScriptRoot 'check_wt_history_reproducibility.ps1'
    },
    [pscustomobject]@{
        Name = 'Patch 6.0'
        Path = Join-Path $PSScriptRoot 'check_wt_history_patch_6_0_reproducibility.ps1'
    },
    [pscustomobject]@{
        Name = 'Patch 6.6'
        Path = Join-Path $PSScriptRoot 'check_wt_history_patch_6_6_reproducibility.ps1'
    },
    [pscustomobject]@{
        Name = 'Patch 6.8'
        Path = Join-Path $PSScriptRoot 'check_wt_history_patch_6_8_reproducibility.ps1'
    }
)

$failures = New-Object 'System.Collections.Generic.List[string]'
$environmentNames = @(
    'VT2_SOURCE_REPO',
    'GIT_ALTERNATE_OBJECT_DIRECTORIES',
    'GIT_OBJECT_DIRECTORY',
    'GIT_DIR',
    'GIT_WORK_TREE',
    'GIT_NO_LAZY_FETCH',
    'GIT_OPTIONAL_LOCKS'
)
$environmentState = @{}
foreach ($name in $environmentNames) {
    $environmentState[$name] = [pscustomobject]@{
        Present = Test-Path "Env:$name"
        Value = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
}

try {
    foreach ($name in $environmentNames) {
        # On current .NET/Windows, SetEnvironmentVariable(name, $null,
        # 'Process') can leave a present empty variable. Git interprets an
        # empty GIT_DIR/GIT_OBJECT_DIRECTORY as a real invalid path, so remove
        # absent-state variables through the provider instead.
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }

    foreach ($check in $checks) {
        $baseArguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File',
            $check.Path, '-RepoRoot', $root, '-SourceRepo', $root, '-Quiet')
        $ordinary = Invoke-HostScript -HostPath $hostPath -Arguments $baseArguments
        if ($ordinary.ExitCode -ne 0 -or
            $ordinary.Output.IndexOf('SKIP', [StringComparison]::Ordinal) -lt 0 -or
            $ordinary.Output.IndexOf('unavailable or incomplete',
                [StringComparison]::Ordinal) -lt 0) {
            $failures.Add("$($check.Name) ordinary partial checkout must visibly SKIP with exit 0; exit=$($ordinary.ExitCode) output=$($ordinary.Output)") | Out-Null
        }

        $requiredArguments = @($baseArguments + '-RequireSource')
        $required = Invoke-HostScript -HostPath $hostPath -Arguments $requiredArguments
        if ($required.ExitCode -ne 2 -or
            $required.Output.IndexOf('required but unavailable or incomplete',
                [StringComparison]::Ordinal) -lt 0) {
            $failures.Add("$($check.Name) required partial checkout must fail closed with exit 2; exit=$($required.ExitCode) output=$($required.Output)") | Out-Null
        }
    }
}
finally {
    foreach ($name in $environmentNames) {
        $saved = $environmentState[$name]
        if ($saved.Present) {
            [Environment]::SetEnvironmentVariable($name, $saved.Value, 'Process')
        }
        else {
            Remove-Item "Env:$name" -ErrorAction SilentlyContinue
        }
    }
}

foreach ($name in $environmentNames) {
    $saved = $environmentState[$name]
    $currentPresent = Test-Path "Env:$name"
    $currentValue = [Environment]::GetEnvironmentVariable($name, 'Process')
    if ($currentPresent -ne $saved.Present -or
        ($saved.Present -and $currentValue -cne $saved.Value)) {
        $failures.Add("environment restoration drift for $name") | Out-Null
    }
}

if ($failures.Count -gt 0) {
    Write-Host '[check_wt_history_source_checkout:selftest] FAILED' -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  X $_" -ForegroundColor Red }
    exit 2
}

Write-Host '[check_wt_history_source_checkout:selftest] OK - all six reproducers visibly skip an incomplete checkout and fail closed when source is required.' -ForegroundColor Green
exit 0
