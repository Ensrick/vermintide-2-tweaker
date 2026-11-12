# #942: exact command-owned heat capture receipt admission.
# The ordinary source-contract self-test calls this only after real metadata
# adoption. No network, build, claim, game, upload or publication operation.
function Test-VtWt942ReceiptRouteContract {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Root)
    $ErrorActionPreference='Stop'
    $exceptions=Import-PowerShellDataFile (Join-Path $Root 'tools/verify/live_test_contract_exceptions.psd1')
    $assertions=0;$negativeCount=0;$witnesses=0
    $assert={param([bool]$Value,[string]$Message)
        if(-not$Value){throw ('WT942 receipt contract: '+$Message)}
    }
    $copy={
        param($Value)
        if($Value -is [Collections.IDictionary]){
            $cloned=@{};foreach($key in $Value.Keys){$cloned[$key]=& $copy $Value[$key]};return $cloned
        }
        if($Value -is [Array] -or $Value -is [Collections.IList]){
            $cloned=@();foreach($item in $Value){$cloned+=,(& $copy $item)};return ,$cloned
        }
        return $Value
    }
    # Independent literal oracle: no expectation is derived from anchor text.
    $signatures=@('[wt:942:capture] begin %s','[wt:942:capture] row=%s','[wt:942:capture] end count=%d')
    $read={
        param([string]$Tree,[string]$Directory,[string]$Name)
        & $assert ($Tree -cmatch '^[0-9a-f]{40}$' -and $Directory -cin @('weapon_tweaker','weapon_tweaker_dev') -and $Name -cin @('_wt_diagnostics.lua','_wt_fire_sword_heat_runtime.lua','_wt_fire_sword_owner.lua')) 'fixed immutable witness path required'
        $start=New-Object Diagnostics.ProcessStartInfo
        $start.FileName='git'
        $start.Arguments='-C "'+$Root+'" show '+$Tree+':'+$Directory+'/'+$Name
        $start.UseShellExecute=$false;$start.CreateNoWindow=$true
        $start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
        $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
        $start.StandardOutputEncoding=New-Object Text.UTF8Encoding($false,$true)
        $start.StandardErrorEncoding=New-Object Text.UTF8Encoding($false,$true)
        $start.EnvironmentVariables['GIT_NO_LAZY_FETCH']='1'
        $process=New-Object Diagnostics.Process;$process.StartInfo=$start
        try{
            if(-not$process.Start()){throw 'Unable to start immutable witness reader'}
            $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
            if(-not$process.WaitForExit(30000)){$process.Kill();$process.WaitForExit();throw 'Immutable witness reader timed out'}
            $text=$stdout.GetAwaiter().GetResult();$errorText=$stderr.GetAwaiter().GetResult()
            if($process.ExitCode -ne 0){throw ('Immutable witness missing; no lazy fetch: '+$errorText)}
            & $assert ($text.Length -gt 0 -and $text.Length -lt 131072) 'immutable witness size outside bound'
            return $text
        }finally{$process.Dispose()}
    }
    $reject={param([scriptblock]$Action,[string]$Pattern,[string]$Label)
        $message=$null;try{& $Action|Out-Null}catch{$message=$_.Exception.Message}
        & $assert ($message -and $message -match $Pattern) ('control accepted: '+$Label+' result='+$message)
    }
    foreach($stream in @(
        @{Id='wt';Directory='weapon_tweaker'},
        @{Id='wt_dev';Directory='weapon_tweaker_dev'}
    )){
        $id=$stream.Id;$directory=$stream.Directory
        $prefix=$directory+'/scripts/mods/'+$directory+'/'
        $diag=$prefix+'_wt_diagnostics.lua'
        $runtime=$prefix+'_wt_fire_sword_heat_runtime.lua'
        $owner=$prefix+'_wt_fire_sword_owner.lua'
        $rows=@($exceptions.ReceiptRouteOverrides|Where-Object{[string]$_.ModId -ceq $id -and [string]$_.Marker -ceq '[wt:942:capture]'})
        $shape={param($Items)
            & $assert (@($Items).Count -eq 3) 'exactly three capture routes per alias required'
            foreach($signature in $signatures){
                $selected=@($Items|Where-Object{[string]$_.Signature -ceq $signature})
                & $assert ($selected.Count -eq 1) ('unique literal signature missing: '+$signature)
                $row=$selected[0]
                & $assert ([string]$row.ModId -ceq $id -and [string]$row.Source -ceq $diag) 'wrong alias/default source'
                & $assert ([string]$row.Marker -ceq '[wt:942:capture]' -and -not$row.ContainsKey('AddRoute')) 'no synthetic route or marker-wide permission'
                & $assert (@($row.ActionCommands).Count -eq 1 -and [string]$row.ActionCommands[0] -ceq '/wt_heat_capture') 'capture command ownership drift'
                & $assert (@($row.EmitterAnchors).Count -eq 1 -and $row.EmitterAnchors[0] -is [string] -and @($row.GuardAnchors).Count -eq 3 -and $row.GuardAnchors[0] -is [string]) 'default-source Lua strings and two explicit cross-source witnesses required'
            }
        }
        & $shape $rows
        & $assert (@(@($exceptions.ReceiptFamilyOverrides)+@($exceptions.ReceiptDiscoveryOverrides)|Where-Object{[string]$_.Marker -ceq '[wt:942:capture]'}).Count -eq 0) 'family/discovery bypass'
        & $assert (@(@($exceptions.ReceiptRouteOverrides)+@($exceptions.ReceiptFamilyOverrides)+@($exceptions.ReceiptDiscoveryOverrides)|Where-Object{[string]$_.Marker -ceq '[wt:942]' -and [string]$_.Signature -ceq '[wt:942] inert: %s'}).Count -eq 0) 'unrelated inert receipt grant'
        $tree=[string]$rows[0].ModTree
        & $assert ($tree -cmatch '^[0-9a-f]{40}$' -and @($rows|Where-Object{[string]$_.ModTree -cne $tree -or $_.ContainsKey('ModTrees')}).Count -eq 0) 'one actual adopted immutable tree per alias required'
        foreach($pin in @(Get-VtConsumedModTreePins -Exceptions $exceptions -ModId $id)){
            & $assert (@($pin.Trees) -ccontains $tree) 'consumed sibling pin disagreement'
        }
        $sources=@{}
        foreach($name in @('_wt_diagnostics.lua','_wt_fire_sword_heat_runtime.lua','_wt_fire_sword_owner.lua')){
            $sources[$prefix+$name]=& $read $tree $directory $name;$witnesses++
        }
        $apply={param($Texts=$sources,$Items=$rows,[string]$Tree=$tree)
            $documents=@();$commands=@();$routes=New-Object 'System.Collections.Generic.List[object]'
            foreach($path in @($Texts.Keys)){
                $text=[string]$Texts[$path]
                $doc=[pscustomobject]@{RelativePath=$path;Content=$text;Tokens=@(Get-VtLuaTokens -Content $text)}
                & $assert (-not(Test-VtLuaMutatesGlobalPrintf -Tokens $doc.Tokens)) 'global printf mutation in witness'
                $documents+=@($doc);$scan=Get-VtDirectLuaCallRoutes -Document $doc
                $commands+=@($scan.CommandRoutes)
                foreach($route in @($scan.ReceiptRoutes)){$routes.Add($route)}
            }
            Set-VtStructuralReceiptBounds -Documents $documents -Routes $routes
            Set-VtReceiptOverrideBounds -ModId $id -ModTree $Tree -Documents $documents -Routes $routes -CommandRoutes $commands -Exceptions @{ReceiptRouteOverrides=@($Items)}
            return ,$routes
        }
        $baseline=& $apply -Items @()
        & $assert (@($baseline|Where-Object{[string]$_.Marker -ceq '[wt:942:capture]'}).Count -eq 3 -and @($baseline|Where-Object{[string]$_.Signature -ceq '[wt:942:capture] row=%s' -and -not$_.Bound}).Count -eq 1) 'actual indexed row loop must need an override'
        $actual=& $apply
        $qualified=@($actual|Where-Object{[string]$_.Marker -ceq '[wt:942:capture]'})
        & $assert ($qualified.Count -eq 3 -and @($qualified|Where-Object{-not$_.Bound -or [string]$_.BoundProof -cnotlike 'override:*' -or @($_.ActionCommands).Count -ne 1 -or $_.ActionCommands[0] -cne '/wt_heat_capture'}).Count -eq 0) 'three exact finite command-owned routes required'
        & $reject {& $apply -Tree ('0'*40)} 'tree drift' 'wrong adopted tree';$negativeCount++
        & $reject {& $apply -Items @($rows+$rows[0])} 'Duplicate receipt-route' 'duplicate route';$negativeCount++
        foreach($path in @($diag,$runtime,$owner)){
            $missing=$sources.Clone();$missing.Remove($path)
            & $reject {& $apply -Texts $missing} '(source missing|anchor drift|unregistered action command)' ('missing witness '+$path);$negativeCount++
        }
        $changed=& $copy $rows;$changed[0].ActionCommands=@('/verify_wt_loadout_cache')
        & $reject {& $shape $changed} 'command ownership' 'wrong registered command';$negativeCount++
        $changed=& $copy $rows;$changed[0].ActionCommands=@('/missing_wt942_command')
        & $reject {& $apply -Items $changed} 'unregistered action command' 'invented command';$negativeCount++
        $changed=& $copy $rows;$changed[0].Source=$runtime
        & $reject {& $apply -Items $changed} 'emitter anchor drift' 'wrong existing source';$negativeCount++
        $changed=& $copy $rows;$changed[0].Signature='[wt:942:capture] invented=%s'
        & $reject {& $shape $changed} 'unique literal signature' 'invented signature';$negativeCount++
        foreach($mutation in @(
            @($diag,'#value <= 960','#value <= 961','guard anchor drift'),
            @($diag,'not value:find("[^ -~]")','true','guard anchor drift'),
            @($diag,'type(data.count) ~= "number"','false','guard anchor drift'),
            @($diag,'data.count < 0','false','guard anchor drift'),
            @($diag,'data.count > 8','data.count > 9','guard anchor drift'),
            @($diag,'data.count % 1 ~= 0','false','guard anchor drift'),
            @($diag,'type(data.rows) ~= "table"','false','guard anchor drift'),
            @($diag,'not bounded(data.header)','false','guard anchor drift'),
            @($diag,'index <= data.count and not bounded(rawget(data.rows, index))','false','guard anchor drift'),
            @($diag,'for index = 1, 8 do','for index = 1, 9 do','guard anchor drift'),
            @($diag,'if index > data.count then break end','if false then break end','guard anchor drift'),
            @($diag,'mod:command("wt_heat_capture",','mod:command("wrong_wt942",','unregistered action command'),
            @($diag,'[wt:942:capture] begin %s','[wt:942:capture] wrong-begin %s','emitter anchor drift'),
            @($diag,'[wt:942:capture] row=%s','[wt:942:capture] wrong-row=%s','(emitter|guard) anchor drift'),
            @($diag,'[wt:942:capture] end count=%d','[wt:942:capture] wrong-end count=%d','(emitter|guard) anchor drift'),
            @($runtime,'capture.pending = false','capture.pending = true','guard anchor drift'),
            @($runtime,'if not capture or not capture.pending then','if not capture then','guard anchor drift'),
            @($owner,'if action == "dump" then return runtime:capture_dump() end','if action == "dump" then return runtime:capture_arm() end','guard anchor drift')
        )){
            $texts=$sources.Clone();$before=[string]$texts[$mutation[0]]
            & $assert ($before.Contains($mutation[1])) ('actual mutation preimage absent: '+$mutation[1])
            $texts[$mutation[0]]=$before.Replace($mutation[1],$mutation[2])
            & $reject {& $apply -Texts $texts} $mutation[3] ('actual source mutation '+$mutation[1]);$negativeCount++
        }
        # Genuine file-local/raw-printf shadows leave every token anchor in
        # place, but the normal raw-route census must drop all three emitters.
        # No AddRoute exists to manufacture them back into authority.
        foreach($shadow in @('local printf = function(...) end','local function printf(...) end','printf = function(...) end')){
            $texts=$sources.Clone();$texts[$diag]=$shadow+[Environment]::NewLine+$sources[$diag]
            $doc=[pscustomobject]@{RelativePath=$diag;Content=$texts[$diag];Tokens=@(Get-VtLuaTokens -Content $texts[$diag])}
            & $assert (@((Get-VtDirectLuaCallRoutes -Document $doc).ReceiptRoutes|Where-Object{[string]$_.Marker -ceq '[wt:942:capture]'}).Count -eq 0) 'shadowed printf survived the real raw-route census'
            & $reject {& $apply -Texts $texts} 'no longer resolves an indexed route' ('file/raw printf shadow '+$shadow);$negativeCount++
        }
        foreach($mutation in @('_G.printf = function(...) end','rawset(_G, "printf", function(...) end)')){
            $texts=$sources.Clone();$texts[$owner]=$mutation+[Environment]::NewLine+$sources[$owner]
            & $reject {& $apply -Texts $texts} 'global printf mutation' 'cross-file global printf replacement';$negativeCount++
        }
        $extra=$sources.Clone()
        $extra[$diag]+=[Environment]::NewLine+"function mod.update() printf('[wt:942:capture] rogue=%s', 'x') printf('[wt:942] inert: %s', 'x') end"+[Environment]::NewLine
        $expanded=& $apply -Texts $extra
        & $assert (@($expanded|Where-Object{[string]$_.Signature -ceq '[wt:942:capture] rogue=%s' -and -not$_.Bound -and @($_.ActionCommands).Count -eq 0}).Count -eq 1) 'automatic sibling borrowed capture admission'
        & $assert (@($expanded|Where-Object{[string]$_.Marker -ceq '[wt:942]' -and $_.Bound}).Count -eq 0) 'inert output borrowed capture admission'
        $targets=@([pscustomobject]@{ReceiptRoutes=@($expanded.ToArray())})
        $actualTargets=@([pscustomobject]@{ReceiptRoutes=@($actual.ToArray())})
        $authority=[pscustomobject]@{Kind='source-contract-fixture'}
        $tick=[string][char]96
        $command='1. Run '+$tick+'/wt_heat_capture'+$tick+' with the dump argument.'
        $selector='Expected: '+$tick+'[wt:942:capture] begin'+$tick
        & $assert (@(Get-VtCardEvidenceErrors -Card ($command+[Environment]::NewLine+$selector) -Authority $authority -Targets $targets).Count -eq 0) 'exact begin selector rejected with its owner command'
        & $assert (@(Get-VtCardEvidenceErrors -Card $selector -Authority $authority -Targets $targets) -match 'action-command-mismatch').Count 'commandless receipt accepted'
        $argumentSpan='1. Run '+$tick+'/wt_heat_capture dump'+$tick+'.'+[Environment]::NewLine+$selector
        & $assert (@(Get-VtCardEvidenceErrors -Card $argumentSpan -Authority $authority -Targets $targets) -match 'action-command-mismatch').Count 'argument-bearing span invented base command ownership'
        $wrong='1. Run '+$tick+'/verify_wt_loadout_cache'+$tick+'.'+[Environment]::NewLine+$selector
        & $assert (@(Get-VtCardEvidenceErrors -Card $wrong -Authority $authority -Targets $targets) -match 'action-command-mismatch').Count 'unrelated registered command accepted'
        $generic=$command+[Environment]::NewLine+'Expected: '+$tick+'[wt:942:capture] row='+$tick
        & $assert (@(Get-VtCardEvidenceErrors -Card $generic -Authority $authority -Targets $actualTargets).Count -eq 0) 'finite complete capture family rejected'
        & $assert (@(Get-VtCardEvidenceErrors -Card $generic -Authority $authority -Targets $targets) -match 'not-bounded').Count 'generic row reference hid an unbounded sibling'
        $wide=$command+[Environment]::NewLine+'Expected: '+$tick+'[wt:942:capture]'+$tick+'.'
        & $assert (@(Get-VtCardEvidenceErrors -Card $wide -Authority $authority -Targets $targets) -match 'not-bounded').Count 'bare marker hid an unbounded sibling'
    }
    Write-Host ('[live-test-contract] WT942 adopted-source capture routes passed: 2 aliases, '+$witnesses+' immutable witnesses, 6 exact command-owned routes, '+$negativeCount+' rejected controls; inert output remains unqualified.')
    return [pscustomobject]@{Aliases=2;Witnesses=$witnesses;Routes=6;Rejected=$negativeCount;GameplayVerified=$false}
}
