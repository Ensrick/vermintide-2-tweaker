[CmdletBinding()]
param([switch]$SelfTest, [switch]$Quiet)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'tools/ship/workshop-upload-evidence.ps1')
$script:passed = 0
function Assert-Evidence {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "[check_workshop_upload_evidence] FAIL: $Name" }
    $script:passed++
    if (-not $Quiet) { Write-Host "  [PASS] $Name" }
}
function Assert-Rejected {
    param([scriptblock]$Action, [string]$Name, [string]$Pattern = '.')
    $failure = $null
    try { $null = & $Action } catch { $failure = $_.Exception.Message }
    Assert-Evidence ($null -ne $failure -and $failure -match $Pattern) "$Name (observed: $failure)"
}

$shipText = [IO.File]::ReadAllText((Join-Path $repoRoot 'tools/ship/ship.ps1'))
$tokens = $null; $errors = $null
$shipAst = [Management.Automation.Language.Parser]::ParseInput($shipText, [ref]$tokens, [ref]$errors)
Assert-Evidence ($errors.Count -eq 0) 'ship parses'
Assert-Evidence ($shipText -notmatch 'Get-Content \$workshopLog -Tail|\$cutoff\s*=\s*\(Get-Date\)\.AddMinutes') 'stale tail/time fallback removed'
Assert-Evidence ($shipText.Contains('$shipManifestId = $receiptAcceptance.ManifestId')) 'card refresh consumes validated manifest field without manufacturing NoChange ID'
$uploadTries = @($shipAst.FindAll({param($node)
    $node -is [Management.Automation.Language.TryStatementAst] -and
    $node.Body.Extent.Text.Contains('$receiptAcceptance = Invoke-WithShipVmbRc')
}, $true) | Sort-Object { $_.Extent.Text.Length })
Assert-Evidence ($uploadTries.Count -ge 1) 'actual installed upload block found'
$actualUpload = [scriptblock]::Create($uploadTries[0].Extent.Text)
$uploadCommands = @($uploadTries[0].FindAll({param($node)
    $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Invoke-ShipLauncherNoWindow'
}, $true))
Assert-Evidence ($uploadCommands.Count -eq 1) 'exactly one launcher upload invocation remains'
if (-not $SelfTest) {
    Write-Host "[check_workshop_upload_evidence] $script:passed structural assertions PASS; use -SelfTest for offline/native cases."
    exit 0
}

