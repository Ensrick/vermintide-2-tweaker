# #1751: tiny Git fixtures exercise the complete checker and hook dispatch.
# Owned by: check_file_sizes.ps1 -SelfTest; no primary checkout is modified.
function Invoke-FileSizeStagedSelfTest {
    param([string]$CheckerSource, [string]$HookSource, [string]$HelperSource)
    $fixture = Join-Path ([IO.Path]::GetTempPath()) ('vt2-file-size-staged-' + [Guid]::NewGuid().ToString('N'))
    $fixture = [IO.Path]::GetFullPath($fixture)
    $hostExe = Join-Path $PSHOME 'pwsh.exe'
    if (-not [IO.File]::Exists($hostExe)) { $hostExe = Join-Path $PSHOME 'powershell.exe' }
    $gitExe = @(Get-Command git -CommandType Application -ErrorAction Stop)[0].Source
    $utf8 = New-Object Text.UTF8Encoding($false)
    $targetPath = 'qa/baselines/file_sizes_target.json'
    $baseTarget = '{"target":1500,"hard_limit":2500,"generated":"base","files":{"a.lua":1601}}'
    $emptyTarget = '{"target":1500,"hard_limit":2500,"files":{}}'
    $invalidTarget = '{"target":1500,"hard_limit":2500,"files":{"a.lua":1415}}'
    $ledger = Join-Path $fixture 'probe-ledger.txt'
    $driver = Join-Path $fixture 'probe-driver.ps1'
    $pass = 0
    function Write-CaseFile([string]$Relative, [string]$Text) {
        $full = [IO.Path]::GetFullPath((Join-Path $fixture $Relative))
        if (-not $full.StartsWith($fixture + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture write escaped ownership.' }
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $full))
        [IO.File]::WriteAllText($full, $Text, $utf8)
    }
    function Invoke-CaseGit([string[]]$Arguments) {
        $previous = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $text = @(& $gitExe -C $fixture @Arguments 2>&1)
            $code = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $previous }
        if ($code -ne 0) { throw "Fixture git failed ($code): $($text -join ' | ')" }
    }
    function Reset-Case {
        Invoke-CaseGit @('read-tree', 'HEAD')
        Write-CaseFile $targetPath $baseTarget
        Write-CaseFile 'qa/baselines/file_sizes.json' '{"hard_limit":2500,"files":{}}'
        Write-CaseFile 'a.lua' (("-- owned`n") * 1601)
        Write-CaseFile 'b.lua' "-- ordinary`n"
        Write-CaseFile 'README.md' "baseline`n"
        if ([IO.File]::Exists($ledger)) { [IO.File]::Delete($ledger) }
        foreach ($name in @('probe-fail-git', 'probe-selector-fail')) {
            $fault = Join-Path $fixture $name
            if ([IO.File]::Exists($fault)) { [IO.File]::Delete($fault) }
        }
    }
    function Stage-Target([string]$Text) {
        Write-CaseFile $targetPath $Text
        Invoke-CaseGit @('add', '--', $targetPath)
    }
    function Invoke-Case([string]$Name, [string]$Mode, [int]$Expected) {
        $index = Join-Path $fixture '.git/index'
        $before = (Get-FileHash -LiteralPath $index -Algorithm SHA256).Hash
        $previous = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $output = @(& $hostExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $driver -Mode $Mode `
                -RootPath $fixture -NativeHost $hostExe -NativeGit $gitExe -Ledger $ledger 2>&1 | ForEach-Object { "$_" })
            $code = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $previous }
        if ($code -ne $Expected) { throw "${Name}: expected exit $Expected, got $code -- $($output -join ' | ')" }
        if ((Get-FileHash -LiteralPath $index -Algorithm SHA256).Hash -ne $before) { throw "${Name}: index changed" }
        $script:FileSizeLastLedger = if ([IO.File]::Exists($ledger)) { [IO.File]::ReadAllLines($ledger) } else { @() }
        $pass++
        Write-Host "  [PASS] staged baseline $Name (exit $code)"
    }
    try {
        [void][IO.Directory]::CreateDirectory($fixture)
        Write-CaseFile 'qa/check_file_sizes.ps1' $CheckerSource
        Write-CaseFile 'qa/worktree_state.ps1' $HelperSource
        Write-CaseFile 'tools/hooks/pre-commit.ps1' $HookSource
        foreach ($name in @('check_diff_whitespace', 'check_dev_only_edits', 'check_release_bundle_atomicity', 'check_build_receipts',
            'run_all', 'check_hook_test_coverage', 'check_native_resource_safety')) { Write-CaseFile ("qa/$name.ps1") '# explicit boundary double' }
        Write-CaseFile 'tools/mod-lint/lint-mod.ps1' '# explicit boundary double'
        Write-CaseFile '.gitignore' "probe-*`nrenamed-baseline.json`n"
        Write-CaseFile 'qa/baselines/file_sizes.json' '{"hard_limit":2500,"files":{}}'
        Write-CaseFile $targetPath $baseTarget
        Write-CaseFile 'a.lua' (("-- owned`n") * 1601)
        Write-CaseFile 'b.lua' "-- ordinary`n"
        Write-CaseFile 'README.md' "baseline`n"
        $driverSource = @'
param([string]$Mode,[string]$RootPath,[string]$NativeHost,[string]$NativeGit,[string]$Ledger)
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$global:FileSizeProbeHost=$NativeHost
$global:FileSizeProbeGit=$NativeGit
$global:FileSizeProbeLedger=$Ledger
$global:FileSizeProbeRoot=$RootPath
function global:git {
    [IO.File]::AppendAllText($global:FileSizeProbeLedger, ('git|' + ($args -join '|') + "`n"))
    if ((Test-Path -LiteralPath (Join-Path $global:FileSizeProbeRoot 'probe-selector-fail')) -and $args -contains 'diff' -and $args -contains '--diff-filter=ACMR') {
        $global:LASTEXITCODE=73
        return
    }
    if ((Test-Path -LiteralPath (Join-Path $global:FileSizeProbeRoot 'probe-fail-git')) -and $args -contains 'cat-file') {
        $global:LASTEXITCODE=73
        return
    }
    & $global:FileSizeProbeGit @args
    $global:LASTEXITCODE=$LASTEXITCODE
}
function global:pwsh {
    $values=@($args)
    $at=[Array]::IndexOf($values,'-File')
    if ($at -lt 0) { throw 'Unexpected hook child invocation' }
    $file=[string]$values[$at+1]
    [IO.File]::AppendAllText($global:FileSizeProbeLedger, ('child|' + $file + '|' + ($values -join '|') + "`n"))
    if ((Split-Path -Leaf $file) -eq 'check_file_sizes.ps1') { & $global:FileSizeProbeHost @values; $global:LASTEXITCODE=$LASTEXITCODE }
    else { $global:LASTEXITCODE=0 }
}
Set-Location -LiteralPath $RootPath
if ($Mode -eq 'checker') { & (Join-Path $RootPath 'qa/check_file_sizes.ps1') -RepoRoot $RootPath -BaselineOnly -Staged }
elseif ($Mode -eq 'normal') { & (Join-Path $RootPath 'qa/check_file_sizes.ps1') -RepoRoot $RootPath -Quiet }
elseif ($Mode -eq 'hook') { & (Join-Path $RootPath 'tools/hooks/pre-commit.ps1') }
elseif ($Mode -eq 'disconnected') { & (Join-Path $RootPath 'probe-disconnected-hook.ps1') }
else { throw 'Unknown fixture mode' }
exit $LASTEXITCODE
'@
        Write-CaseFile 'probe-driver.ps1' $driverSource
        Invoke-CaseGit @('init', '-q')
        Invoke-CaseGit @('add', '--', '.')
        Invoke-CaseGit @('-c', 'user.name=FileSizeFixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=.git/fixture-hooks', 'commit', '-qm', 'owned fixture base')

        Reset-Case; Stage-Target $invalidTarget
        Write-CaseFile $targetPath $baseTarget
        Invoke-Case 'invalid indexed1415 despite fixed worktree' 'checker' 2

        Reset-Case; Stage-Target ($baseTarget.Replace('"base"', '"changed"'))
        Write-CaseFile $targetPath $invalidTarget
        Invoke-Case 'valid index despite invalid worktree' 'checker' 0

        Reset-Case; Write-CaseFile 'a.lua' (("-- owned`n") * 1499)
        Stage-Target $emptyTarget; Invoke-CaseGit @('add', '--', 'a.lua')
        Invoke-Case 'legitimate indexed below-target retirement' 'checker' 0

        Reset-Case; Stage-Target $emptyTarget
        Invoke-Case 'still-oversized indexed removal rejected' 'checker' 2

        Reset-Case; Stage-Target '{'
        Invoke-Case 'malformed indexed JSON rejected' 'checker' 2

        Reset-Case; Stage-Target '{"target":1500,"hard_limit":2500,"files":{"a.lua":"1601"}}'
        Invoke-Case 'string count rejected without coercion' 'checker' 2

        Reset-Case; Stage-Target ($baseTarget.Replace('1601', '1600'))
        Invoke-Case 'indexed growth beyond changed ceiling rejected' 'checker' 2

        Reset-Case; Write-CaseFile 'a.lua' ((("-- owned`n") * 1599) + "`n `n")
        Stage-Target ($baseTarget.Replace('1601', '1600')); Invoke-CaseGit @('add', '--', 'a.lua')
        Invoke-Case 'index metric excludes empty but counts whitespace-only lines' 'checker' 0

        Reset-Case; [IO.File]::Delete((Join-Path $fixture 'a.lua'))
        Stage-Target $emptyTarget; Invoke-CaseGit @('add', '-A', '--', 'a.lua')
        Invoke-Case 'actual indexed Lua deletion retires' 'checker' 0

        Reset-Case; Stage-Target ($baseTarget.Replace('"base"', '"metadata"'))
        Write-CaseFile 'b.lua' (("-- unrelated`n") * 3000); Invoke-CaseGit @('add', '--', 'b.lua')
        Invoke-Case 'metadata-only baseline does not scan unrelated Lua' 'checker' 0
        if (@($script:FileSizeLastLedger | Where-Object { $_ -match '\|ls-files\|' -and ($_ -match '\|a\.lua$' -or $_ -match '\|b\.lua$') }).Count) {
            throw 'Metadata-only change read a Lua index row.'
        }

        Reset-Case; Stage-Target ($baseTarget.Replace('"base"', '"read-error"'))
        Write-CaseFile 'probe-fail-git' 'owned read fault'
        Invoke-Case 'Git blob reader error exits2' 'checker' 2

        Reset-Case; [IO.File]::Delete((Join-Path $fixture $targetPath))
        Invoke-CaseGit @('add', '-A', '--', $targetPath)
        Invoke-Case 'baseline deletion checker fails closed' 'checker' 2
        Invoke-Case 'baseline-only deletion reaches actual hook guard' 'hook' 1

        Reset-Case; Write-CaseFile 'renamed-baseline.json' $baseTarget
        [IO.File]::Delete((Join-Path $fixture $targetPath))
        Invoke-CaseGit @('add', '-A', '--', $targetPath)
        Invoke-CaseGit @('add', '-f', '--', 'renamed-baseline.json')
        Invoke-Case 'baseline rename old side reaches actual hook guard' 'hook' 1

        Reset-Case; Write-CaseFile 'probe-symlink' '../README.md'
        $linkObject = @(& $gitExe -C $fixture hash-object -w -- (Join-Path $fixture 'probe-symlink'))
        if ($LASTEXITCODE -ne 0 -or $linkObject.Count -ne 1 -or $linkObject[0] -notmatch '^[0-9a-f]{40,64}$') { throw 'Cannot create owned symlink index object.' }
        Invoke-CaseGit @('update-index', '--add', '--cacheinfo', ("120000,$($linkObject[0]),$targetPath"))
        Invoke-Case 'non-regular baseline index type checker fails closed' 'checker' 2
        Invoke-Case 'baseline type change reaches actual hook guard' 'hook' 1

        Reset-Case; Stage-Target $invalidTarget
        Invoke-Case 'JSON-only actual hook blocks invalid1415' 'hook' 1
        $needle = '$sizeOutput = & pwsh -NoProfile -File $sizeScript -BaselineOnly -Staged 2>&1'
        if ($HookSource.Split([string[]]@($needle), [StringSplitOptions]::None).Count -ne 2) { throw 'Exact hook control call not unique.' }
        Write-CaseFile 'probe-disconnected-hook.ps1' ($HookSource.Replace($needle, '$sizeOutput = @(); $global:LASTEXITCODE = 0 # same-oracle disconnection'))
        Invoke-Case 'same invalid1415 passes only disconnected guard control' 'disconnected' 0

        Reset-Case; Stage-Target $invalidTarget
        Write-CaseFile 'probe-selector-fail' 'owned ordinary selector read fault'
        Invoke-Case 'known baseline mutation selector read failure blocks' 'hook' 1

        Reset-Case; Stage-Target ($baseTarget.Replace('"base"', '"valid-hook"'))
        Invoke-Case 'valid JSON-only hook does not run expensive gates' 'hook' 0
        if (@($script:FileSizeLastLedger | Where-Object { $_ -match '^child\|.*(run_all|lint-mod|check_lua)' }).Count) { throw 'JSON-only hook ran expensive gates.' }

        Reset-Case; Write-CaseFile 'README.md' "docs changed`n"; Invoke-CaseGit @('add', '--', 'README.md')
        Invoke-Case 'docs-only hook retains zero expensive calls' 'hook' 0
        if (@($script:FileSizeLastLedger | Where-Object { $_ -match '^child\|.*(run_all|lint-mod|check_lua|check_file_sizes)' }).Count) { throw 'Docs-only hook dispatched an expensive/baseline checker.' }

        Reset-Case
        Invoke-Case 'normal checker keeps existing frozen-debt advisory' 'normal' 1
        Write-Host '[file_sizes_staged] actual checker/hook cases passed; no primary/index mutation.'
        return $true
    }
    finally {
        if ([IO.Directory]::Exists($fixture)) {
            $resolved = [IO.Path]::GetFullPath($fixture)
            $parent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('\', '/')) + [IO.Path]::DirectorySeparatorChar
            if (-not $resolved.StartsWith($parent, [StringComparison]::OrdinalIgnoreCase) -or
                -not (Split-Path -Leaf $resolved).StartsWith('vt2-file-size-staged-', [StringComparison]::Ordinal) -or
                ((Get-Item -LiteralPath $resolved -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw 'Refusing cleanup outside the owned staged-baseline fixture.'
            }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
