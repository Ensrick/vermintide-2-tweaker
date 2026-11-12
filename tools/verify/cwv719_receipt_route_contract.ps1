# #719: exact already-published Crowbill observer receipt admission.
# Invoked by the existing source-contract self-test; no network/game/upload.
function Test-VtCwv719ReceiptRouteContract {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Root)
    $ErrorActionPreference='Stop'
    $exceptions=Import-PowerShellDataFile (Join-Path $Root 'tools/verify/live_test_contract_exceptions.psd1')
    $rows=@($exceptions.ReceiptRouteOverrides|Where-Object{[string]$_.Marker -ceq '[cwv:719]'})
    $mod='character_weapon_variants'
    $prefix='character_weapon_variants/scripts/mods/'
    $helper=$prefix+'character_weapon_variants/_cwv_issue719_transaction_check.lua'
    $entry=$prefix+'character_weapon_variants/character_weapon_variants.lua'
    $check=$prefix+'character_weapon_variants/_cwv_regression_identity.lua'
    # Independent literal oracle: never derive the expected signature/command
    # or witness source from the anchors being tested.
    $signature='[cwv:719] peer observation role=%s peer=%s verdict=%s %s'
    $assert={param([bool]$Value,[string]$Message)
        if(-not$Value){throw ('CWV719 receipt contract: '+$Message)}
    }
    $shape={param($Items)
        & $assert (@($Items).Count -eq 1) 'exactly one holder route required'
        $r=$Items[0]
        & $assert ([string]$r.ModId -ceq $mod -and [string]$r.Source -ceq $helper) 'wrong owner/source'
        & $assert ([string]$r.Signature -ceq $signature -and [bool]$r.AddRoute) 'exact synthetic route missing'
        & $assert (@($r.ActionCommands).Count -eq 1 -and [string]$r.ActionCommands[0] -ceq '/cwv_regression_test') 'command ownership drift'
    }
    & $shape $rows
    & $assert (@(@($exceptions.ReceiptFamilyOverrides)+@($exceptions.ReceiptDiscoveryOverrides)|Where-Object{[string]$_.Marker -ceq '[cwv:719]'}).Count -eq 0) 'family/discovery bypass'
    $tree=[string]$rows[0].ModTree
    & $assert ($tree -cmatch '^[0-9a-f]{40}$') 'one canonical immutable tree required'
    foreach($pin in @(Get-VtConsumedModTreePins -Exceptions $exceptions -ModId $mod)){
        & $assert (@($pin.Trees) -ccontains $tree) 'consumed sibling pin disagreement'
    }
    # Read only the three fixed Lua blobs from the pinned scripts/mods tree.
    # Redirect UTF-8 explicitly under both PS hosts; no working-copy witnesses,
    # archive tree, object-store writes or implicit promisor network hydration.
    $read={param([string]$Path)
        & $assert ($Path.StartsWith($prefix,[StringComparison]::Ordinal)) 'witness escaped mod root'
        $relative=$Path.Substring($prefix.Length)
        $start=New-Object Diagnostics.ProcessStartInfo
        $start.FileName='git';$start.Arguments='-C "'+$Root+'" show '+$tree+':'+$relative
        $start.UseShellExecute=$false;$start.CreateNoWindow=$true
        $start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
        $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
        $start.StandardOutputEncoding=New-Object Text.UTF8Encoding($false,$true)
        $start.StandardErrorEncoding=New-Object Text.UTF8Encoding($false,$true)
        $start.EnvironmentVariables['GIT_NO_LAZY_FETCH']='1'
        $process=New-Object Diagnostics.Process;$process.StartInfo=$start
        try{
            if(-not$process.Start()){throw 'Unable to start owned immutable witness reader'}
            $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
            if(-not$process.WaitForExit(30000)){$process.Kill();$process.WaitForExit();throw 'Owned immutable witness reader timed out'}
            $text=$stdout.GetAwaiter().GetResult();$errorText=$stderr.GetAwaiter().GetResult()
            if($process.ExitCode -ne 0){throw ('Immutable witness missing: '+$Path+' '+$errorText)}
            & $assert ($text.Length -gt 0 -and $text.Length -lt 262144) 'immutable witness size outside bound'
            return $text
        }finally{$process.Dispose()}
    }
    $sources=@{}
    foreach($path in @($helper,$entry,$check)){$sources[$path]=& $read $path}
    $apply={param($Texts=$sources,$Items=$rows,[string]$Tree=$tree)
        $documents=@();$commands=@();$routes=New-Object 'System.Collections.Generic.List[object]'
        foreach($path in @($Texts.Keys)){
            $text=[string]$Texts[$path]
            $doc=[pscustomobject]@{RelativePath=$path;Content=$text;Tokens=@(Get-VtLuaTokens -Content $text)}
            & $assert (-not(Test-VtLuaMutatesGlobalPrintf -Tokens $doc.Tokens)) 'global printf mutation in witness'
            $documents+=$doc;$scan=Get-VtDirectLuaCallRoutes -Document $doc
            $commands+=@($scan.CommandRoutes)
            foreach($route in @($scan.ReceiptRoutes)){$routes.Add($route)}
        }
        Set-VtStructuralReceiptBounds -Documents $documents -Routes $routes
        Set-VtReceiptOverrideBounds -ModId $mod -ModTree $Tree -Documents $documents -Routes $routes -CommandRoutes $commands -Exceptions @{ReceiptRouteOverrides=@($Items)}
        return ,$routes
    }
    $baseline=& $apply -Items @()
    & $assert (@($baseline|Where-Object{[string]$_.Marker -ceq '[cwv:719]'}).Count -eq 0) 'fixture no longer exercises the missing indirect route'
    $actual=& $apply
    $qualified=@($actual|Where-Object{[string]$_.Marker -ceq '[cwv:719]'})
    & $assert ($qualified.Count -eq 1 -and [string]$qualified[0].Signature -ceq $signature -and $qualified[0].Bound -and [string]$qualified[0].BoundProof -like 'override:*') 'holder route not uniquely qualified'
    & $assert (@($qualified[0].ActionCommands).Count -eq 1 -and $qualified[0].ActionCommands[0] -ceq '/cwv_regression_test') 'qualified route lost command ownership'
    $reject={param([scriptblock]$Action,[string]$Pattern,[string]$Label)
        $message=$null;try{& $Action|Out-Null}catch{$message=$_.Exception.Message}
        & $assert ($message -and $message -match $Pattern) ('negative accepted: '+$Label+' result='+$message)
    }
    & $reject {& $apply -Tree ('0'*40)} 'tree drift' 'wrong deployed tree'
    foreach($path in @($helper,$entry,$check)){
        $missing=$sources.Clone();$missing.Remove($path)
        & $reject {& $apply -Texts $missing} '(?:source missing|anchor drift|unregistered action command)' ('missing immutable witness '+$path)
    }
    & $reject {& $apply -Items @($rows+$rows[0])} 'Duplicate receipt-route' 'duplicate holder route'
    $copy=@($rows[0].Clone());$copy[0].ActionCommands=@('/missing_cwv719_command')
    & $reject {& $apply -Items $copy} 'unregistered action command' 'invented owner command'
    $copy=@($rows[0].Clone());$copy[0].ActionCommands=@()
    & $reject {& $shape $copy} 'command ownership' 'missing explicit command ownership'
    $mutations=@(
        @($helper,'[cwv:719] peer observation role=%s peer=%s verdict=%s %s','[cwv:719] holder role=%s peer=%s verdict=%s %s','emitter anchor drift'),
        @($helper,'return rawget(_G, name)','return rawget(_G, "wrong_sink")','emitter anchor drift'),
        @($helper,'local sink = global("printf")','local sink = global("print")','emitter anchor drift'),
        @($helper,'local ok = pcall(sink, fmt, ...)','local ok = true','emitter anchor drift'),
        @($entry,'_cwv_issue719_transaction_check")(mod, {','_cwv_issue719_transaction_check")(mod, { env = injected,','emitter anchor drift'),
        @($check,'local transaction_error = _issue719_transaction_check(','local transaction_error = another_check(','emitter anchor drift'),
        @($check,'_rt_register("issue719_imperial_crowbill_remote_identity", function()','_rt_register("wrong719", function()','guard anchor drift'),
        @($check,'ctx.regression_fixtures.isolated_register(ctx.rt_register, _om)','ctx.rt_register','guard anchor drift'),
        @($check,'local _issue719_transaction_check = ctx.issue719_transaction_check','local _issue719_transaction_check = ctx.other_check','guard anchor drift'),
        @($entry,'issue719_transaction_check = _issue719_transaction_check,','issue719_transaction_check = another_check,','guard anchor drift'),
        @($entry,'mod:dofile("scripts/mods/character_weapon_variants/_cwv_regression_identity")(mod, _cwv_regression_context)','mod:dofile("scripts/mods/character_weapon_variants/_cwv_regression_identity")(mod, other_context)','guard anchor drift'),
        @($entry,'rt_register = _rt_register,','rt_register = other_register,','guard anchor drift'),
        @($entry,'_RT_CHECKS[#_RT_CHECKS + 1] =','_OTHER_CHECKS[#_OTHER_CHECKS + 1] =','guard anchor drift'),
        @($entry,'local ok, err = pcall(c.fn)','local ok, err = pcall(other.fn)','guard anchor drift'),
        @($entry,'mod:command("cwv_regression_test",','mod:command("wrong719",','unregistered action command'),
        @($helper,'for scan_index = 1, 32 do','for scan_index = 1, 33 do','guard anchor drift'),
        @($helper,'MAX_SAMPLE_BYTES, MAX_EMISSIONS = 1536, 33','MAX_SAMPLE_BYTES, MAX_EMISSIONS = 1536, 34','guard anchor drift'),
        @($helper,'budget.emitted >= MAX_EMISSIONS','budget.emitted > MAX_EMISSIONS','guard anchor drift'),
        @($helper,'budget.emitted = budget.emitted + 1','budget.emitted = budget.emitted + 0','guard anchor drift'),
        @($helper,'MAX_LINE_BYTES, MAX_RESULT_BYTES = 512, 768, 2048','MAX_LINE_BYTES, MAX_RESULT_BYTES = 512, 769, 2048','guard anchor drift'),
        @($helper,'#line > MAX_LINE_BYTES','#line < MAX_LINE_BYTES','guard anchor drift'),
        @($helper,'line:find("[^ -~]")','false','guard anchor drift'),
        @($helper,'if type(sink) ~= "function" then budget.lossy = true; return end','if type(sink) ~= "function" then return end','guard anchor drift'),
        @($helper,'if not ok then budget.lossy = true end','if not ok then budget.lossy = false end','guard anchor drift'),
        @($helper,'if not complete then complete = next(players, cursor) == nil end','complete = true','guard anchor drift'),
        @($helper,'return "skip: legs 1-2 passed; peer observation incomplete"','return nil','guard anchor drift'),
        @($helper,'return "skip: legs 1-2 passed; diagnostic evidence was not fully representable"','return nil','guard anchor drift'),
        @($helper,'local budget = { lossy = false, emitted = 0 }','local budget = retained_budget','guard anchor drift'),
        @($helper,'err = peer_observation(family, budget)','err = nil','guard anchor drift')
    )
    $negativeCount=7
    foreach($mutation in $mutations){
        $texts=$sources.Clone();$before=[string]$texts[$mutation[0]]
        & $assert ($before.Contains($mutation[1])) ('mutation preimage absent: '+$mutation[1])
        $texts[$mutation[0]]=$before.Replace($mutation[1],$mutation[2])
        & $reject {& $apply -Texts $texts} $mutation[3] ('actual source mutation '+$mutation[1])
        $negativeCount++
    }
    $extra=$sources.Clone()
    $extra[$helper]+="`nfunction mod.update() printf('[cwv:719] forged=unbounded') end`n"
    $siblings=@((& $apply -Texts $extra)|Where-Object{[string]$_.Marker -ceq '[cwv:719]'})
    & $assert ($siblings.Count -eq 2 -and @($siblings|Where-Object{[string]$_.Signature -ceq '[cwv:719] forged=unbounded' -and -not $_.Bound -and @($_.ActionCommands).Count -eq 0}).Count -eq 1) 'automatic sibling borrowed holder permission'
    $targets=@([pscustomobject]@{ReceiptRoutes=@($actual.ToArray())})
    $authority=[pscustomobject]@{Kind='source-only-fixture'}
    $selector='Expected: `[cwv:719] peer observation role=owner peer=... verdict=ok ... publishes exact identity`'
    $card='1. Run `/cwv_regression_test`.'+"`n"+$selector
    & $assert (@(Get-VtCardEvidenceErrors -Card $card -Authority $authority -Targets $targets).Count -eq 0) 'exact solo selector rejected'
    & $assert (@(Get-VtCardEvidenceErrors -Card $selector -Authority $authority -Targets $targets) -match 'action-command-mismatch').Count 'commandless holder evidence accepted'
    foreach($skip in @('no_player_manager','diagnostic_budget','diagnostic_text_budget','no_crowbill_peer')){
        $unqualified='1. Run `/cwv_regression_test`.'+"`n"+'Expected: `[cwv:719] peer observation SKIP reason='+$skip+'`'
        & $assert (@(Get-VtCardEvidenceErrors -Card $unqualified -Authority $authority -Targets $targets) -match 'signature-not-source-registered').Count ('SKIP sibling borrowed admission: '+$skip)
    }
    Write-Host ("[live-test-contract] CWV719 immutable-source route passed: 3 witnesses, 1 exact holder route, {0} rejected mutations/invalid inputs; four SKIP siblings remain unqualified." -f $negativeCount)
    return [pscustomobject]@{Witnesses=3;Routes=1;Rejected=$negativeCount;Tree=$tree;GameplayVerified=$false}
}