$id = '3712896117'
$manifest = '6852607942336154153'
$t0 = [datetime]'2026-07-13T11:59:20'
$t1 = [datetime]'2026-07-13T11:59:55'
$begin = "[2026-07-13 11:59:20] [AppID 552500] Upload starting for workshop item $id by AppID 552500`n"
$content = "[2026-07-13 11:59:24] [AppID 552500] Uploaded new content ( ManifestID $manifest ) for item $id.`n"
$finish = "[2026-07-13 11:59:54] [AppID 552500] Upload finished for workshop item $id : OK`n"
$noChange = "[2026-07-13 11:59:24] [AppID 552500] No content change detected for item $id`n"
$good = $begin + $content + $finish
function Parse-Fixture {
    param([string]$Value)
    ConvertFrom-VtWorkshopUploadTransaction -Text $Value -PublishedId $id -StartedAt $t0 -EndedAt $t1
}
$parsed = Parse-Fixture $good
Assert-Evidence ($parsed.Status -ceq 'UPLOADED' -and $parsed.ManifestId -ceq $manifest) 'exact ordered upload parses UInt64 manifest as string'
$parsed = Parse-Fixture ($begin + $noChange + $finish)
Assert-Evidence ($parsed.Status -ceq 'NOCHANGE' -and $null -eq $parsed.ManifestId) 'observed NoChange grammar has no period and no manufactured manifest'
Assert-Evidence ((Parse-Fixture ($good.Replace("`n", "`r`n"))).Status -ceq 'UPLOADED') 'CRLF accepted'
$noise = ((1..75 | ForEach-Object { "[2026-07-13 11:59:23] [AppID 552500] unrelated diagnostic $($_) manifest $id" }) -join "`n") + "`n"
$other = $good.Replace($id, ($id + '9'))
Assert-Evidence ((Parse-Fixture ($other + $begin + $noise + $content + $finish)).Status -ceq 'UPLOADED') 'more than 40 interleaved lines and substring foreign item ignored'
foreach ($case in @(
    @{ Name='real July13 Uploaded then Timeout'; Text=$good.Replace(' : OK', ' : Timeout') },
    @{ Name='real reverting outcome'; Text=$good.Replace('Uploaded new content', 'Reverting to previous content') },
    @{ Name='missing start'; Text=$content+$finish },
    @{ Name='missing outcome'; Text=$begin+$finish },
    @{ Name='missing terminal'; Text=$begin+$content },
    @{ Name='duplicate start'; Text=$begin+$good },
    @{ Name='duplicate upload'; Text=$begin+$content+$content+$finish },
    @{ Name='mixed outcomes'; Text=$begin+$content+$noChange+$finish },
    @{ Name='duplicate finish'; Text=$good+$finish },
    @{ Name='retry after failed terminal'; Text=$good.Replace(' : OK',' : Timeout')+$good },
    @{ Name='retry after successful terminal'; Text=$good+$good },
    @{ Name='out of order'; Text=$finish+$begin+$content },
    @{ Name='wrong event app'; Text=$good.Replace('[AppID 552500]','[AppID 552501]') },
    @{ Name='wrong starting app'; Text=$good.Replace('by AppID 552500','by AppID 552501') },
    @{ Name='nonexact OK'; Text=$good.Replace(' : OK',' : OK extra') },
    @{ Name='bad NoChange period'; Text=$begin+$noChange.Replace("$id`n","$id.`n")+$finish },
    @{ Name='case alias extra target'; Text=$good+$finish.Replace('Upload finished','upload finished') },
    @{ Name='leadingzero extra target'; Text=$good+$finish.Replace($id,"0$id") },
    @{ Name='malformed envelope'; Text=$good.Replace('[AppID 552500]','[AppID552500]') },
    @{ Name='invalid date'; Text=$good.Replace('2026-07-13','2026-99-13') },
    @{ Name='old timestamp'; Text=$good.Replace('2026-07-13','2026-07-12') },
    @{ Name='future timestamp'; Text=$good.Replace('2026-07-13','2026-07-14') },
    @{ Name='timestamp reverses'; Text=$good.Replace('11:59:24','11:59:19') },
    @{ Name='overflow manifest'; Text=$good.Replace($manifest,'18446744073709551616') },
    @{ Name='zero manifest'; Text=$good.Replace($manifest,'0') },
    @{ Name='leadingzero manifest'; Text=$good.Replace($manifest,'01') },
    @{ Name='partial final line'; Text=$good.TrimEnd([char]10) },
    @{ Name='extra CR before newline'; Text=$good.Replace("`n", "`r`r`n") },
    @{ Name='oversized line'; Text=$begin+('x'*8193)+"`n"+$content+$finish },
    @{ Name='oversized append'; Text=('x'*1048577)+"`n" }
)) { Assert-Rejected { Parse-Fixture $case.Text } $case.Name }
foreach ($badId in @('0','01','-1','+1','1e3','18446744073709551616','3712896117.0',"3712896117`n")) {
    Assert-Rejected { ConvertFrom-VtWorkshopUploadTransaction -Text $good -PublishedId $badId -StartedAt $t0 -EndedAt $t1 } "bad item ID $badId"
}
Assert-Rejected { ConvertFrom-VtWorkshopUploadTransaction -Text $good -PublishedId $id -StartedAt $t1 -EndedAt $t0 } 'backwards observer clock'
Assert-Evidence ((ConvertFrom-VtWorkshopUploadTransaction -Text $good -PublishedId $id -StartedAt $t0.AddMilliseconds(950) -EndedAt $t1).Status -ceq 'UPLOADED') 'second-resolution timestamp accepts captured subsecond start floor'

# Native file tests operate only under one newly allocated disposable directory.
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('vt2-workshop-evidence-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($fixtureRoot)
$path = Join-Path $fixtureRoot 'workshop_log.txt'
$previous = Join-Path $fixtureRoot 'workshop_log.previous.txt'
$receiptPath = Join-Path $fixtureRoot 'receipt.json'
$cfgPath = Join-Path $fixtureRoot 'itemV2.cfg'
$utf8 = [Text.UTF8Encoding]::new($false)
function Reset-Log { [IO.File]::WriteAllText($path, "existing prefix`n", $utf8) }
function Live-Transaction {
    param([string]$Item = $id, [string]$Outcome = 'Uploaded', [string]$Terminal = 'OK')
    $stamp = [datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture)
    $middle = if ($Outcome -eq 'NoChange') { "No content change detected for item $Item" } else { "Uploaded new content ( ManifestID $manifest ) for item $Item." }
    return "[$stamp] [AppID 552500] Upload starting for workshop item $Item by AppID 552500`n[$stamp] [AppID 552500] $middle`n[$stamp] [AppID 552500] Upload finished for workshop item $Item : $Terminal`n"
}
function Append-Log { param([string]$Value) [IO.File]::AppendAllText($path, $Value, $utf8) }
function Assert-Closed {
    $exclusive = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $exclusive.Dispose()
    Assert-Evidence $true 'observer handle closed on completed/failed path'
}
try {
    Reset-Log
    $result = Invoke-VtWorkshopUploadEvidence -Path $path -PublishedId $id -UploadAction { Append-Log (Live-Transaction) }
    Assert-Evidence ($result.Status -ceq 'UPLOADED' -and $result.ManifestId -ceq $manifest) 'native append succeeds with retained same-file proof'
    Assert-Closed
    Reset-Log
    $result = Invoke-VtWorkshopUploadEvidence -Path $path -PublishedId $id -UploadAction { Append-Log (Live-Transaction -Outcome NoChange) }
    Assert-Evidence ($result.Status -ceq 'NOCHANGE' -and $null -eq $result.ManifestId) 'native no-change remains manifestless'
    Reset-Log
    Append-Log (Live-Transaction)
    Assert-Rejected { Invoke-VtWorkshopUploadEvidence -Path $path -PublishedId $id -UploadAction { Append-Log "unrelated new line`n" } } 'same-second old successful transaction cannot satisfy append boundary'
    Assert-Closed
    Reset-Log
    Assert-Rejected { Invoke-VtWorkshopUploadEvidence -Path $path -PublishedId $id -UploadAction { Append-Log (Live-Transaction -Terminal Timeout) } } 'native timeout after Uploaded fails'
    Assert-Closed
    Reset-Log
    Assert-Rejected { Invoke-VtWorkshopUploadEvidence -Path $path -PublishedId $id -UploadAction { throw 'planted launcher error' } } 'launcher exception retained' 'planted launcher error'
    Assert-Closed
    Reset-Log
    Assert-Rejected { Invoke-VtWorkshopUploadEvidence -Path $path -PublishedId $id -UploadAction { [IO.File]::WriteAllText($path, '', $utf8) } } 'native truncate fails'
    Assert-Closed
    Reset-Log
    Assert-Rejected { Invoke-VtWorkshopUploadEvidence -Path $path -PublishedId $id -UploadAction { [IO.File]::WriteAllText($path, "rewritten data!`n"+(Live-Transaction), $utf8) } } 'native truncate-regrow invalidates prefix' 'prefix'
    Assert-Closed
    Reset-Log
    Assert-Rejected { Invoke-VtWorkshopUploadEvidence -Path $path -PublishedId $id -UploadAction {
        [IO.File]::Move($path, $previous)
        [IO.File]::WriteAllText($path, "existing prefix`n"+(Live-Transaction), $utf8)
        [IO.File]::AppendAllText($previous, (Live-Transaction), $utf8)
    } } 'Steam-style rotation allowed by read-only observer but fails evidence' 'rotated'
    Assert-Closed
    Reset-Log
    Assert-Rejected { Invoke-VtWorkshopUploadEvidence -Path $path -PublishedId $id -UploadAction { Append-Log ((Live-Transaction).TrimEnd([char]10)) } } 'native partial tail fails'
    Reset-Log
    Assert-Rejected { Invoke-VtWorkshopUploadEvidence -Path $path -PublishedId $id -UploadAction { Append-Log (('x'*1048576)+"`n") } } 'native append budget bounded' 'budget'
    [IO.File]::WriteAllText($path, 'partial', $utf8)
    $script:called = $false
    Assert-Rejected { Invoke-VtWorkshopUploadEvidence -Path $path -PublishedId $id -UploadAction { $script:called = $true } } 'incomplete boundary prevents launcher action'
    Assert-Evidence (-not $script:called) 'pre-capture denial has zero launcher calls'
    Assert-Closed
    [IO.File]::WriteAllText($path, ('x'*16777216)+"`n", $utf8)
    Assert-Rejected { Invoke-VtWorkshopUploadEvidence -Path $path -PublishedId $id -UploadAction { throw 'must not run' } } 'native prefix work budget bounded' 'budget'
    Assert-Closed
    Reset-Log
    $result = Invoke-VtWorkshopUploadEvidence -Path $path -PublishedId '0' -ResolveBootstrapId { $id } -UploadAction { Append-Log (Live-Transaction) }
    Assert-Evidence ($result.PublishedId -ceq $id) 'bootstrap resolves positive ID against original pre-upload capture'
    foreach ($invalid in @('0','01','18446744073709551616')) {
        Reset-Log
        Assert-Rejected { Invoke-VtWorkshopUploadEvidence -Path $path -PublishedId '0' -ResolveBootstrapId { $invalid } -UploadAction { Append-Log (Live-Transaction) } } "bootstrap invalid assigned ID $invalid"
        Assert-Closed
    }
    Reset-Log
    Assert-Rejected { Invoke-VtWorkshopUploadEvidence -Path $path -PublishedId '0' -ResolveBootstrapId { throw 'resolver failure' } -UploadAction { Append-Log (Live-Transaction) } } 'bootstrap resolver exception closes observer' 'resolver failure'
    Assert-Closed
    Assert-Rejected { Invoke-VtWorkshopUploadEvidence -Path $path -PublishedId '0' -UploadAction { throw 'must not run' } } 'bootstrap requires explicit resolver' 'resolver'
    Assert-Rejected { Invoke-VtWorkshopUploadEvidence -Path $path -PublishedId $id -ResolveBootstrapId { $id } -UploadAction { throw 'must not run' } } 'normal upload cannot change target ID' 'only valid'
    $script:called = $false
    Assert-Rejected { Invoke-VtWorkshopUploadEvidence -Path $path -PublishedId "$id`n" -UploadAction { $script:called = $true } } 'newline item rejected before launcher'
    Assert-Evidence (-not $script:called) 'newline ID cannot invoke UploadAction'
    Reset-Log
    $originalParser = (Get-Command ConvertFrom-VtWorkshopUploadTransaction).ScriptBlock
    & {
        function ConvertFrom-VtWorkshopUploadTransaction {
            param($Text, $PublishedId, $StartedAt, $EndedAt)
            $result = & $originalParser -Text $Text -PublishedId $PublishedId -StartedAt $StartedAt -EndedAt $EndedAt
            Append-Log "unrelated line appended during final verification`n"
            return $result
        }
        Assert-Rejected { Invoke-VtWorkshopUploadEvidence -Path $path -PublishedId $id -UploadAction { Append-Log (Live-Transaction) } } 'ordinary growth during final verification is conservatively unavailable' 'changed during verification'
    }
    Assert-Closed

    # Execute actual ship try/catch/finally, with only the launcher and its
    # configuration boundary replaced. All capture/parser/cleanup code is real.
    function Invoke-WithShipVmbRc { param($RepoRoot, $Resolution, [scriptblock]$Action) & $Action }
    function Invoke-ShipLauncherNoWindow {
        param($LauncherExecutableLease, $ArgumentList, [switch]$ReplayOutput)
        $script:launcherCalls++
        Assert-Evidence ($ArgumentList[0] -ceq 'upload') 'installed block preserves launcher upload arguments'
        Append-Log (Live-Transaction -Terminal $script:terminal)
        return [pscustomobject]@{ ExitCode = $script:launcherExit }
    }
    $workshopLog = $path; $publishedId = $id; $Mod = 'fixture'
    $launcherExecutableLease = $null; $vmbRcResolution = $null
    $uploadArgs = @('upload', 'fixture', '--publication-receipt', $receiptPath)
    $bootstrapIdResolver = $null
    foreach ($mode in @('OK','Timeout','LauncherError')) {
        Reset-Log
        [IO.File]::WriteAllText($receiptPath, 'fixture', $utf8)
        $script:launcherCalls = 0; $script:terminal = if ($mode -eq 'Timeout') { 'Timeout' } else { 'OK' }
        $script:launcherExit = if ($mode -eq 'LauncherError') { 7 } else { 0 }
        $uploadFailure = $null; $publicationReceiptAccepted = $false
        . $actualUpload
        Assert-Evidence ($script:launcherCalls -eq 1) "installed $mode block invokes launcher once"
        Assert-Evidence (-not [IO.File]::Exists($receiptPath)) "installed $mode block removes ephemeral receipt"
        if ($mode -eq 'OK') { Assert-Evidence ($publicationReceiptAccepted -and $receiptAcceptance.Status -ceq 'UPLOADED') 'installed success exposes validated result' }
        else { Assert-Evidence (-not $publicationReceiptAccepted -and $null -ne $uploadFailure) "installed $mode never accepts receipt after failed evidence" }
        Assert-Closed
    }
    $resolvers = @($shipAst.FindAll({param($node)
        $node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -ceq '$bootstrapIdResolver' -and
        $node.Right.Extent.Text.Contains('$cfgAfterBootstrap')
    }, $true))
    Assert-Evidence ($resolvers.Count -eq 1) 'actual bootstrap assigned-ID resolver found'
    $resolverFactory = [scriptblock]::Create('return ' + $resolvers[0].Right.Extent.Text)
    $bootstrapIdResolver = & $resolverFactory
    $publishedId = '0'; $script:launcherExit = 0; $script:terminal = 'OK'
    foreach ($cfg in @("published_id = ${id}L;", 'published_id = 0L;', "published_id = ${id}L; published_id = 12L;")) {
        Reset-Log
        [IO.File]::WriteAllText($cfgPath, $cfg, $utf8)
        $uploadFailure = $null; $publicationReceiptAccepted = $false
        . $actualUpload
        if ($cfg -ceq "published_id = ${id}L;") {
            Assert-Evidence ($publicationReceiptAccepted -and $receiptAcceptance.PublishedId -ceq $id) 'actual bootstrap resolver accepts assigned ID on original transaction'
        }
        else { Assert-Evidence (-not $publicationReceiptAccepted -and $uploadFailure -match 'exactly one positive') 'actual bootstrap resolver rejects zero/duplicate cfg IDs' }
        Assert-Closed
    }
}
finally {
    # One level of known private fixture files, no recursive delete or traversal.
    $fullRoot = [IO.Path]::GetFullPath($fixtureRoot)
    $parent = [IO.DirectoryInfo]::new($fullRoot)
    while ($null -ne $parent) {
        if (($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Unsafe fixture cleanup ancestry.' }
        $parent = $parent.Parent
    }
    if ([IO.Path]::GetFileName($fullRoot) -cnotmatch '^vt2-workshop-evidence-[a-f0-9]{32}$') { throw 'Unsafe fixture cleanup root.' }
    $files = @(Get-ChildItem -LiteralPath $fullRoot -Force)
    foreach ($file in $files) {
        if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            [IO.Path]::GetDirectoryName($file.FullName) -cne $fullRoot) { throw 'Unsafe fixture cleanup descendant.' }
    }
    foreach ($file in $files) { [IO.File]::Delete($file.FullName) }
    [IO.Directory]::Delete($fullRoot, $false)
}
Write-Host "[check_workshop_upload_evidence] $script:passed assertions PASS."
exit 0
